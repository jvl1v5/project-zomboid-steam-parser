<#
.SYNOPSIS
    ProjectZomboidModParser
    Parses Steam Workshop pages, creates an HTML report with tag highlighting, 
    and generates config lines for Project Zomboid servers.
    Reads IDs from an external file (PZ_Mod_IDs.txt).
#>

# --- CONFIGURATION ---

# Base URL for the workshop items
# You can change this if the URL structure changes or for different Steam games
$BaseUrl = "https://steamcommunity.com/sharedfiles/filedetails/?id="

# Path to the input file (located in the same folder as the script); semicolon-separated list of Workshop IDs
$InputFile = "$PSScriptRoot\PZ_Mod_IDs.txt"

# Filename for the output HTML report
$timestamp = Get-Date -Format "yyyyMMdd-His"
$OutputFile = "$PSScriptRoot\ProjectZomboidModReport_$timestamp.html"

# Throttling in seconds (Randomized wait time between requests to avoid bans)
$ThrottleSecondsMin = 5
$ThrottleSecondsMax = 15

# Retry Configuration (Wait time in case of too many requests)
$RetriesMax = 5
$RetryPauseSeconds = 30
$MaxConsecutiveErrors = 3

# Comma-separated list of tags to highlight with a green checkmark
$SearchTags = @(       
    "Build 42"
)

# --- INPUT PREPARATION ---

# Check if input file exists, otherwise create a dummy file
if (-not (Test-Path $InputFile)) {
    Write-Warning "File 'PZ_Mod_IDs.txt' not found. Creating a sample file..."
    # Example IDs (Project Zomboid Mods)
    "2890530068;2460351205" | Out-File $InputFile -Encoding UTF8
    Write-Host "Please enter your IDs into 'PZ_Mod_IDs.txt' and restart the script." -ForegroundColor Yellow
    Exit
}

# Read IDs: Remove newlines and split by semicolon
$RawContent = Get-Content $InputFile -Raw
$SteamIDs = $RawContent -replace "`r`n", "" -replace "`n", "" -split ";" | 
            ForEach-Object { $_.Trim() } | 
            Where-Object { -not [string]::IsNullOrWhiteSpace($_) }

# Arrays for the summary (servertest.ini)
$CollectedModIds = @()
$CollectedSearchIds = @()

Write-Host "Starting Project Zomboid Mod Parser..." -ForegroundColor Cyan
Write-Host "IDs found: $($SteamIDs.Count)" -ForegroundColor Gray

