param(
    [string]$UnityScenePath = 'BTech Simulator/Assets/Scenes/InitialHostel.unity',
    [string]$OutputJsonPath = 'b-tech-simulator/tests/reports/initial_hostel_extract.json'
)

if (!(Test-Path $UnityScenePath)) { throw "Unity scene not found: $UnityScenePath" }

$lines = Get-Content $UnityScenePath
$records = @()
$current = [ordered]@{}

foreach ($line in $lines) {
    if ($line -match '^--- !u!') {
        if ($current.Contains('name')) {
            $records += [PSCustomObject]$current
        }
        $current = [ordered]@{}
        continue
    }

    if ($line -match '^\s*m_Name:\s*(.+)$') { $current['name'] = $Matches[1].Trim() }
    if ($line -match '^\s*propertyPath:\s*m_LocalPosition\.x$') { $current['pending'] = 'x' }
    if ($line -match '^\s*propertyPath:\s*m_LocalPosition\.y$') { $current['pending'] = 'y' }
    if ($line -match '^\s*propertyPath:\s*m_LocalPosition\.z$') { $current['pending'] = 'z' }
    if ($line -match '^\s*value:\s*(-?\d+(\.\d+)?)$' -and $current.Contains('pending')) {
        $axis = $current['pending']
        $current[$axis] = [double]$Matches[1]
        $current.Remove('pending')
    }
}

if ($current.Contains('name')) { $records += [PSCustomObject]$current }

$interestingNames = @('Camera1','Camera2','full-room','bunkbed','curtains','mirror','hostel floor','SwitchCamera','Player')
$filtered = $records | Where-Object { $interestingNames -contains $_.name }

$outDir = Split-Path -Parent $OutputJsonPath
if (!(Test-Path $outDir)) { New-Item -ItemType Directory -Force $outDir | Out-Null }
$filtered | ConvertTo-Json -Depth 5 | Set-Content -Path $OutputJsonPath
Write-Output "Wrote scene extract: $OutputJsonPath (records: $($filtered.Count))"
