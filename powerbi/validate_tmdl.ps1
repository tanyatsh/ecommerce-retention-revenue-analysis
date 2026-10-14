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

$requiredBusinessTables = @(
    'Monthly Revenue',
    'Customers',
    'Cohort Retention',
    'Cohort Horizons',
    'RFM Segments',
    'Monthly Experience',
    'Date'
)
$actualTableNames = @($database.Model.Tables | ForEach-Object Name)
$missingBusinessTables = @($requiredBusinessTables | Where-Object { $_ -notin $actualTableNames })
$guidPattern = '[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}'
$templateNamePattern = "^DateTableTemplate_$guidPattern$"
$localDateNamePattern = "^LocalDateTable_$guidPattern$"
$dateTemplateTables = @($database.Model.Tables | Where-Object { $_.Name -match $templateNamePattern })
$localDateTables = @($database.Model.Tables | Where-Object { $_.Name -match $localDateNamePattern })
$generatedDateTableNames = @($dateTemplateTables.Name) + @($localDateTables.Name)
$unexpectedTables = @(
    $actualTableNames | Where-Object {
        $_ -notin $requiredBusinessTables -and $_ -notin $generatedDateTableNames
    }
)

if ($missingBusinessTables.Count -gt 0 -or $unexpectedTables.Count -gt 0) {
    Write-Error "TMDL table contract mismatch. Missing business tables: $($missingBusinessTables -join ', '); unexpected tables: $($unexpectedTables -join ', ')."
    exit 1
}
if ($dateTemplateTables.Count -ne 1) {
    Write-Error "Expected one Power BI DateTableTemplate table; found $($dateTemplateTables.Count)."
    exit 1
}
if ($localDateTables.Count -eq 0) {
    Write-Error 'Expected Power BI-generated LocalDateTable objects.'
    exit 1
}

$dateTemplate = $dateTemplateTables[0]
if (-not $dateTemplate.IsHidden -or -not $dateTemplate.IsPrivate -or $dateTemplate.Measures.Count -ne 0 -or $dateTemplate.Partitions.Count -ne 1 -or $dateTemplate.Partitions[0].SourceType.ToString() -ne 'Calculated') {
    Write-Error 'The Power BI DateTableTemplate object does not match the expected generated-table structure.'
    exit 1
}
$invalidLocalDateTables = @(
    $localDateTables | Where-Object {
        -not $_.IsHidden -or
        -not $_.ShowAsVariationsOnly -or
        $_.Measures.Count -ne 0 -or
        $_.Partitions.Count -ne 1 -or
        $_.Partitions[0].SourceType.ToString() -ne 'Calculated'
    }
)
if ($invalidLocalDateTables.Count -gt 0) {
    Write-Error "Invalid generated LocalDateTable objects: $($invalidLocalDateTables.Name -join ', ')."
    exit 1
}

$expectedMeasuresByTable = @{
    'Monthly Revenue' = @(
        'Gross Order Value (GMV)', 'Item Value', 'Freight', 'Payments', 'Orders',
        'Orders with GMV', 'Orders Missing GMV', 'Monthly Purchasing Customers',
        'Average Order Value', 'Previous Month GMV', 'GMV Month-over-Month %',
        'Reporting Period Label', 'GMV (BRL millions)', 'Orders (thousands)'
    )
    'Customers' = @('Unique Customers', 'Repeat Customers', 'Repeat Customer Share')
    'Cohort Retention' = @('Cohort Retention %')
    'Cohort Horizons' = @(
        'Weighted Retention %', 'Month 1 Retention %', 'Month 3 Retention %',
        'Month 6 Retention %', 'Month 12 Retention %', 'GMV Display EN',
        'Orders Display EN', 'Customers Display EN'
    )
    'RFM Segments' = @(
        'RFM Customers', 'RFM Customer Share', 'RFM Orders', 'RFM Monetary Value',
        'RFM Snapshot Label', 'RFM Customers (thousands)'
    )
    'Monthly Experience' = @(
        'Delivered Orders', 'Reviewed Orders', 'Unreviewed Orders',
        'Multiple-Review Orders', 'Review Coverage %', 'Late Deliveries',
        'Late Delivery Rate', 'On-Time Delivery Rate', 'Average Delivery Days',
        'Average Delivery Delay Days', 'Average Review Score'
    )
    'Date' = @()
}
$expectedMeasureKeys = @(
    foreach ($tableName in $expectedMeasuresByTable.Keys) {
        foreach ($measureName in $expectedMeasuresByTable[$tableName]) {
            "${tableName}::$measureName"
        }
    }
)
$actualMeasureKeys = @(
    foreach ($tableName in $requiredBusinessTables) {
        foreach ($measure in $database.Model.Tables[$tableName].Measures) {
            "${tableName}::$($measure.Name)"
        }
    }
)
$measureDifference = @(Compare-Object -ReferenceObject $expectedMeasureKeys -DifferenceObject $actualMeasureKeys)
if ($measureDifference.Count -gt 0) {
    Write-Error "Business measure contract mismatch:`n$($measureDifference | Out-String)"
    exit 1
}
$generatedMeasureCount = (
    $database.Model.Tables |
        Where-Object { $_.Name -in $generatedDateTableNames } |
        ForEach-Object { $_.Measures.Count } |
        Measure-Object -Sum
).Sum
if ($generatedMeasureCount -ne 0) {
    Write-Error 'Power BI-generated date tables must not contain business measures.'
    exit 1
}
$measureCount = $actualMeasureKeys.Count

