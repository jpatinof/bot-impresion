const fs = require('fs');
const path = require('path');

const projectRoot = path.resolve(__dirname, '..');
const packageJsonPath = path.join(projectRoot, 'package.json');
const updaterConfigPath = path.join(projectRoot, 'windows', 'updater-config.json');

function parseArgs(argv) {
  const args = {};

  for (let index = 0; index < argv.length; index += 1) {
    const token = argv[index];

    if (!token.startsWith('--')) {
      continue;
    }

    const key = token.slice(2);
    const next = argv[index + 1];

    if (!next || next.startsWith('--')) {
      args[key] = 'true';
      continue;
    }

    args[key] = next;
    index += 1;
  }

  return args;
}

function ensureTrailingNewline(text) {
  return text.endsWith('\n') ? text : `${text}\n`;
}

function githubLatestDownloadUrl(repo, assetName) {
  return `https://github.com/${repo}/releases/latest/download/${assetName}`;
}

function writeJson(filePath, value) {
  const content = ensureTrailingNewline(JSON.stringify(value, null, 2));
  fs.mkdirSync(path.dirname(filePath), { recursive: true });
  fs.writeFileSync(filePath, content, 'utf8');
}

function main() {
  const args = parseArgs(process.argv.slice(2));

  if (args.help === 'true') {
    process.stdout.write([
      'Uso:',
      '  npm run release:prepare -- --repo OWNER/REPO --installer bot-impresion-setup.exe',
      '',
      'Opciones:',
      '  --version         Version a publicar. Default: package.json version',
      '  --repo            Repositorio GitHub en formato OWNER/REPO',
      '  --installer       Nombre del asset del instalador',
      '  --manifest-asset  Nombre del asset del manifest. Default: latest.json',
      '  --manifest-url    URL explicita del manifest remoto',
      '  --download-url    URL explicita del instalador remoto',
      '  --notes-url       URL opcional a notas de version',
      '  --published-at    Fecha ISO opcional para el manifest',
      '  --output          Ruta del manifest a generar. Default: release/latest.json',
      '  --skip-config-update true para no tocar updater-config.json'
    ].join('\n'));
    return;
  }

  const packageJson = JSON.parse(fs.readFileSync(packageJsonPath, 'utf8'));
  const updaterConfig = JSON.parse(fs.readFileSync(updaterConfigPath, 'utf8'));
  const version = args.version || packageJson.version;
  const githubRepo = args.repo || updaterConfig.githubRepo || '';
  const installerAssetName = args.installer || updaterConfig.installerAssetName || 'bot-impresion-setup.exe';
  const manifestAssetName = args['manifest-asset'] || updaterConfig.manifestAssetName || 'latest.json';
  const notesUrl = args['notes-url'] || updaterConfig.releaseNotesUrl || '';
  const publishedAt = args['published-at'] || new Date().toISOString();
  const shouldUpdateConfig = args['skip-config-update'] !== 'true';
  const outputPath = path.resolve(projectRoot, args.output || path.join('release', manifestAssetName));
  const manifestUrl = args['manifest-url'] || (githubRepo ? githubLatestDownloadUrl(githubRepo, manifestAssetName) : updaterConfig.manifestUrl || '');
  const downloadUrl = args['download-url'] || (githubRepo ? githubLatestDownloadUrl(githubRepo, installerAssetName) : '');

  if (!manifestUrl) {
    throw new Error('No se pudo resolver manifestUrl. Usa --repo o --manifest-url.');
  }

  if (!downloadUrl) {
    throw new Error('No se pudo resolver downloadUrl. Usa --repo o --download-url.');
  }

  if (shouldUpdateConfig) {
    updaterConfig.currentVersion = version;
    updaterConfig.manifestUrl = manifestUrl;
    updaterConfig.githubRepo = githubRepo;
    updaterConfig.manifestAssetName = manifestAssetName;
    updaterConfig.installerAssetName = installerAssetName;
    updaterConfig.releaseNotesUrl = notesUrl;
  }

  const manifest = {
    version,
    downloadUrl,
    publishedAt,
    notesUrl,
    assets: {
      installer: installerAssetName,
      manifest: manifestAssetName
    }
  };

  if (shouldUpdateConfig) {
    writeJson(updaterConfigPath, updaterConfig);
  }
  writeJson(outputPath, manifest);

  const instructionsPath = path.join(path.dirname(outputPath), 'github-release-instructions.txt');
  const tag = `v${version}`;
  const instructions = [
    'Flujo recomendado para GitHub Releases',
    '',
    `1. Genera o copia tu asset final con nombre ${installerAssetName}.`,
    `2. Crea una release/tag ${tag} en GitHub.`,
    `3. Sube estos assets a la release:`,
    `   - ${path.relative(projectRoot, outputPath)}`,
    `   - <ruta a ${installerAssetName}>`,
    '   - <ruta a bot-impresion-windows-package.zip> (opcional, recomendado)',
    '',
    githubRepo
      ? `Comando gh sugerido: gh release create ${tag} "${installerAssetName}" "bot-impresion-windows-package.zip" "${path.relative(projectRoot, outputPath)}" --repo ${githubRepo} --title "${tag}"`
      : 'Comando gh sugerido: gh release create <tag> <installer> <package-zip> <manifest> --repo OWNER/REPO --title <tag>',
    '',
    `Manifest remoto esperado: ${manifestUrl}`,
    `Asset remoto esperado: ${downloadUrl}`
  ].join('\n');

  fs.writeFileSync(instructionsPath, ensureTrailingNewline(instructions), 'utf8');

  process.stdout.write(`${JSON.stringify({
    version,
    manifestPath: path.relative(projectRoot, outputPath),
    instructionsPath: path.relative(projectRoot, instructionsPath),
    manifestUrl,
    downloadUrl
  }, null, 2)}\n`);
}

main();
