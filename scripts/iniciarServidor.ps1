# =====================================================================
# IniciarServidor.ps1
# Verifica lock, actualiza modpack/mundo, y arranca el servidor
# =====================================================================

param(
    [switch]$Force   # Ignora un lock existente (usar solo si estas seguro que esta huerfano)
)

$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
. (Join-Path $ScriptDir "Config.ps1")
. (Join-Path $ScriptDir "RconFunctions.ps1")

Write-Host "=== Iniciando servidor de Minecraft ===" -ForegroundColor Cyan

# 1. Chequear lock remoto
Write-Host "`n[1/7] Verificando si hay otro host activo..." -ForegroundColor Yellow
$lockContent = rclone cat $RemoteLockFile 2>$null
if ($LASTEXITCODE -eq 0 -and $lockContent) {
    $lockData = $lockContent | ConvertFrom-Json
    $lockTime = [datetime]$lockData.timestamp
    $hoursOld = ((Get-Date) - $lockTime).TotalHours

    Write-Host "  LOCK ENCONTRADO:" -ForegroundColor Red
    Write-Host "    Host: $($lockData.host)" -ForegroundColor Red
    Write-Host "    Desde: $($lockData.timestamp) ($([math]::Round($hoursOld,1)) horas)" -ForegroundColor Red

    if ($hoursOld -gt $LockStaleHours) {
        Write-Host "  Este lock tiene mas de $LockStaleHours horas, podria estar huerfano" -ForegroundColor Yellow
        Write-Host "  (por ejemplo, si ese host se colgo sin cerrar bien)." -ForegroundColor Yellow
        Write-Host "  Confirma con $($lockData.host) antes de forzar. Si estas seguro, corre:" -ForegroundColor Yellow
        Write-Host "    .\IniciarServidor.ps1 -Force" -ForegroundColor Gray
    }

    if (-not $Force) {
        Write-Host "`n  Abortando inicio. El servidor ya esta siendo hosteado." -ForegroundColor Red
        exit 1
    } else {
        Write-Host "`n  -Force activado: ignorando el lock existente." -ForegroundColor Yellow
    }
} else {
    Write-Host "  Sin lock activo. Via libre." -ForegroundColor Green
}

# 2. Traer whitelist/ops/bans actualizados
Write-Host "`n[2/7] Actualizando configuracion desde Git..." -ForegroundColor Yellow
Push-Location $ServerPath
git pull origin main
if ($LASTEXITCODE -ne 0) {
    Write-Host "  ERROR: git pull fallo. Resuelve conflictos manualmente antes de continuar." -ForegroundColor Red
    Pop-Location
    exit 1
}
Pop-Location
Write-Host "  Configuracion actualizada." -ForegroundColor Green

# 3. Verificar/actualizar modpack
Write-Host "`n[3/7] Verificando version del modpack..." -ForegroundColor Yellow
$manifest = Get-Content $ManifestPath | ConvertFrom-Json

$needsDownload = $true
if (Test-Path $InstalledMarker) {
    $installed = Get-Content $InstalledMarker | ConvertFrom-Json
    if ($installed.version -eq $manifest.version) {
        $needsDownload = $false
    }
}

if ($needsDownload) {
    Write-Host "  Modpack desactualizado o no instalado. Descargando $($manifest.version)..." -ForegroundColor Yellow
    $tempZip = Join-Path $env:TEMP "modpack-download.zip"
    try {
        Invoke-WebRequest -Uri $manifest.url -OutFile $tempZip -ErrorAction Stop
    } catch {
        Write-Host "  ERROR: no se pudo descargar el modpack desde:" -ForegroundColor Red
        Write-Host "    $($manifest.url)" -ForegroundColor Red
        Write-Host "  Motivo: $_" -ForegroundColor Red
        Write-Host "  Verifica que el Release existe en GitHub y que la URL en modpack.manifest.json es correcta." -ForegroundColor Red
        exit 1
    }

    $actualHash = (Get-FileHash $tempZip -Algorithm SHA256).Hash
    if ($actualHash -ne $manifest.sha256) {
        Write-Host "  ERROR: el hash del modpack descargado NO coincide con el manifest." -ForegroundColor Red
        Write-Host "  Esperado: $($manifest.sha256)" -ForegroundColor Red
        Write-Host "  Obtenido: $actualHash" -ForegroundColor Red
        Write-Host "  Abortando por seguridad - no se reemplazan los mods." -ForegroundColor Red
        exit 1
    }

    if (Test-Path $ModsFolder) { Remove-Item $ModsFolder -Recurse -Force }
    New-Item -ItemType Directory -Path $ModsFolder | Out-Null
    Expand-Archive -Path $tempZip -DestinationPath $ModsFolder -Force
    Remove-Item $tempZip -Force

    @{ version = $manifest.version; sha256 = $manifest.sha256 } | ConvertTo-Json | Set-Content $InstalledMarker
    Write-Host "  Modpack actualizado a $($manifest.version)." -ForegroundColor Green
} else {
    Write-Host "  Modpack ya esta en la ultima version ($($manifest.version))." -ForegroundColor Green
}

