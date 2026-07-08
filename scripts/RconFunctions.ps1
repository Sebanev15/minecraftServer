# =====================================================================
# RconFunctions.ps1 - Implementacion del protocolo Source RCON
# =====================================================================

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
        $length = 4 + 4 + $bodyBytes.Length + 2
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

    $authPacket = New-RconPacket -RequestId 1 -Type 3 -Body $Password
    $stream.Write($authPacket, 0, $authPacket.Length)
    $authResponse = Read-RconResponse -Stream $stream

    if ($authResponse.RequestId -eq -1) {
        $client.Close()
        throw "Autenticacion RCON fallida. Verifica rcon.password en server.properties."
    }

    $cmdPacket = New-RconPacket -RequestId 2 -Type 2 -Body $Command
    $stream.Write($cmdPacket, 0, $cmdPacket.Length)
    Start-Sleep -Milliseconds 200
    $cmdResponse = Read-RconResponse -Stream $stream

    $client.Close()
    return $cmdResponse.Body
}

function Wait-ForServerExit {
    param([string]$ProcessName, [int]$TimeoutSeconds)

    $elapsed = 0
    while ($elapsed -lt $TimeoutSeconds) {
        $proc = Get-Process -Name $ProcessName -ErrorAction SilentlyContinue
        if (-not $proc) { return $true }
        Start-Sleep -Seconds 2
        $elapsed += 2
        Write-Host "  Esperando cierre del servidor... ($elapsed s)" -ForegroundColor DarkGray
    }
    return $false
}

function Wait-ForServerReady {
    param([string]$ProcessName, [int]$TimeoutSeconds, [int]$PollSeconds = 3)

    $elapsed = 0
    while ($elapsed -lt $TimeoutSeconds) {
        $proc = Get-Process -Name $ProcessName -ErrorAction SilentlyContinue
        if ($proc) {
            # El proceso existe; probamos si RCON ya responde (senal de que "Done" ya paso)
            try {
                Send-RconCommand -HostName $RconHost -Port $RconPort -Password $RconPassword -Command "list" | Out-Null
                return $true
            } catch {
                # todavia no esta listo, seguimos esperando
            }
        }
        Start-Sleep -Seconds $PollSeconds
        $elapsed += $PollSeconds
        Write-Host "  Esperando que el servidor termine de arrancar... ($elapsed s)" -ForegroundColor DarkGray
    }
    return $false
}