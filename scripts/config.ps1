# =====================================================================
# Config.ps1 - Configuracion compartida por todos los scripts
# Cada host debe ajustar $ServerPath a su propia ruta local.
# =====================================================================

$ServerPath      = "E:\MinecraftServerFinal"
$WorldFolder     = Join-Path $ServerPath "world"
$WorldZip        = Join-Path $ServerPath "world.zip"
$ModsFolder      = Join-Path $ServerPath "mods"
$ManifestPath    = Join-Path $ServerPath "modpack.manifest.json"
$InstalledMarker = Join-Path $ServerPath "modpack.installed.json"
$RunScript       = Join-Path $ServerPath "run.bat"

$RconHost        = "127.0.0.1"
$RconPort        = 25575
$RconPassword    = "pass123"     # Debe coincidir con server.properties

$RcloneRemote    = "mcworld:minecraft-server"
$RemoteWorldZip  = "$RcloneRemote/world.zip"
$RemoteLockFile  = "$RcloneRemote/host.lock"

$JavaProcessName = "java"
$StateFiles      = @("whitelist.json", "ops.json", "banned-players.json", "banned-ips.json")
$MaxWaitSeconds  = 120
$LockStaleHours  = 12   # Si un lock es mas viejo que esto, se avisa que podria estar huerfano

# Direccion fija de conexion via Tailscale MagicDNS (sin depender de servicios externos)
$TailscaleHostname     = "mcserver"                    # Nombre que toma quien este hosteando
$TailscaleDomainSuffix = "taild2e858.ts.net"             # Sacalo de 'tailscale status', la parte despues del primer punto
$OriginalHostname      = $env:COMPUTERNAME              # Nombre a devolver al cerrar