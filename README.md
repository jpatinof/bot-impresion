## Bot Impresion

Bot de WhatsApp para recibir documentos y enviarlos a impresion en Windows y Linux.

### Windows hoy

El proyecto ya queda preparado para distribucion simple en Windows con instalador `.exe` y actualizacion desde la bandeja.

- Instalador principal: `bot-impresion-setup.exe`
- Paquete auxiliar: `bot-impresion-windows-package.zip`
- Manifest de actualizacion: `latest.json`
- Repo publico: `https://github.com/jpatinof/bot-impresion`

### Instalar en Windows

1. Descarga `bot-impresion-setup.exe` desde Releases.
2. Ejecuta el instalador. Si Windows SmartScreen muestra una alerta por ser una app sin firma, usa `Mas informacion` -> `Ejecutar de todas formas`.
3. Espera a que cree la carpeta `%LOCALAPPDATA%\BotImpresion`, los accesos directos y arranque el bot en segundo plano, sin dejar una consola CMD abierta.
4. Si no hay sesion guardada, se abrira una ventana de Windows con el QR de WhatsApp; escanealo desde el telefono.
5. Si tu impresora no se llama `L220`, define `PRINTER_NAME` en Windows antes de iniciar de nuevo.

### Actualizar en Windows

La bandeja de Windows puede comprobar actualizaciones y descargar/ejecutar la nueva version automaticamente cuando la release publique `latest.json` y `bot-impresion-setup.exe`.

El lanzador de Windows usa `windows/launch-tray-hidden.vbs` para iniciar la bandeja con PowerShell oculto; la ventana del QR sigue apareciendo aparte cuando WhatsApp pide autenticacion.

### Desarrollo rapido

- `npm install`
- `npm run validate`
- `npm start`

En Windows, cuando WhatsApp pida autenticacion, el bot genera `whatsapp-qr.png` y `state.json` dentro de `%LOCALAPPDATA%\BotImpresion\data\qr-window` para que la ventanita del QR se actualice y se cierre al completar la sesion.

### Construir instalador Windows

- `npm run build:windows-installer`
- Salida esperada en `release\`:
  - `bot-impresion-setup.exe`
  - `bot-impresion-windows-package.zip`

### Publicar una release

Consulta `RELEASE.md`.
