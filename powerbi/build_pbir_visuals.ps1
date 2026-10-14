$ErrorActionPreference = 'Stop'

$reportRoot = Join-Path $PSScriptRoot 'pbip\OlistRetentionDashboard.Report'
$definitionRoot = Join-Path $reportRoot 'definition'
$page1 = '3b907662fe814f5aad31'
$page2 = '9af4b1d78c8e42c79d55'
$schema = 'https://developer.microsoft.com/json-schemas/fabric/item/report/definition/visualContainer/2.9.0/schema.json'

function Write-Utf8NoBom([string]$path, [string]$content) {
    $utf8NoBom = New-Object System.Text.UTF8Encoding($false)
    [System.IO.File]::WriteAllText($path, $content, $utf8NoBom)
}

function New-MeasureProjection([string]$table, [string]$measure, [string]$displayName = '') {
    $projection = [ordered]@{
        field = [ordered]@{ Measure = [ordered]@{ Expression = [ordered]@{ SourceRef = [ordered]@{ Entity = $table } }; Property = $measure } }
        queryRef = "$table.$measure"
        nativeQueryRef = $measure
    }
    if ($displayName) { $projection.displayName = $displayName }
    return $projection
}

function New-ColumnProjection([string]$table, [string]$column, [string]$displayName = '') {
    $projection = [ordered]@{
        field = [ordered]@{ Column = [ordered]@{ Expression = [ordered]@{ SourceRef = [ordered]@{ Entity = $table } }; Property = $column } }
        queryRef = "$table.$column"
        nativeQueryRef = $column
        active = $true
    }
    if ($displayName) { $projection.displayName = $displayName }
    return $projection
}

function New-TitleObject([string]$text, [string]$fontSize = '11D') {
    return [ordered]@{
        title = @([ordered]@{ properties = [ordered]@{
            show = [ordered]@{ expr = [ordered]@{ Literal = [ordered]@{ Value = 'true' } } }
            text = [ordered]@{ expr = [ordered]@{ Literal = [ordered]@{ Value = "'$text'" } } }
            fontSize = [ordered]@{ expr = [ordered]@{ Literal = [ordered]@{ Value = $fontSize } } }
        } })
    }
}

function Write-Visual([string]$page, [string]$name, [int]$x, [int]$y, [int]$width, [int]$height, [int]$z, [string]$type, $queryState, [string]$title = '', $sortDefinition = $null, $objects = $null) {
    $visual = [ordered]@{ visualType = $type }
    if ($null -ne $queryState) {
        $query = [ordered]@{ queryState = $queryState }
        if ($null -ne $sortDefinition) { $query.sortDefinition = $sortDefinition }
        $visual.query = $query
    }
    if ($null -ne $objects) { $visual.objects = $objects }
    if ($title) { $visual.visualContainerObjects = New-TitleObject $title }
    $visual.drillFilterOtherVisuals = $true

    $document = [ordered]@{
        '$schema' = $schema
        name = $name
        position = [ordered]@{ x = $x; y = $y; z = $z; height = $height; width = $width; tabOrder = $z }
        visual = $visual
    }

    $visualFolder = Join-Path $definitionRoot "pages\$page\visuals\$name"
    New-Item -ItemType Directory -Force -Path $visualFolder | Out-Null
    Write-Utf8NoBom (Join-Path $visualFolder 'visual.json') ($document | ConvertTo-Json -Depth 100)
}

function Write-Textbox([string]$page, [string]$name, [int]$x, [int]$y, [int]$width, [int]$height, [int]$z, [string]$text, [string]$fontSize, [string]$color, [string]$weight = 'normal') {
    $document = [ordered]@{
        '$schema' = $schema
        name = $name
        position = [ordered]@{ x = $x; y = $y; z = $z; height = $height; width = $width; tabOrder = $z }
        visual = [ordered]@{
            visualType = 'textbox'
            objects = [ordered]@{ general = @([ordered]@{ properties = [ordered]@{
                paragraphs = @([ordered]@{
                    horizontalTextAlignment = 'left'
                    textRuns = @([ordered]@{ value = $text; textStyle = [ordered]@{ fontFamily = 'Segoe UI'; fontSize = $fontSize; fontWeight = $weight; color = $color } })
                })
            } }) }
            drillFilterOtherVisuals = $true
        }
    }
    $visualFolder = Join-Path $definitionRoot "pages\$page\visuals\$name"
    New-Item -ItemType Directory -Force -Path $visualFolder | Out-Null
    Write-Utf8NoBom (Join-Path $visualFolder 'visual.json') ($document | ConvertTo-Json -Depth 100)
}

