'use strict';
const crypto = require('node:crypto');
const fs = require('node:fs');
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
module.exports = { linuxName, validateAccount, hashPassword, verifyPassword, sessionSecret, run, sessions, formatTrafficBytes, parseProcIoBytes, sessionPids, createTrafficCollector };
