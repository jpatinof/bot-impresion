## Bot Impresion

Bot de WhatsApp para recibir documentos y enviarlos a impresion en Windows y Linux.

### Windows hoy

El proyecto ya publica releases y manifiesto de actualizacion en GitHub, pero todavia no genera un instalador `.exe` real.

- Asset principal actual: `bot-impresion-windows.zip`
- Manifest de actualizacion: `latest.json`
- Repo publico: `https://github.com/jpatinof/bot-impresion`

### Instalar en Windows

1. Descarga `bot-impresion-windows.zip` desde Releases.
2. Extrae el ZIP en una carpeta fija, por ejemplo `C:\bot-impresion`.
3. Instala Node.js 20 LTS o superior.
4. Abre PowerShell en la carpeta extraida y ejecuta `npm install`.
5. Si tu impresora no se llama `L220`, define `PRINTER_NAME` en tu sesion o en el sistema.
6. Inicia el bot con `npm run start:windows`.
7. Escanea el QR de WhatsApp cuando aparezca.

### Actualizar en Windows

La bandeja de Windows puede comprobar actualizaciones y descargar el ZIP mas reciente, pero la sustitucion de archivos sigue siendo manual mientras no exista un instalador `.exe`.

### Desarrollo rapido

- `npm install`
- `npm run validate`
- `npm start`

### Publicar una release

Consulta `RELEASE.md`.
