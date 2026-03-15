const { Client, LocalAuth } = require('whatsapp-web.js');
const qrcode = require('qrcode-terminal');
const QRCode = require('qrcode');
const fs = require('fs');
const path = require('path');
const { execFile, spawn } = require('child_process');
const { promisify } = require('util');
const { createCanvas } = require('@napi-rs/canvas');

const execFileAsync = promisify(execFile);

const IS_WINDOWS = process.platform === 'win32';
const APP_HOME = process.env.BOT_IMPRESION_HOME || __dirname;
const APP_DATA_DIR = process.env.BOT_IMPRESION_DATA_DIR
    || (IS_WINDOWS && process.env.LOCALAPPDATA
        ? path.join(process.env.LOCALAPPDATA, 'BotImpresion', 'data')
        : APP_HOME);
const PRINTER_NAME = process.env.PRINTER_NAME || 'L220';
const USERS_FILE = path.join(APP_DATA_DIR, 'users.json');
const TEMP_DIR = path.join(APP_DATA_DIR, 'temp');
const WINDOWS_DIR = path.join(__dirname, 'windows');
const QR_WINDOW_DIR = path.join(APP_DATA_DIR, 'qr-window');
const QR_WINDOW_IMAGE_PATH = path.join(QR_WINDOW_DIR, 'whatsapp-qr.png');
const QR_WINDOW_STATE_PATH = path.join(QR_WINDOW_DIR, 'state.json');
const QR_WINDOW_SCRIPT = path.join(WINDOWS_DIR, 'whatsapp-qr-window.ps1');
const PASSWORD_MAX_ATTEMPTS = 3;
const PASSWORD_TTL_MS = 10 * 60 * 1000;
const IMAGE_EXTENSIONS = new Set(['.jpg', '.jpeg', '.png', '.gif', '.bmp', '.webp', '.tif', '.tiff']);
const CONVERTIBLE_DOCUMENT_EXTENSIONS = new Set([
    '.doc',
    '.docx',
    '.odt',
    '.rtf',
    '.txt',
    '.xls',
    '.xlsx',
    '.ods',
    '.ppt',
    '.pptx',
    '.odp'
]);
const MIME_EXTENSION_MAP = {
    'application/pdf': 'pdf',
    'image/jpeg': 'jpg',
    'image/png': 'png',
    'image/gif': 'gif',
    'image/bmp': 'bmp',
    'image/webp': 'webp',
    'image/tiff': 'tiff',
    'application/msword': 'doc',
    'application/vnd.openxmlformats-officedocument.wordprocessingml.document': 'docx',
    'application/vnd.oasis.opendocument.text': 'odt',
    'application/rtf': 'rtf',
    'text/plain': 'txt',
    'application/vnd.ms-excel': 'xls',
    'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet': 'xlsx',
    'application/vnd.oasis.opendocument.spreadsheet': 'ods',
    'application/vnd.ms-powerpoint': 'ppt',
    'application/vnd.openxmlformats-officedocument.presentationml.presentation': 'pptx',
    'application/vnd.oasis.opendocument.presentation': 'odp'
};

const pendingPasswordRequests = new Map();
let pdfjsLibPromise = null;
let qrWindowProcess = null;

class PdfPasswordError extends Error {
    constructor(code) {
        super(code);
        this.name = 'PdfPasswordError';
        this.code = code;
    }
}

class NodeCanvasFactory {
    create(width, height) {
        const canvas = createCanvas(Math.max(1, Math.ceil(width)), Math.max(1, Math.ceil(height)));
        const context = canvas.getContext('2d');
        return { canvas, context };
    }

    reset(target, width, height) {
        target.canvas.width = Math.max(1, Math.ceil(width));
        target.canvas.height = Math.max(1, Math.ceil(height));
    }

    destroy(target) {
        target.canvas.width = 0;
        target.canvas.height = 0;
        target.canvas = null;
        target.context = null;
    }
}

function sleep(ms) {
    return new Promise((resolve) => setTimeout(resolve, ms));
}

function ensureDirectory(dirPath) {
    if (!fs.existsSync(dirPath)) {
        fs.mkdirSync(dirPath, { recursive: true });
    }
}

