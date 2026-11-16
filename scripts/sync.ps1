<#
.SYNOPSIS
    Valheim mod sync for Windows.

.DESCRIPTION
    Fetches the shared manifest (mods.json) from GitHub and makes the local
    BepInEx install match it exactly: same mods, same versions, verified by
    SHA256. Mods that are no longer in the manifest are moved to
    BepInEx\plugins-disabled instead of being deleted.

.PARAMETER ValheimDir
    Game folder containing valheim.exe. Auto-detected from Steam when omitted.

.PARAMETER ManifestUrl
    Override the manifest URL.

.EXAMPLE
    powershell -ExecutionPolicy Bypass -File scripts\sync.ps1
#>
param(
    [string]$ValheimDir = "",
    [string]$ManifestUrl = "",
    [switch]$Quiet
)

$DefaultManifestUrl = "https://qinminbao.com/valheim/mods.json"
$FallbackManifestUrl = "https://raw.githubusercontent.com/zengjunzhe/valheim-mod-sync/main/mods.json"
$PackageBaseUrl = "https://qinminbao.com/valheim/packages"
$FallbackPackageBaseUrl = "https://thunderstore.io/package/download"
if (-not $ManifestUrl) {
    $repoRoot = Split-Path -Parent $PSScriptRoot
    $mirrorFile = Join-Path $repoRoot "mirror.txt"
    if (Test-Path $mirrorFile) {
        $ManifestUrl = (Get-Content -Path $mirrorFile -TotalCount 1).Trim()
    }
}
if (-not $ManifestUrl) { $ManifestUrl = $DefaultManifestUrl }

