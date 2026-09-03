#Requires -Modules Microsoft.Graph.Authentication
#Requires -Modules Microsoft.Graph.Applications
#Requires -Modules Microsoft.PowerApps.Administration.PowerShell

<#
.SYNOPSIS
Exports active Copilot Studio agent Application IDs dynamically for GCC (not GCC High).

.DESCRIPTION
This script discovers Copilot Studio platform app registrations in Entra ID
(named like "<Agent Name> (Microsoft Copilot Studio)") and exports their
AgentName + ApplicationId to ActiveCopilotAgents.csv.

It does not rely on Get-AdminPowerAppCopilot. Instead, it uses Microsoft Graph
(app registrations + service principals), which works reliably in GCC where
Copilot admin cmdlets/endpoints may be unavailable.

This is read-only.
#>

[CmdletBinding()]
param(
    [string]$OutputPath = ".\ActiveCopilotAgents.csv",
    [string]$TenantId,
    [switch]$UseDeviceCode,
    [ValidateSet("Global","USGov","USGovDoD","China")]
    [string]$GraphEnvironment = "Global"
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function Normalize-Guid {
    param([string]$Value)

    if ([string]::IsNullOrWhiteSpace($Value)) { return $null }

    $guid = [Guid]::Empty
    if ([Guid]::TryParse($Value.Trim(), [ref]$guid)) {
        return $guid.ToString().ToLowerInvariant()
    }

    return $null
}

function Ensure-GraphModule {
    if (-not (Get-Module -ListAvailable -Name Microsoft.Graph.Applications)) {
        throw "Microsoft.Graph.Applications is required. Install with: Install-Module Microsoft.Graph -Scope CurrentUser"
    }
}

function Ensure-GraphConnection {
    param(
        [string]$Environment,
        [string]$TenantId,
        [switch]$UseDeviceCode
    )

    $requiredScopes = @("Application.Read.All","Directory.Read.All")
    $context = Get-MgContext -ErrorAction SilentlyContinue

    $missingScope = $true
    $tenantMatches = (-not $TenantId) -or ($context -and $context.TenantId -eq $TenantId)

    if ($context) {
        $missingScope = @($requiredScopes | Where-Object { $context.Scopes -notcontains $_ }).Count -gt 0
    }

    if (-not $context -or $missingScope -or $context.Environment -ne $Environment -or -not $tenantMatches) {
        $connectParams = @{
            Environment = $Environment
            Scopes      = $requiredScopes
            NoWelcome   = $true
        }
        if ($TenantId) { $connectParams["TenantId"] = $TenantId }

        if ($UseDeviceCode) {
            Connect-MgGraph @connectParams -UseDeviceCode
            return
        }

        try {
            Connect-MgGraph @connectParams
        } catch {
            Write-Warning "Interactive sign-in failed. Falling back to device code."
            Connect-MgGraph @connectParams -UseDeviceCode
        }
    }
}

Write-Host ""
Write-Host "==============================================="
Write-Host "Export Active Copilot Agents (GCC)"
Write-Host "==============================================="
Write-Host ""

Ensure-GraphModule
Import-Module Microsoft.Graph.Authentication
Import-Module Microsoft.Graph.Applications

Ensure-GraphConnection -Environment $GraphEnvironment -TenantId $TenantId -UseDeviceCode:$UseDeviceCode

$ctx = Get-MgContext
if ($ctx.Environment -ne "Global") {
    throw "This script is for GCC (moderate), which should use GraphEnvironment Global. Current: $($ctx.Environment)"
}

Write-Host "Connected to tenant: $($ctx.TenantId)"
Write-Host "Collecting Copilot Studio platform app registrations..."
Write-Host ""

$applicationProperties = "id,appId,displayName,createdDateTime"
$appCandidates = Get-MgApplication -All -Property $applicationProperties |
    Where-Object { $_.DisplayName -like "*(Microsoft Copilot Studio)" } |
    Sort-Object DisplayName

$results = foreach ($app in $appCandidates) {
    $normalizedAppId = Normalize-Guid -Value $app.AppId
    if (-not $normalizedAppId) { continue }

    # Keep only registrations that actually have a service principal in tenant
    $sp = Get-MgServicePrincipal `
        -Filter "appId eq '$($app.AppId)'" `
        -Property "id,appId,displayName,servicePrincipalType,accountEnabled" `
        -ConsistencyLevel eventual `
        -ErrorAction SilentlyContinue |
        Select-Object -First 1

    if (-not $sp) { continue }

    $agentName = $app.DisplayName -replace '\s*\(Microsoft Copilot Studio\)\s*$',''

    [PSCustomObject]@{
        AgentName      = $agentName
        ApplicationId  = $normalizedAppId
    }
}

$exportRows = @($results | Sort-Object AgentName, ApplicationId -Unique)

$resolvedOutputPath = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($OutputPath)
$exportRows | Export-Csv -LiteralPath $resolvedOutputPath -NoTypeInformation -Encoding UTF8

Write-Host "Generated: $resolvedOutputPath"
Write-Host "Rows exported: $($exportRows.Count)"
Write-Host ""