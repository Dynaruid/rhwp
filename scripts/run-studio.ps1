#Requires -Version 5.1
<#
.SYNOPSIS
  rhwp-studio Vite 개발 서버를 실행합니다.

.DESCRIPTION
  저장소 루트에서 WASM(pkg/) 존재 여부를 확인하고, 필요 시 Docker로 WASM을 빌드한 뒤
  rhwp-studio를 http://localhost:<Port> 로 띄웁니다.

.PARAMETER BuildWasm
  pkg/ 유무와 관계없이 Docker로 WASM을 다시 빌드합니다.

.PARAMETER SkipWasm
  pkg/가 없어도 WASM 빌드를 건너뜁니다. (이미 빌드된 pkg를 쓰는 경우)

.PARAMETER Port
  Vite 포트 (기본: 7700).

.PARAMETER BindHost
  Vite bind 주소 (기본: 0.0.0.0).

.PARAMETER Ci
  npm install 대신 npm ci를 사용합니다.

.EXAMPLE
  .\scripts\run-studio.ps1

.EXAMPLE
  .\scripts\run-studio.ps1 -BuildWasm

.EXAMPLE
  .\scripts\run-studio.ps1 -Port 7701
#>
[CmdletBinding()]
param(
    [switch]$BuildWasm,
    [switch]$SkipWasm,
    [int]$Port = 7700,
    [string]$BindHost = "0.0.0.0",
    [switch]$Ci
)

$ErrorActionPreference = "Stop"

$RepoRoot = Resolve-Path (Join-Path $PSScriptRoot "..")
$StudioDir = Join-Path $RepoRoot "rhwp-studio"
$PkgDir = Join-Path $RepoRoot "pkg"
$PkgWasm = Join-Path $PkgDir "rhwp_bg.wasm"
$EnvDocker = Join-Path $RepoRoot ".env.docker"
$EnvDockerExample = Join-Path $RepoRoot ".env.docker.example"

function Write-Step([string]$Message) {
    Write-Host ""
    Write-Host "==> $Message" -ForegroundColor Cyan
}

function Ensure-Command([string]$Name) {
    if (-not (Get-Command $Name -ErrorAction SilentlyContinue)) {
        throw "'$Name' 명령을 찾을 수 없습니다. PATH를 확인하세요."
    }
}

if (-not (Test-Path -LiteralPath $StudioDir)) {
    throw "rhwp-studio 디렉터리를 찾을 수 없습니다: $StudioDir"
}

Ensure-Command "node"
Ensure-Command "npm"

$needWasm = $BuildWasm -or (-not (Test-Path -LiteralPath $PkgWasm))
if ($needWasm -and -not $SkipWasm) {
    Ensure-Command "docker"

    if (-not (Test-Path -LiteralPath $EnvDocker)) {
        if (-not (Test-Path -LiteralPath $EnvDockerExample)) {
            throw ".env.docker.example 이 없습니다: $EnvDockerExample"
        }
        Write-Step ".env.docker 생성 (.env.docker.example 복사)"
        Copy-Item -LiteralPath $EnvDockerExample -Destination $EnvDocker
    }

    Write-Step "WASM 빌드 (docker compose run --rm wasm)"
    Push-Location $RepoRoot
    try {
        docker compose --env-file .env.docker run --rm wasm
        if ($LASTEXITCODE -ne 0) {
            throw "WASM 빌드 실패 (exit $LASTEXITCODE)"
        }
    }
    finally {
        Pop-Location
    }

    if (-not (Test-Path -LiteralPath $PkgWasm)) {
        throw "WASM 빌드 후에도 pkg/rhwp_bg.wasm 이 없습니다."
    }
}
elseif (-not (Test-Path -LiteralPath $PkgWasm)) {
    Write-Warning "pkg/rhwp_bg.wasm 이 없습니다. -BuildWasm 으로 빌드하거나 Docker WASM 빌드를 먼저 실행하세요."
}
else {
    Write-Step "기존 WASM 사용: $PkgWasm"
}

$nodeModules = Join-Path $StudioDir "node_modules"
if (-not (Test-Path -LiteralPath $nodeModules) -or $Ci) {
    Write-Step ("npm " + ($(if ($Ci) { "ci" } else { "install" })) + " (rhwp-studio)")
    Push-Location $StudioDir
    try {
        if ($Ci) {
            npm ci
        }
        else {
            npm install
        }
        if ($LASTEXITCODE -ne 0) {
            throw "npm 의존성 설치 실패 (exit $LASTEXITCODE)"
        }
    }
    finally {
        Pop-Location
    }
}
else {
    Write-Step "기존 node_modules 사용"
}

Write-Step "Vite 시작: http://localhost:$Port/"
Write-Host "    bind=$BindHost  (종료: Ctrl+C)" -ForegroundColor DarkGray
Write-Host ""

Set-Location $StudioDir
& npx vite --host $BindHost --port $Port
exit $LASTEXITCODE
