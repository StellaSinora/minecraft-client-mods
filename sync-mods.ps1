param(
  [string]$ManifestUrl,
  [string]$ManifestPath,
  [Parameter(Mandatory = $true)][string]$ModsDir,
  [switch]$InstallShaders
)

$ErrorActionPreference = "Stop"
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

function Write-Step([string]$Message) {
  Write-Host "  > $Message"
}

function Get-Sha256([string]$Path) {
  return (Get-FileHash -Path $Path -Algorithm SHA256).Hash.ToLower()
}

try {
  if (-not (Test-Path -LiteralPath $ModsDir)) {
    New-Item -ItemType Directory -Path $ModsDir -Force | Out-Null
    Write-Step "Created mods folder: $ModsDir"
  }

  $tempRoot = Join-Path $env:TEMP ("mc-mods-sync-" + [guid]::NewGuid().ToString("N"))
  New-Item -ItemType Directory -Path $tempRoot -Force | Out-Null

  if ($ManifestPath) {
    if (-not (Test-Path -LiteralPath $ManifestPath)) {
      throw "mods.json not found: $ManifestPath"
    }
    Write-Step "Using local mods.json"
    $manifest = Get-Content -LiteralPath $ManifestPath -Raw -Encoding UTF8 | ConvertFrom-Json
  } else {
    if (-not $ManifestUrl) { throw "ManifestUrl or ManifestPath is required." }
    $downloadedManifest = Join-Path $tempRoot "mods.json"
    $manifestRequest = $ManifestUrl
    if ($manifestRequest -notmatch '\?') {
      $manifestRequest = $manifestRequest + '?t=' + [DateTimeOffset]::UtcNow.ToUnixTimeSeconds()
    }
    Write-Step "Downloading mods.json..."
    Invoke-WebRequest -Uri $manifestRequest -OutFile $downloadedManifest -UseBasicParsing
    $manifest = Get-Content -LiteralPath $downloadedManifest -Raw -Encoding UTF8 | ConvertFrom-Json
  }
  if (-not $manifest.mods -or $manifest.mods.Count -eq 0) {
    throw "mods.json has no mods list."
  }

  $wanted = @{}
  foreach ($mod in $manifest.mods) {
    if (-not $mod.file -or -not $mod.url) { continue }
    $wanted[$mod.file] = $mod
  }

  Write-Step ("Manifest loaded: {0} mods" -f $wanted.Count)

  if ($InstallShaders) {
    $shaderMods = @()
    if ($manifest.shaders) { $shaderMods = @($manifest.shaders) }
    foreach ($mod in $shaderMods) {
      if (-not $mod.file -or -not $mod.url) { continue }
      $wanted[$mod.file] = $mod
    }
    Write-Step "Shader: installing Oculus + Embeddium"
  } else {
    Write-Step "Shader skipped. Normal mods.json download."
  }

  $removeUnknown = $true
  if ($null -ne $manifest.removeUnknownMods) {
    $removeUnknown = [bool]$manifest.removeUnknownMods
  }

  if ($removeUnknown) {
    $existing = Get-ChildItem -LiteralPath $ModsDir -Filter "*.jar" -File -ErrorAction SilentlyContinue
    $removed = 0
    foreach ($jar in $existing) {
      if (-not $wanted.ContainsKey($jar.Name)) {
        Write-Step ("Removing unknown mod: {0}" -f $jar.Name)
        Remove-Item -LiteralPath $jar.FullName -Force
        $removed++
      }
    }
    Write-Step ("Removed {0} unknown jar(s)" -f $removed)
  }

  $downloaded = 0
  $skipped = 0
  $failed = 0
  $index = 0
  $total = $wanted.Count

  foreach ($name in ($wanted.Keys | Sort-Object)) {
    $index++
    $mod = $wanted[$name]
    $target = Join-Path $ModsDir $name
    $needDownload = $true

    if (Test-Path -LiteralPath $target) {
      $local = Get-Item -LiteralPath $target
      $sizeOk = (-not $mod.size) -or ([int64]$mod.size -eq $local.Length)
      $hashOk = $true
      if ($mod.sha256) {
        $hashOk = ((Get-Sha256 $target) -eq ([string]$mod.sha256).ToLower())
      }
      if ($sizeOk -and $hashOk) {
        Write-Host ("  [{0}/{1}] OK     {2}" -f $index, $total, $name)
        $skipped++
        $needDownload = $false
      } else {
        Write-Step ("Outdated, replacing: {0}" -f $name)
        Remove-Item -LiteralPath $target -Force
      }
    }

    if (-not $needDownload) { continue }

    $localSrc = Join-Path $PSScriptRoot ("mods\" + $name)
    if (Test-Path -LiteralPath $localSrc) {
      $localItem = Get-Item -LiteralPath $localSrc
      $localSizeOk = (-not $mod.size) -or ([int64]$mod.size -eq $localItem.Length)
      $localHashOk = $true
      if ($mod.sha256) {
        $localHashOk = ((Get-Sha256 $localSrc) -eq ([string]$mod.sha256).ToLower())
      }
      if ($localSizeOk -and $localHashOk) {
        Copy-Item -LiteralPath $localSrc -Destination $target -Force
        Write-Host ("  [{0}/{1}] COPY   {2}" -f $index, $total, $name)
        $downloaded++
        continue
      }
    }

    $tempFile = Join-Path $tempRoot $name
    Write-Host ("  [{0}/{1}] GET    {2}" -f $index, $total, $name)
    try {
      Invoke-WebRequest -Uri $mod.url -OutFile $tempFile -UseBasicParsing

      if ($mod.size -and ([int64]$mod.size -ne (Get-Item -LiteralPath $tempFile).Length)) {
        throw "Size mismatch for $name"
      }
      if ($mod.sha256) {
        $actual = Get-Sha256 $tempFile
        if ($actual -ne ([string]$mod.sha256).ToLower()) {
          throw "SHA256 mismatch for $name"
        }
      }

      Move-Item -LiteralPath $tempFile -Destination $target -Force
      $downloaded++
    } catch {
      $failed++
      Write-Host ("  !! Failed: {0} - {1}" -f $name, $_.Exception.Message) -ForegroundColor Red
      if (Test-Path -LiteralPath $tempFile) {
        Remove-Item -LiteralPath $tempFile -Force -ErrorAction SilentlyContinue
      }
    }
  }

  Write-Host ""
  Write-Step ("Downloaded: {0}" -f $downloaded)
  Write-Step ("Already OK : {0}" -f $skipped)
  Write-Step ("Failed     : {0}" -f $failed)

  if ($failed -gt 0) { exit 1 }
  exit 0
} catch {
  Write-Host ("  ERROR: {0}" -f $_.Exception.Message) -ForegroundColor Red
  exit 1
} finally {
  if ($tempRoot -and (Test-Path -LiteralPath $tempRoot)) {
    Remove-Item -LiteralPath $tempRoot -Recurse -Force -ErrorAction SilentlyContinue
  }
}
