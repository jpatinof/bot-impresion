# Publicar una nueva version

1. Sube la version en `package.json`.
2. Genera el instalador Windows real y el paquete auxiliar:
   `npm run build:windows-installer`
3. Genera el manifest y sincroniza `windows/updater-config.json`:
   `npm run release:prepare -- --repo OWNER/REPO --installer bot-impresion-setup.exe`
4. Comprueba localmente el manifest:
   `npm run release:check-local`
5. Publica la release en GitHub con el instalador `.exe`, el manifest y opcionalmente el paquete `.zip`:
   `npm run release:publish -- -Repo OWNER/REPO -InstallerPath C:\ruta\bot-impresion-setup.exe`

El updater de Windows consume por defecto `latest.json` desde GitHub Releases usando:

`https://github.com/OWNER/REPO/releases/latest/download/latest.json`

Cada release debe adjuntar estos assets con nombres estables:

- `latest.json`
- `bot-impresion-setup.exe`

Notas operativas:

- El instalador actual se basa en IExpress y debe lanzar `powershell.exe -File install-app.ps1` directamente. Ejecutar `install-app.cmd` desde IExpress puede fallar con `Error en la creacion del proceso ...\install-app.cmd` en algunos equipos.
- Como el `.exe` no esta firmado, SmartScreen puede bloquear o esconder la ejecucion; indica al usuario que use `Mas informacion` -> `Ejecutar de todas formas`.

Asset opcional recomendado para soporte o reinstalacion manual:

- `bot-impresion-windows-package.zip`

El updater de Windows descargara `bot-impresion-setup.exe` y lo ejecutara para aplicar la actualizacion de forma simple. El instalador deja la app en `%LOCALAPPDATA%\BotImpresion`, crea accesos directos y arranca el bot automaticamente.

Si no quieres usar GitHub Releases, puedes definir `manifestUrl` manualmente en `windows/updater-config.json` y apuntar a cualquier URL publica que sirva el mismo JSON.