function Role($projection) { return [ordered]@{ projections = @($projection) } }
function Roles([object[]]$projections) { return [ordered]@{ projections = $projections } }
function MeasureField([string]$table, [string]$measure) { return (New-MeasureProjection $table $measure).field }
function ColumnField([string]$table, [string]$column) { return (New-ColumnProjection $table $column).field }

foreach ($page in @($page1, $page2)) {
    $visualRoot = Join-Path $definitionRoot "pages\$page\visuals"
    if (Test-Path $visualRoot) { Get-ChildItem -LiteralPath $visualRoot -Directory | Remove-Item -Recurse -Force }
    New-Item -ItemType Directory -Force -Path $visualRoot | Out-Null
}

# Executive Overview
Write-Textbox $page1 '10101010101010101010' 32 16 700 38 100 'Executive Overview' '22pt' '#172B4D' 'bold'
Write-Textbox $page1 '10101010101010101011' 32 52 950 28 101 'Eligible orders | Jan 2017-Aug 2018 | GMV includes item value and freight' '10pt' '#60748A'

$page1Cards = @(
    @('10101010101010101012', 32,   230, 'Monthly Revenue', 'Gross Order Value (GMV)', 'Gross Order Value'),
    @('10101010101010101013', 278,  230, 'Monthly Revenue', 'Orders', 'Orders'),
    @('10101010101010101014', 524,  230, 'Customers', 'Unique Customers', 'Unique Customers'),
    @('10101010101010101015', 770,  230, 'Monthly Revenue', 'Average Order Value', 'Average Order Value'),
    @('10101010101010101016', 1016, 232, 'Customers', 'Repeat Customer Share', 'Repeat Customer Share')
)
$cardObjects = [ordered]@{
    categoryLabels = @([ordered]@{ properties = [ordered]@{
        show = [ordered]@{ expr = [ordered]@{ Literal = [ordered]@{ Value = 'false' } } }
    } })
}
$z = 200
foreach ($card in $page1Cards) {
    $state = [ordered]@{ Data = Role (New-MeasureProjection $card[3] $card[4]) }
    Write-Visual $page1 $card[0] $card[1] 92 $card[2] 112 $z 'cardVisual' $state $card[5] $null $cardObjects
    $z++
}

$dateProjection = New-ColumnProjection 'Date' 'Year Month' 'Month'
$dateSort = [ordered]@{ sort = @([ordered]@{ field = (ColumnField 'Date' 'Year Month'); direction = 'Ascending' }); isDefaultSort = $true }
$gmvOrdersState = [ordered]@{
    Category = Role $dateProjection
    Y = Role (New-MeasureProjection 'Monthly Revenue' 'Gross Order Value (GMV)' 'GMV')
    Y2 = Role (New-MeasureProjection 'Monthly Revenue' 'Orders')
    Tooltips = Roles @(
        (New-MeasureProjection 'Monthly Revenue' 'Item Value'),
        (New-MeasureProjection 'Monthly Revenue' 'Freight'),
        (New-MeasureProjection 'Monthly Revenue' 'Payments'),
        (New-MeasureProjection 'Monthly Revenue' 'Monthly Purchasing Customers'),
        (New-MeasureProjection 'Monthly Revenue' 'Average Order Value'),
        (New-MeasureProjection 'Monthly Revenue' 'GMV Month-over-Month %')
    )
}
$chartObjects = [ordered]@{
    categoryAxis = @([ordered]@{ properties = [ordered]@{ fontSize = [ordered]@{ expr = [ordered]@{ Literal = [ordered]@{ Value = '10D' } } } } })
    valueAxis = @([ordered]@{ properties = [ordered]@{ fontSize = [ordered]@{ expr = [ordered]@{ Literal = [ordered]@{ Value = '10D' } } } } })
    legend = @([ordered]@{ properties = [ordered]@{ fontSize = [ordered]@{ expr = [ordered]@{ Literal = [ordered]@{ Value = '10D' } } } } })
}
Write-Visual $page1 '10101010101010101017' 32 220 792 292 300 'lineClusteredColumnComboChart' $gmvOrdersState 'Monthly GMV and Orders' $dateSort $chartObjects

$aovState = [ordered]@{ Category = Role $dateProjection; Y = Role (New-MeasureProjection 'Monthly Revenue' 'Average Order Value') }
Write-Visual $page1 '10101010101010101018' 32 528 792 160 301 'lineChart' $aovState 'Monthly Average Order Value' $dateSort $chartObjects

