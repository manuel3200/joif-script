'use strict';

const fs = require('node:fs');
const crypto = require('node:crypto');
const os = require('node:os');
try { require('dotenv').config(); } catch (_) {}

const BOT_TOKEN = (process.env.TELEGRAM_BOT_TOKEN || '').trim();
const ADMIN_ID = (process.env.TELEGRAM_ADMIN_ID || '').trim();
const API_PORT = Number(process.env.PORT) || 3000;
const API_KEY = (process.env.API_KEY || process.env.NODE_API_SECRET || '').trim();

if (!BOT_TOKEN || !ADMIN_ID) {
  console.error('[TG-BOT] Faltan TELEGRAM_BOT_TOKEN o TELEGRAM_ADMIN_ID en .env. Bot detenido.');
  process.exit(1);
}

const TG_API = `https://api.telegram.org/bot${BOT_TOKEN}`;
const LOCAL_API = `http://127.0.0.1:${API_PORT}`;

async function tgCall(method, payload = {}) {
  const res = await fetch(`${TG_API}/${method}`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify(payload)
  });
  return res.json();
}

async function sendMsg(text) {
  try {
    await tgCall('sendMessage', {
      chat_id: ADMIN_ID,
      text,
      parse_mode: 'HTML',
      disable_web_page_preview: true
    });
  } catch (e) {
    console.error('[TG-BOT] Error enviando mensaje:', e.message);
  }
}

async function localApi(method, path, body) {
  const opts = {
    method,
    headers: { 'x-api-key': API_KEY, 'Content-Type': 'application/json' }
  };
  if (body !== undefined) opts.body = JSON.stringify(body);
  const res = await fetch(`${LOCAL_API}${path}`, opts);
  const data = await res.json().catch(() => ({}));
  return { ok: res.ok, status: res.status, data };
}

async function handleCommand(text) {
  const parts = text.trim().split(/\s+/);
  const cmd = (parts[0] || '').toLowerCase().split('@')[0];

  if (cmd === '/start' || cmd === '/help') {
    return sendMsg(
      `🤖 <b>JOIF Cloud Bot [Modo Alfa]</b>\n` +
      `Nodo: <code>${os.hostname()}</code>\n\n` +
      `<b>Comandos disponibles:</b>\n` +
      `• /status — Estado de RAM, CPU, online y servicios\n` +
      `• /demo [alias] — Crea cuenta Demo 6h (2 conn)\n` +
      `• /renovar &lt;usuario&gt; &lt;dias&gt; — Suma días a una cuenta\n` +
      `• /bloquear &lt;usuario&gt; — Bloquea y desconecta\n` +
      `• /desbloquear &lt;usuario&gt; — Reactiva cuenta\n` +
      `• /purgar — Elimina cuentas Demo vencidas`
    );
  }

  if (cmd === '/status') {
    const { ok, data } = await localApi('GET', '/api/system/status');
    if (!ok) return sendMsg(`❌ Error consultando estado: ${data.error || 'API no disponible'}`);
    const s = data.services || {};
    const on = (v) => (v ? '🟢' : '🔴');
    return sendMsg(
      `📊 <b>Estado del Nodo: ${data.hostname}</b>\n` +
      `• RAM: <b>${data.ram_percent}%</b> (${data.ram_used_mb}M / ${data.ram_total_mb}M)\n` +
      `• Load: <code>${(data.load_avg || [0]).join(', ')}</code>\n` +
      `• Usuarios: <b>${data.active_users}</b> activos / ${data.total_users} total\n` +
      `• Online ahora: <b>${data.online_connections}</b>\n` +
      `• Tráfico total: <b>${data.total_gb_used}</b>\n\n` +
      `${on(s.ssh)} SSH  ${on(s.ws_proxy)} WS  ${on(s.stunnel)} SSL  ${on(s.badvpn_7300)} BadVPN\n` +
      `${on(s.limitador)} Limitador  ${on(s.firewall)} Firewall  ${on(s.bbr)} BBR  ${on(s.smartdns)} SmartDNS`
    );
  }

  if (cmd === '/demo') {
    const rawAlias = (parts[1] || crypto.randomBytes(2).toString('hex')).replace(/[^A-Za-z0-9_-]/g, '');
    const username = rawAlias.startsWith('demo-') ? rawAlias : `demo-${rawAlias}`;
    const password = crypto.randomBytes(4).toString('hex');
    const exp = new Date(Date.now() + 6 * 3600 * 1000).toISOString();
    const { ok, data } = await localApi('POST', '/api/users', {
      username,
      password,
      expiration_date: exp,
      max_connections: 2,
      data_limit_gb: 0
    });
    if (!ok) return sendMsg(`❌ No se pudo crear demo: ${data.error || 'Error'}`);
    return sendMsg(
      `✅ <b>Cuenta Demo Creada (6 Horas)</b>\n\n` +
      `👤 Usuario: <code>${username}</code>\n` +
      `🔑 Clave: <code>${password}</code>\n` +
      `📱 Conexiones: <b>2</b>\n` +
      `🖥 Servidor: <code>${os.hostname()}</code>`
    );
  }

  if (cmd === '/renovar') {
    const user = parts[1];
    const days = Number(parts[2]);
    if (!user || !Number.isInteger(days) || days < 1) {
      return sendMsg('Uso: <code>/renovar usuario 30</code>');
    }
    const { ok, data } = await localApi('PATCH', `/api/users/${encodeURIComponent(user)}`, { add_days: days });
    if (!ok) return sendMsg(`❌ Error renovando ${user}: ${data.error || 'Error'}`);
    return sendMsg(`✅ Cuenta <code>${user}</code> renovada <b>+${days} días</b>.`);
  }

  if (cmd === '/bloquear') {
    const user = parts[1];
    if (!user) return sendMsg('Uso: <code>/bloquear usuario</code>');
    const { ok, data } = await localApi('POST', `/api/users/${encodeURIComponent(user)}/revoke`);
    if (!ok) return sendMsg(`❌ Error bloqueando ${user}: ${data.error || 'Error'}`);
    return sendMsg(`🔒 Cuenta <code>${user}</code> bloqueada y desconectada.`);
  }

  if (cmd === '/desbloquear') {
    const user = parts[1];
    if (!user) return sendMsg('Uso: <code>/desbloquear usuario</code>');
    const { ok, data } = await localApi('POST', `/api/users/${encodeURIComponent(user)}/unlock`);
    if (!ok) return sendMsg(`❌ Error desbloqueando ${user}: ${data.error || 'Error'}`);
    return sendMsg(`🔓 Cuenta <code>${user}</code> reactivada.`);
  }

  if (cmd === '/purgar') {
    const { ok, data } = await localApi('POST', '/api/users/purge-demos', { grace_hours: 0 });
    if (!ok) return sendMsg(`❌ Error en purga: ${data.error || 'Error'}`);
    return sendMsg(`🧹 ${data.message || 'Purga completada.'}`);
  }
}

