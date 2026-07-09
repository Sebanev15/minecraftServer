# =====================================================================
# CerrarServidor.ps1
# Cierra el servidor de forma limpia y sincroniza el mundo a Drive
# =====================================================================

$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
. (Join-Path $ScriptDir "Config.ps1")
. (Join-Path $ScriptDir "RconFunctions.ps1")

Write-Host "=== Cerrando servidor de Minecraft ===" -ForegroundColor Cyan

# 1. Enviar stop por RCON
Write-Host "`n[1/7] Enviando comando 'stop' via RCON..." -ForegroundColor Yellow
try {
    $response = Send-RconCommand -HostName $RconHost -Port $RconPort -Password $RconPassword -Command "stop"
    Write-Host "  Respuesta del servidor: $response" -ForegroundColor Gray
} catch {
    Write-Host "  ERROR: $_" -ForegroundColor Red
    exit 1
}

# 2. Esperar cierre del proceso
Write-Host "`n[2/7] Esperando a que el servidor cierre completamente..." -ForegroundColor Yellow
$closed = Wait-ForServerExit -ProcessName $JavaProcessName -TimeoutSeconds $MaxWaitSeconds
if (-not $closed) {
    Write-Host "  ADVERTENCIA: el servidor no cerro dentro de $MaxWaitSeconds segundos." -ForegroundColor Red
    Write-Host "  No se continua con el backup para evitar corromper el mundo." -ForegroundColor Red
    exit 1
}
Write-Host "  Servidor cerrado correctamente." -ForegroundColor Green

# 3. Comprimir el mundo
Write-Host "`n[3/7] Comprimiendo carpeta world/..." -ForegroundColor Yellow
if (Test-Path $WorldZip) { Remove-Item $WorldZip -Force }
Compress-Archive -Path (Join-Path $WorldFolder "*") -DestinationPath $WorldZip -Force
$sizeMB = [math]::Round((Get-Item $WorldZip).Length / 1MB, 2)
Write-Host "  world.zip creado ($sizeMB MB)." -ForegroundColor Green

# 4. Subir a Drive
Write-Host "`n[4/7] Subiendo mundo a Google Drive..." -ForegroundColor Yellow
rclone copy $WorldZip "$RcloneRemote/" --progress
if ($LASTEXITCODE -ne 0) {
    Write-Host "  ERROR: la subida a Drive fallo. El lock NO se libera." -ForegroundColor Red
    Write-Host "  Reintenta manualmente: rclone copy `"$WorldZip`" `"$RcloneRemote/`" --progress" -ForegroundColor Gray
    exit 1
}
Write-Host "  Mundo sincronizado correctamente." -ForegroundColor Green

# 5. Commit y push de archivos de estado si cambiaron
Write-Host "`n[5/7] Verificando cambios en whitelist/ops/bans..." -ForegroundColor Yellow
Push-Location $ServerPath
$gitStatus = git status --porcelain -- $StateFiles
if ($gitStatus) {
    git add $StateFiles
    git commit -m "Actualizacion de estado del server ($(Get-Date -Format 'yyyy-MM-dd HH:mm'))"
    git push origin main
    if ($LASTEXITCODE -ne 0) {
        Write-Host "  ADVERTENCIA: el push fallo. Sube los cambios manualmente con 'git push'." -ForegroundColor Red
    } else {
        Write-Host "  Cambios de whitelist/ops/bans subidos." -ForegroundColor Green
    }
} else {
    Write-Host "  Sin cambios en archivos de estado." -ForegroundColor Gray
}
Pop-Location

# 6. Liberar el lock
Write-Host "`n[6/7] Liberando lock de host..." -ForegroundColor Yellow
rclone deletefile $RemoteLockFile 2>$null
Write-Host "  Lock liberado. El servidor ya puede ser iniciado por otro host." -ForegroundColor Green

# 7. Devolver el nombre de Tailscale para que el proximo host lo pueda tomar
Write-Host "`n[7/7] Liberando direccion de conexion (Tailscale)..." -ForegroundColor Yellow
try {
    tailscale set --hostname $OriginalHostname
    Write-Host "  Nombre devuelto a $OriginalHostname. Listo para el proximo host." -ForegroundColor Green
} catch {
    Write-Host "  ADVERTENCIA: no se pudo devolver el nombre de Tailscale. $_" -ForegroundColor Red
    Write-Host "  El proximo host podria recibir '$TailscaleHostname-1' en vez de '$TailscaleHostname'." -ForegroundColor Yellow
}

Write-Host "`n=== Cierre completo ===" -ForegroundColor Cyan