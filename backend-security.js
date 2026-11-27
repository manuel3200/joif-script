'use strict';
const crypto = require('node:crypto');
const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');
const { spawn } = require('node:child_process');
const reserved = new Set(['root', 'daemon', 'bin', 'sys', 'nobody', 'sshd', 'www-data', 'postgres', 'mysql']);
function linuxName(name) {
  if (typeof name !== 'string' || !/^[A-Za-z0-9_][A-Za-z0-9_-]{0,31}$/.test(name) || reserved.has(name.toLowerCase())) throw Error('Nombre de cuenta Linux inválido.');
  return name;
}
function validateAccount(body) {
  let hwid = null;
  if (body.hwid && typeof body.hwid === 'string') {
    const trimmed = body.hwid.trim();
    if (trimmed.length > 0 && trimmed.length <= 128 && /^[A-Za-z0-9_-]+$/.test(trimmed)) {
      hwid = trimmed;
    }
  }

  const alias = typeof body.alias === 'string' && body.alias.trim() 
    ? body.alias.trim() 
    : (typeof body.client_name === 'string' && body.client_name.trim() ? body.client_name.trim() : (typeof body.username === 'string' ? body.username.trim() : null));

  const username = hwid ? linuxName(hwid) : linuxName(body.username);
  const nativeName = username;
  const password = hwid ? hwid : body.password;

  if (typeof password !== 'string' || !password || password.length > 256 || /[\r\n\0:]/.test(password)) throw Error('Contraseña inválida.');
  if (typeof body.expiration_date !== 'string' || !/^\d{4}-\d{2}-\d{2}(T.*)?$/.test(body.expiration_date)) throw Error('Fecha inválida.');
  const date = body.expiration_date.slice(0, 10), timestamp = Date.parse(body.expiration_date.length === 10 ? date + 'T00:00:00Z' : body.expiration_date);
  if (!Number.isFinite(timestamp) || new Date(Date.parse(date + 'T00:00:00Z')).toISOString().slice(0, 10) !== date || timestamp <= Date.now()) throw Error('El vencimiento debe ser una fecha futura válida.');
  const connections = body.max_connections === undefined ? 1 : Number(body.max_connections);
  if (!Number.isInteger(connections) || connections < 1 || connections > 100) throw Error('El límite de conexiones debe estar entre 1 y 100.');

  return { username, nativeName, password, date: new Date(Math.ceil(timestamp / 86400000) * 86400000).toISOString().slice(0, 10), expiresAt: new Date(timestamp).toISOString(), connections, hwid, alias: alias || username };
}
function hashPassword(value) {
  const salt = crypto.randomBytes(16).toString('hex');
  return 'scrypt$' + salt + '$' + crypto.scryptSync(value, salt, 64).toString('hex');
}
function verifyPassword(value, saved) {
  if (typeof value !== 'string' || value.length > 256 || typeof saved !== 'string') return false;
  if (!saved.startsWith('scrypt$')) {
    const hash = s => crypto.createHash('sha256').update(s).digest(); return crypto.timingSafeEqual(hash(value), hash(saved));
  }
  const [, salt, digest] = saved.split('$');
  if (!salt || !digest || !/^[a-f0-9]{128}$/.test(digest)) return false;
  return crypto.timingSafeEqual(crypto.scryptSync(value, salt, 64), Buffer.from(digest, 'hex'));
}
function sessionSecret(dir, env = process.env) {
  if (env.SESSION_SECRET) { if (env.SESSION_SECRET.length < 32 || env.SESSION_SECRET === 'default_secret_key') throw Error('SESSION_SECRET debe tener al menos 32 caracteres.'); return env.SESSION_SECRET; }
  const file = path.join(dir, '.session-secret');
  if (!fs.existsSync(file)) fs.writeFileSync(file, crypto.randomBytes(48).toString('base64url'), { mode: 0o600, flag: 'wx' });
  return fs.readFileSync(file, 'utf8').trim();
}
function run(file, args, input = '') {
  return new Promise((resolve, reject) => {
    const child = spawn(file, args, { shell: false, stdio: ['pipe', 'pipe', 'pipe'] });
    let output = '', error = ''; const timeout = setTimeout(() => child.kill(), 15000);
    child.stdout.on('data', d => { output += d; }); child.stderr.on('data', d => { error += d; });
    child.on('error', e => { clearTimeout(timeout); reject(e); });
    child.on('close', code => { clearTimeout(timeout); if (code === 0) resolve(output); else { const error = Error('No se pudo completar la operación del sistema.'); error.exitCode = code; reject(error); } });
    child.stdin.on('error', () => {}); child.stdin.end(input);
  });
}
function sessions(output, username) {
  linuxName(username); let count = 0, elapsed = 0;
  for (const line of output.split('\n')) {
    const trimmed = line.trim();
    if (!trimmed) continue;
    // Formato 1: ps -eo user:32,etimes,args (detecta sshd, sshd-session con o sin @notty, y dropbear)
    const ownerMatch = trimmed.match(/^([A-Za-z0-9_.-]+)\s+(\d+)\s+(.+)$/);
    if (ownerMatch) {
      const owner = ownerMatch[1], secs = Number(ownerMatch[2]), args = ownerMatch[3];
      if (owner === username && /\b(sshd(?:-session)?|dropbear)\b/i.test(args) && !/\[(priv|net|accepted)\]|listener/i.test(args)) {
        count++; elapsed = Math.max(elapsed, secs);
      }
      continue;
    }
    // Formato 2 (legacy): ps -eo etimes,args
    const legacyMatch = trimmed.match(/^(\d+)\s+sshd(?:-session)?:\s+([^\s@]+)(?:@|$)/);
    if (legacyMatch && legacyMatch[2] === username) { count++; elapsed = Math.max(elapsed, Number(legacyMatch[1])); }
  }
  const h = Math.floor(elapsed / 3600), m = Math.floor(elapsed % 3600 / 60), s = elapsed % 60;
  return { count, time: `${h}:${String(m).padStart(2, '0')}:${String(s).padStart(2, '0')}` };
}
function formatTrafficBytes(bytes) {
  const safe = Number.isFinite(Number(bytes)) && Number(bytes) > 0 ? Number(bytes) : 0;
  const gb = 1024 * 1024 * 1024;
  const mb = 1024 * 1024;
  if (safe >= gb) return `${(safe / gb).toFixed(2)} GB`;
  return `${(safe / mb).toFixed(2)} MB`;
}
function parseProcIoBytes(ioContent) {
  if (typeof ioContent !== 'string' || !ioContent) return 0;
  const rMatch = ioContent.match(/^rchar:\s*(\d+)/m);
  const wMatch = ioContent.match(/^wchar:\s*(\d+)/m);
  const rchar = rMatch ? Number(rMatch[1]) : 0;
  const wchar = wMatch ? Number(wMatch[1]) : 0;
  if (!Number.isFinite(rchar) || !Number.isFinite(wchar)) return 0;
  // sshd-session / dropbear lee del socket entrante y escribe al saliente (2x); dividir por 2 da el tráfico real RX+TX
  return Math.floor((rchar + wchar) / 2);
}
function sessionPids(psOutput) {
  const list = [];
  if (typeof psOutput !== 'string' || !psOutput) return list;
  for (const line of psOutput.split('\n')) {
    const trimmed = line.trim();
    if (!trimmed) continue;
    const match = trimmed.match(/^([A-Za-z0-9_.-]+)\s+(\d+)\s+(\d+)\s+(.+)$/);
    if (!match) continue;
    const owner = match[1], pid = Number(match[2]), etimes = Number(match[3]), args = match[4];
    if (owner === 'root' || owner === 'USER' || reserved.has(owner.toLowerCase())) continue;
    if (/\b(sshd(?:-session)?|dropbear)\b/i.test(args) && !/\[(priv|net|accepted)\]|listener/i.test(args)) {
      list.push({ user: owner, pid, etimes });
    }
  }
  return list;
}
function createTrafficCollector(options = {}) {
  const lastByPid = new Map();
  const listFn = options.listSessions || (async () => sessionPids(await run('ps', ['-eo', 'user:32,pid,etimes,args'])));
  const readIoFn = options.readProcIo || (pid => {
    try { return fs.readFileSync(`/proc/${pid}/io`, 'utf8'); } catch (_) { return ''; }
  });
  async function sampleDeltas() {
    const active = await listFn();
    const seenPids = new Set();
    const deltas = new Map();
    for (const item of active) {
      seenPids.add(item.pid);
      const current = parseProcIoBytes(readIoFn(item.pid));
      const prev = lastByPid.get(item.pid) || 0;
      if (current > prev) {
        deltas.set(item.user, (deltas.get(item.user) || 0) + (current - prev));
      }
      lastByPid.set(item.pid, current);
    }
    for (const pid of lastByPid.keys()) {
      if (!seenPids.has(pid)) lastByPid.delete(pid);
    }
    return deltas;
  }
  async function flushToDb(database) {
    if (!database || typeof database.query !== 'function') return 0;
    const deltas = await sampleDeltas();
    let updated = 0;
    for (const [uname, deltaBytes] of deltas.entries()) {
      if (deltaBytes > 0) {
        await database.query('UPDATE users SET bytes_used = COALESCE(bytes_used, 0) + ? WHERE username = ? COLLATE NOCASE', [deltaBytes, uname]);
        updated++;
      }
    }
    return updated;
  }
  return { sampleDeltas, flushToDb };
}
function allSessions(psOutput) {
  const map = new Map();
  for (const item of sessionPids(psOutput)) {
    const key = item.user.toLowerCase();
    const cur = map.get(key) || { count: 0, elapsed: 0 };
    cur.count += 1;
    cur.elapsed = Math.max(cur.elapsed, item.etimes);
    map.set(key, cur);
  }
  const result = new Map();
  for (const [key, val] of map.entries()) {
    const h = Math.floor(val.elapsed / 3600), m = Math.floor(val.elapsed % 3600 / 60), s = val.elapsed % 60;
    result.set(key, { count: val.count, time: `${h}:${String(m).padStart(2, '0')}:${String(s).padStart(2, '0')}` });
  }
  return result;
}
function createRateLimiter({ windowMs = 60000, max = 60 } = {}) {
  const buckets = new Map();
  return function check(key, now = Date.now()) {
    const id = String(key || 'unknown');
    if (buckets.size > 5000) {
      for (const [k, entry] of buckets.entries()) {
        if (entry.resetAt <= now) buckets.delete(k);
      }
    }
    let entry = buckets.get(id);
    if (!entry || entry.resetAt <= now) {
      entry = { count: 0, resetAt: now + windowMs };
      buckets.set(id, entry);
    }
    entry.count += 1;
    const allowed = entry.count <= max;
    return { allowed, remaining: Math.max(0, max - entry.count), retryAfterSec: Math.max(1, Math.ceil((entry.resetAt - now) / 1000)) };
  };
}
function validateUserPatch(body, existingUser, now = Date.now()) {
  const patch = {};
  if (body.max_connections !== undefined) {
    const conn = Number(body.max_connections);
    if (!Number.isInteger(conn) || conn < 1 || conn > 100) throw Error('El límite de conexiones debe estar entre 1 y 100.');
    patch.max_connections = conn;
  }
  if (body.alias !== undefined && body.alias !== null) {
    const alias = String(body.alias).trim();
    if (!alias || alias.length > 64 || /[\r\n\0]/.test(alias)) throw Error('Alias inválido.');
    patch.alias = alias;
  }
  if (body.password !== undefined && body.password !== null && body.password !== '') {
    const pass = String(body.password);
    if (pass.length > 256 || /[\r\n\0:]/.test(pass)) throw Error('Contraseña inválida.');
    patch.password = pass;
  }
  if (body.hwid !== undefined && body.hwid !== null && body.hwid !== '') {
    const trimmed = String(body.hwid).trim();
    if (!trimmed || trimmed.length > 128 || !/^[A-Za-z0-9_-]+$/.test(trimmed)) throw Error('HWID inválido.');
    patch.hwid = linuxName(trimmed);
  }
  if (body.add_days !== undefined || body.set_days !== undefined || body.expiration_date !== undefined) {
    let targetMs;
    if (body.add_days !== undefined) {
      const delta = Number(body.add_days);
      if (!Number.isInteger(delta) || delta < -3650 || delta > 3650 || delta === 0) throw Error('Cantidad de días inválida.');
      const baseMs = Number.isFinite(Date.parse(existingUser.expiration_date)) ? Math.max(Date.parse(existingUser.expiration_date), now) : now;
      targetMs = baseMs + delta * 86400000;
    } else if (body.set_days !== undefined) {
      const days = Number(body.set_days);
      if (!Number.isInteger(days) || days < 1 || days > 3650) throw Error('Los días deben estar entre 1 y 3650.');
      targetMs = now + days * 86400000;
    } else {
      const raw = String(body.expiration_date || '');
      if (!/^\d{4}-\d{2}-\d{2}(T.*)?$/.test(raw)) throw Error('Fecha inválida.');
      const datePart = raw.slice(0, 10);
      targetMs = Date.parse(raw.length === 10 ? datePart + 'T00:00:00Z' : raw);
      if (!Number.isFinite(targetMs) || new Date(Date.parse(datePart + 'T00:00:00Z')).toISOString().slice(0, 10) !== datePart) throw Error('Fecha inválida.');
    }
    if (!Number.isFinite(targetMs)) throw Error('Fecha inválida.');
    patch.expiresAt = new Date(targetMs).toISOString();
    patch.chageDate = new Date(Math.ceil(targetMs / 86400000) * 86400000).toISOString().slice(0, 10);
    patch.isFuture = targetMs > now;
  }
  if (body.reset_traffic === true) {
    patch.reset_traffic = true;
  }
  if (body.data_limit_gb !== undefined || body.data_limit_bytes !== undefined) {
    patch.data_limit_bytes = parseDataLimitBytes(body);
  }
  if (Object.keys(patch).length === 0) throw Error('No se enviaron campos válidos para actualizar.');
  return patch;
}
function parseDataLimitBytes(body) {
  if (!body || typeof body !== 'object') return 0;
  if (body.data_limit_bytes !== undefined && body.data_limit_bytes !== '' && body.data_limit_bytes !== null) {
    const b = Number(body.data_limit_bytes);
    if (!Number.isFinite(b) || b < 0 || b > 100 * 1024 * 1024 * 1024 * 1024) throw Error('Cuota de datos inválida.');
    return Math.floor(b);
  }
  if (body.data_limit_gb !== undefined && body.data_limit_gb !== '' && body.data_limit_gb !== null) {
    const gb = Number(body.data_limit_gb);
    if (!Number.isFinite(gb) || gb < 0 || gb > 100000) throw Error('Cuota en GB inválida (usa 0 para ilimitado).');
    return Math.round(gb * 1024 * 1024 * 1024);
  }
  return 0;
}
function formatDataLimit(bytes) {
  const n = Number(bytes);
  if (!Number.isFinite(n) || n <= 0) return 'Ilimitado';
  return formatTrafficBytes(n);
}
function getHostTelemetry() {
  const totalMb = Math.round(os.totalmem() / (1024 * 1024));
  let freeMb = Math.round(os.freemem() / (1024 * 1024));
  let osName = `${os.type()} ${os.release()}`;
  if (process.platform === 'linux') {
    try {
      const meminfo = fs.readFileSync('/proc/meminfo', 'utf8');
      const avail = meminfo.match(/^MemAvailable:\s+(\d+)/m);
      if (avail) freeMb = Math.round(Number(avail[1]) / 1024);
    } catch (_) {}
    try {
      const rel = fs.readFileSync('/etc/os-release', 'utf8');
      const pretty = rel.match(/^PRETTY_NAME="([^"]+)"/m);
      if (pretty) osName = pretty[1];
    } catch (_) {}
  }
  const usedMb = Math.max(0, totalMb - freeMb);
  const ramPercent = totalMb > 0 ? Number(((usedMb / totalMb) * 100).toFixed(1)) : 0;
  return {
    hostname: os.hostname(),
    os: osName,
    arch: os.arch(),
    uptime_sec: Math.floor(os.uptime()),
    cpu_cores: os.cpus().length,
    load_avg: os.loadavg().map(v => Number(v.toFixed(2))),
    ram_total_mb: totalMb,
    ram_used_mb: usedMb,
    ram_free_mb: freeMb,
    ram_percent: ramPercent
  };
}
module.exports = { linuxName, validateAccount, hashPassword, verifyPassword, sessionSecret, run, sessions, formatTrafficBytes, parseProcIoBytes, sessionPids, createTrafficCollector, allSessions, createRateLimiter, validateUserPatch, getHostTelemetry, parseDataLimitBytes, formatDataLimit };
