Here's a GitHub-ready README.md that describes both scripts and their purpose.

# Copilot Studio Identity Audit Toolkit

PowerShell tools for discovering, inventorying, and auditing Microsoft Copilot Studio identities in Microsoft Entra ID.

This toolkit helps administrators understand which App Registrations and Service Principals are associated with Copilot Studio agents and identify potentially orphaned identities that may remain after agents are deleted.

## Overview

Copilot Studio creates Microsoft Entra ID App Registrations and Service Principals to support authentication and integration scenarios. Over time, administrators may need to:

- Discover active Copilot Studio agents
- Inventory associated App Registrations
- Identify orphaned identities
- Validate cleanup after agent deletion
- Support governance and security reviews

This repository provides two PowerShell scripts that work together to accomplish those tasks.

---

# Scripts

## createactiveagentlist.ps1

### Purpose

Discovers active Copilot Studio agents by querying Microsoft Entra ID through Microsoft Graph and exports a list of agent Application IDs.

### What It Does

- Connects to Microsoft Graph
- Searches for App Registrations named:

```
<Agent Name> (Microsoft Copilot Studio)
```

- Verifies that a corresponding Service Principal exists
- Extracts:
  - Agent Name
  - Application ID
- Exports results to:

```text
ActiveCopilotAgents.csv
```

### Output

Example:

| AgentName | ApplicationId |
|------------|-------------|
| HR Assistant | 11111111-1111-1111-1111-111111111111 |
| IT Help Desk | 22222222-2222-2222-2222-222222222222 |

### Why It Matters

This script provides the authoritative list of currently active Copilot Studio agents and serves as the baseline for identifying orphaned App Registrations.

---

## CopilotStudioIdentityAudit.ps1

### Purpose

Inventories Copilot Studio-related App Registrations and Service Principals and compares them against active agents.

### What It Does

The script:

1. Imports the ActiveCopilotAgents.csv file.
2. Collects all App Registrations from Microsoft Entra ID.
3. Collects all Service Principals from Microsoft Entra ID.
4. Identifies possible Copilot Studio-related identities based on naming patterns:
   - Copilot
   - Agent
   - Bot
   - Power Virtual Agent
   - Microsoft Copilot Studio
5. Matches discovered identities against active agent Application IDs.
6. Flags identities that do not appear in the active agent list.
7. Generates inventory and governance reports.

### Generated Reports

#### CopilotStudioInventory.csv

Complete inventory of discovered Copilot Studio-related App Registrations.

Includes:

- Display Name
- Application ID
- Object ID
- Service Principal ID
- Active Agent Match
- Potential Orphan Status
- Created Date

---

#### PotentialOrphanedApps.csv

Lists App Registrations that appear to no longer be associated with an active Copilot Studio agent.

These require administrator review before deletion.

---

#### PotentialOrphanedServicePrincipals.csv

Lists Service Principals that appear to be disconnected from active agents.

Useful for cleanup and governance reviews.

---

#### CopilotStudioOrphanReport.html

A consolidated HTML report containing:

- Summary statistics
- Orphaned applications
- Orphaned service principals
- Inventory preview

Designed for sharing with security, identity, and governance teams.

---

# Workflow

## Step 1

Run:

```powershell
.\createactiveagentlist.ps1
```

This creates:

```text
ActiveCopilotAgents.csv
```

---

## Step 2

Run:

```powershell
.\CopilotStudioIdentityAudit.ps1
```

This compares active agents against all discovered identities.

---

## Step 3

Review:

```text
CopilotStudioInventory.csv
PotentialOrphanedApps.csv
PotentialOrphanedServicePrincipals.csv
CopilotStudioOrphanReport.html
```

---

# Requirements

## Microsoft Graph PowerShell

Required modules:

```powershell
Install-Module Microsoft.Graph.Authentication
Install-Module Microsoft.Graph.Applications
```

## Power Platform Administration

Required for some environments:

```powershell
Install-Module Microsoft.PowerApps.Administration.PowerShell
```

---

# Required Permissions

Microsoft Graph permissions:

```text
Application.Read.All
Directory.Read.All
AuditLog.Read.All
```

Administrative consent may be required depending on tenant configuration.

---

# Governance Use Cases

This toolkit can help:

- Validate Copilot Studio cleanup activities
- Identify orphaned App Registrations
- Support Entra ID governance reviews
- Prepare for security audits
- Investigate unexpected growth in App Registrations
- Understand Copilot Studio identity footprint

---

# Disclaimer

The orphan detection process is heuristic-based and should be considered an administrative review tool.

Always validate findings before removing App Registrations or Service Principals from production environments.


This README will look professional on GitHub and clearly explains how the two scripts work together to discover active Copilot Studio agents and identify potentially orphaned Entra ID identities.
