# =====================================================================
# ServerManager.ps1 - Menu principal
# Este es el unico script que los hosts necesitan ejecutar
# =====================================================================

$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
. (Join-Path $ScriptDir "Config.ps1")
. (Join-Path $ScriptDir "RconFunctions.ps1")

function Show-Estado {
    Write-Host "`n=== Estado del servidor ===" -ForegroundColor Cyan

    $lockContent = rclone cat $RemoteLockFile 2>$null
    if ($LASTEXITCODE -eq 0 -and $lockContent) {
        $lockData = $lockContent | ConvertFrom-Json
        Write-Host "Estado: EN USO" -ForegroundColor Red
        Write-Host "Host actual: $($lockData.host)" -ForegroundColor White
        Write-Host "Desde: $($lockData.timestamp)" -ForegroundColor White
    } else {
        Write-Host "Estado: LIBRE" -ForegroundColor Green
    }

    $worldInfo = rclone lsl $RemoteWorldZip 2>$null
    if ($worldInfo) {
        Write-Host "Ultima sincronizacion del mundo: $worldInfo" -ForegroundColor White
    }

    Push-Location $ServerPath
    $branch = git branch --show-current
    $behind = git rev-list --count HEAD..origin/main 2>$null
    Write-Host "Rama local: $branch" -ForegroundColor White
    if ($behind -and $behind -gt 0) {
        Write-Host "Hay $behind commits nuevos en el repo remoto (hace falta git pull)" -ForegroundColor Yellow
    } else {
        Write-Host "Repositorio local al dia." -ForegroundColor Green
    }
    Pop-Location

    $tailscaleStatus = tailscale status 2>$null
    if ($LASTEXITCODE -eq 0) {
        Write-Host "Tailscale: conectado" -ForegroundColor Green
    } else {
        Write-Host "Tailscale: no se pudo verificar (¿esta corriendo?)" -ForegroundColor Yellow
    }
}

function Show-Menu {
    Clear-Host
    Write-Host "=================================" -ForegroundColor Cyan
    Write-Host " Minecraft Server Manager" -ForegroundColor Cyan
    Write-Host "=================================" -ForegroundColor Cyan
    Write-Host "1) Iniciar servidor"
    Write-Host "2) Finalizar servidor"
    Write-Host "3) Actualizar (solo sincronizar sin jugar)"
    Write-Host "4) Estado del servidor"
    Write-Host "5) Salir"
    Write-Host "=================================" -ForegroundColor Cyan
}

do {
    Show-Menu
    $opcion = Read-Host "Elegi una opcion"

    switch ($opcion) {
        "1" {
            & (Join-Path $ScriptDir "IniciarServidor.ps1")
            Read-Host "`nPresiona Enter para volver al menu"
        }
        "2" {
            & (Join-Path $ScriptDir "CerrarServidor.ps1")
            Read-Host "`nPresiona Enter para volver al menu"
        }
        "3" {
            Write-Host "`nEsto trae los cambios mas recientes sin arrancar el servidor." -ForegroundColor Yellow
            Push-Location $ServerPath
            git pull origin main
            Pop-Location
            Read-Host "`nPresiona Enter para volver al menu"
        }
        "4" {
            Show-Estado
            Read-Host "`nPresiona Enter para volver al menu"
        }
        "5" {
            Write-Host "Chau!" -ForegroundColor Cyan
        }
        default {
            Write-Host "Opcion invalida." -ForegroundColor Red
            Start-Sleep -Seconds 1
        }
    }
} while ($opcion -ne "5")