$expectedCsvByTable = [ordered]@{
    'Monthly Revenue' = 'monthly_revenue_orders.csv'
    'Customers' = 'customer_purchase_summary.csv'
    'Cohort Retention' = 'cohort_retention.csv'
    'Cohort Horizons' = 'cohort_horizon_summary.csv'
    'RFM Segments' = 'rfm_segment_summary.csv'
    'Monthly Experience' = 'monthly_delivery_reviews.csv'
}
$expectedMTables = @($expectedCsvByTable.Keys)
$mTables = @(
    $database.Model.Tables |
        Where-Object { @($_.Partitions | Where-Object { $_.SourceType.ToString() -eq 'M' }).Count -gt 0 } |
        ForEach-Object Name
)
$mTableDifference = @(Compare-Object -ReferenceObject $expectedMTables -DifferenceObject $mTables)
if ($mTableDifference.Count -gt 0) {
    Write-Error "M table contract mismatch. Expected: $($expectedMTables -join ', '); actual: $($mTables -join ', ')."
    exit 1
}

$queryOrder = [string[]](ConvertFrom-Json -InputObject $database.Model.Annotations['PBI_QueryOrder'].Value)
$expectedQueryOrder = @('DataFolder') + $expectedMTables
if ((ConvertTo-Json -InputObject $queryOrder -Compress) -ne (ConvertTo-Json -InputObject $expectedQueryOrder -Compress)) {
    Write-Error "PBI_QueryOrder must contain DataFolder followed by the six M table queries. Expected: $($expectedQueryOrder -join ', '); actual: $($queryOrder -join ', ')."
    exit 1
}

$dataFolder = $database.Model.Expressions['DataFolder']
$expressionNames = @($database.Model.Expressions | ForEach-Object Name)
if ($expressionNames.Count -ne 1 -or $expressionNames[0] -ne 'DataFolder') {
    Write-Error "Expected DataFolder as the only shared M expression. Actual: $($expressionNames -join ', ')."
    exit 1
}
if ($null -eq $dataFolder -or $dataFolder.Expression -notmatch 'IsParameterQuery=true' -or $dataFolder.Expression -notmatch 'Type="Text"' -or $dataFolder.Expression -notmatch 'IsParameterQueryRequired=true') {
    Write-Error 'DataFolder must be a required Power Query text parameter.'
    exit 1
}
if ($dataFolder.Expression -match '(?i)[A-Z]:\\Users\\') {
    Write-Error 'DataFolder contains a machine-specific user path.'
    exit 1
}

$validatedMPartitions = 0
foreach ($tableName in $expectedMTables) {
    $table = $database.Model.Tables[$tableName]
    $mPartitions = @($table.Partitions | Where-Object { $_.SourceType.ToString() -eq 'M' })
    if ($mPartitions.Count -ne 1) {
        Write-Error "Table '$tableName' must contain exactly one M partition."
        exit 1
    }
    $partition = $mPartitions[0]
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
    $expectedCsv = $expectedCsvByTable[$tableName]
    if (-not $fileMatch.Success -or $fileMatch.Groups[1].Value -ne $expectedCsv) {
        Write-Error "M partition '$($partition.Name)' must read '$expectedCsv' through the DataFolder parameter."
        exit 1
    }
    if ($expression -match '(?i)[A-Z]:\\Users\\') {
        Write-Error "M partition '$($partition.Name)' contains a machine-specific path."
        exit 1
    }
}

$dateTable = $database.Model.Tables['Date']
$datePartitions = @($dateTable.Partitions)
if ($datePartitions.Count -ne 1 -or $datePartitions[0].SourceType.ToString() -ne 'Calculated') {
    Write-Error 'Date must remain a single DAX-calculated partition.'
    exit 1
}
$dateExpression = $datePartitions[0].Source.Expression
foreach ($mTableName in $expectedMTables) {
    if ($dateExpression.Contains("'$mTableName'")) {
        Write-Error "Date calculated table must not depend on imported M table '$mTableName'."
        exit 1
    }
}

