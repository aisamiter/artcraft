# Levanta ArtCraft en modo desarrollo en Windows: frontend (Vite/Nx) + Rust (Tauri) juntos.
# Uso (desde cualquier carpeta): .\script\artcraft\local_dev.ps1
# Reemplaza correr windows_frontend_dev.ps1 y windows_rust_dev.ps1 en dos terminales.
#
# Funciona tambien sin ventanas (sesiones no interactivas): Vite corre oculto y sus logs
# van a $LogDir\vite.log. Ctrl-C / cierre de la app detiene Vite y todo su arbol de procesos.

param(
    [int]$VitePort = 5173,
    [int]$ViteTimeoutSeconds = 180,
    [string]$LogDir = (Join-Path $env:TEMP "artcraft-dev")
)

$ErrorActionPreference = "Stop"
$repo = (Resolve-Path (Join-Path $PSScriptRoot "..\..")).Path
$frontend = Join-Path $repo "frontend"

# PATH completo (maquina + usuario) por si la terminal se abrio antes de instalar las herramientas.
$machinePath = [Environment]::GetEnvironmentVariable("Path", "Machine")
$userPath = [Environment]::GetEnvironmentVariable("Path", "User")
$env:Path = "$machinePath;$userPath;$env:USERPROFILE\.cargo\bin"

# boring-sys2 (bindgen) necesita libclang.
if (-not $env:LIBCLANG_PATH -and (Test-Path "C:\Program Files\LLVM\bin\libclang.dll")) {
    $env:LIBCLANG_PATH = "C:\Program Files\LLVM\bin"
}

function Test-PortListening([int]$Port) {
    $null -ne (Get-NetTCPConnection -State Listen -LocalPort $Port -ErrorAction SilentlyContinue)
}

function Stop-ProcessTree([int]$ProcessId) {
    & taskkill.exe /PID $ProcessId /T /F *> $null
}

foreach ($tool in "node", "npm", "cargo") {
    if (-not (Get-Command $tool -ErrorAction SilentlyContinue)) {
        throw "Falta '$tool' en el PATH. Ver _docs/dev_setup.md."
    }
}
cargo tauri --version *> $null
if ($LASTEXITCODE -ne 0) { throw "Falta tauri-cli: cargo install tauri-cli --version 2.10.0 --locked" }

New-Item -ItemType Directory -Force $LogDir | Out-Null
$viteLog = Join-Path $LogDir "vite.log"
$viteErrLog = Join-Path $LogDir "vite.err.log"
$viteProcess = $null

try {
    if (Test-PortListening $VitePort) {
        Write-Host "Ya hay algo escuchando en el puerto $VitePort; se reutiliza (no se detendra al salir)."
    }
    else {
        if (-not (Test-Path (Join-Path $frontend "node_modules\.bin\vite.cmd"))) {
            Write-Host "Instalando dependencias del frontend (npm install)..."
            Push-Location $frontend
            try { npm install } finally { Pop-Location }
            if ($LASTEXITCODE -ne 0) { throw "npm install fallo." }
        }

        Write-Host "Iniciando Vite en segundo plano (logs: $viteLog)..."
        $env:VITE_ENVIRONMENT_TYPE = "production"
        $viteProcess = Start-Process cmd.exe -ArgumentList "/c", "npx nx dev artcraft" `
            -WorkingDirectory $frontend -WindowStyle Hidden -PassThru `
            -RedirectStandardOutput $viteLog -RedirectStandardError $viteErrLog

        $deadline = (Get-Date).AddSeconds($ViteTimeoutSeconds)
        while (-not (Test-PortListening $VitePort)) {
            if ($viteProcess.HasExited) { throw "Vite termino antes de abrir el puerto. Ver $viteErrLog" }
            if ((Get-Date) -gt $deadline) { throw "Vite no abrio el puerto $VitePort en $ViteTimeoutSeconds s. Ver $viteLog" }
            Start-Sleep -Seconds 2
        }
        Write-Host "Vite listo en http://localhost:$VitePort"
    }

    Push-Location $repo
    try { & (Join-Path $repo "script\artcraft\windows_rust_dev.ps1") }
    finally { Pop-Location }
}
finally {
    if ($viteProcess -and -not $viteProcess.HasExited) {
        Write-Host "Deteniendo Vite..."
        Stop-ProcessTree $viteProcess.Id
    }
}
