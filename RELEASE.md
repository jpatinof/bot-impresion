# Publicar una nueva version

1. Sube la version en `package.json`.
2. Genera el manifest y sincroniza `windows/updater-config.json`:
   `npm run release:prepare -- --repo OWNER/REPO --installer bot-impresion-windows.zip`
3. Genera el ZIP real que vas a publicar con el mismo nombre del asset configurado.
4. Comprueba localmente el manifest:
   `npm run release:check-local`
5. Publica manualmente en GitHub Releases:
   `npm run release:publish -- -Repo OWNER/REPO -InstallerPath C:\ruta\bot-impresion-windows.zip`

El updater de Windows consume por defecto `latest.json` desde GitHub Releases usando:

`https://github.com/OWNER/REPO/releases/latest/download/latest.json`

Cada release debe adjuntar dos assets con nombres estables:

- `latest.json`
- `bot-impresion-windows.zip`

Mientras no exista un instalador `.exe`, el updater solo descargara el ZIP publicado y la actualizacion seguira siendo manual.

Si no quieres usar GitHub Releases, puedes definir `manifestUrl` manualmente en `windows/updater-config.json` y apuntar a cualquier URL publica que sirva el mismo JSON.