# 4. Bajar el mundo mas reciente desde Drive
Write-Host "`n[4/7] Descargando mundo desde Google Drive..." -ForegroundColor Yellow
$downloadedZip = Join-Path $env:TEMP "world.zip"
rclone deletefile $downloadedZip 2>$null
rclone copy $RemoteWorldZip $env:TEMP --progress
if ($LASTEXITCODE -ne 0) {
    Write-Host "  ERROR: no se pudo descargar world.zip desde Drive." -ForegroundColor Red
    exit 1
}

if (-not (Test-Path $downloadedZip)) {
    Write-Host "  ERROR: no se pudo descargar world.zip desde Drive." -ForegroundColor Red
    exit 1
}

if (Test-Path $WorldFolder) { Remove-Item $WorldFolder -Recurse -Force }
New-Item -ItemType Directory -Path $WorldFolder | Out-Null
Expand-Archive -Path $downloadedZip -DestinationPath $WorldFolder -Force
Remove-Item $downloadedZip -Force
Write-Host "  Mundo actualizado desde Drive." -ForegroundColor Green

# 5. Crear el lock
Write-Host "`n[5/7] Reservando el servidor a tu nombre..." -ForegroundColor Yellow
$lockData = @{
    host      = $env:USERNAME
    pc        = $env:COMPUTERNAME
    timestamp = (Get-Date -Format "o")
} | ConvertTo-Json

$localLockPath = Join-Path $env:TEMP "host.lock"
$lockData | Set-Content $localLockPath
rclone copy $localLockPath "$RcloneRemote/" --progress
Remove-Item $localLockPath -Force
Write-Host "  Lock creado a nombre de $env:USERNAME." -ForegroundColor Green

# 6. Reclamar el nombre fijo de conexion via Tailscale MagicDNS
Write-Host "`n[6/7] Reclamando direccion de conexion (Tailscale)..." -ForegroundColor Yellow
try {
    tailscale set --hostname $TailscaleHostname
    Start-Sleep -Seconds 2   # dar tiempo a que MagicDNS propague el cambio
    Write-Host "  Direccion fija: $TailscaleHostname.$TailscaleDomainSuffix" -ForegroundColor Green
} catch {
    Write-Host "  ADVERTENCIA: no se pudo renombrar el dispositivo en Tailscale. $_" -ForegroundColor Red
    Write-Host "  El servidor va a arrancar igual, pero avisa a tus amigos la IP manualmente:" -ForegroundColor Yellow
    Write-Host "    $(tailscale ip -4)" -ForegroundColor Yellow
}

# 7. Arrancar el servidor
Write-Host "`n[7/7] Arrancando el servidor..." -ForegroundColor Yellow
Start-Process -FilePath $RunScript -WorkingDirectory $ServerPath
Write-Host "  Servidor iniciandose en una nueva ventana." -ForegroundColor Green
Write-Host "  Tus amigos se conectan siempre a: $TailscaleHostname.$TailscaleDomainSuffix" -ForegroundColor Cyan
Write-Host "  Cuando termines de jugar, usa la opcion 'Finalizar servidor' del menu." -ForegroundColor Cyan

Write-Host "`n=== Inicio completo ===" -ForegroundColor Cyan