function writeJsonFile(filePath, payload) {
    fs.writeFileSync(filePath, JSON.stringify(payload, null, 2), 'utf-8');
}

function updateQrWindowState(status, extra = {}) {
    if (!IS_WINDOWS) {
        return;
    }

    try {
        ensureDirectory(QR_WINDOW_DIR);
        writeJsonFile(QR_WINDOW_STATE_PATH, {
            status,
            updatedAt: new Date().toISOString(),
            ...extra
        });
    } catch (err) {
        console.error('[QR] No se pudo actualizar el estado de la ventana QR:', err.message);
    }
}

function closeQrWindow() {
    updateQrWindowState('ready');

    if (qrWindowProcess && !qrWindowProcess.killed) {
        qrWindowProcess.kill();
        qrWindowProcess = null;
    }
}

function ensureQrWindow() {
    if (!IS_WINDOWS || !fs.existsSync(QR_WINDOW_SCRIPT)) {
        return;
    }

    if (qrWindowProcess && !qrWindowProcess.killed) {
        return;
    }

    qrWindowProcess = spawn('powershell.exe', [
        '-NoProfile',
        '-ExecutionPolicy', 'Bypass',
        '-WindowStyle', 'Hidden',
        '-File', QR_WINDOW_SCRIPT,
        '-StatePath', QR_WINDOW_STATE_PATH,
        '-ImagePath', QR_WINDOW_IMAGE_PATH,
        '-ParentProcessId', String(process.pid)
    ], {
        stdio: 'ignore',
        windowsHide: true
    });

    qrWindowProcess.on('exit', () => {
        qrWindowProcess = null;
    });

    qrWindowProcess.on('error', (err) => {
        console.error('[QR] No se pudo abrir la ventana QR de Windows:', err.message);
        qrWindowProcess = null;
    });
}

async function renderQrImage(qrText) {
    ensureDirectory(QR_WINDOW_DIR);
    await QRCode.toFile(QR_WINDOW_IMAGE_PATH, qrText, {
        type: 'png',
        width: 360,
        margin: 2,
        color: {
            dark: '#111827',
            light: '#FFFFFFFF'
        }
    });
}

async function handleQrReceived(qrText) {
    console.log('[QR] Escanea el siguiente codigo QR con WhatsApp:');
    qrcode.generate(qrText, { small: true });

    if (!IS_WINDOWS) {
        return;
    }

    try {
        await renderQrImage(qrText);
        updateQrWindowState('qr', {
            title: 'Vincular WhatsApp',
            message: 'Escanea este codigo QR con WhatsApp para iniciar sesion en el bot.'
        });
        ensureQrWindow();
    } catch (err) {
        console.error('[QR] No se pudo preparar la ventana QR de Windows:', err.message);
    }
}

function registerProcessShutdownHandlers() {
    const shutdown = () => {
        closeQrWindow();
    };

    process.on('exit', shutdown);
    process.on('SIGINT', () => {
        shutdown();
        process.exit(0);
    });
    process.on('SIGTERM', () => {
        shutdown();
        process.exit(0);
    });
}

function loadUsers() {
    try {
        if (!fs.existsSync(USERS_FILE)) {
            fs.writeFileSync(USERS_FILE, JSON.stringify([], null, 2), 'utf-8');
            return [];
        }

        const users = JSON.parse(fs.readFileSync(USERS_FILE, 'utf-8'));
        return Array.isArray(users) ? users : [];
    } catch (err) {
        console.error('[USERS] No se pudo leer users.json:', err.message);
        return [];
    }
}

function saveUsers(users) {
    try {
        fs.writeFileSync(USERS_FILE, JSON.stringify(users, null, 2), 'utf-8');
    } catch (err) {
        console.error('[USERS] No se pudo guardar users.json:', err.message);
    }
}

