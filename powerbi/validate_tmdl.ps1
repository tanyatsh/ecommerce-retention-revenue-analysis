param(
    [string]$PowerBIBin = 'C:\Program Files\Microsoft Power BI Desktop\bin'
)

$ErrorActionPreference = 'Stop'
$repositoryRoot = Split-Path -Parent $PSScriptRoot
$definitionPath = Join-Path $repositoryRoot 'powerbi\pbip\OlistRetentionDashboard.SemanticModel\definition'
$tabularAssembly = Join-Path $PowerBIBin 'Microsoft.PowerBI.Tabular.dll'

if (-not (Test-Path -LiteralPath $tabularAssembly)) {
    Write-Error "Power BI Tabular assembly not found: $tabularAssembly"
    exit 1
}

Get-ChildItem -LiteralPath $PowerBIBin -File -Filter 'Microsoft.PowerBI*.dll' | ForEach-Object {
    try {
        [System.Reflection.Assembly]::LoadFrom($_.FullName) | Out-Null
    }
    catch {
        # Optional Power BI assemblies may have process-specific dependencies.
    }
}
[System.Reflection.Assembly]::LoadFrom($tabularAssembly) | Out-Null

try {
    $database = [Microsoft.AnalysisServices.Tabular.TmdlSerializer]::DeserializeDatabaseFromFolder($definitionPath)
}
catch {
    Write-Error "TMDL validation failed: $($_.Exception.Message)"
    exit 1
}

$expectedTables = @(
    'Monthly Revenue',
    'Customers',
    'Cohort Retention',
    'Cohort Horizons',
    'RFM Segments',
    'Monthly Experience',
    'Date'
)
$actualTables = @($database.Model.Tables | ForEach-Object Name | Sort-Object)
$missingTables = @($expectedTables | Where-Object { $_ -notin $actualTables })
$extraTables = @($actualTables | Where-Object { $_ -notin $expectedTables })

if ($missingTables.Count -gt 0 -or $extraTables.Count -gt 0) {
    Write-Error "TMDL table contract mismatch. Missing: $($missingTables -join ', '); extra: $($extraTables -join ', ')."
    exit 1
}
$measureCount = ($database.Model.Tables | ForEach-Object { $_.Measures.Count } | Measure-Object -Sum).Sum
if ($measureCount -ne 37) {
    Write-Error 'Expected exactly 37 DAX measures.'
    exit 1
}

$mTables = @(
    $database.Model.Tables |
        Where-Object { @($_.Partitions | Where-Object { $_.SourceType.ToString() -eq 'M' }).Count -gt 0 } |
        ForEach-Object Name
)
$queryOrder = [string[]](ConvertFrom-Json -InputObject $database.Model.Annotations['PBI_QueryOrder'].Value)
$expectedQueryOrder = @('DataFolder') + $mTables
$queryOrderDifference = @(Compare-Object -ReferenceObject $expectedQueryOrder -DifferenceObject $queryOrder)
if ($queryOrderDifference.Count -gt 0) {
    Write-Error "PBI_QueryOrder must contain DataFolder and exactly the M table queries. Expected: $($expectedQueryOrder -join ', '); query order: $($queryOrder -join ', ')."
    exit 1
}

$dataFolder = $database.Model.Expressions['DataFolder']
if ($null -eq $dataFolder -or $dataFolder.Expression -notmatch 'IsParameterQuery=true' -or $dataFolder.Expression -notmatch 'Type="Text"' -or $dataFolder.Expression -notmatch 'IsParameterQueryRequired=true') {
    Write-Error 'DataFolder must be a required Power Query text parameter.'
    exit 1
}

$expectedCsvByTable = @{
    'Monthly Revenue' = 'monthly_revenue_orders.csv'
    'Customers' = 'customer_purchase_summary.csv'
    'Cohort Retention' = 'cohort_retention.csv'
    'Cohort Horizons' = 'cohort_horizon_summary.csv'
    'RFM Segments' = 'rfm_segment_summary.csv'
    'Monthly Experience' = 'monthly_delivery_reviews.csv'
}