$repeatState = [ordered]@{
    Category = Role (New-ColumnProjection 'Customers' 'is_repeat_customer' 'Customer Type')
    Y = Role (New-MeasureProjection 'Customers' 'Unique Customers')
}
$donutObjects = [ordered]@{
    legend = @([ordered]@{ properties = [ordered]@{
        show = [ordered]@{ expr = [ordered]@{ Literal = [ordered]@{ Value = 'false' } } }
    } })
    labels = @([ordered]@{ properties = [ordered]@{
        fontSize = [ordered]@{ expr = [ordered]@{ Literal = [ordered]@{ Value = '10D' } } }
    } })
}
Write-Visual $page1 '10101010101010101019' 840 220 408 396 302 'donutChart' $repeatState 'Repeat Customer Distribution' $null $donutObjects
Write-Textbox $page1 '1010101010101010101a' 862 630 178 28 303 '● One-time customers' '10pt' '#1F7A8C' 'bold'
Write-Textbox $page1 '1010101010101010101b' 1042 630 182 28 304 '● Repeat customers' '10pt' '#E76F51' 'bold'

# Customer Retention & Experience
Write-Textbox $page2 '20202020202020202020' 32 16 760 38 100 'Customer Retention & Experience' '22pt' '#172B4D' 'bold'
Write-Textbox $page2 '20202020202020202021' 32 52 980 28 101 'Exact-month mature cohorts | RFM snapshot Sep 1, 2018 | Delivered-order experience' '10pt' '#60748A'

$page2Cards = @(
    @('20202020202020202022', 32,   190, 'Cohort Horizons', 'Month 1 Retention %', 'M1 Retention'),
    @('20202020202020202023', 234,  190, 'Cohort Horizons', 'Month 3 Retention %', 'M3 Retention'),
    @('20202020202020202024', 436,  190, 'Cohort Horizons', 'Month 6 Retention %', 'M6 Retention'),
    @('20202020202020202025', 638,  190, 'Cohort Horizons', 'Month 12 Retention %', 'M12 Retention'),
    @('20202020202020202026', 840,  190, 'Monthly Experience', 'Late Delivery Rate', 'Late Delivery Rate'),
    @('20202020202020202027', 1042, 206, 'Monthly Experience', 'Average Review Score', 'Average Review Score')
)
$z = 200
foreach ($card in $page2Cards) {
    $state = [ordered]@{ Data = Role (New-MeasureProjection $card[3] $card[4]) }
    Write-Visual $page2 $card[0] $card[1] 92 $card[2] 102 $z 'cardVisual' $state $card[5] $null $cardObjects
    $z++
}

$cohortState = [ordered]@{
    Rows = Role (New-ColumnProjection 'Cohort Retention' 'cohort_month' 'Cohort Month')
    Columns = Role (New-ColumnProjection 'Cohort Retention' 'month_number' 'Month Number')
    Values = Role (New-MeasureProjection 'Cohort Retention' 'Cohort Retention %' 'Retention')
}
$cohortObjects = [ordered]@{
    values = @(
        [ordered]@{ properties = [ordered]@{ fontSize = [ordered]@{ expr = [ordered]@{ Literal = [ordered]@{ Value = '9D' } } } } },
        [ordered]@{
            properties = [ordered]@{
                backColor = [ordered]@{ solid = [ordered]@{ color = [ordered]@{ expr = [ordered]@{
                    FillRule = [ordered]@{
                        Input = [ordered]@{ SelectRef = [ordered]@{ ExpressionName = 'Cohort Retention.Cohort Retention %' } }
                        FillRule = [ordered]@{ linearGradient3 = [ordered]@{
                            min = [ordered]@{ color = [ordered]@{ Literal = [ordered]@{ Value = "'#F6F8FB'" } }; value = [ordered]@{ Literal = [ordered]@{ Value = '0D' } } }
                            mid = [ordered]@{ color = [ordered]@{ Literal = [ordered]@{ Value = "'#A8DADC'" } }; value = [ordered]@{ Literal = [ordered]@{ Value = '0.003D' } } }
                            max = [ordered]@{ color = [ordered]@{ Literal = [ordered]@{ Value = "'#1F7A8C'" } }; value = [ordered]@{ Literal = [ordered]@{ Value = '0.01D' } } }
                            nullColoringStrategy = [ordered]@{ strategy = [ordered]@{ Literal = [ordered]@{ Value = "'noColor'" } } }
                        } }
                    }
                } } } }
            }
            selector = [ordered]@{
                data = @([ordered]@{ dataViewWildcard = [ordered]@{ matchingOption = 1 } })
                metadata = 'Cohort Retention.Cohort Retention %'
            }
        }
    )
    subTotals = @([ordered]@{ properties = [ordered]@{
        rowSubtotals = [ordered]@{ expr = [ordered]@{ Literal = [ordered]@{ Value = 'false' } } }
        columnSubtotals = [ordered]@{ expr = [ordered]@{ Literal = [ordered]@{ Value = 'false' } } }
    } })
    total = @([ordered]@{ properties = [ordered]@{
        rowTotal = [ordered]@{ expr = [ordered]@{ Literal = [ordered]@{ Value = 'false' } } }
        columnTotal = [ordered]@{ expr = [ordered]@{ Literal = [ordered]@{ Value = 'false' } } }
        rowGrandTotal = [ordered]@{ expr = [ordered]@{ Literal = [ordered]@{ Value = 'false' } } }
        columnGrandTotal = [ordered]@{ expr = [ordered]@{ Literal = [ordered]@{ Value = 'false' } } }
    } })
}
Write-Visual $page2 '20202020202020202028' 32 204 660 484 300 'pivotTable' $cohortState 'Exact-Month Cohort Retention Heatmap' $null $cohortObjects