// Monitor de alertas automáticas (RAM >= 90% y transiciones de SmartDNS Failover)
let lastRamAlert = 0;
let lastSmartDnsState = null;

async function checkAlerts() {
  try {
    const { ok, data } = await localApi('GET', '/api/system/status');
    if (ok && Number(data.ram_percent) >= 90 && Date.now() - lastRamAlert > 15 * 60 * 1000) {
      lastRamAlert = Date.now();
      await sendMsg(`⚠️ <b>Alerta RAM Alta en ${data.hostname}</b>\nUso actual: <b>${data.ram_percent}%</b> (${data.ram_used_mb}M / ${data.ram_total_mb}M)`);
    }
  } catch (_) {}

  try {
    if (fs.existsSync('/run/joif-smartdns-state')) {
      const cur = fs.readFileSync('/run/joif-smartdns-state', 'utf8').trim();
      if (lastSmartDnsState && cur !== lastSmartDnsState) {
        if (cur === 'FAILOVER') {
          await sendMsg(`🚨 <b>Smart DNS en FAILOVER (${os.hostname()})</b>\nArgentina no respondió; DNAT suspendido temporalmente para mantener internet local.`);
        } else if (cur === 'ACTIVE' && lastSmartDnsState === 'FAILOVER') {
          await sendMsg(`✅ <b>Smart DNS Recuperado (${os.hostname()})</b>\nArgentina volvió a responder; DNAT reactivado automáticamente.`);
        }
      }
      lastSmartDnsState = cur;
    }
  } catch (_) {}
}

let offset = 0;
async function pollLoop() {
  while (true) {
    try {
      const data = await tgCall('getUpdates', { offset, timeout: 25, allowed_updates: ['message'] });
      if (data && data.ok && Array.isArray(data.result)) {
        for (const upd of data.result) {
          offset = upd.update_id + 1;
          const msg = upd.message;
          if (!msg || !msg.text) continue;
          if (String(msg.chat?.id) !== String(ADMIN_ID)) continue;
          await handleCommand(msg.text);
        }
      }
    } catch (e) {
      await new Promise((r) => setTimeout(r, 5000));
    }
  }
}

console.log(`[TG-BOT] Iniciado en modo Alfa para admin ${ADMIN_ID}`);
sendMsg(`🤖 <b>JOIF Cloud Bot [Alfa] conectado</b> en <code>${os.hostname()}</code>. Envía /help para ver comandos.`);
setInterval(checkAlerts, 60000).unref();
pollLoop();
