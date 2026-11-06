'use strict';

const net = require('node:net');
const path = require('node:path');
try { require('dotenv').config(); } catch {}

const PROXY_PORT = Number(process.env.PROXY_PORT) || 80;
const SSH_PORT = Number(process.env.SSH_PORT) || 22;
const ALLOWED_TARGET_PORTS = new Set([22, 143, 7300, SSH_PORT]);

const RESPONSE_101 = Buffer.from(
  'HTTP/1.1 101 Switching Protocols\r\n' +
  'Upgrade: websocket\r\n' +
  'Connection: Upgrade\r\n\r\n'
);

function parseTarget(headerValue, defaultPort) {
  if (!headerValue || typeof headerValue !== 'string') return defaultPort;
  const cleaned = headerValue.trim();
  const match = cleaned.match(/^(?:https?:\/\/)?(?:127\.0\.0\.1|localhost)?:?(\d{1,5})$/i);
  if (match) {
    const port = Number(match[1]);
    if (ALLOWED_TARGET_PORTS.has(port)) return port;
  }
  return defaultPort;
}

function createProxyServer(options = {}) {
  let database = options.db;
  if (!database) {
    try {
      database = require('./db');
    } catch {
      database = null;
    }
  }
  const listenPort = options.proxyPort || PROXY_PORT;
  const defaultSshPort = options.sshPort || SSH_PORT;

  const server = net.createServer((clientSocket) => {
    // 1. Optimización para latencia cero en juegos (Desactivar Nagle)
    clientSocket.setNoDelay(true);
    // 2. Anti-desconexiones en redes móviles (Keepalive cada 15 segundos)
    clientSocket.setKeepAlive(true, 15000);

    // Timeout de 10s para recibir el payload inicial HTTP
    const handshakeTimeout = setTimeout(() => {
      clientSocket.destroy();
    }, 10000);

    let chunks = [];
    let totalLength = 0;

    const onData = async (chunk) => {
      chunks.push(chunk);
      totalLength += chunk.length;

      const buffer = Buffer.concat(chunks, totalLength);
      let headerEnd = buffer.indexOf('\r\n\r\n');
      let delimiterLength = 4;

      if (headerEnd === -1) {
        headerEnd = buffer.indexOf('\n\n');
        delimiterLength = 2;
      }

      // Si no han llegado las cabeceras completas y no supera 16 KB, esperar siguiente paquete
      if (headerEnd === -1) {
        if (totalLength > 16384) {
          clearTimeout(handshakeTimeout);
          clientSocket.removeListener('data', onData);
          clientSocket.destroy();
        }
        return;
      }

      // Cabeceras completas recibidas
      clearTimeout(handshakeTimeout);
      clientSocket.removeListener('data', onData);

      const headerText = buffer.subarray(0, headerEnd).toString('latin1');
      const remainingBytes = buffer.subarray(headerEnd + delimiterLength);

      // 3. Extraer cabeceras relevantes
      let hwid = null;
      let realHost = null;

      for (const line of headerText.split(/\r?\n/)) {
        const colon = line.indexOf(':');
        if (colon === -1) continue;
        const key = line.slice(0, colon).trim().toLowerCase();
        const value = line.slice(colon + 1).trim();

        if (key === 'x-hwid') {
          hwid = value;
        } else if (key === 'x-real-host') {
          realHost = value;
        }
      }

      // 4. Validación de HWID contra SQLite si se proporcionó
      if (hwid && database) {
        try {
          const result = await database.query(
            'SELECT username, status, expiration_date FROM users WHERE hwid = ? OR username = ?',
            [hwid, hwid]
          );

          if (!result || result.rowCount === 0) {
            clientSocket.write('HTTP/1.1 403 Forbidden\r\nContent-Type: text/plain\r\nConnection: close\r\n\r\nDispositivo no autorizado.\r\n');
            clientSocket.destroy();
            return;
          }

          const user = result.rows[0];
          const expires = Date.parse(user.expiration_date);
          if (user.status !== 'active' || (Number.isFinite(expires) && expires <= Date.now())) {
            clientSocket.write('HTTP/1.1 403 Forbidden\r\nContent-Type: text/plain\r\nConnection: close\r\n\r\nCuenta suspendida o expirada.\r\n');
            clientSocket.destroy();
            return;
          }
        } catch (err) {
          console.error('[PROXY] Error consultando base de datos:', err.message);
          clientSocket.destroy();
          return;
        }
      }

      // 5. Determinar puerto de destino seguro (local 127.0.0.1)
      const targetPort = parseTarget(realHost, defaultSshPort);

      // 6. Conexión rápida a SSH / Dropbear local
      const sshSocket = net.createConnection({ port: targetPort, host: '127.0.0.1' }, () => {
        sshSocket.setNoDelay(true);
        sshSocket.setKeepAlive(true, 15000);

        // Responder con HTTP 101 estándar limpio
        clientSocket.write(RESPONSE_101);

        // Si llegaron bytes pipelined (SSH greeting inicial junto al payload), enviarlos de inmediato
        if (remainingBytes.length > 0) {
          sshSocket.write(remainingBytes);
        }

        // Streaming bidireccional no bloqueante con libuv
        clientSocket.pipe(sshSocket);
        sshSocket.pipe(clientSocket);
      });

      sshSocket.on('error', () => clientSocket.destroy());
      clientSocket.on('error', () => sshSocket.destroy());
      sshSocket.on('close', () => clientSocket.destroy());
      clientSocket.on('close', () => sshSocket.destroy());
    };

    clientSocket.on('data', onData);
    clientSocket.on('error', () => clientSocket.destroy());
  });

  return server;
}

function parseCliArgs() {
  const args = process.argv.slice(2);
  let proxyPort = Number(process.env.PROXY_PORT) || 80;
  let sshPort = Number(process.env.SSH_PORT) || 22;

  for (let i = 0; i < args.length; i++) {
    const arg = args[i];
    if (arg === '-p' || arg === '--port') {
      const val = Number(args[++i]);
      if (val > 0 && val < 65536) proxyPort = val;
    } else if (arg === '-s' || arg === '--ssh' || arg === '--target') {
      const val = Number(args[++i]);
      if (val > 0 && val < 65536) sshPort = val;
    } else if (/^\d+$/.test(arg)) {
      proxyPort = Number(arg);
    }
  }
  return { proxyPort, sshPort };
}

if (require.main === module) {
  const { proxyPort, sshPort } = parseCliArgs();
  const server = createProxyServer({ proxyPort, sshPort });
  server.listen(proxyPort, '0.0.0.0', () => {
    console.log(`🚀 [PROXY-NODE] WebSocket Proxy activo en 0.0.0.0:${proxyPort}`);
    console.log(`➡️ [PROXY-NODE] Reenvío optimizado a 127.0.0.1:${sshPort} (Zero-Latency / KeepAlive activo)`);
  });

  const shutdown = () => {
    server.close(() => process.exit(0));
  };
  process.on('SIGINT', shutdown);
  process.on('SIGTERM', shutdown);
}

module.exports = { createProxyServer, parseTarget, RESPONSE_101 };
