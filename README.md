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
3. Espera a que cree la carpeta `%LOCALAPPDATA%\BotImpresion`, los accesos directos y arranque el bot.
4. Escanea el QR de WhatsApp cuando aparezca.
5. Si tu impresora no se llama `L220`, define `PRINTER_NAME` en Windows antes de iniciar de nuevo.

### Actualizar en Windows

La bandeja de Windows puede comprobar actualizaciones y descargar/ejecutar la nueva version automaticamente cuando la release publique `latest.json` y `bot-impresion-setup.exe`.

### Desarrollo rapido

- `npm install`
- `npm run validate`
- `npm start`

### Construir instalador Windows

- `npm run build:windows-installer`
- Salida esperada en `release\`:
  - `bot-impresion-setup.exe`
  - `bot-impresion-windows-package.zip`

### Publicar una release

Consulta `RELEASE.md`.
