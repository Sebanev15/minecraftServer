# Minecraft Server Final


## Estructura esperada

La carpeta del servidor debe verse asi:

```text
MinecraftServerFinal/
  scripts/
    config.ps1
    iniciarServidor.ps1
    cerrarServidor.ps1
    serverManager.ps1
    RconFunctions.ps1
  world/
  mods/
  run.bat
  server.properties
  whitelist.json
  ops.json
  banned-players.json
  banned-ips.json
```

El detalle importante es que la carpeta scripts debe estar dentro del directorio raiz del servidor. A partir de ahi, config.ps1 calcula automaticamente la ruta raiz del server.

## Que tiene que tener instalado cada host

1. Git.
2. Java compatible con el modpack.
3. rclone configurado con acceso al remote usado para el mundo.
4. Tailscale instalado y con sesion iniciada.

## config.ps1

El archivo scripts/config.ps1 concentra los datos compartidos:

- RCON host, puerto y password.
- Remote de rclone para el mundo.
- Nombres de host de Tailscale.
- Tiempo maximo de espera para cerrar el proceso de Java.


## Configuracion de rclone


### Que hace rclone en este flujo

El servidor usa rclone para guardar y recuperar el mundo desde una carpeta compartida de Google Drive. La carpeta compartida se llama `minecraft-server` y dentro de esa carpeta viven los archivos sincronizados entre hosts.

En los scripts actuales se usan estas rutas:

- Remote del mundo: `mcworld:minecraft-server/world.zip`
- Lock del host: `mcworld:minecraft-server/host.lock`

La idea es esta:

- `minecraft-server` es la carpeta compartida en Google Drive.
- `world.zip` es el backup del mundo que se sube y se baja entre maquinas.
- `host.lock` es el archivo que indica que una maquina esta hosteando en ese momento.

### Como dejarlo listo

1. Instalar rclone.

```powershell
winget install Rclone.Rclone
```

2. Abrir una consola nueva y comprobar que rclone responde.

```powershell
rclone version
```

Si ese comando falla, no sigas con la configuracion hasta resolver la instalacion.

3. Ejecutar el asistente interactivo.

```powershell
rclone config
```

4. Crear un remote nuevo.

En el menu de `rclone config`, elegir la opcion para crear un remote nuevo. El nombre debe ser `mcworld`, porque los scripts ya esperan ese nombre.

5. Elegir el tipo de almacenamiento.

Cuando te pregunte por el tipo de storage, elegi Google Drive. En la lista de opciones normalmente aparece como `drive`.

6. Iniciar sesion en Google.

Durante el asistente te va a pedir autenticacion. Ese paso puede abrir el navegador o pedir un token en la consola, dependiendo del metodo de login. Completa ese paso una vez tengas la carpeta compartida `minecraft-server`.

7. Confirmar opciones avanzadas si el asistente las muestra.

En general, para un uso normal no hace falta tocar nada raro. Si no tenes un motivo concreto, acepta los valores por defecto.

8. Guardar la configuracion.

Cuando el asistente pregunte si queres guardar el remote, confirmalo. Al final debe quedar un remote llamado `mcworld`.

9. Verificar que el remote exista.

```powershell
rclone listremotes
```

La salida debe incluir `mcworld:`.

10. Verificar que la carpeta compartida exista en Google Drive.

```powershell
rclone lsd mcworld:
```

La cuenta conectada a rclone debe ver la carpeta compartida `minecraft-server`. Si no aparece, revisa permisos o la cuenta con la que iniciaste sesion.

11. Confirmar que la ruta compartida se puede leer y escribir.

Probalo creando un archivo chico y sincronizandolo dentro de la carpeta compartida:

```powershell
Set-Content .\rclone-test.txt "prueba"
rclone copy .\rclone-test.txt mcworld:minecraft-server\ --progress
rclone cat mcworld:minecraft-server\rclone-test.txt
Remove-Item .\rclone-test.txt
```

### Prueba minima de rclone

Antes de intentar levantar el server, conviene probar tres cosas:

```powershell
rclone lsd mcworld:minecraft-server
rclone copy .\world.zip mcworld:minecraft-server\ --progress
```

Si alguno de esos comandos falla, el server no va a poder sincronizar bien el mundo ni detectar el lock del host..

## Como levantar el server paso a paso

### Paso 1: abrir una consola en la carpeta scripts

La persona nueva debe abrir PowerShell en la carpeta scripts del server.

### Paso 2: iniciar el menu

Ejecutar:

```powershell
.\serverManager.ps1
```
Una vez veamos un menu parecido a este:
```text
=================================
Minecraft Server Manager
=================================
1) Iniciar servidor
2) Finalizar servidor
3) Actualizar (solo sincronizar sin jugar)
4) Estado del servidor
5) Salir
=================================
```
significa que se ejecuto correctamente el `serverManager.ps1`.
## Como levantar el servidor?
Para levantar el serivor simplemente debemos de ingresar la opcion 1. Esto hara comprobaciones y terminara abriendo una terminal aparte (esto es normal, significa que esta levantando el servidor)
## Como cerrar el server correctamente
Al terminar de jugar, la persona que esta hosteando debe usar la opcion de cerrar servidor ya que esto sirve para subir todos los cambios y dejar todo listo para el proximo host. Si no se hace esto el proximo host no quedara con los ultimos cambios