$ErrorActionPreference = "Stop"
$ProgressPreference = "SilentlyContinue"
try { [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12 } catch { }

function Write-Info([string]$Message) {
    if (-not $Quiet) { Write-Host $Message }
}

function Stop-WithError([string]$Message) {
    Write-Host "ERROR: $Message" -ForegroundColor Red
    exit 1
}

function Resolve-ValheimDir {
    param([string]$Explicit)

    $candidates = New-Object System.Collections.Generic.List[string]
    if ($Explicit) { [void]$candidates.Add($Explicit) }

    $steamPath = $null
    try {
        $steamPath = (Get-ItemProperty -Path "HKCU:\Software\Valve\Steam" -Name SteamPath -ErrorAction Stop).SteamPath
    } catch { }

    if ($steamPath) {
        [void]$candidates.Add((Join-Path $steamPath "steamapps\common\Valheim"))
        $vdf = Join-Path $steamPath "steamapps\libraryfolders.vdf"
        if (Test-Path $vdf) {
            foreach ($line in Get-Content -Path $vdf) {
                if ($line -match '"path"\s+"([^"]+)"') {
                    $lib = $Matches[1] -replace '\\\\', '\'
                    [void]$candidates.Add((Join-Path $lib "steamapps\common\Valheim"))
                }
            }
        }
    }

    [void]$candidates.Add("C:\Program Files (x86)\Steam\steamapps\common\Valheim")
    [void]$candidates.Add("C:\Program Files\Steam\steamapps\common\Valheim")

    foreach ($candidate in $candidates) {
        if ([string]::IsNullOrWhiteSpace($candidate)) { continue }
        if (Test-Path (Join-Path $candidate "valheim.exe")) { return $candidate }
    }
    return $null
}

function Get-PackageFile {
    param(
        [string]$Namespace,
        [string]$Name,
        [string]$Version,
        [string]$OutFile,
        [string]$Sha256
    )

    $urls = @(
        "$PackageBaseUrl/$Namespace-$Name-$Version.zip",
        "$FallbackPackageBaseUrl/$Namespace/$Name/$Version/"
    )

    foreach ($url in $urls) {
        try {
            Invoke-WebRequest -Uri $url -OutFile $OutFile -UseBasicParsing
            $actual = (Get-FileHash -Path $OutFile -Algorithm SHA256).Hash.ToLowerInvariant()
            if ($actual -eq $Sha256.ToLowerInvariant()) { return }
        } catch { }
    }
    throw "Failed to download $Namespace-$Name $Version (hash mismatch or network)"
}

$V = Resolve-ValheimDir -Explicit $ValheimDir
if (-not $V) {
    Stop-WithError "Valheim not found. Pass -ValheimDir 'D:\Steam\steamapps\common\Valheim'."
}

if (Get-Process -Name "valheim" -ErrorAction SilentlyContinue) {
    Stop-WithError "Close Valheim before syncing."
}

$ts = [DateTimeOffset]::UtcNow.ToUnixTimeSeconds()
$manifest = $null
$manifestErr = $null
foreach ($url in @($ManifestUrl, $FallbackManifestUrl)) {
    if (-not $url) { continue }
    try {
        $manifest = Invoke-RestMethod -Uri "$url`?ts=$ts" -UseBasicParsing
        break
    } catch {
        $manifestErr = $_.Exception.Message
    }
}
if (-not $manifest) {
    Stop-WithError "Failed to fetch manifest: $manifestErr"
}

$tmp = Join-Path $env:TEMP ("valheim-mod-sync-" + [Guid]::NewGuid().ToString("N"))
New-Item -ItemType Directory -Path $tmp -Force | Out-Null

$exitCode = 0
try {
    # ---------- BepInEx ----------
    $pack = $manifest.bepinex
    $packId = "$($pack.namespace)-$($pack.name)"
    $markerPath = Join-Path $V "BepInEx\.mod-sync-bepinex"
    $preloader = Join-Path $V "BepInEx\core\BepInEx.Preloader.dll"

    $markerOk = $false
    if ((Test-Path $markerPath) -and (Test-Path $preloader)) {
        $marker = (Get-Content -Path $markerPath -Raw).Trim()
        if ($marker -eq "$packId $($pack.version) $($pack.sha256)") { $markerOk = $true }
    }

    if ($markerOk) {
        Write-Info "= BepInEx $($pack.version)"
    } else {
        Write-Info "-> BepInEx $($pack.version)"
        $packZip = Join-Path $tmp "bepinex.zip"
        Get-PackageFile -Namespace $pack.namespace -Name $pack.name -Version $pack.version -OutFile $packZip -Sha256 $pack.sha256

        $packExtract = Join-Path $tmp "bepinex"
        Expand-Archive -Path $packZip -DestinationPath $packExtract -Force

        # The archive also holds README/icon at the top level; the real root is
        # the folder that contains start_game_bepinex.sh.
        $launcher = Get-ChildItem -Path $packExtract -Filter "start_game_bepinex.sh" -Recurse -File | Select-Object -First 1
        if ($launcher) { $src = $launcher.Directory.FullName } else { $src = $packExtract }

        Copy-Item -Path (Join-Path $src "*") -Destination $V -Recurse -Force
        New-Item -ItemType Directory -Path (Join-Path $V "BepInEx") -Force | Out-Null
        Set-Content -Path $markerPath -Value "$packId $($pack.version) $($pack.sha256)" -Encoding ASCII
    }

    # ---------- mods ----------
    $plugins = Join-Path $V "BepInEx\plugins"
    New-Item -ItemType Directory -Path $plugins -Force | Out-Null
    $statePath = Join-Path $plugins ".mod-sync-state.json"

    $oldState = @{}
    if (Test-Path $statePath) {
        $raw = Get-Content -Path $statePath -Raw
        if ($raw -and $raw.Trim()) {
            try {
                $stateObj = $raw | ConvertFrom-Json
                foreach ($prop in $stateObj.PSObject.Properties) { $oldState[$prop.Name] = $prop.Value }
            } catch { }
        }
    }

    $newState = @{}
    $installed = 0
    $skipped = 0
    $removed = 0

    foreach ($mod in @($manifest.mods)) {
        $id = "$($mod.namespace)-$($mod.name)"
        $dest = Join-Path $plugins $id
        $cur = $oldState[$id]

        if ($cur -and $cur.version -eq $mod.version -and $cur.sha256 -eq $mod.sha256 -and (Test-Path $dest)) {
            $newState[$id] = @{ version = $mod.version; sha256 = $mod.sha256 }
            $skipped++
            continue
        }

        Write-Info "-> $id $($mod.version)"
        $zip = Join-Path $tmp "$id.zip"
        Get-PackageFile -Namespace $mod.namespace -Name $mod.name -Version $mod.version -OutFile $zip -Sha256 $mod.sha256

        if (Test-Path $dest) { Remove-Item -Path $dest -Recurse -Force }
        New-Item -ItemType Directory -Path $dest -Force | Out-Null
        Expand-Archive -Path $zip -DestinationPath $dest -Force

        # Some packages nest the payload under plugins\ (and config\).
        $nestedPlugins = Join-Path $dest "plugins"
        if (Test-Path $nestedPlugins) {
            Get-ChildItem -Path $nestedPlugins -Force | ForEach-Object {
                Move-Item -Path $_.FullName -Destination $dest -Force
            }
            Remove-Item -Path $nestedPlugins -Recurse -Force
        }
        $nestedConfig = Join-Path $dest "config"
        if (Test-Path $nestedConfig) {
            $cfgDir = Join-Path $V "BepInEx\config"
            New-Item -ItemType Directory -Path $cfgDir -Force | Out-Null
            Copy-Item -Path (Join-Path $nestedConfig "*") -Destination $cfgDir -Recurse -Force
            Remove-Item -Path $nestedConfig -Recurse -Force
        }

        $newState[$id] = @{ version = $mod.version; sha256 = $mod.sha256 }
        $installed++
    }

    # ---------- disable mods removed from the manifest ----------
    $disabledDir = Join-Path $V "BepInEx\plugins-disabled"
    foreach ($key in @($oldState.Keys)) {
        if ($newState.ContainsKey($key)) { continue }
        $dir = Join-Path $plugins $key
        if (-not (Test-Path $dir)) { continue }

        New-Item -ItemType Directory -Path $disabledDir -Force | Out-Null
        $target = Join-Path $disabledDir ("{0}-{1}" -f $key, (Get-Date -Format "yyyyMMdd-HHmmss"))
        Move-Item -Path $dir -Destination $target
        Write-Info "-- disabled $key (moved to plugins-disabled)"
        $removed++
    }

    $newState | ConvertTo-Json -Depth 6 | Set-Content -Path $statePath -Encoding UTF8

    Write-Host "Done: $installed installed/updated, $skipped up to date, $removed disabled."
    Write-Host "Launch Valheim from Steam, or double-click scripts\play.bat."
} catch {
    Write-Host "ERROR: $($_.Exception.Message)" -ForegroundColor Red
    $exitCode = 1
} finally {
    Remove-Item -Path $tmp -Recurse -Force -ErrorAction SilentlyContinue
}

exit $exitCode
