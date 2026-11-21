$ErrorActionPreference='Stop'
$Root=Split-Path -Parent $PSScriptRoot;$Dest=Join-Path $Root 'android/app/src/main/assets/lactea/curated';$Existing=@(Get-ChildItem -Path $Dest -File -ErrorAction SilentlyContinue|Where-Object{$_.Extension -in '.milk','.milk2'});$Has3=$Existing|Where-Object{$_.Extension -eq '.milk2'};$Marker=Join-Path $Dest 'UPSTREAM_COMMIT.txt'
if($Existing.Count -gt 0 -and $Has3 -and (Test-Path $Marker)){exit 0}
$Temp=Join-Path $env:TEMP 'yazen-projectm-presets';$Repo=Join-Path $Temp 'repo'
try{
 if(Test-Path $Temp){Remove-Item $Temp -Recurse -Force};New-Item -ItemType Directory -Path $Temp -Force|Out-Null
 git clone --depth 1 https://github.com/M0Rf30/projectm-presets.git $Repo;if($LASTEXITCODE-ne 0){throw 'clone failed'}
 $Commit=(git -C $Repo rev-parse HEAD).Trim()
 $Files=@();$Files+=Get-ChildItem (Join-Path $Repo 'presets') -Recurse -File -Filter '*.milk';$Files+=Get-ChildItem (Join-Path $Repo 'milk2') -Recurse -File -Filter '*.milk2'
 if($Files.Count-eq 0 -or -not($Files|Where-Object{$_.Extension-eq'.milk2'})){throw 'MilkDrop2/3 assets missing'}
 if(Test-Path $Dest){Remove-Item $Dest -Recurse -Force};New-Item -ItemType Directory -Path $Dest -Force|Out-Null
 foreach($f in $Files){$rel=$f.FullName.Substring($Repo.Length).TrimStart([char[]]@('\','/'));$flat=$rel -replace '[\\/]','__';Copy-Item -LiteralPath $f.FullName -Destination (Join-Path $Dest $flat) -Force}
 Copy-Item (Join-Path $Repo 'LICENSE') (Join-Path $Dest 'LICENSE') -Force;Set-Content $Marker $Commit -Encoding ascii
 $TD=Join-Path $Root 'android/app/src/main/assets/lactea/textures';foreach($src in @((Join-Path $Repo 'textures'),(Join-Path $Repo 'presets/textures'),(Join-Path $Repo 'milk2/textures'))){if(Test-Path $src){New-Item -ItemType Directory -Path $TD -Force|Out-Null;Copy-Item (Join-Path $src '*') $TD -Recurse -Force}}
 Write-Host "Prepared $($Files.Count) MilkDrop 2/3 presets from $Commit"
}catch{if(Test-Path $Dest){Remove-Item $Dest -Recurse -Force};Write-Warning "Using YAZEN fallback presets: $($_.Exception.Message)"}