function sanitizeFilename(filename) {
    const cleaned = String(filename || 'archivo')
        .replace(/[<>:"/\\|?*\x00-\x1F]/g, '_')
        .replace(/\s+/g, ' ')
        .trim();

    return cleaned || `archivo_${Date.now()}`;
}

function extensionFromMime(mimetype) {
    if (!mimetype) {
        return 'bin';
    }

    return MIME_EXTENSION_MAP[mimetype.split(';')[0].trim().toLowerCase()] || 'bin';
}

function resolveIncomingFilename(media) {
    const originalName = media.filename ? sanitizeFilename(media.filename) : '';
    if (originalName && path.extname(originalName)) {
        return originalName;
    }

    const extension = extensionFromMime(media.mimetype);
    const baseName = originalName || `archivo_${Date.now()}`;
    return `${baseName}.${extension}`;
}

function cleanupFile(filePath) {
    try {
        if (filePath && fs.existsSync(filePath)) {
            fs.unlinkSync(filePath);
            console.log('[CLEANUP] Archivo eliminado:', filePath);
        }
    } catch (err) {
        console.error('[CLEANUP] No se pudo eliminar archivo:', filePath, err.message);
    }
}

function cleanupFiles(filePaths) {
    for (const filePath of filePaths) {
        cleanupFile(filePath);
    }
}

function validateFileHasContent(filePath, label) {
    if (!filePath || !fs.existsSync(filePath)) {
        throw new Error(`${label} no encontrado.`);
    }

    const stats = fs.statSync(filePath);
    if (stats.size < 1) {
        throw new Error(`${label} vacio.`);
    }

    return stats;
}

function getPendingKey(chatId, senderId) {
    return `${chatId}::${senderId}`;
}

function clearPendingPasswordRequest(chatId, senderId, cleanupStoredFile = true) {
    const key = getPendingKey(chatId, senderId);
    const pending = pendingPasswordRequests.get(key);
    if (!pending) {
        return null;
    }

    pendingPasswordRequests.delete(key);
    if (cleanupStoredFile) {
        cleanupFile(pending.filePath);
    }

    return pending;
}

function setPendingPasswordRequest(chatId, senderId, filePath, filename) {
    const key = getPendingKey(chatId, senderId);
    clearPendingPasswordRequest(chatId, senderId, true);

    const pending = {
        chatId,
        senderId,
        filePath,
        filename,
        attemptsUsed: 0,
        expiresAt: Date.now() + PASSWORD_TTL_MS
    };

    pendingPasswordRequests.set(key, pending);
    return pending;
}

function getPendingPasswordRequest(chatId, senderId) {
    const key = getPendingKey(chatId, senderId);
    const pending = pendingPasswordRequests.get(key);
    if (!pending) {
        return null;
    }

    if (pending.expiresAt <= Date.now()) {
        clearPendingPasswordRequest(chatId, senderId, true);
        return null;
    }

    return pending;
}

function purgeExpiredPasswordRequests() {
    const now = Date.now();
    for (const [key, pending] of pendingPasswordRequests.entries()) {
        if (pending.expiresAt <= now) {
            pendingPasswordRequests.delete(key);
            cleanupFile(pending.filePath);
            console.log('[PDF] Solicitud de clave expirada:', pending.senderId);
        }
    }
}

function getMessageSenderId(msg) {
    return msg.author || msg.from;
}

function isImageExtension(ext) {
    return IMAGE_EXTENSIONS.has(ext);
}

function isConvertibleDocumentExtension(ext) {
    return CONVERTIBLE_DOCUMENT_EXTENSIONS.has(ext);
}

function isSupportedIncomingExtension(ext) {
    return ext === '.pdf' || isImageExtension(ext) || isConvertibleDocumentExtension(ext);
}

function findExistingPath(pathsToCheck) {
    for (const candidate of pathsToCheck) {
        if (candidate && fs.existsSync(candidate)) {
            return candidate;
        }
    }

    return null;
}

async function canExecute(command, args = ['--version']) {
    try {
        await execFileAsync(command, args, { windowsHide: true, timeout: 10000 });
        return true;
    } catch (_) {
        return false;
    }
}

async function resolveLibreOfficePath() {
    const candidates = [
        process.env.LIBREOFFICE_PATH,
        'C:\\Program Files\\LibreOffice\\program\\soffice.exe',
        'C:\\Program Files (x86)\\LibreOffice\\program\\soffice.exe',
        '/usr/bin/libreoffice',
        '/usr/bin/soffice',
        '/snap/bin/libreoffice'
    ];

    const existing = findExistingPath(candidates);
    if (existing) {
        return existing;
    }

    if (await canExecute('soffice')) {
        return 'soffice';
    }

    if (await canExecute('libreoffice')) {
        return 'libreoffice';
    }

    return null;
}

function getPowerShellExecutable() {
    return process.env.POWERSHELL_PATH || (IS_WINDOWS ? 'powershell.exe' : 'pwsh');
}

async function runPowerShellCommand(command, timeout = 30000) {
    return execFileAsync(
        getPowerShellExecutable(),
        ['-NoProfile', '-ExecutionPolicy', 'Bypass', '-Command', command],
        {
            windowsHide: true,
            timeout,
            maxBuffer: 10 * 1024 * 1024
        }
    );
}

async function runPowerShellFile(scriptPath, args, timeout = 120000) {
    return execFileAsync(
        getPowerShellExecutable(),
        ['-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', scriptPath, ...args],
        {
            windowsHide: true,
            timeout,
            maxBuffer: 10 * 1024 * 1024
        }
    );
}

function escapePowerShellString(value) {
    return String(value || '').replace(/'/g, "''");
}

async function getPdfjsLib() {
    if (!pdfjsLibPromise) {
        pdfjsLibPromise = import('pdfjs-dist/legacy/build/pdf.mjs');
    }

    return pdfjsLibPromise;
}

async function closePdfDocument(document) {
    if (!document) {
        return;
    }

    try {
        await document.cleanup();
    } catch (_) {
        // Ignorado.
    }

    try {
        await document.destroy();
    } catch (_) {
        // Ignorado.
    }
}

async function openPdfDocument(filePath, password) {
    validateFileHasContent(filePath, 'PDF');

    const pdfjsLib = await getPdfjsLib();
    const data = new Uint8Array(fs.readFileSync(filePath));
    let passwordReason = null;

    const loadingTask = pdfjsLib.getDocument({
        data,
        disableWorker: true,
        password: typeof password === 'string' ? password : undefined,
        useSystemFonts: true,
        isEvalSupported: false,
        verbosity: 0
    });

    loadingTask.onPassword = (updatePassword, reason) => {
        passwordReason = reason;
        updatePassword(typeof password === 'string' ? password : '');
    };

    try {
        const document = await loadingTask.promise;
        return { document, encrypted: passwordReason !== null };
    } catch (err) {
        const providedPassword = typeof password === 'string' && password.length > 0;

        if (passwordReason === pdfjsLib.PasswordResponses.NEED_PASSWORD && !providedPassword) {
            throw new PdfPasswordError('PASSWORD_REQUIRED');
        }

        if (passwordReason !== null && providedPassword) {
            throw new PdfPasswordError('INCORRECT_PASSWORD');
        }

        if (passwordReason === pdfjsLib.PasswordResponses.NEED_PASSWORD) {
            throw new PdfPasswordError('PASSWORD_REQUIRED');
        }

        throw err;
    }
}

async function inspectPdf(filePath, password) {
    let document;

    try {
        const opened = await openPdfDocument(filePath, password);
        document = opened.document;

        if (!Number.isFinite(document.numPages) || document.numPages < 1) {
            throw new Error('PDF sin paginas imprimibles.');
        }

        return {
            totalPages: document.numPages,
            encrypted: opened.encrypted
        };
    } finally {
        await closePdfDocument(document);
    }
}

async function convertDocumentToPdf(documentPath, filename) {
    const libreOfficePath = await resolveLibreOfficePath();
    if (!libreOfficePath) {
        throw new Error('LibreOffice no esta disponible en este equipo.');
    }

    const ext = path.extname(filename).toLowerCase();
    const pdfName = `${path.basename(filename, ext)}.pdf`;
    const outputPdfPath = path.join(TEMP_DIR, pdfName);

    cleanupFile(outputPdfPath);

    const args = [
        '--headless',
        '--invisible',
        '--nodefault',
        '--nofirststartwizard',
        '--nologo',
        '--convert-to',
        'pdf',
        documentPath,
        '--outdir',
        TEMP_DIR
    ];

    console.log('[CONVERT] Convirtiendo documento con LibreOffice:', filename);
    await execFileAsync(libreOfficePath, args, {
        windowsHide: true,
        timeout: 120000,
        maxBuffer: 10 * 1024 * 1024
    });

    validateFileHasContent(outputPdfPath, 'PDF convertido');
    await inspectPdf(outputPdfPath);
    return outputPdfPath;
}

async function validatePrinterHardware() {
    if (IS_WINDOWS) {
        try {
            const printerName = escapePowerShellString(PRINTER_NAME);
            const command = `$printer = Get-Printer -Name '${printerName}' -ErrorAction SilentlyContinue; if ($null -eq $printer) { Write-Output 'missing'; exit 2 }; if ($printer.PrinterStatus -eq 'Offline') { Write-Output 'offline'; exit 3 }; Write-Output 'ready'`;
            const { stdout } = await runPowerShellCommand(command, 15000);
            const status = stdout.trim().toLowerCase();

            if (status === 'ready') {
                return { available: true, error: null };
            }

            return { available: false, error: status || 'unknown' };
        } catch (err) {
            console.error('[PRINTER] Error validando impresora en Windows:', err.message);
            return { available: false, error: 'exception' };
        }
    }

    try {
        const { stdout } = await execFileAsync('lpstat', ['-p', PRINTER_NAME], {
            timeout: 10000,
            windowsHide: true
        });

        if (stdout.toLowerCase().includes('idle')) {
            return { available: true, error: null };
        }

        return { available: false, error: stdout.trim() || 'unknown' };
    } catch (err) {
        console.error('[PRINTER] Error validando impresora:', err.message);
        return { available: false, error: 'exception' };
    }
}

async function purgeRAM() {
    if (IS_WINDOWS) {
        return true;
    }

    try {
        await execFileAsync('sudo', ['sync'], { timeout: 10000, windowsHide: true });
        await execFileAsync('sudo', ['sh', '-c', 'echo 3 > /proc/sys/vm/drop_caches'], {
            timeout: 10000,
            windowsHide: true
        });
        return true;
    } catch (err) {
        console.error('[RAM] No se pudo purgar cache:', err.message);
        return false;
    }
}

async function convertPdfToAllImages(pdfPath, timestamp, password) {
    let document;
    const imageFiles = [];

    try {
        const opened = await openPdfDocument(pdfPath, password);
        document = opened.document;
        const canvasFactory = new NodeCanvasFactory();

        for (let pageNumber = 1; pageNumber <= document.numPages; pageNumber += 1) {
            const page = await document.getPage(pageNumber);
            const viewport = page.getViewport({ scale: 2.2 });
            const target = canvasFactory.create(viewport.width, viewport.height);

            await page.render({
                canvasContext: target.context,
                viewport,
                canvasFactory
            }).promise;

            const outputPath = path.join(TEMP_DIR, `page_${timestamp}_${pageNumber}.png`);
            fs.writeFileSync(outputPath, target.canvas.toBuffer('image/png'));
            validateFileHasContent(outputPath, `Imagen de pagina ${pageNumber}`);
            imageFiles.push(outputPath);

            page.cleanup();
            canvasFactory.destroy(target);
        }

        return imageFiles;
    } catch (err) {
        cleanupFiles(imageFiles);
        throw err;
    } finally {
        await closePdfDocument(document);
    }
}

async function waitForJobCompletion(jobId, maxWaitSeconds = 120) {
    if (IS_WINDOWS) {
        return { completed: true, error: null };
    }

    const startTime = Date.now();
    const maxWaitMs = maxWaitSeconds * 1000;

    while (Date.now() - startTime <= maxWaitMs) {
        try {
            const completed = await execFileAsync('lpstat', ['-W', 'completed', '-o'], {
                timeout: 5000,
                windowsHide: true
            });

            if (completed.stdout.includes(`-${jobId}`)) {
                return { completed: true, error: null };
            }

            const active = await execFileAsync('lpstat', ['-o'], {
                timeout: 5000,
                windowsHide: true
            });

            if (!active.stdout.includes(`-${jobId}`)) {
                return { completed: false, error: 'Job desaparecio de la cola.' };
            }
        } catch (err) {
            console.error('[PRINT] Error verificando job:', err.message);
        }

        await sleep(2000);
    }

    return { completed: false, error: 'Timeout esperando completar job.' };
}

async function printImageWithPriority(imagePath, pageNumber, totalPages) {
    validateFileHasContent(imagePath, `Imagen pagina ${pageNumber}`);

    if (IS_WINDOWS) {
        try {
            const scriptPath = path.join(WINDOWS_DIR, 'print-image.ps1');
            await runPowerShellFile(scriptPath, ['-PrinterName', PRINTER_NAME, '-ImagePath', imagePath], 120000);
            return { success: true, error: null };
        } catch (err) {
            console.error('[PRINT] Error imprimiendo imagen en Windows:', err.message);
            return { success: false, error: err.message };
        }
    }

    try {
        const { stdout } = await execFileAsync('lp', ['-d', PRINTER_NAME, '-o', 'media=Letter', '-o', 'fit-to-page', imagePath], {
            timeout: 30000,
            windowsHide: true
        });

        const jobIdMatch = stdout.match(/request id is .+-(\d+)/i);
        if (!jobIdMatch || !jobIdMatch[1]) {
            return { success: false, error: 'No se pudo obtener job ID.' };
        }

        const result = await waitForJobCompletion(jobIdMatch[1], 120);
        return result.completed
            ? { success: true, error: null }
            : { success: false, error: result.error };
    } catch (err) {
        console.error(`[PRINT] Error imprimiendo pagina ${pageNumber}/${totalPages}:`, err.message);
        return { success: false, error: err.message };
    }
}

function findBrowserExecutable() {
    const windowsCandidates = [
        path.join(process.env.PROGRAMFILES || '', 'Google', 'Chrome', 'Application', 'chrome.exe'),
        path.join(process.env['PROGRAMFILES(X86)'] || '', 'Google', 'Chrome', 'Application', 'chrome.exe'),
        path.join(process.env.PROGRAMFILES || '', 'Microsoft', 'Edge', 'Application', 'msedge.exe'),
        path.join(process.env['PROGRAMFILES(X86)'] || '', 'Microsoft', 'Edge', 'Application', 'msedge.exe')
    ];
    const linuxCandidates = [
        '/usr/bin/chromium-browser',
        '/usr/bin/chromium',
        '/snap/bin/chromium',
        '/usr/bin/google-chrome',
        '/usr/bin/microsoft-edge'
    ];

    return findExistingPath(IS_WINDOWS ? windowsCandidates : linuxCandidates) || undefined;
}

async function registerUser(senderId) {
    const users = loadUsers();
    if (!users.includes(senderId)) {
        users.push(senderId);
        saveUsers(users);
        console.log('[USER] Nuevo usuario registrado:', senderId);
    }
}

async function performSequentialPrint(msg, imageFiles) {
    const totalPages = imageFiles.length;
    let printedPages = 0;
    const failedPages = [];

    if (!IS_WINDOWS) {
        await msg.reply('Liberando memoria del sistema...');
        await purgeRAM();
        await sleep(1000);
    }

    await msg.reply('Iniciando impresion secuencial...');

    for (let index = 0; index < imageFiles.length; index += 1) {
        const pageNumber = index + 1;
        const result = await printImageWithPriority(imageFiles[index], pageNumber, totalPages);

        if (result.success) {
            printedPages += 1;
            await msg.reply(`Pagina ${pageNumber}/${totalPages} impresa correctamente.`);
        } else {
            failedPages.push(pageNumber);
            await msg.reply(`Error al imprimir pagina ${pageNumber}/${totalPages}.`);
        }

        if (pageNumber < totalPages) {
            await sleep(500);
        }
    }

    if (printedPages === totalPages) {
        await msg.reply(`Trabajo completado. Se imprimieron ${totalPages} pagina(s).`);
    } else if (printedPages > 0) {
        await msg.reply(`Impresion parcial: ${printedPages}/${totalPages}. Fallaron las paginas ${failedPages.join(', ')}.`);
    } else {
        await msg.reply('No se pudo imprimir ninguna pagina.');
    }
}

async function handlePdfWorkflow(msg, pdfPath, filename, password) {
    const printerStatus = await validatePrinterHardware();
    if (!printerStatus.available) {
        await msg.reply('La impresora no esta disponible. Verifica que este encendida y conectada.');
        return;
    }

    const pdfInfo = await inspectPdf(pdfPath, password);
    const timestamp = Date.now();
    let imageFiles = [];

    try {
        await msg.reply(`Procesando PDF de ${pdfInfo.totalPages} pagina(s)...`);
        imageFiles = await convertPdfToAllImages(pdfPath, timestamp, password);
        await msg.reply(`Documento listo. ${imageFiles.length} pagina(s) preparada(s) para imprimir.`);
        await performSequentialPrint(msg, imageFiles);
    } finally {
        cleanupFiles(imageFiles);
    }

    console.log('[PDF] Flujo completado para:', filename);
}

async function handleImageWorkflow(msg, imagePath, filename) {
    const printerStatus = await validatePrinterHardware();
    if (!printerStatus.available) {
        await msg.reply('La impresora no esta disponible. Verifica que este encendida y conectada.');
        return;
    }

    await msg.reply(`Procesando imagen ${filename}...`);
    const result = await printImageWithPriority(imagePath, 1, 1);

    if (result.success) {
        await msg.reply('Imagen enviada a impresion correctamente.');
    } else {
        await msg.reply('No se pudo imprimir la imagen.');
    }
}

async function handleConvertibleDocumentWorkflow(msg, documentPath, filename) {
    let convertedPdfPath = null;

    try {
        await msg.reply('Convirtiendo documento a PDF...');
        convertedPdfPath = await convertDocumentToPdf(documentPath, filename);
        await msg.reply('Documento convertido correctamente.');
        await handlePdfWorkflow(msg, convertedPdfPath, `${filename}.pdf`, null);
    } catch (err) {
        console.error('[DOC] Error convirtiendo documento:', err.message);
        await msg.reply('No se pudo convertir el documento. Asegurate de enviar un DOCX, DOC, ODT, RTF, TXT, XLSX o PPTX valido y que LibreOffice este instalado.');
    } finally {
        cleanupFile(convertedPdfPath);
    }
}

async function promptForPdfPassword(msg, senderId, pdfPath, filename) {
    setPendingPasswordRequest(msg.from, senderId, pdfPath, filename);
    await msg.reply('Este PDF tiene contrasena. Responde con la clave por este chat. Tienes 3 intentos y la solicitud vence en 10 minutos.');
}

async function handlePasswordReply(msg) {
    const senderId = getMessageSenderId(msg);
    const pending = getPendingPasswordRequest(msg.from, senderId);
    if (!pending) {
        return false;
    }

    const password = (msg.body || '').trim();
    if (!password) {
        await msg.reply('Envia la contrasena del PDF en un solo mensaje.');
        return true;
    }

    pending.attemptsUsed += 1;
    pending.expiresAt = Date.now() + PASSWORD_TTL_MS;

    try {
        await inspectPdf(pending.filePath, password);
        clearPendingPasswordRequest(pending.chatId, pending.senderId, false);
        await msg.reply('Clave correcta. Continuando con la impresion...');

        try {
            await handlePdfWorkflow(msg, pending.filePath, pending.filename, password);
        } finally {
            cleanupFile(pending.filePath);
        }

        return true;
    } catch (err) {
        if (err instanceof PdfPasswordError && err.code === 'INCORRECT_PASSWORD') {
            const remainingAttempts = PASSWORD_MAX_ATTEMPTS - pending.attemptsUsed;

            if (remainingAttempts > 0) {
                await msg.reply(`Clave incorrecta. Te quedan ${remainingAttempts} intento(s).`);
            } else {
                clearPendingPasswordRequest(pending.chatId, pending.senderId, true);
                await msg.reply('Se agotaron los 3 intentos por clave erronea. Envia el PDF de nuevo si deseas reintentar.');
            }

            return true;
        }

        clearPendingPasswordRequest(pending.chatId, pending.senderId, true);
        console.error('[PDF] Error procesando PDF protegido:', err.message);
        await msg.reply('No se pudo procesar el PDF protegido. Envia el archivo de nuevo.');
        return true;
    }
}

async function handleIncomingMediaMessage(msg) {
    const senderId = getMessageSenderId(msg);
    let downloadedFilePath = null;

    await registerUser(senderId);
    ensureDirectory(TEMP_DIR);

    const media = await msg.downloadMedia();
    if (!media) {
        await msg.reply('No se pudo descargar el archivo. Intentalo de nuevo.');
        return;
    }

    const filename = resolveIncomingFilename(media);
    const extension = path.extname(filename).toLowerCase();
    if (!isSupportedIncomingExtension(extension)) {
        await msg.reply('Formato no soportado. Envia PDF, imagen o un documento compatible con LibreOffice como DOCX, XLSX o PPTX.');
        return;
    }

    downloadedFilePath = path.join(TEMP_DIR, `${Date.now()}_${filename}`);
    fs.writeFileSync(downloadedFilePath, Buffer.from(media.data, 'base64'));
    validateFileHasContent(downloadedFilePath, filename);
    console.log('[DOWNLOAD] Archivo recibido:', downloadedFilePath);

    try {
        if (extension === '.pdf') {
            try {
                await inspectPdf(downloadedFilePath);
                await handlePdfWorkflow(msg, downloadedFilePath, filename, null);
                cleanupFile(downloadedFilePath);
                return;
            } catch (err) {
                if (err instanceof PdfPasswordError && err.code === 'PASSWORD_REQUIRED') {
                    await promptForPdfPassword(msg, senderId, downloadedFilePath, filename);
                    downloadedFilePath = null;
                    return;
                }

                throw err;
            }
        }

        if (isImageExtension(extension)) {
            await handleImageWorkflow(msg, downloadedFilePath, filename);
            return;
        }

        if (isConvertibleDocumentExtension(extension)) {
            await handleConvertibleDocumentWorkflow(msg, downloadedFilePath, filename);
            return;
        }

        await msg.reply('Formato no soportado.');
    } finally {
        cleanupFile(downloadedFilePath);
    }
}

const client = new Client({
    authStrategy: new LocalAuth({
        dataPath: path.join(APP_DATA_DIR, '.wwebjs_auth')
    }),
    puppeteer: {
        executablePath: findBrowserExecutable(),
        args: [
            '--no-sandbox',
            '--disable-setuid-sandbox',
            '--disable-dev-shm-usage'
        ]
    }
});

client.on('qr', async (qr) => {
    await handleQrReceived(qr);
});

client.on('authenticated', () => {
    console.log('[AUTH] Autenticacion exitosa.');
    closeQrWindow();
});

client.on('auth_failure', (message) => {
    console.error('[AUTH] Fallo de autenticacion:', message);
    updateQrWindowState('waiting', {
        title: 'Esperando nuevo codigo QR',
        message: 'La autenticacion fallo. Espera a que WhatsApp genere un nuevo codigo QR.'
    });
});

client.on('disconnected', (reason) => {
    console.warn('[WA] Cliente desconectado:', reason);
    updateQrWindowState('waiting', {
        title: 'Sesion desconectada',
        message: 'La sesion se desconecto. Espera a que aparezca un nuevo codigo QR si hace falta.'
    });
});

client.on('ready', async () => {
    console.log('[READY] Bot de impresion listo en', process.platform);
    closeQrWindow();

    try {
        const users = loadUsers();
        for (const userId of users) {
            try {
                await client.sendMessage(userId, 'Sistema listo. La impresora esta disponible para recibir documentos.');
            } catch (err) {
                console.error('[WA] No se pudo notificar a', userId, err.message);
            }

            await sleep(1000);
        }
    } catch (err) {
        console.error('[READY] Error enviando avisos de arranque:', err.message);
    }
});

client.on('message', async (msg) => {
    purgeExpiredPasswordRequests();

    try {
        if (!msg.hasMedia) {
            const consumedByPasswordFlow = await handlePasswordReply(msg);
            if (!consumedByPasswordFlow) {
                return;
            }

            return;
        }

        clearPendingPasswordRequest(msg.from, getMessageSenderId(msg), true);
        await handleIncomingMediaMessage(msg);
    } catch (err) {
        console.error('[ERROR] Error general procesando mensaje:', err.message);
        try {
            await msg.reply('Ocurrio un error inesperado. Envia el archivo nuevamente.');
        } catch (_) {
            // Ignorado.
        }
    }
});

ensureDirectory(APP_DATA_DIR);
ensureDirectory(TEMP_DIR);
updateQrWindowState('ready');
registerProcessShutdownHandlers();
setInterval(purgeExpiredPasswordRequests, 60 * 1000).unref();

console.log('[START] Iniciando bot de impresion...');
client.initialize().catch((err) => {
    console.error('[FATAL] No se pudo inicializar el cliente:', err.message);
    process.exit(1);
});
