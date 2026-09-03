#Requires -Modules Microsoft.Graph.Authentication
#Requires -Modules Microsoft.Graph.Applications

[CmdletBinding()]
param(
    [string]$ActiveAgentsCsv = ".\ActiveCopilotAgents.csv",
    [string]$OutputFolder = ".\CopilotStudioAudit"
)

$ErrorActionPreference = "Stop"

Write-Host ""
Write-Host "==============================================="
Write-Host "Copilot Studio App Registration Audit"
Write-Host "==============================================="
Write-Host ""

if (-not (Test-Path -LiteralPath $OutputFolder)) {
    New-Item -Path $OutputFolder -ItemType Directory | Out-Null
}

Write-Host "Connecting to Microsoft Graph..."
Connect-MgGraph -Scopes @(
    "Application.Read.All",
    "Directory.Read.All",
    "AuditLog.Read.All"
) | Out-Null
Write-Host "Connected."
Write-Host ""

if (-not (Test-Path -LiteralPath $ActiveAgentsCsv)) {
    throw "Cannot find file: $ActiveAgentsCsv"
}

Write-Host "Loading active Copilot Studio agents..."
$ActiveAgents = Import-Csv -Path $ActiveAgentsCsv

# Normalize and deduplicate known Application IDs from CSV
$KnownAgentIds = $ActiveAgents |
    ForEach-Object { $_.ApplicationId } |
    Where-Object { -not [string]::IsNullOrWhiteSpace($_) } |
    ForEach-Object { $_.Trim().ToLowerInvariant() } |
    Sort-Object -Unique

Write-Host "Active agents loaded: $($ActiveAgents.Count)"
Write-Host ""

Write-Host "Collecting App Registrations..."
$Applications = Get-MgApplication -All
Write-Host "App Registrations found: $($Applications.Count)"
Write-Host ""

Write-Host "Collecting Service Principals..."
$ServicePrincipals = Get-MgServicePrincipal -All
Write-Host "Service Principals found: $($ServicePrincipals.Count)"
Write-Host ""

# Heuristics for likely Copilot Studio-related identities
$NameRegex = '(?i)(copilot|agent|bot|power virtual agent|microsoft copilot studio)'

$CopilotApps = $Applications | Where-Object {
    $_.DisplayName -match $NameRegex
}

$CopilotSPs = $ServicePrincipals | Where-Object {
    $_.DisplayName -match $NameRegex
}

Write-Host "Potential Copilot Studio App Registrations : $($CopilotApps.Count)"
Write-Host "Potential Copilot Studio Service Principals : $($CopilotSPs.Count)"
Write-Host ""

# Speed up joins using hashtables
$SpByAppId = @{}
foreach ($sp in $CopilotSPs) {
    if (-not [string]::IsNullOrWhiteSpace($sp.AppId)) {
        $key = $sp.AppId.Trim().ToLowerInvariant()
        if (-not $SpByAppId.ContainsKey($key)) {
            $SpByAppId[$key] = $sp
        }
    }
}

$KnownIdSet = @{}
foreach ($id in $KnownAgentIds) { $KnownIdSet[$id] = $true }

$Inventory = foreach ($app in $CopilotApps) {
    $appIdKey = if ([string]::IsNullOrWhiteSpace($app.AppId)) { "" } else { $app.AppId.Trim().ToLowerInvariant() }
    $sp = if ($SpByAppId.ContainsKey($appIdKey)) { $SpByAppId[$appIdKey] } else { $null }
    $isMapped = $KnownIdSet.ContainsKey($appIdKey)

    [PSCustomObject]@{
        DisplayName         = $app.DisplayName
        ApplicationId       = $app.AppId
        ObjectId            = $app.Id
        HasServicePrincipal = [bool]$sp
        ServicePrincipalId  = if ($sp) { $sp.Id } else { $null }
        ActiveAgentMatch    = $isMapped
        PotentialOrphan     = -not $isMapped
        CreatedDateTime     = $app.CreatedDateTime
    }
}

$OrphanedApps = $Inventory | Where-Object { $_.PotentialOrphan -eq $true }

$OrphanedSPs = $CopilotSPs |
    Where-Object {
        $spKey = if ([string]::IsNullOrWhiteSpace($_.AppId)) { "" } else { $_.AppId.Trim().ToLowerInvariant() }
        -not $KnownIdSet.ContainsKey($spKey)
    } |
    Select-Object DisplayName, AppId, Id, ServicePrincipalType

