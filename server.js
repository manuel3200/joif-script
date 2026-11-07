const express = require('express');
const cors = require('cors');
const crypto = require('node:crypto');
const { spawn } = require('child_process');
const db = require('./db');
const path = require('path');
const jwt = require('jsonwebtoken');
require('dotenv').config();
const security = require('./backend-security');
const SESSION_SECRET = security.sessionSecret(__dirname);

const app = express();
// The web panel and API share their origin.
app.use(express.json({ limit: '100kb' }));

// Servir el panel web ligero estático
app.use(express.static(path.join(__dirname, 'public')));

// ============================================
// MIDDLEWARE DE AUTENTICACIÓN JWT & API KEY
// ============================================
const authMiddleware = (req, res, next) => {
  const apiKey = req.headers['x-api-key'];
  const expectedApiKey = process.env.API_KEY || process.env.NODE_API_SECRET;
  if (typeof apiKey === 'string' && typeof expectedApiKey === 'string') {
    const bufA = Buffer.from(apiKey);
    const bufB = Buffer.from(expectedApiKey);
    if (bufA.length === bufB.length && crypto.timingSafeEqual(bufA, bufB)) {
      req.user = { username: 'central_hub' };
      return next();
    }
  }

  const authHeader = req.headers['authorization'];
  const token = authHeader && authHeader.split(' ')[1];
  if (!token) return res.status(401).json({ error: 'Acceso denegado' });

  jwt.verify(token, SESSION_SECRET, (err, user) => {
    if (err) return res.status(403).json({ error: 'Token inválido o expirado' });
    req.user = user;
    next();
  });
};

// ============================================
// ENDPOINTS DE GESTIÓN (API)
// ============================================

// Autenticación del Panel Web
app.post('/api/auth/login', async (req, res) => {
  const { username, password } = req.body;
  try {
    const userRes = await db.query("SELECT value FROM admin_config WHERE key = 'admin_user'");
    const passRes = await db.query("SELECT value FROM admin_config WHERE key = 'admin_pass'");
    const needsChangeRes = await db.query("SELECT value FROM admin_config WHERE key = 'needs_password_change'");

    const adminUser = userRes.rows[0]?.value || 'admin';
    const adminPass = passRes.rows[0]?.value;
    const needsChange = needsChangeRes.rows[0]?.value === 'true';

    if (username === adminUser && security.verifyPassword(password, adminPass)) {
      if (!adminPass.startsWith('scrypt$')) await db.query("UPDATE admin_config SET value = ? WHERE key = 'admin_pass'", [security.hashPassword(password)]);
      const secret = SESSION_SECRET;
      const token = jwt.sign({ username: adminUser }, secret, { expiresIn: '12h' });
      res.json({ token, needsChange });
    } else {
      res.status(401).json({ error: 'Credenciales incorrectas' });
    }
  } catch (err) {
    res.status(500).json({ error: err.message });
  }
});

// Cambio de contraseña obligatorio
app.post('/api/auth/change-password', authMiddleware, async (req, res) => {
  const { newPassword } = req.body;
  if (typeof newPassword !== 'string' || newPassword.length < 12 || newPassword.length > 256) return res.status(400).json({ error: 'La contraseña debe tener entre 12 y 256 caracteres.' });
  try {
    await db.query("UPDATE admin_config SET value = ? WHERE key = 'admin_pass'", [security.hashPassword(newPassword)]);
    await db.query("UPDATE admin_config SET value = 'false' WHERE key = 'needs_password_change'");
    res.json({ success: true });
  } catch (err) {
    res.status(500).json({ error: err.message });
  }
});

app.post('/api/users/:username/config', authMiddleware, async (req, res) => {
  try {
    const host = req.body.host;
    if (typeof host !== 'string' || host.length > 253 || !/^[A-Za-z0-9.-]+$/.test(host)) return res.status(400).json({ error: 'Host SSH inválido.' });
    const result = await db.query('SELECT username, password, hwid, status, expiration_date FROM users WHERE username = ?', [req.params.username]);
    const user = result.rows[0];
    if (!user) return res.status(404).json({ error: 'Cuenta inexistente.' });
    if (user.status !== 'active' || !Number.isFinite(Date.parse(user.expiration_date)) || Date.parse(user.expiration_date) <= Date.now()) return res.status(403).json({ error: 'Cuenta vencida o revocada.' });
    const nativeName = security.linuxName(user.username);
    const config = { schema_version: 1, protocol: 'ssh', server_string: host + ':22@' + nativeName + ':' + user.password, udpgw_ports: '7300', payload: '', sni_host: '', use_payload: false, use_ssl: false, is_locked: true, author_note: 'Cuenta SSH', hwid: user.hwid || '', use_hwid_auth: false, auth_user: nativeName, auth_pass: user.password };
    res.set('Cache-Control', 'no-store').json({ data: require('./joif').encrypt(config) });
  } catch (_) { res.status(500).json({ error: 'No se pudo generar la configuración.' }); }
});

