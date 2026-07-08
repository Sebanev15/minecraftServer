# =====================================================================
# CerrarServidor.ps1
# Cierra el servidor de Minecraft de forma limpia y sincroniza el mundo
# =====================================================================

# ---------------------- CONFIGURACION ----------------------
# Ajusta estas rutas y valores a tu entorno antes de usar el script

$ServerPath      = "E:\MinecraftServerFinal"      # Carpeta raiz del server
$WorldFolder     = Join-Path $ServerPath "world"
$WorldZip        = Join-Path $ServerPath "world.zip"
$RconHost        = "127.0.0.1"
$RconPort        = 25575
$RconPassword    = "pass123"           # Debe coincidir con server.properties
$RcloneRemote    = "mcworld:minecraft-server"      # Remote + carpeta en Drive
$RemoteWorldZip  = "$RcloneRemote/world.zip"
$RemoteLockFile  = "$RcloneRemote/host.lock"
$JavaProcessName = "java"                          # Nombre del proceso a esperar
$StateFiles      = @("whitelist.json", "ops.json", "banned-players.json", "banned-ips.json")
$MaxWaitSeconds  = 120                             # Tiempo max de espera a que el server cierre

# ---------------------- FUNCION: ENVIAR COMANDO RCON ----------------------
function Send-RconCommand {
    param(
        [string]$HostName,
        [int]$Port,
        [string]$Password,
        [string]$Command
    )

    function New-RconPacket {
        param([int]$RequestId, [int]$Type, [string]$Body)
        $bodyBytes = [System.Text.Encoding]::ASCII.GetBytes($Body)
        $length = 4 + 4 + $bodyBytes.Length + 2  # requestId + type + body + 2 null terminators
        $stream = New-Object System.IO.MemoryStream
        $writer = New-Object System.IO.BinaryWriter($stream)
        $writer.Write([int32]$length)
        $writer.Write([int32]$RequestId)
        $writer.Write([int32]$Type)
        $writer.Write($bodyBytes)
        $writer.Write([byte]0)
        $writer.Write([byte]0)
        $writer.Flush()
        return $stream.ToArray()
    }

    function Read-RconResponse {
        param([System.Net.Sockets.NetworkStream]$Stream)
        $lengthBytes = New-Object byte[] 4
        $read = $Stream.Read($lengthBytes, 0, 4)
        if ($read -lt 4) { throw "Conexion RCON cerrada inesperadamente." }
        $length = [System.BitConverter]::ToInt32($lengthBytes, 0)

        $payload = New-Object byte[] $length
        $offset = 0
        while ($offset -lt $length) {
            $r = $Stream.Read($payload, $offset, $length - $offset)
            if ($r -eq 0) { throw "Conexion RCON cerrada mientras se leia la respuesta." }
            $offset += $r
        }

        $requestId = [System.BitConverter]::ToInt32($payload, 0)
        $type      = [System.BitConverter]::ToInt32($payload, 4)
        $bodyLen   = $length - 4 - 4 - 2
        $body      = ""
        if ($bodyLen -gt 0) {
            $body = [System.Text.Encoding]::ASCII.GetString($payload, 8, $bodyLen)
        }
        return [PSCustomObject]@{ RequestId = $requestId; Type = $type; Body = $body }
    }

    $client = New-Object System.Net.Sockets.TcpClient
    try {
        $client.Connect($HostName, $Port)
    } catch {
        throw "No se pudo conectar a RCON en $HostName`:$Port. Verifica que enable-rcon=true y que el server este corriendo."
    }

    $stream = $client.GetStream()

    # --- Autenticacion ---
    $authPacket = New-RconPacket -RequestId 1 -Type 3 -Body $Password
    $stream.Write($authPacket, 0, $authPacket.Length)
    $authResponse = Read-RconResponse -Stream $stream

    if ($authResponse.RequestId -eq -1) {
        $client.Close()
        throw "Autenticacion RCON fallida. Verifica rcon.password en server.properties."
    }

    # --- Enviar comando ---
    $cmdPacket = New-RconPacket -RequestId 2 -Type 2 -Body $Command
    $stream.Write($cmdPacket, 0, $cmdPacket.Length)
    Start-Sleep -Milliseconds 200
    $cmdResponse = Read-RconResponse -Stream $stream

    $client.Close()
    return $cmdResponse.Body
}

