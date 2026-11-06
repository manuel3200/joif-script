'use strict';
const security = require('./backend-security');
async function reconcileAccounts(db, system = security.run, now = Date.now()) {
  const { rows } = await db.query('SELECT id, username, hwid, expiration_date, status FROM users');
  const summary = { expired: 0, missing: 0, errors: 0 };
  for (const account of rows) {
    try {
      const name = security.linuxName(account.hwid || account.username);
      let passwd;
      try { passwd = await system('getent', ['passwd', name]); } catch (e) { if (e.exitCode === 2) { summary.missing++; continue; } throw e; }
      const fields = passwd.trim().split(':');
      if (fields[0] !== name || Number(fields[2]) < 1000) throw Error('Cuenta del sistema: no se modifica.');
      const expires = Date.parse(account.expiration_date);
      if (!Number.isFinite(expires)) throw Error('Fecha inválida en base de datos.');
      if (account.status !== 'active' || expires <= now) {
        await system('sudo', ['-n', 'usermod', '-L', '--', name]);
        await system('sudo', ['-n', 'chage', '-E', '0', '--', name]);
        try { await system('sudo', ['-n', 'pkill', '-u', name, 'sshd']); } catch (e) { if (e.exitCode !== 1) throw e; }
        if (account.status === 'active') { await db.query("UPDATE users SET status = 'expired' WHERE id = ?", [account.id]); summary.expired++; }
      }
    } catch (_) { summary.errors++; }
  }
  return summary;
}
function startReconciler(db) {
  if (process.platform !== 'linux') return;
  let busy = false;
  const tick = async () => {
    if (busy) return; busy = true;
    try { const result = await reconcileAccounts(db); if (result.expired || result.missing || result.errors) console.log('[Accounts] Reconciliación:', result); }
    catch (_) { console.error('[Accounts] No se pudo reconciliar la base de datos.'); }
    finally { busy = false; }
  };
  setTimeout(tick, 2000).unref(); setInterval(tick, 30000).unref();
}
module.exports = { reconcileAccounts, startReconciler };
