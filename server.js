const express = require('express');
const cors = require('cors');
const crypto = require('node:crypto');
const db = require('./db');
const path = require('path');
const jwt = require('jsonwebtoken');
require('dotenv').config();
const security = require('./backend-security');
const SESSION_SECRET = security.sessionSecret(__dirname);

const app = express();
app.use(cors());
app.use(express.json({ limit: '100kb' }));
if (typeof express.urlencoded === 'function') app.use(express.urlencoded({ extended: false, limit: '100kb' }));

// Servir el panel web ligero estático
app.use(express.static(path.join(__dirname, 'public')));

const loginLimiter = typeof security.createRateLimiter === 'function'
  ? security.createRateLimiter({ windowMs: 15 * 60 * 1000, max: 12 })
  : () => ({ allowed: true, retryAfterSec: 1 });
const checkLimiter = typeof security.createRateLimiter === 'function'
  ? security.createRateLimiter({ windowMs: 60 * 1000, max: 180 })
  : () => ({ allowed: true, retryAfterSec: 1 });

function clientIp(req) {
  return (req && (req.ip || req.socket?.remoteAddress || req.headers?.['x-forwarded-for'])) || 'unknown';
}

// ============================================
// MIDDLEWARE DE AUTENTICACIÓN JWT & API KEY
// ============================================
const authMiddleware = (req, res, next) => {
  const apiKey = req.headers['x-api-key'];
  const expectedApiKey = process.env.API_KEY || process.env.NODE_API_SECRET;
  if (typeof apiKey === 'string' && typeof expectedApiKey === 'string' && expectedApiKey.length > 0) {
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

// Autenticación del Panel Web (con rate-limit anti fuerza bruta)
app.post('/api/auth/login', async (req, res) => {
  const rate = loginLimiter(clientIp(req));
  if (!rate.allowed) {
    res.set('Retry-After', String(rate.retryAfterSec));
    return res.status(429).json({ error: 'Demasiados intentos de acceso. Intenta nuevamente más tarde.' });
  }
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

// Obtener todos los usuarios (enriquecidos con conexiones en vivo y tráfico formateado)
app.get('/api/users', authMiddleware, async (req, res) => {
  try {
    if (trafficCollector) {
      try { await trafficCollector.flushToDb(db); } catch (_) {}
    }
    const result = await db.query('SELECT id, username, expiration_date, hwid, alias, max_connections, COALESCE(bytes_used, 0) AS bytes_used, status, created_at FROM users');
    let sessionMap = new Map();
    if (process.platform === 'linux' && typeof security.allSessions === 'function') {
      try {
        sessionMap = security.allSessions(await security.run('ps', ['-eo', 'user:32,pid,etimes,args']));
      } catch (_) {}
    }
    const enriched = result.rows.map(row => {
      const live = sessionMap.get(String(row.username || '').toLowerCase()) || { count: 0, time: '00:00:00' };
      const bytes = Number(row.bytes_used) > 0 ? Number(row.bytes_used) : 0;
      return {
        ...row,
        bytes_used: bytes,
        gb_used: typeof security.formatTrafficBytes === 'function' ? security.formatTrafficBytes(bytes) : '0.00 MB',
        active_connections: live.count,
        time_online: live.time
      };
    });
    res.json(enriched);
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
        await security.run('sudo', ['-n', 'useradd', '-M', '-s', '/bin/false', '--badname', '--', account.nativeName]);
        created = true;
      } catch (err) {
        try {
          await security.run('sudo', ['-n', 'useradd', '-M', '-s', '/bin/false', '--', account.nativeName]);
          created = true;
        } catch (_) {}
        let existsOnLinux = false;
        try {
          await security.run('getent', ['passwd', account.nativeName]);
          existsOnLinux = true;
        } catch (_) {}
        if (!existsOnLinux && !created) throw err;
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
    const result = await db.query('SELECT id, username, hwid, alias FROM users WHERE username = ? COLLATE NOCASE OR hwid = ? COLLATE NOCASE OR alias = ? COLLATE NOCASE LIMIT 1', [target, target, target]);
    if (!result.rowCount) return res.status(404).json({ error: 'Usuario no encontrado.' });
    const row = result.rows[0];
    const nativeName = security.linuxName(row.username);
    if (process.platform === 'linux') {
      await security.run('sudo', ['-n', 'usermod', '-L', '--', nativeName]);
      await security.run('sudo', ['-n', 'chage', '-E', '0', '--', nativeName]);
      try { await security.run('sudo', ['-n', 'pkill', '-KILL', '-u', nativeName]); } catch (e) { if (e.exitCode !== 1) throw e; }
    }
    await db.query("UPDATE users SET status = 'revoked' WHERE id = ?", [row.id]);
    res.json({ message: 'Cuenta revocada.' });
  } catch (e) { res.status(500).json({ error: 'No se pudo revocar la cuenta; reintenta la operación.' }); }
});

app.post('/api/users/:username/unlock', authMiddleware, async (req, res) => {
  try {
    const target = req.params.username;
    const result = await db.query('SELECT id, username, hwid, alias, expiration_date FROM users WHERE username = ? COLLATE NOCASE OR hwid = ? COLLATE NOCASE OR alias = ? COLLATE NOCASE LIMIT 1', [target, target, target]);
    if (!result.rowCount) return res.status(404).json({ error: 'Usuario no encontrado.' });
    const row = result.rows[0];
    const nativeName = security.linuxName(row.username);
    const expMs = Date.parse(row.expiration_date);
    if (!Number.isFinite(expMs) || expMs <= Date.now()) {
      return res.status(400).json({ error: 'La cuenta está vencida; renueva su fecha antes de desbloquearla.' });
    }
    const chageDate = new Date(Math.ceil(expMs / 86400000) * 86400000).toISOString().slice(0, 10);
    if (process.platform === 'linux') {
      await security.run('sudo', ['-n', 'usermod', '-U', '--', nativeName]);
      await security.run('sudo', ['-n', 'chage', '-E', chageDate, '--', nativeName]);
    }
    await db.query("UPDATE users SET status = 'active' WHERE id = ?", [row.id]);
    res.json({ message: 'Cuenta reactivada con éxito.' });
  } catch (e) { res.status(500).json({ error: 'No se pudo reactivar la cuenta.' }); }
});

const handlePatchUser = async (req, res) => {
  try {
    const target = req.params.username;
    const result = await db.query('SELECT id, username, password, hwid, alias, expiration_date, max_connections, status FROM users WHERE username = ? COLLATE NOCASE OR hwid = ? COLLATE NOCASE OR alias = ? COLLATE NOCASE LIMIT 1', [target, target, target]);
    if (!result.rowCount) return res.status(404).json({ error: 'Usuario no encontrado.' });
    const row = result.rows[0];
    let patch;
    try { patch = security.validateUserPatch(req.body || {}, row); } catch (e) { return res.status(400).json({ error: e.message }); }

    let currentNative = security.linuxName(row.username);
    let nextUsername = row.username;
    let nextPassword = row.password;
    let nextHwid = row.hwid;
    let nextAlias = patch.alias !== undefined ? patch.alias : row.alias;
    let nextMax = patch.max_connections !== undefined ? patch.max_connections : row.max_connections;
    let nextExp = patch.expiresAt !== undefined ? patch.expiresAt : row.expiration_date;
    let nextStatus = row.status;

    if (patch.hwid && patch.hwid !== row.username) {
      const dup = await db.query('SELECT id FROM users WHERE (username = ? OR hwid = ?) AND id != ?', [patch.hwid, patch.hwid, row.id]);
      if (dup.rowCount) return res.status(409).json({ error: 'El nuevo HWID ya está asignado a otra cuenta.' });
      if (process.platform === 'linux') {
        try { await security.run('sudo', ['-n', 'pkill', '-KILL', '-u', currentNative]); } catch (e) { if (e.exitCode !== 1) throw e; }
        await security.run('sudo', ['-n', 'usermod', '-l', patch.hwid, '--', currentNative]);
        await security.run('sudo', ['-n', 'chpasswd'], patch.hwid + ':' + patch.hwid + '\n');
      }
      currentNative = patch.hwid;
      nextUsername = patch.hwid;
      nextPassword = patch.hwid;
      nextHwid = patch.hwid;
    } else if (patch.password !== undefined) {
      if (process.platform === 'linux') {
        await security.run('sudo', ['-n', 'chpasswd'], currentNative + ':' + patch.password + '\n');
      }
      nextPassword = patch.password;
    }

    if (patch.expiresAt !== undefined) {
      if (process.platform === 'linux') {
        await security.run('sudo', ['-n', 'chage', '-E', patch.chageDate, '--', currentNative]);
        if (patch.isFuture) {
          await security.run('sudo', ['-n', 'usermod', '-U', '--', currentNative]);
        }
      }
      if (patch.isFuture && row.status !== 'active') {
        nextStatus = 'active';
      }
    }

    const sql = patch.reset_traffic
      ? 'UPDATE users SET username = ?, password = ?, hwid = ?, alias = ?, max_connections = ?, expiration_date = ?, status = ?, bytes_used = 0 WHERE id = ?'
      : 'UPDATE users SET username = ?, password = ?, hwid = ?, alias = ?, max_connections = ?, expiration_date = ?, status = ? WHERE id = ?';
    await db.query(sql, [nextUsername, nextPassword, nextHwid, nextAlias, nextMax, nextExp, nextStatus, row.id]);

    res.json({
      message: 'Cuenta actualizada con éxito.',
      user: {
        id: row.id,
        username: nextUsername,
        hwid: nextHwid,
        alias: nextAlias,
        max_connections: nextMax,
        expiration_date: nextExp,
        status: nextStatus
      }
    });
  } catch (e) { res.status(500).json({ error: 'No se pudo actualizar la cuenta: ' + (e.message || 'error interno') }); }
};
if (typeof app.patch === 'function') app.patch('/api/users/:username', authMiddleware, handlePatchUser);
app.post('/api/users/:username/update', authMiddleware, handlePatchUser);

// Telemetría real y estado de servicios del nodo (para Panel Web y monitoreo)
app.get('/api/system/status', authMiddleware, async (req, res) => {
  try {
    if (trafficCollector) {
      try { await trafficCollector.flushToDb(db); } catch (_) {}
    }
    const telemetry = typeof security.getHostTelemetry === 'function' ? security.getHostTelemetry() : {};
    const usersRes = await db.query('SELECT status, expiration_date, COALESCE(bytes_used, 0) AS bytes_used FROM users');
    const now = Date.now();
    let activeUsers = 0, expiredUsers = 0, revokedUsers = 0, totalBytes = 0;
    for (const u of usersRes.rows) {
      totalBytes += Number(u.bytes_used) > 0 ? Number(u.bytes_used) : 0;
      const exp = Date.parse(u.expiration_date);
      if (u.status === 'revoked') revokedUsers++;
      else if (u.status !== 'active' || !Number.isFinite(exp) || exp <= now) expiredUsers++;
      else activeUsers++;
    }

    let onlineConnections = 0;
    const services = {
      ssh: false,
      joif_api: true,
      ws_proxy: false,
      stunnel: false,
      badvpn_7300: false,
      badvpn_7200: false,
      limitador: false,
      bbr: false,
      smartdns: false
    };

    if (process.platform === 'linux') {
      try {
        const psOut = await security.run('ps', ['-eo', 'user:32,pid,etimes,args']);
        onlineConnections = security.sessionPids(psOut).length;
      } catch (_) {}

      const isActive = async (svc) => {
        try { await security.run('systemctl', ['is-active', '--quiet', svc]); return true; } catch (_) { return false; }
      };
      services.ssh = (await isActive('ssh')) || (await isActive('sshd'));
      services.ws_proxy = await isActive('joif-proxy');
      services.stunnel = await isActive('stunnel4');
      services.badvpn_7300 = await isActive('badvpn-7300');
      services.badvpn_7200 = await isActive('badvpn-7200');
      services.limitador = await isActive('joif-limitador');
      try {
        const cc = await security.run('sysctl', ['-n', 'net.ipv4.tcp_congestion_control']);
        services.bbr = cc.trim() === 'bbr';
      } catch (_) {}
      try {
        await security.run('iptables', ['-t', 'nat', '-C', 'OUTPUT', '-j', 'JOIF_SMARTDNS_OUT']);
        services.smartdns = true;
      } catch (_) {}
    }

    res.json({
      ...telemetry,
      port: Number(process.env.PORT || 3000),
      total_users: usersRes.rows.length,
      active_users: activeUsers,
      expired_users: expiredUsers,
      revoked_users: revokedUsers,
      online_connections: onlineConnections,
      total_bytes_used: totalBytes,
      total_gb_used: typeof security.formatTrafficBytes === 'function' ? security.formatTrafficBytes(totalBytes) : '0.00 MB',
      services
    });
  } catch (err) {
    res.status(500).json({ error: err.message });
  }
});

// Healthcheck del backend y API CheckUser
app.get(['/health', '/api/health'], (req, res) => {
  res.json({ status: 'ok', service: 'joif-checkuser', port: Number(process.env.PORT || 3000) });
});

// Obtener todos los usuarios array simple (CheckUser Global - Protegido para evitar enumeración pública)
app.get(['/check', '/api/check'], authMiddleware, async (req, res) => {
  try {
    const userRes = await db.query('SELECT username FROM users WHERE status = \'active\' AND julianday(expiration_date) > julianday(\'now\')');
    const userList = userRes.rows.map(row => row.username);
    res.json(userList);
  } catch (err) {
    res.status(500).json({ error: err.message });
  }
});

const trafficCollector = (process.platform === 'linux' && typeof security.createTrafficCollector === 'function')
  ? security.createTrafficCollector()
  : null;

async function handleCheckUser(id, req, res) {
  const rate = checkLimiter(clientIp(req));
  if (!rate.allowed) {
    res.set('Retry-After', String(rate.retryAfterSec));
    return res.status(429).json({ error: 'Demasiadas consultas. Intenta en unos segundos.' });
  }
  if (typeof id !== 'string' || !id.trim()) {
    return res.status(400).json({ error: 'Usuario requerido' });
  }
  const target = id.trim();
  try {
    if (trafficCollector) {
      try { await trafficCollector.flushToDb(db); } catch (_) {}
    }
    const userRes = await db.query(
      'SELECT username, hwid, alias, expiration_date, max_connections, status, COALESCE(bytes_used, 0) AS bytes_used FROM users WHERE username = ? COLLATE NOCASE OR hwid = ? COLLATE NOCASE OR alias = ? COLLATE NOCASE LIMIT 1',
      [target, target, target]
    );
    if (userRes.rowCount === 0) {
      return res.status(404).json({ error: 'Usuario no encontrado' });
    }

    const user = userRes.rows[0];
    if (user.status !== 'active' || !Number.isFinite(Date.parse(user.expiration_date)) || Date.parse(user.expiration_date) <= Date.now()) {
      return res.status(403).json({ error: 'Cuenta vencida o revocada.' });
    }
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
        const current = security.sessions(await security.run('ps', ['-eo', 'user:32,etimes,args']), linuxUser);
        activeConnections = current.count; timeOnline = current.time;
      } catch (_) { console.error('[CheckUser] No se pudieron consultar las conexiones.'); }
    }

    const expDateStr = user.expiration_date.split('T')[0];
    const [year, month, day] = expDateStr.split('-');
    const formattedDate = `${day}/${month}/${year}`;
    const bytesUsed = Number(user.bytes_used) > 0 ? Number(user.bytes_used) : 0;
    const formattedUsage = typeof security.formatTrafficBytes === 'function'
      ? security.formatTrafficBytes(bytesUsed)
      : '0.00 MB';

    res.json({
      count_connections: activeConnections,
      expiration_date: formattedDate,
      expiration_days: diffDays > 0 ? diffDays : 0,
      limit_connections: user.max_connections,
      time_online: timeOnline,
      username: user.username,
      uuid: user.hwid || null,
      bytes_used: bytesUsed,
      gb_used: formattedUsage,
      data_used: formattedUsage
    });
  } catch (err) {
    res.status(500).json({ error: err.message });
  }
}

// Validar Cuenta (CheckUser API) - Compatible con SSHPLUS, MiVPNApp, DTunnel, Conecta4G y GLTunnel
app.get(['/api/check/:id', '/check/:id', '/checkUser/:id', '/checkuser/:id'], (req, res) => {
  return handleCheckUser(req.params.id, req, res);
});

app.get(['/checkUser', '/checkuser'], (req, res) => {
  const id = req.query.user || req.query.username || req.query.id;
  return handleCheckUser(id, req, res);
});

app.post(['/checkUser', '/checkuser', '/api/checkUser', '/api/checkuser'], (req, res) => {
  const id = req.body?.user || req.body?.username || req.body?.id || req.query.user || req.query.username;
  return handleCheckUser(id, req, res);
});

// BadVPN UDPGW es gestionado de forma modular e independiente por systemd (badvpn-7300 / badvpn-7200)
require('./account-reconciler').startReconciler(db);

if (trafficCollector && typeof setInterval === 'function') {
  const trafficTimer = setInterval(() => {
    trafficCollector.flushToDb(db).catch(() => {});
  }, 15000);
  if (typeof trafficTimer.unref === 'function') trafficTimer.unref();
}

const PORT = process.env.PORT || 3000;
(db.ready || Promise.resolve()).then(() => app.listen(PORT, () => {
  console.log(`Edge Node Manager & Web Panel Backend ejecutándose en http://localhost:${PORT}`);
})).catch(() => { console.error("La base de datos no está lista. El servidor no se inició."); process.exitCode = 1; });
