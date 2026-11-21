$ErrorActionPreference = 'Stop'
$Root = Split-Path -Parent $PSScriptRoot
$Dest = Join-Path $Root 'android/app/src/main/assets/lactea/curated'
$Marker = Join-Path $Dest 'UPSTREAM_COMMIT.txt'
$Index = Join-Path $Dest 'PRESET_INDEX.txt'
$ExistingMilk = @(Get-ChildItem -Path $Dest -File -Filter '*.milk' -ErrorAction SilentlyContinue)
$ExistingMilk2 = @(Get-ChildItem -Path $Dest -File -Filter '*.milk2' -ErrorAction SilentlyContinue)
if ((Test-Path $Marker) -and (Test-Path $Index) -and $ExistingMilk.Count -ge 6 -and $ExistingMilk2.Count -ge 6) { return }
if (-not (Get-Command git -ErrorAction SilentlyContinue)) { throw 'Git is required to fetch the licensed MilkDrop preset pack.' }
$Temp = Join-Path ([System.IO.Path]::GetTempPath()) ('yazen-projectm-presets-' + [guid]::NewGuid().ToString('N'))
$Repo = Join-Path $Temp 'repo'
$Stage = Join-Path $Temp 'curated'
try {
    New-Item -ItemType Directory -Path $Temp -Force | Out-Null
    git clone --depth 1 https://github.com/M0Rf30/projectm-presets.git $Repo
    if ($LASTEXITCODE -ne 0) { throw 'Could not download projectm-presets; refusing to package fallback placeholders.' }
    $MilkDir = Join-Path $Repo 'presets'; $Milk2Dir = Join-Path $Repo 'milk2'
    if (-not (Test-Path $MilkDir) -or -not (Test-Path $Milk2Dir)) { throw 'Required .milk and .milk2 directories are missing.' }
    $Milk = @(Get-ChildItem $MilkDir -Recurse -File -Filter '*.milk')
    $Milk2 = @(Get-ChildItem $Milk2Dir -Recurse -File -Filter '*.milk2')
    if ($Milk.Count -lt 6 -or $Milk2.Count -lt 6) { throw "Expected at least 6 .milk and 6 .milk2 files; found $($Milk.Count) and $($Milk2.Count)." }
    $AllPresets = @($Milk) + @($Milk2)
    if ($AllPresets | Where-Object { $_.Length -le 0 }) { throw 'An upstream preset file is empty.' }
    $Commit = (git -C $Repo rev-parse HEAD).Trim()
    New-Item -ItemType Directory -Path $Stage -Force | Out-Null
    foreach ($f in (@($Milk) + @($Milk2))) {
        $rel = $f.FullName.Substring($Repo.Length).TrimStart([char[]]@('\','/'))
        $flat = $rel -replace '[\\/]', '__'
        Copy-Item -LiteralPath $f.FullName -Destination (Join-Path $Stage $flat)
    }
    Copy-Item (Join-Path $Repo 'LICENSE') (Join-Path $Stage 'LICENSE')
    Set-Content (Join-Path $Stage 'UPSTREAM_COMMIT.txt') $Commit -Encoding ascii
    $lines = @("Source: https://github.com/M0Rf30/projectm-presets", "Commit: $Commit", "MilkDrop 2 (.milk): $($Milk.Count)", "MilkDrop 3 (.milk2): $($Milk2.Count)", "Total: $($Milk.Count + $Milk2.Count)")
    $lines += Get-ChildItem $Stage -File | Where-Object { $_.Extension -in '.milk','.milk2' } | Sort-Object Name | ForEach-Object Name
    Set-Content (Join-Path $Stage 'PRESET_INDEX.txt') $lines -Encoding utf8
    if (Test-Path $Dest) { Remove-Item $Dest -Recurse -Force }
    New-Item -ItemType Directory -Path (Split-Path $Dest -Parent) -Force | Out-Null
    Move-Item $Stage $Dest
    $TextureDest = Join-Path $Root 'android/app/src/main/assets/lactea/textures'
    foreach ($source in @((Join-Path $Repo 'textures'),(Join-Path $MilkDir 'textures'),(Join-Path $Milk2Dir 'textures'))) {
        if (Test-Path $source) { New-Item -ItemType Directory -Path $TextureDest -Force | Out-Null; Copy-Item (Join-Path $source '*') $TextureDest -Recurse -Force }
    }
    Write-Host "Prepared $($Milk.Count) MilkDrop 2 + $($Milk2.Count) MilkDrop 3 presets from $Commit"
} finally { if (Test-Path $Temp) { Remove-Item $Temp -Recurse -Force } }