$rfmSort = [ordered]@{ sort = @([ordered]@{ field = (MeasureField 'RFM Segments' 'RFM Customers'); direction = 'Descending' }); isDefaultSort = $true }
$rfmState = [ordered]@{
    Category = Role (New-ColumnProjection 'RFM Segments' 'rfm_segment' 'RFM Segment')
    Y = Role (New-MeasureProjection 'RFM Segments' 'RFM Customers' 'Customers')
    Tooltips = Roles @(
        (New-MeasureProjection 'RFM Segments' 'RFM Customer Share'),
        (New-MeasureProjection 'RFM Segments' 'RFM Orders'),
        (New-MeasureProjection 'RFM Segments' 'RFM Monetary Value')
    )
}
$rfmObjects = [ordered]@{
    categoryAxis = @([ordered]@{ properties = [ordered]@{
        fontSize = [ordered]@{ expr = [ordered]@{ Literal = [ordered]@{ Value = '10D' } } }
        maximumSize = [ordered]@{ expr = [ordered]@{ Literal = [ordered]@{ Value = '45D' } } }
    } })
    valueAxis = @([ordered]@{ properties = [ordered]@{ fontSize = [ordered]@{ expr = [ordered]@{ Literal = [ordered]@{ Value = '9D' } } } } })
}
Write-Visual $page2 '20202020202020202029' 708 204 540 250 301 'clusteredBarChart' $rfmState 'RFM Customer Segments - Sep 1, 2018' $rfmSort $rfmObjects

$experienceState = [ordered]@{
    Category = Role $dateProjection
    Y = Role (New-MeasureProjection 'Monthly Experience' 'Late Delivery Rate')
    Y2 = Role (New-MeasureProjection 'Monthly Experience' 'Average Review Score')
    Tooltips = Roles @(
        (New-MeasureProjection 'Monthly Experience' 'Delivered Orders'),
        (New-MeasureProjection 'Monthly Experience' 'Review Coverage %'),
        (New-MeasureProjection 'Monthly Experience' 'Average Delivery Days'),
        (New-MeasureProjection 'Monthly Experience' 'Average Delivery Delay Days'),
        (New-MeasureProjection 'Monthly Experience' 'Multiple-Review Orders')
    )
}
Write-Visual $page2 '2020202020202020202a' 708 470 540 218 302 'lineClusteredColumnComboChart' $experienceState 'Late Delivery and Review Score Trend' $dateSort $chartObjects

# Register the existing portfolio theme with the PBIR report.
$registeredResources = Join-Path $reportRoot 'StaticResources\RegisteredResources'
New-Item -ItemType Directory -Force -Path $registeredResources | Out-Null
Copy-Item (Join-Path $PSScriptRoot 'theme\olist_portfolio_theme.json') (Join-Path $registeredResources 'OlistPortfolio.json') -Force

$reportPath = Join-Path $definitionRoot 'report.json'
$report = Get-Content -Raw $reportPath | ConvertFrom-Json
$report.themeCollection.customTheme = [pscustomobject][ordered]@{
    name = 'Olist Portfolio'
    reportVersionAtImport = [ordered]@{ visual = '2.5.0'; report = '3.1.0'; page = '2.0.0' }
    type = 'RegisteredResources'
}
$report.resourcePackages = @(
    [pscustomobject][ordered]@{
        name = 'SharedResources'; type = 'SharedResources'; items = @(
            [ordered]@{ name = 'CY25SU12'; path = 'BaseThemes/CY25SU12.json'; type = 'BaseTheme' }
        )
    },
    [pscustomobject][ordered]@{
        name = 'RegisteredResources'; type = 'RegisteredResources'; items = @(
            [ordered]@{ name = 'Olist Portfolio'; path = 'OlistPortfolio.json'; type = 'CustomTheme' }
        )
    }
)
Write-Utf8NoBom $reportPath ($report | ConvertTo-Json -Depth 100)

Write-Output 'Created 23 editable PBIR visuals across two pages and registered the Olist Portfolio theme.'