// Obtener todos los usuarios
app.get('/api/users', authMiddleware, async (req, res) => {
  try {
    const result = await db.query('SELECT id, username, expiration_date, hwid, alias, max_connections, status, created_at FROM users');
    res.json(result.rows);
  } catch (err) {
    res.status(500).json({ error: err.message });
  }
});

// Crear usuario (Registra en DB y ejecuta comando en Linux)
app.post('/api/users', authMiddleware, async (req, res) => {
  let account;
  try { account = security.validateAccount(req.body); } catch (e) { return res.status(400).json({ error: e.message }); }
  let created = false;
  try {
    const exists = await db.query('SELECT id FROM users WHERE username = ? OR (hwid IS NOT NULL AND hwid = ?)', [account.username, account.hwid || account.username]);
    if (exists.rowCount) return res.status(409).json({ error: 'La cuenta ya existe.' });
    if (process.platform === 'linux') {
      try {
        await security.run('sudo', ['-n', 'useradd', '-M', '-s', '/bin/false', '--', account.nativeName]);
        created = true;
      } catch (err) {
        let existsOnLinux = false;
        try {
          await security.run('getent', ['passwd', account.nativeName]);
          existsOnLinux = true;
        } catch (_) {}
        if (!existsOnLinux) throw err;
      }
      await security.run('sudo', ['-n', 'chpasswd'], account.nativeName + ':' + account.password + '\n');
      await security.run('sudo', ['-n', 'chage', '-E', account.date, '--', account.nativeName]);
    }
    const result = await db.query('INSERT INTO users (username, password, expiration_date, max_connections, hwid, alias) VALUES (?, ?, ?, ?, ?, ?)', [account.username, account.password, account.expiresAt, account.connections, account.hwid, account.alias]);
    res.status(201).json({ message: 'Usuario creado con éxito', id: result.lastID, username: account.username, alias: account.alias });
  } catch (e) {
    if (created) { try { await security.run('sudo', ['-n', 'userdel', '-f', '--', account.nativeName]); } catch (_) { console.error('Requiere reconciliar cuenta Linux después de un alta fallida.'); } }
    res.status(500).json({ error: 'No se pudo crear la cuenta: ' + (e.message || 'Revisa los registros del servidor.') });
  }
});

app.delete('/api/users/:username', authMiddleware, async (req, res) => {
  try {
    const target = req.params.username;
    const result = await db.query('SELECT id, username, hwid, alias FROM users WHERE username = ? OR hwid = ? OR alias = ?', [target, target, target]);
    if (!result.rowCount) return res.status(404).json({ error: 'Usuario no encontrado.' });
    const row = result.rows[0];
    const nativeName = security.linuxName(row.username);
    if (process.platform === 'linux') {
      try { await security.run('sudo', ['-n', 'pkill', '-u', nativeName]); } catch (e) { if (e.exitCode !== 1) console.error(e); }
      let exists = true; try { await security.run('getent', ['passwd', nativeName]); } catch (e) { if (e.exitCode === 2) exists = false; else throw e; }
      if (exists) await security.run('sudo', ['-n', 'userdel', '-f', '--', nativeName]);
    }
    await db.query('DELETE FROM users WHERE id = ?', [row.id]);
    res.json({ message: 'Usuario eliminado con éxito.' });
  } catch (e) { res.status(500).json({ error: 'No se pudo eliminar la cuenta; se conserva el registro para reintentar.' }); }
});

app.delete('/api/users', authMiddleware, async (req, res) => {
  try {
    const result = await db.query('SELECT id, username, hwid, alias FROM users');
    if (process.platform === 'linux') {
      for (const row of result.rows) {
        const nativeName = security.linuxName(row.username);
        try { await security.run('sudo', ['-n', 'pkill', '-u', nativeName]); } catch (_) {}
        try { await security.run('sudo', ['-n', 'userdel', '-f', '--', nativeName]); } catch (_) {}
      }
    }
    await db.query('DELETE FROM users');
    res.json({ message: 'Todos los usuarios han sido eliminados por completo.' });
  } catch (e) { res.status(500).json({ error: 'No se pudo eliminar a todos los usuarios.' }); }
});