# Export CSVs
$Inventory |
    Sort-Object DisplayName |
    Export-Csv -Path (Join-Path $OutputFolder "CopilotStudioInventory.csv") -NoTypeInformation -Encoding UTF8

$OrphanedApps |
    Sort-Object DisplayName |
    Export-Csv -Path (Join-Path $OutputFolder "PotentialOrphanedApps.csv") -NoTypeInformation -Encoding UTF8

$OrphanedSPs |
    Sort-Object DisplayName |
    Export-Csv -Path (Join-Path $OutputFolder "PotentialOrphanedServicePrincipals.csv") -NoTypeInformation -Encoding UTF8

# HTML report
$style = @"
<style>
body { font-family: Segoe UI, Arial, sans-serif; margin: 24px; }
h1, h2 { color: #1f1f1f; }
table { border-collapse: collapse; width: 100%; margin-bottom: 24px; }
th { background-color: #0078D4; color: white; text-align: left; }
th, td { border: 1px solid #cccccc; padding: 6px; font-size: 12px; }
.summary li { margin-bottom: 4px; }
</style>
"@

$summary = @"
<h1>Copilot Studio Identity Audit</h1>
<p>Generated: $(Get-Date -Format "yyyy-MM-dd HH:mm:ss zzz")</p>
<h2>Summary</h2>
<ul class='summary'>
  <li>Active Agents: $($ActiveAgents.Count)</li>
  <li>Candidate App Registrations: $($CopilotApps.Count)</li>
  <li>Candidate Service Principals: $($CopilotSPs.Count)</li>
  <li>Potential Orphaned Apps: $($OrphanedApps.Count)</li>
  <li>Potential Orphaned Service Principals: $($OrphanedSPs.Count)</li>
</ul>
"@

$orphanAppsTable = if ($OrphanedApps.Count -gt 0) {
    $OrphanedApps |
        Sort-Object DisplayName |
        Select-Object DisplayName, ApplicationId, ObjectId, HasServicePrincipal, ServicePrincipalId, CreatedDateTime |
        ConvertTo-Html -Fragment -PreContent "<h2>Potential Orphaned Applications</h2>"
} else {
    "<h2>Potential Orphaned Applications</h2><p>None found.</p>"
}

$orphanSPsTable = if ($OrphanedSPs.Count -gt 0) {
    $OrphanedSPs |
        Sort-Object DisplayName |
        ConvertTo-Html -Fragment -PreContent "<h2>Potential Orphaned Service Principals</h2>"
} else {
    "<h2>Potential Orphaned Service Principals</h2><p>None found.</p>"
}

$inventoryPreview = if ($Inventory.Count -gt 0) {
    $Inventory |
        Sort-Object DisplayName |
        Select-Object -First 100 DisplayName, ApplicationId, ActiveAgentMatch, PotentialOrphan, HasServicePrincipal |
        ConvertTo-Html -Fragment -PreContent "<h2>Inventory Preview (first 100)</h2>"
} else {
    "<h2>Inventory Preview</h2><p>No candidate applications found.</p>"
}

$fullHtml = ConvertTo-Html -Title "Copilot Studio Orphan Report" -Head $style -Body @(
    $summary
    $orphanAppsTable
    $orphanSPsTable
    $inventoryPreview
)

$reportPath = Join-Path $OutputFolder "CopilotStudioOrphanReport.html"
$fullHtml | Out-File -FilePath $reportPath -Encoding UTF8

Write-Host ""
Write-Host "==============================================="
Write-Host "Audit Complete"
Write-Host "==============================================="
Write-Host ""
Write-Host "Reports Generated:"
Write-Host ""
Write-Host (Join-Path $OutputFolder "CopilotStudioInventory.csv")
Write-Host (Join-Path $OutputFolder "PotentialOrphanedApps.csv")
Write-Host (Join-Path $OutputFolder "PotentialOrphanedServicePrincipals.csv")
Write-Host (Join-Path $OutputFolder "CopilotStudioOrphanReport.html")
Write-Host ""

$OrphanedApps |
    Sort-Object DisplayName |
    Select-Object DisplayName, ApplicationId, PotentialOrphan |
    Format-Table -AutoSize