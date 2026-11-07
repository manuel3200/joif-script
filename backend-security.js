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
  const username = linuxName(body.username), nativeName = username;
  if (typeof body.password !== 'string' || !body.password || body.password.length > 256 || /[\r\n\0:]/.test(body.password)) throw Error('Contraseña inválida.');
  if (typeof body.expiration_date !== 'string' || !/^\d{4}-\d{2}-\d{2}(T.*)?$/.test(body.expiration_date)) throw Error('Fecha inválida.');
  const date = body.expiration_date.slice(0, 10), timestamp = Date.parse(body.expiration_date.length === 10 ? date + 'T00:00:00Z' : body.expiration_date);
  if (!Number.isFinite(timestamp) || new Date(Date.parse(date + 'T00:00:00Z')).toISOString().slice(0, 10) !== date || timestamp <= Date.now()) throw Error('El vencimiento debe ser una fecha futura válida.');
  const connections = body.max_connections === undefined ? 1 : Number(body.max_connections);
  if (!Number.isInteger(connections) || connections < 1 || connections > 100) throw Error('El límite de conexiones debe estar entre 1 y 100.');
  let hwid = null;
  if (body.hwid && typeof body.hwid === 'string') {
    const trimmed = body.hwid.trim();
    if (trimmed.length > 0 && trimmed.length <= 128 && /^[A-Za-z0-9_-]+$/.test(trimmed)) {
      hwid = trimmed;
    }
  }
  return { username, nativeName, password: body.password, date: new Date(Math.ceil(timestamp / 86400000) * 86400000).toISOString().slice(0, 10), expiresAt: new Date(timestamp).toISOString(), connections, hwid };
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
    const match = line.trim().match(/^(\d+)\s+sshd:\s+([^\s@]+)@/);
    if (match && match[2] === username) { count++; elapsed = Math.max(elapsed, Number(match[1])); }
  }
  const h = Math.floor(elapsed / 3600), m = Math.floor(elapsed % 3600 / 60), s = elapsed % 60;
  return { count, time: `${h}:${String(m).padStart(2, '0')}:${String(s).padStart(2, '0')}` };
}
module.exports = { linuxName, validateAccount, hashPassword, verifyPassword, sessionSecret, run, sessions };
