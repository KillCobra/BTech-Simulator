param(
    [ValidateSet('audit','fix')]
    [string]$Mode = 'audit',
    [string]$UnityRoot = 'BTech Simulator',
    [string]$GodotRoot = 'b-tech-simulator'
)

$unityImported = Join-Path $UnityRoot 'Assets/IMPORTED'
$godotImported = Join-Path $GodotRoot 'assets/imported'

if (!(Test-Path $unityImported)) { throw "Unity imported path not found: $unityImported" }
if (!(Test-Path $godotImported)) { throw "Godot imported path not found: $godotImported" }

function Get-RelativeList([string]$basePath, [string]$excludeExt) {
    $base = (Resolve-Path $basePath).Path
    Get-ChildItem -Recurse -File $basePath |
        Where-Object { $_.Extension -ne $excludeExt } |
        ForEach-Object { $_.FullName.Replace($base + '\','') }
}

$unityAssets = Get-RelativeList $unityImported '.meta'
$godotAssets = Get-RelativeList $godotImported '.import'

$missingInGodot = Compare-Object -ReferenceObject $unityAssets -DifferenceObject $godotAssets -PassThru |
    Where-Object { $_.SideIndicator -eq '<=' }

$extraInGodot = Compare-Object -ReferenceObject $unityAssets -DifferenceObject $godotAssets -PassThru |
    Where-Object { $_.SideIndicator -eq '=>' }

$expectedScripts = @(
    'scripts/autoload/game_manager.gd',
    'scripts/autoload/game_state.gd',
    'scripts/autoload/scene_loader.gd',
    'scripts/autoload/save_system.gd',
    'scripts/autoload/time_of_day_manager.gd',
    'scripts/player/player_controller.gd',
    'scripts/player/player_interact.gd',
    'scripts/player/camera_manager.gd'
)

$missingScripts = $expectedScripts | Where-Object { -not (Test-Path (Join-Path $GodotRoot $_)) }

$projectPath = Join-Path $GodotRoot 'project.godot'
$projectText = if (Test-Path $projectPath) { Get-Content $projectPath -Raw } else { '' }
$requiredActions = @(
    'move_up','move_down','move_left','move_right','look','attack','interact','crouch',
    'jump','previous','next','sprint','camera_switch','ui_up','ui_down','ui_left','ui_right','ui_accept','ui_cancel'
)
$missingActions = $requiredActions | Where-Object { $projectText -notmatch "(?m)^$($_)=" }

$sceneChecks = @(
    'scenes/sample_scene.tscn',
    'scenes/initial_hostel.tscn'
) | ForEach-Object {
    $path = Join-Path $GodotRoot $_
    [PSCustomObject]@{ Scene = $_; Exists = (Test-Path $path) }
}

if ($Mode -eq 'fix') {
    foreach ($rel in $missingInGodot) {
        $src = Join-Path $unityImported $rel
        $dst = Join-Path $godotImported $rel
        $dstDir = Split-Path -Parent $dst
        if (!(Test-Path $dstDir)) { New-Item -ItemType Directory -Force $dstDir | Out-Null }
        Copy-Item -LiteralPath $src -Destination $dst -Force
    }
}

$reportDir = Join-Path $GodotRoot 'tests/reports'
if (!(Test-Path $reportDir)) { New-Item -ItemType Directory -Force $reportDir | Out-Null }

$report = [PSCustomObject]@{
    timestamp = (Get-Date).ToString('s')
    mode = $Mode
    unity_asset_count = $unityAssets.Count
    godot_asset_count = $godotAssets.Count
    missing_assets_in_godot = @($missingInGodot)
    extra_assets_in_godot = @($extraInGodot)
    missing_expected_scripts = @($missingScripts)
    missing_input_actions = @($missingActions)
    scene_files = $sceneChecks
}

$reportPath = Join-Path $reportDir 'migration_audit.json'
$report | ConvertTo-Json -Depth 6 | Set-Content -Path $reportPath

Write-Output "Wrote audit report: $reportPath"
Write-Output "Missing assets in Godot: $($missingInGodot.Count)"
Write-Output "Missing scripts: $($missingScripts.Count)"
Write-Output "Missing input actions: $($missingActions.Count)"
