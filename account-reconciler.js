'use strict';
const security = require('./backend-security');

function isDemoAccount(account) {
  const u = String(account.username || '').toLowerCase();
  const a = String(account.alias || '').toLowerCase();
  return u.startsWith('demo') || a.startsWith('demo');
}

async function reconcileAccounts(db, system = security.run, now = Date.now()) {
  const { rows } = await db.query(
    'SELECT id, username, hwid, alias, expiration_date, status, COALESCE(bytes_used, 0) AS bytes_used, COALESCE(data_limit_bytes, 0) AS data_limit_bytes FROM users'
  );
  const summary = { expired: 0, quota_exhausted: 0, missing: 0, errors: 0 };
  for (const account of rows) {
    try {
      const name = security.linuxName(account.username);
      let passwd;
      try { passwd = await system('getent', ['passwd', name]); } catch (e) { if (e.exitCode === 2) { summary.missing++; continue; } throw e; }
      const fields = passwd.trim().split(':');
      if (fields[0] !== name || Number(fields[2]) < 1000) throw Error('Cuenta del sistema: no se modifica.');
      const expires = Date.parse(account.expiration_date);
      if (!Number.isFinite(expires)) throw Error('Fecha inválida en base de datos.');
      const limitBytes = Number(account.data_limit_bytes) > 0 ? Number(account.data_limit_bytes) : 0;
      const usedBytes = Number(account.bytes_used) > 0 ? Number(account.bytes_used) : 0;
      const quotaExceeded = limitBytes > 0 && usedBytes >= limitBytes;

      if (account.status !== 'active' || expires <= now || quotaExceeded) {
        await system('sudo', ['-n', 'usermod', '-L', '--', name]);
        await system('sudo', ['-n', 'chage', '-E', '0', '--', name]);
        try { await system('sudo', ['-n', 'pkill', '-KILL', '-u', name]); } catch (e) { if (e.exitCode !== 1) throw e; }
        if (account.status === 'active') {
          const nextStatus = (quotaExceeded && expires > now) ? 'quota_exhausted' : 'expired';
          await db.query('UPDATE users SET status = ? WHERE id = ?', [nextStatus, account.id]);
          if (nextStatus === 'quota_exhausted') summary.quota_exhausted++;
          else summary.expired++;
        }
      }
    } catch (_) { summary.errors++; }
  }
  return summary;
}

async function purgeExpiredDemos(db, system = security.run, now = Date.now(), graceMs = 24 * 60 * 60 * 1000) {
  const { rows } = await db.query('SELECT id, username, alias, expiration_date, status FROM users');
  const summary = { purged: 0, errors: 0, users: [] };
  for (const account of rows) {
    if (!isDemoAccount(account)) continue;
    const expires = Date.parse(account.expiration_date);
    if (!Number.isFinite(expires) || expires > now - graceMs) continue;
    try {
      const name = security.linuxName(account.username);
      if (process.platform === 'linux' || system !== security.run) {
        try { await system('sudo', ['-n', 'pkill', '-KILL', '-u', name]); } catch (e) { if (e.exitCode !== 1) throw e; }
        try { await system('sudo', ['-n', 'userdel', '-f', '--', name]); } catch (e) { if (e.exitCode !== 6) throw e; }
      }
      await db.query('DELETE FROM users WHERE id = ?', [account.id]);
      summary.purged++;
      summary.users.push(account.username);
    } catch (_) { summary.errors++; }
  }
  return summary;
}

function startReconciler(db) {
  if (process.platform !== 'linux') return;
  let busy = false;
  const tick = async () => {
    if (busy) return; busy = true;
    try {
      const result = await reconcileAccounts(db);
      if (result.expired || result.quota_exhausted || result.missing || result.errors) {
        console.log('[Accounts] Reconciliación:', result);
      }
    } catch (_) {
      console.error('[Accounts] No se pudo reconciliar la base de datos.');
    } finally { busy = false; }
  };
  const purgeTick = async () => {
    try {
      const res = await purgeExpiredDemos(db);
      if (res.purged) console.log(`[PURGA] ${res.purged} cuentas Demo eliminadas tras 24h de expiración:`, res.users.join(', '));
    } catch (_) {}
  };
  setTimeout(tick, 2000).unref();
  setInterval(tick, 30000).unref();
  setTimeout(purgeTick, 10000).unref();
  setInterval(purgeTick, 6 * 60 * 60 * 1000).unref();
}

module.exports = { reconcileAccounts, purgeExpiredDemos, startReconciler, isDemoAccount };