app.post('/api/users/:username/revoke', authMiddleware, async (req, res) => {
  try {
    const target = req.params.username;
    const result = await db.query('SELECT id, username, hwid, alias FROM users WHERE username = ? OR hwid = ? OR alias = ?', [target, target, target]);
    if (!result.rowCount) return res.status(404).json({ error: 'Usuario no encontrado.' });
    const row = result.rows[0];
    const nativeName = security.linuxName(row.username);
    if (process.platform === 'linux') {
      await security.run('sudo', ['-n', 'usermod', '-L', '--', nativeName]);
      await security.run('sudo', ['-n', 'chage', '-E', '0', '--', nativeName]);
      try { await security.run('sudo', ['-n', 'pkill', '-u', nativeName, 'sshd']); } catch (e) { if (e.exitCode !== 1) throw e; }
    }
    await db.query("UPDATE users SET status = 'revoked' WHERE id = ?", [row.id]);
    res.json({ message: 'Cuenta revocada.' });
  } catch (e) { res.status(500).json({ error: 'No se pudo revocar la cuenta; reintenta la operación.' }); }
});

// Obtener todos los usuarios array simple (CheckUser Global)
app.get(['/check', '/api/check'], async (req, res) => {
  try {
    const userRes = await db.query('SELECT username FROM users WHERE status = \'active\' AND julianday(expiration_date) > julianday(\'now\')');
    const userList = userRes.rows.map(row => row.username);
    res.json(userList);
  } catch (err) {
    res.status(500).json({ error: err.message });
  }
});

// Validar Cuenta (CheckUser API) - Compatible con SSHPLUS
app.get(['/api/check/:id', '/check/:id'], async (req, res) => {
  const { id } = req.params;
  try {
    const userRes = await db.query('SELECT username, hwid, expiration_date, max_connections, status FROM users WHERE username = ? OR hwid = ? LIMIT 1', [id, id]);
    if (userRes.rowCount === 0) {
      return res.status(404).json({ error: 'Usuario no encontrado' });
    }

    const user = userRes.rows[0];
    if (user.status !== 'active' || !Number.isFinite(Date.parse(user.expiration_date)) || Date.parse(user.expiration_date) <= Date.now()) return res.status(403).json({ error: 'Cuenta vencida o revocada.' });
    const linuxUser = user.username;
    
    // Calcular días restantes
    const expDate = new Date(user.expiration_date);
    const now = new Date();
    const diffTime = expDate - now;
    const diffDays = Math.ceil(diffTime / (1000 * 60 * 60 * 24));
    
    // Obtener conexiones activas y tiempo en línea
    let activeConnections = 0;
    let timeOnline = "00:00:00";
    if (process.platform === 'linux') {
      try {
        const current = security.sessions(await security.run('ps', ['-eo', 'etimes,args']), linuxUser);
        activeConnections = current.count; timeOnline = current.time;
      } catch (_) { console.error('[CheckUser] No se pudieron consultar las conexiones.'); }
    }

    const expDateStr = user.expiration_date.split('T')[0];
    const [year, month, day] = expDateStr.split('-');
    const formattedDate = `${day}/${month}/${year}`;

    res.json({
      count_connections: activeConnections,
      expiration_date: formattedDate,
      expiration_days: diffDays > 0 ? diffDays : 0,
      limit_connections: user.max_connections,
      time_online: timeOnline,
      username: user.username,
      uuid: user.hwid || null
    });
  } catch (err) {
    res.status(500).json({ error: err.message });
  }
});

// ============================================
// UDPGW DAEMON MANAGER
// ============================================
let udpgwProcess = null;

function startUdpgw() {
  if (process.platform !== 'linux') {
    console.log('[UDPGW] Entorno no Linux detectado. Saltando supervisor de badvpn-udpgw.');
    return;
  }

  console.log('[UDPGW] Iniciando daemon badvpn-udpgw en puerto 7300...');
  
  // Ejecutamos badvpn-udpgw
  udpgwProcess = spawn('badvpn-udpgw', [
    '--listen-addr', '127.0.0.1:7300',
    '--max-clients', '1000',
    '--max-connections-for-client', '10'
  ], {
    stdio: 'ignore' // Silenciamos los logs masivos de badvpn
  });

  udpgwProcess.on('error', (err) => {
    console.error('[UDPGW] Error al iniciar proceso:', err.message);
    if (err.code === 'ENOENT') {
      console.error('[UDPGW] IMPORTANTE: badvpn-udpgw no está instalado en el sistema.');
    }
  });

  udpgwProcess.on('close', (code) => {
    console.warn(`[UDPGW] Proceso terminado abruptamente (Código: ${code}). Reiniciando en 5 segundos...`);
    udpgwProcess = null;
    setTimeout(startUdpgw, 5000);
  });
}

// Iniciar supervisor al arrancar el agente
startUdpgw();
require('./account-reconciler').startReconciler(db);

const PORT = process.env.PORT || 3000;
(db.ready || Promise.resolve()).then(() => app.listen(PORT, () => {
  console.log(`Edge Node Manager & Web Panel Backend ejecutándose en http://localhost:${PORT}`);
})).catch(() => { console.error("La base de datos no está lista. El servidor no se inició."); process.exitCode = 1; });