$validatedMPartitions = 0
foreach ($table in $database.Model.Tables) {
    foreach ($partition in $table.Partitions | Where-Object { $_.SourceType.ToString() -eq 'M' }) {
		$validatedMPartitions += 1
        $expression = $partition.Source.Expression
        $quotedSelfReference = '#"' + $table.Name.Replace('"', '""') + '"'
        $hasSelfReference = $expression.Contains($quotedSelfReference)
        if (-not $table.Name.Contains(' ')) {
            $bareNamePattern = '(?m)(?<![A-Za-z0-9_])' + [regex]::Escape($table.Name) + '(?![A-Za-z0-9_])'
            $hasSelfReference = $hasSelfReference -or [regex]::IsMatch($expression, $bareNamePattern)
        }
        if ($hasSelfReference) {
            Write-Error "M partition '$($partition.Name)' references its own query name."
            exit 1
        }
        if ($expression -notmatch '(?s)^\s*let\s+.+\s+in\s+Typed\s*$') {
            Write-Error "M partition '$($partition.Name)' must terminate with 'in Typed'."
            exit 1
        }
        $fileMatch = [regex]::Match($expression, 'File\.Contents\(\s*DataFolder\s*&\s*"\\([^"]+)"\s*\)')
        $expectedCsv = $expectedCsvByTable[$table.Name]
        if (-not $fileMatch.Success -or $fileMatch.Groups[1].Value -ne $expectedCsv) {
        	Write-Error "M partition '$($partition.Name)' must read '$expectedCsv' through the DataFolder parameter."
        	exit 1
        }
        if ($expression -match '(?i)[A-Z]:\\Users\\') {
        	Write-Error "M partition '$($partition.Name)' contains a machine-specific path."
        	exit 1
        }
    }
}

$dateTable = $database.Model.Tables['Date']
$datePartitions = @($dateTable.Partitions)
if ($datePartitions.Count -ne 1 -or $datePartitions[0].SourceType.ToString() -ne 'Calculated') {
    Write-Error 'Date must remain a single DAX-calculated partition.'
    exit 1
}
$dateExpression = $datePartitions[0].Source.Expression
foreach ($mTableName in $mTables) {
    if ($dateExpression.Contains("'$mTableName'")) {
        Write-Error "Date calculated table must not depend on imported M table '$mTableName'."
        exit 1
    }
}
if ($database.Model.Relationships.Count -ne 2) {
    Write-Error "Expected 2 relationships; found $($database.Model.Relationships.Count)."
    exit 1
}
$unsafeRelationships = @(
    $database.Model.Relationships | Where-Object {
        $_.FromCardinality.ToString() -ne 'Many' -or
        $_.ToCardinality.ToString() -ne 'One' -or
        $_.CrossFilteringBehavior.ToString() -ne 'OneDirection' -or
        -not $_.IsActive
    }
)
if ($unsafeRelationships.Count -gt 0) {
    Write-Error 'Every relationship must be active, many-to-one, and single direction.'
    exit 1
}

Write-Output "TMDL validation passed."
Write-Output "Database: $($database.Name)"
Write-Output "Tables: $($database.Model.Tables.Count)"
Write-Output "Relationships: $($database.Model.Relationships.Count)"
Write-Output "Measures: $measureCount"
Write-Output "M query order: $($queryOrder -join ', ')"
Write-Output "DataFolder parameter and M partition filenames verified: $validatedMPartitions"
Write-Output "Date dependency check: independent calculated table"
$database.Model.Tables |
    Select-Object Name,
        @{Name = 'Columns'; Expression = { $_.Columns.Count }},
        @{Name = 'Measures'; Expression = { $_.Measures.Count }},
        @{Name = 'Partitions'; Expression = { $_.Partitions.Count }} |
    Sort-Object Name |
    Format-Table -AutoSize