function Get-RelationshipKey {
    param($Relationship)
    return "$($Relationship.FromColumn.Table.Name)[$($Relationship.FromColumn.Name)] -> $($Relationship.ToColumn.Table.Name)[$($Relationship.ToColumn.Name)]"
}

$expectedBusinessRelationshipKeys = @(
    'Monthly Revenue[purchase_month] -> Date[Date]',
    'Monthly Experience[purchase_month] -> Date[Date]'
)
$businessRelationships = @(
    $database.Model.Relationships | Where-Object {
        $_.FromColumn.Table.Name -in $requiredBusinessTables -and
        $_.ToColumn.Table.Name -in $requiredBusinessTables
    }
)
$actualBusinessRelationshipKeys = @($businessRelationships | ForEach-Object { Get-RelationshipKey $_ })
$businessRelationshipDifference = @(Compare-Object -ReferenceObject $expectedBusinessRelationshipKeys -DifferenceObject $actualBusinessRelationshipKeys)
if ($businessRelationshipDifference.Count -gt 0) {
    Write-Error "Business relationship contract mismatch. Expected: $($expectedBusinessRelationshipKeys -join '; '); actual: $($actualBusinessRelationshipKeys -join '; ')."
    exit 1
}
$unsafeBusinessRelationships = @(
    $businessRelationships | Where-Object {
        $_.FromCardinality.ToString() -ne 'Many' -or
        $_.ToCardinality.ToString() -ne 'One' -or
        $_.CrossFilteringBehavior.ToString() -ne 'OneDirection' -or
        -not $_.IsActive -or
        $_.JoinOnDateBehavior.ToString() -ne 'DateAndTime'
    }
)
if ($unsafeBusinessRelationships.Count -gt 0) {
    Write-Error 'Both business relationships must be active, many-to-one, single direction, and DateAndTime joins.'
    exit 1
}

$localDateTableNames = @($localDateTables.Name)
$generatedDateRelationships = @(
    $database.Model.Relationships | Where-Object {
        $_.FromColumn.Table.Name -in $requiredBusinessTables -and
        $_.ToColumn.Table.Name -in $localDateTableNames
    }
)
$classifiedRelationshipNames = @($businessRelationships.Name) + @($generatedDateRelationships.Name)
$unexpectedRelationships = @($database.Model.Relationships | Where-Object { $_.Name -notin $classifiedRelationshipNames })
if ($unexpectedRelationships.Count -gt 0) {
    Write-Error "Unexpected relationships: $($unexpectedRelationships.Name -join ', ')."
    exit 1
}
$generatedTargets = @($generatedDateRelationships | ForEach-Object { $_.ToColumn.Table.Name } | Sort-Object -Unique)
$targetDifference = @(Compare-Object -ReferenceObject ($localDateTableNames | Sort-Object) -DifferenceObject $generatedTargets)
if ($targetDifference.Count -gt 0 -or $generatedDateRelationships.Count -ne $localDateTables.Count) {
    Write-Error 'Each generated LocalDateTable must be the target of exactly one generated relationship.'
    exit 1
}
$unsafeGeneratedRelationships = @(
    $generatedDateRelationships | Where-Object {
        $_.ToColumn.Name -ne 'Date' -or
        $_.FromCardinality.ToString() -ne 'Many' -or
        $_.ToCardinality.ToString() -ne 'One' -or
        $_.CrossFilteringBehavior.ToString() -ne 'OneDirection' -or
        -not $_.IsActive -or
        $_.JoinOnDateBehavior.ToString() -ne 'DatePartOnly'
    }
)
if ($unsafeGeneratedRelationships.Count -gt 0) {
    Write-Error 'Generated date relationships must target LocalDateTable[Date] and remain active, many-to-one, single direction, and DatePartOnly.'
    exit 1
}

Write-Output 'TMDL validation passed.'
Write-Output "Business tables verified: $($requiredBusinessTables.Count)"
Write-Output "Generated Auto Date/Time tables verified: $($generatedDateTableNames.Count) ($($dateTemplateTables.Count) template, $($localDateTables.Count) local)"
Write-Output "Business measures verified by name and table: $measureCount"
Write-Output "M query order: $($queryOrder -join ', ')"
Write-Output "DataFolder parameter and M partition filenames verified: $validatedMPartitions"
Write-Output "Business relationships verified: $($businessRelationships.Count)"
Write-Output "Generated Auto Date/Time relationships verified: $($generatedDateRelationships.Count)"
Write-Output 'Date dependency check: independent calculated table'