$ErrorActionPreference = 'Stop'
$Root = Split-Path -Parent $PSScriptRoot
$Source = Join-Path $Root 'third_party/lactea-v0.2.2'
$Jni = Join-Path $Root 'android/app/src/main/jniLibs'
$Include = Join-Path $Root 'android/app/src/main/cpp/include'
$Licenses = Join-Path $Root 'android/app/src/main/assets/lactea/licenses'

if (-not (Get-Command git -ErrorAction SilentlyContinue)) { throw 'Git is required.' }
if (-not (Get-Command cargo -ErrorAction SilentlyContinue) -or -not (Get-Command rustup -ErrorAction SilentlyContinue)) { throw 'Rust/rustup is required.' }
cargo ndk --version | Out-Null
if ($LASTEXITCODE -ne 0) { throw 'Install cargo-ndk: cargo install cargo-ndk' }

& (Join-Path $PSScriptRoot 'prepare_lactea_presets.ps1')
rustup target add aarch64-linux-android
if ($LASTEXITCODE -ne 0) { throw 'Could not install the Android Rust target.' }

if (-not (Test-Path (Join-Path $Source '.git'))) {
    if (Test-Path $Source) { Remove-Item $Source -Recurse -Force }
    New-Item -ItemType Directory -Path (Split-Path -Parent $Source) -Force | Out-Null
    git clone --depth 1 --branch v0.2.2 https://github.com/M0Rf30/lactea.git $Source
    if ($LASTEXITCODE -ne 0) { throw 'Could not clone Lactea source.' }
}

Push-Location $Source
try {
    $Metadata = cargo metadata --no-deps --format-version 1 | ConvertFrom-Json
    if ($LASTEXITCODE -ne 0) { throw 'cargo metadata failed.' }
    $Capi = $Metadata.packages | Where-Object { $_.name -eq 'lactea-capi' } | Select-Object -First 1
    if ($null -eq $Capi -or $Capi.version -ne '0.2.2') {
        throw "Expected lactea-capi 0.2.2; found $($Capi.version)."
    }
    cargo ndk -t arm64-v8a -o $Jni build --release --locked -p lactea-capi --features gles
    if ($LASTEXITCODE -ne 0) { throw 'Lactea C API Android cross-build failed.' }
} finally { Pop-Location }

New-Item -ItemType Directory -Path $Include, $Licenses -Force | Out-Null
Copy-Item -LiteralPath (Join-Path $Source 'crates/lactea-capi/include/lactea.h') -Destination (Join-Path $Include 'lactea.h') -Force
Copy-Item -LiteralPath (Join-Path $Source 'THIRD_PARTY_NOTICES.md') -Destination $Licenses -Force
Copy-Item -LiteralPath (Join-Path $Source 'LICENSE-MIT') -Destination $Licenses -Force
Copy-Item -LiteralPath (Join-Path $Source 'LICENSE-APACHE') -Destination $Licenses -Force
if (-not (Test-Path (Join-Path $Jni 'arm64-v8a/liblactea_capi.so'))) { throw 'liblactea_capi.so missing after build.' }
Write-Host 'Lactea C API 0.2.2 built. Now run flutter build apk --profile.'