# ---------------------- FUNCION: ESPERAR A QUE EL PROCESO CIERRE ----------------------
function Wait-ForServerExit {
    param([string]$ProcessName, [int]$TimeoutSeconds)

    $elapsed = 0
    while ($elapsed -lt $TimeoutSeconds) {
        $proc = Get-Process -Name $ProcessName -ErrorAction SilentlyContinue
        if (-not $proc) {
            return $true
        }
        Start-Sleep -Seconds 2
        $elapsed += 2
        Write-Host "  Esperando cierre del servidor... ($elapsed s)" -ForegroundColor DarkGray
    }
    return $false
}

# =====================================================================
# FLUJO PRINCIPAL
# =====================================================================

Write-Host "=== Cerrando servidor de Minecraft ===" -ForegroundColor Cyan

# 1. Enviar comando stop por RCON
Write-Host "`n[1/6] Enviando comando 'stop' via RCON..." -ForegroundColor Yellow
try {
    $response = Send-RconCommand -HostName $RconHost -Port $RconPort -Password $RconPassword -Command "stop"
    Write-Host "  Respuesta del servidor: $response" -ForegroundColor Gray
} catch {
    Write-Host "  ERROR: $_" -ForegroundColor Red
    Write-Host "  Abortando cierre. Revisa la conexion RCON antes de continuar." -ForegroundColor Red
    exit 1
}

# 2. Esperar a que el proceso Java termine
Write-Host "`n[2/6] Esperando a que el servidor cierre completamente..." -ForegroundColor Yellow
$closed = Wait-ForServerExit -ProcessName $JavaProcessName -TimeoutSeconds $MaxWaitSeconds
if (-not $closed) {
    Write-Host "  ADVERTENCIA: el servidor no cerro dentro de $MaxWaitSeconds segundos." -ForegroundColor Red
    Write-Host "  No se continua con el backup para evitar corromper el mundo." -ForegroundColor Red
    Write-Host "  Verifica manualmente el proceso antes de reintentar." -ForegroundColor Red
    exit 1
}
Write-Host "  Servidor cerrado correctamente." -ForegroundColor Green

# 3. Comprimir el mundo
Write-Host "`n[3/6] Comprimiendo carpeta world/..." -ForegroundColor Yellow
if (Test-Path $WorldZip) { Remove-Item $WorldZip -Force }
Compress-Archive -Path (Join-Path $WorldFolder "*") -DestinationPath $WorldZip -Force
$sizeMB = [math]::Round((Get-Item $WorldZip).Length / 1MB, 2)
Write-Host "  world.zip creado ($sizeMB MB)." -ForegroundColor Green

# 4. Subir el mundo a Drive
Write-Host "`n[4/6] Subiendo mundo a Google Drive..." -ForegroundColor Yellow
rclone copy $WorldZip "$RcloneRemote/" --progress
if ($LASTEXITCODE -ne 0) {
    Write-Host "  ERROR: la subida a Drive fallo. El lock NO se libera para evitar que otro host" -ForegroundColor Red
    Write-Host "  arranque sobre un mundo desactualizado. Reintenta la subida manualmente:" -ForegroundColor Red
    Write-Host "    rclone copy `"$WorldZip`" `"$RcloneRemote/`" --progress" -ForegroundColor Gray
    exit 1
}
Write-Host "  Mundo sincronizado correctamente." -ForegroundColor Green

# 5. Commit y push de archivos de estado (whitelist, ops, bans) si cambiaron
Write-Host "`n[5/6] Verificando cambios en whitelist/ops/bans..." -ForegroundColor Yellow
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

# 6. Liberar el lock remoto
Write-Host "`n[6/6] Liberando lock de host..." -ForegroundColor Yellow
rclone deletefile $RemoteLockFile 2>$null
Write-Host "  Lock liberado. El servidor ya puede ser iniciado por otro host." -ForegroundColor Green

Write-Host "`n=== Cierre completo ===" -ForegroundColor Cyan