<#
.SYNOPSIS
    ProjectZomboidCollectionParser
    Parses a Steam Workshop Collection page and creates an HTML report.
    Generates a list of Workshop IDs suitable for Project Zomboid servers.
#>

param(
    [Parameter(Mandatory=$true, HelpMessage="Please enter the Steam Workshop Collection ID")]
    [string]$CollectionId
)

# --- CONFIGURATION ---

# Base URL for the workshop collections
$CollectionBaseUrl = "https://steamcommunity.com/workshop/filedetails/?id="

# Filename for the output HTML report
$timestamp = Get-Date -Format "yyyyMMdd-His"
$OutputFile = "$PSScriptRoot\ProjectZomboidCollectionReport_$timestamp.html"

# --- MAIN LOGIC ---

$url = "$CollectionBaseUrl$CollectionId"
Write-Host "Fetching Collection: $url ..." -ForegroundColor Cyan

try {
    $request = Invoke-WebRequest -Uri $url -Method Get -UseBasicParsing -ErrorAction Stop
    $content = $request.Content
}
catch {
    Write-Host "Error fetching collection page: $($_.Exception.Message)" -ForegroundColor Red
    Exit
}

# --- PARSING ---

# 1. Collection Name
# Search for <div id="detailsHeaderRight">...<div class="workshopItemTitle">Name</div>
$collectionNameMatch = [regex]::Match($content, '(?s)<div id="detailsHeaderRight">.*?<div class="workshopItemTitle">(.+?)</div>')
$collectionName = if ($collectionNameMatch.Success) { $collectionNameMatch.Groups[1].Value.Trim() } else { "Unknown Collection" }

Write-Host "Collection Name found: $collectionName" -ForegroundColor Green

# 2. Parse Children (Mods)
# Search for collection items directly using the 'collectionItem' class
# Pattern captures:
# Group 1: Mod URL
# Group 2: Workshop ID
# Group 3: Mod Title
$itemPattern = '(?s)class="collectionItem".*?<a href="([^"]+?id=(\d+))".*?<div class="workshopItemTitle">(.+?)</div>'
$matches = [regex]::Matches($content, $itemPattern)
$modItems = @()

foreach ($m in $matches) {
    $modUrl = $m.Groups[1].Value
    $workshopId = $m.Groups[2].Value
    $modTitle = $m.Groups[3].Value.Trim()

    $modItems += [PSCustomObject]@{
        WorkshopId = $workshopId
        ModTitle   = $modTitle
        Url        = $modUrl
    }
}

Write-Host "Found $($modItems.Count) mods in the collection." -ForegroundColor Cyan

# --- HTML GENERATION ---

$HtmlContent = @"
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <title>Project Zomboid Collection Report</title>
    <style>
        body { font-family: 'Segoe UI', Tahoma, Geneva, Verdana, sans-serif; background-color: #1b2838; color: #c7d5e0; padding: 20px; }
        h1 { color: #66c0f4; }
        h2 { color: #ffffff; font-size: 1.2em; margin-bottom: 20px; }
        table { width: 100%; border-collapse: collapse; margin-top: 20px; background-color: #2a475e; box-shadow: 0 0 10px rgba(0,0,0,0.5); }
        th, td { border: 1px solid #1b2838; padding: 12px; text-align: left; vertical-align: top; }
        th { background-color: #171a21; color: #66c0f4; font-weight: bold; }
        tr:nth-child(even) { background-color: #223a4f; }
        a { color: #66c0f4; text-decoration: none; }
        a:hover { text-decoration: underline; color: #ffffff; }
        .config-output { margin-top: 30px; background-color: #101214; padding: 15px; border: 1px solid #66c0f4; font-family: Consolas, monospace; }
        .config-label { color: #66c0f4; font-weight: bold; display: inline-block; width: 150px;}
        .config-value { color: #a3cf06; user-select: all; word-break: break-all; }
        .checkbox-col { text-align: center; width: 40px; }
        input[type="checkbox"] { transform: scale(1.5); cursor: pointer; }
    </style>
    <script>
        function updateConfig() {
            const checkboxes = document.querySelectorAll('.mod-checkbox:checked');
            const workshopIds = [];

            checkboxes.forEach(cb => {
                const wId = cb.getAttribute('data-workshop-id');
                if (wId) workshopIds.push(wId);
            });

            document.getElementById('config-workshop').innerText = workshopIds.join(';');
        }

        function toggleAll(source) {
            const checkboxes = document.querySelectorAll('.mod-checkbox');
            checkboxes.forEach(cb => cb.checked = source.checked);
            updateConfig();
        }
    </script>
</head>
<body>
    <h1>Project Zomboid Collection Report</h1>
    <h2>Collection: <a href="$url" target="_blank">$collectionName</a></h2>
    
    <table>
        <thead>
            <tr>
                <th class="checkbox-col"><input type="checkbox" onclick="toggleAll(this)" title="Select All" checked></th>
                <th>Collection Name</th>
                <th>Mod Title</th>
                <th>Workshop ID</th>
            </tr>
        </thead>
        <tbody>
"@

foreach ($item in $modItems) {
    $HtmlContent += @"
            <tr>
                <td class="checkbox-col">
                    <input type="checkbox" class="mod-checkbox" 
                           data-workshop-id="$($item.WorkshopId)" 
                           checked 
                           onchange="updateConfig()">
                </td>
                <td><a href="$url" target="_blank">$collectionName</a></td>
                <td>$($item.ModTitle)</td>
                <td><a href="$($item.Url)" target="_blank">$($item.WorkshopId)</a></td>
            </tr>
"@
}

# Generate Config String (WorkshopItems only)
$StringWorkshop = ($modItems.WorkshopId) -join ";"

$HtmlContent += @"
        </tbody>
    </table>

    <div class="config-output">
        <h3>PZ Server Config (servertest.ini)</h3>
        <div>
            <span class="config-label">WorkshopItems=</span>
            <span class="config-value" id="config-workshop">$StringWorkshop</span>
        </div>
        <p style="color: #888; font-size: 0.9em; margin-top: 10px;">
            <em>Note: 'Mods=' configuration is not available because this script only parses the collection page. 
            To get internal Mod IDs, visit the individual pages.</em>
        </p>
    </div>

    <p><small>Generated by Project Zomboid Collection Parser on: $(Get-Date)</small><br />
    <small>Build by: <a href="https://github.com/jvl1v5">jvl1v5</a></small></p>

</body>
</html>
"@

# Save and Open
$HtmlContent | Out-File -FilePath $OutputFile -Encoding UTF8
Write-Host "------------------------------------------------"
Write-Host "Done! Report created: $OutputFile" -ForegroundColor Green
Invoke-Item $OutputFile