# HTML Header
$HtmlContent = @"
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <title>Project Zomboid Mod Report</title>
    <style>
        body { font-family: 'Segoe UI', Tahoma, Geneva, Verdana, sans-serif; background-color: #1b2838; color: #c7d5e0; padding: 20px; }
        h1 { color: #66c0f4; }
        table { width: 100%; border-collapse: collapse; margin-top: 20px; background-color: #2a475e; box-shadow: 0 0 10px rgba(0,0,0,0.5); }
        th, td { border: 1px solid #1b2838; padding: 12px; text-align: left; vertical-align: top; }
        th { background-color: #171a21; color: #66c0f4; font-weight: bold; }
        tr:nth-child(even) { background-color: #223a4f; }
        a { color: #66c0f4; text-decoration: none; }
        a:hover { text-decoration: underline; color: #ffffff; }
        .details-block { font-size: 0.9em; }
        .details-block img { display: none; } /* Hide images in details to save space */
        /* Remove default link styling inside details block since we stripped tags, but just in case */
        .details-block a { pointer-events: none; cursor: default; text-decoration: none; color: inherit; }
        .config-output { margin-top: 30px; background-color: #101214; padding: 15px; border: 1px solid #66c0f4; font-family: Consolas, monospace; }
        .config-label { color: #66c0f4; font-weight: bold; display: inline-block; width: 150px;}
        .config-value { color: #a3cf06; user-select: all; word-break: break-all; } /* user-select: all makes copying easier */
        .tag-match { color: #4cff00; font-weight: bold; margin-left: 5px; }
        .checkbox-col { text-align: center; width: 40px; }
        input[type="checkbox"] { transform: scale(1.5); cursor: pointer; }
    </style>
    <script>
        function updateConfig() {
            const checkboxes = document.querySelectorAll('.mod-checkbox:checked');
            const modIds = [];
            const workshopIds = [];

            checkboxes.forEach(cb => {
                const mId = cb.getAttribute('data-mod-id');
                const wId = cb.getAttribute('data-workshop-id');
                
                if (mId && mId !== 'not found' && mId !== 'Mod page not found') modIds.push(mId);
                if (wId && wId.match(/^\d+$/)) workshopIds.push(wId);
            });

            document.getElementById('config-mods').innerText = modIds.join(';');
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
    <h1>Project Zomboid Mod Report</h1>
    <table>
        <thead>
            <tr>
                <th class="checkbox-col"><input type="checkbox" onclick="toggleAll(this)" title="Select All"></th>
                <th>Workshop Link (Search-ID)</th>
                <th>Workshop ID</th>
                <th>Mod ID</th>
                <th>Tags / Details</th>
            </tr>
        </thead>
        <tbody>
"@

# --- MAIN LOOP ---

$consecutiveErrorCount = 0
$counter = 1

foreach ($id in $SteamIDs) {
    # Construct URL using the variable
    $url = "$BaseUrl$id"
    Write-Host "$counter. Processing ID: $id ..." -NoNewline

    $success = $false
    $lastError = $null
    
    # Init vars to avoid scope issues if try fails immediately
    $workshopId = "not found"
    $modId = "not found"
    $rightDetails = ""

    for ($attempt = 1; $attempt -le $RetriesMax; $attempt++) {
        try {
            if ($attempt -gt 1) {
                Write-Host " [Retry $attempt/$RetriesMax] ..." -NoNewline
            }

            $request = Invoke-WebRequest -Uri $url -Method Get -UseBasicParsing -ErrorAction Stop
            $content = $request.Content

            # --- PARSING ---

            # Check for invalid/hidden page first
            if ($content -match '<div class="error_ctn">') {
                $workshopId = "Mod page not found"
                $modId = "Mod page not found"
                $rightDetails = "Mod page not found"
            }
            else {
                # 1. Workshop ID
                $workshopIdMatch = [regex]::Match($content, 'Workshop ID[^:]*:\s*(\d+)')
                $workshopId = if ($workshopIdMatch.Success) { $workshopIdMatch.Groups[1].Value } else { "not found" }

                # 2. Mod ID (Capture ALL occurrences)
                $modIdMatches = [regex]::Matches($content, 'Mod ID[^:]*:\s*([^\s<]+)')
                if ($modIdMatches.Count -gt 0) {
                    $modId = ($modIdMatches | ForEach-Object { $_.Groups[1].Value }) -join ";"
                }
                else {
                    $modId = "not found"
                }

                # 3. Details (Tags etc.)
                $detailsMatch = [regex]::Match($content, '(?s)<div class="rightDetailsBlock">(.+?)</div>')
                $rightDetails = if ($detailsMatch.Success) { $detailsMatch.Groups[1].Value } else { "No Details Found" }
            }

            # --- CLEANUP & HIGHLIGHTING ---
            
            # Remove HTML Links (<a> tags) but keep the text inside
            $rightDetails = $rightDetails -replace '<a[^>]*>', '' -replace '</a>', ''

            # Checks if any configured tag exists in the text and appends a checkmark
            $foundTag = $false
            foreach ($tag in $SearchTags) {
                # Regex escape to ensure special chars in tags don't break regex
                $safeTag = [regex]::Escape($tag)
                
                # Replace:
                # (?i) = case insensitive
                # \b = word boundary (so "Map" doesn't match "Mapping")
                # ($safeTag) = Capture group 1 (the text found)
                # Replacement: '$1 ...' puts the found text back, followed by the span
                if ($rightDetails -match "(?i)\b$safeTag\b") {
                    $foundTag = $true
                    $rightDetails = $rightDetails -replace "(?i)\b($safeTag)\b", '$1 <span class="tag-match">&#10004;</span>'
                }
            }

            $success = $true
            $consecutiveErrorCount = 0
            break # Exit retry loop
        }
        catch {
            $lastError = $_
            if ($attempt -lt $RetriesMax) {
                Write-Host " [Error]" -ForegroundColor Yellow
                Write-Host "   -> Waiting $RetryPauseSeconds seconds before retry..." -ForegroundColor DarkGray
                Start-Sleep -Seconds $RetryPauseSeconds
                Write-Host "   -> Resuming ID: $id ..." -NoNewline
            }
        }
    }

    if ($success) {
        # --- COLLECT DATA ---
        # Determine checked state
        $checkedAttr = if ($foundTag) { "checked" } else { "" }

        # Only add to collection if checked (found tag)
        if ($foundTag) {
            if ($modId -ne "not found" -and $modId -ne "Mod page not found") { $CollectedModIds += $modId }
            if ($id -match '^\d+$') { $CollectedSearchIds += $id }
        }

        # --- HTML ROW ---
        $HtmlContent += @"
            <tr>
                <td class="checkbox-col">
                    <input type="checkbox" class="mod-checkbox" 
                           data-mod-id="$modId" 
                           data-workshop-id="$workshopId" 
                           $checkedAttr 
                           onchange="updateConfig()">
                </td>
                <td><a href="$url" target="_blank">$id</a></td>
                <td>$workshopId</td>
                <td>$modId</td>
                <td class="details-block">$rightDetails</td>
            </tr>
"@
        Write-Host " [OK]" -ForegroundColor Green
    }
    else {
        # Failed after all retries
        $consecutiveErrorCount++
        Write-Host " [FAILED]" -ForegroundColor Red
        Write-Host "   Reason: $($lastError.Exception.Message)" -ForegroundColor Red
        
        $HtmlContent += @"
            <tr>
                <td class="checkbox-col">
                    <input type="checkbox" disabled>
                </td>
                <td><a href="$url" target="_blank">$id</a></td>
                <td colspan="3" style="color: #ff4c4c;">Error: $($lastError.Exception.Message)</td>
            </tr>
"@

        if ($consecutiveErrorCount -ge $MaxConsecutiveErrors) {
            Write-Host "`nCRITICAL: $MaxConsecutiveErrors consecutive errors occurred. Aborting script to prevent bans or further issues." -ForegroundColor Red
            Write-Host "Press any key to exit..."
            $null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
            Exit
        }
    }

    # Throttling
    if ($id -ne $SteamIDs[-1]) { 
        $delay = Get-Random -Minimum $ThrottleSecondsMin -Maximum ($ThrottleSecondsMax + 1)
        Write-Host " - Throttling $delay seconds" -NoNewline
        Start-Sleep -Seconds $delay 
        Write-Host "" # Newline
    }
    $counter++
}

# --- SERVER CONFIG STRINGS (PZ FORMAT) ---

$StringMods = $CollectedModIds -join ";"
$StringWorkshop = $CollectedSearchIds -join ";"

$HtmlContent += @"
        </tbody>
    </table>

    <div class="config-output">
        <h3>PZ Server Config (servertest.ini)</h3>
        <div>
            <span class="config-label">Mods=</span>
            <span class="config-value" id="config-mods">$StringMods</span>
        </div>
        <br>
        <div>
            <span class="config-label">WorkshopItems=</span>
            <span class="config-value" id="config-workshop">$StringWorkshop</span>
        </div>
    </div>

    <p><small>Generated by Project Zomboid Mod Parser on: $(Get-Date)</small><br />
    <small>Build by: <a href="https://github.com/jvl1v5">jvl1v5</a></small></p>

</body>
</html>
"@

# Save and Open
$HtmlContent | Out-File -FilePath $OutputFile -Encoding UTF8
Write-Host "------------------------------------------------"
Write-Host "Done! Report created: $OutputFile" -ForegroundColor Green
Invoke-Item $OutputFile

pause
