'use strict';

const net = require('node:net');
const path = require('node:path');
try { require('dotenv').config(); } catch {}

const PROXY_PORT = Number(process.env.PROXY_PORT) || 80;
const SSH_PORT = Number(process.env.SSH_PORT) || 22;
const ALLOWED_TARGET_PORTS = new Set([22, 143, 7300, SSH_PORT]);

function parsePorts(input, fallback = [80]) {
  if (Array.isArray(input)) {
    const clean = [...new Set(input.map(Number).filter((p) => Number.isInteger(p) && p > 0 && p < 65536))];
    return clean.length > 0 ? clean : fallback;
  }
  if (typeof input === 'number' && Number.isInteger(input) && input > 0 && input < 65536) {
    return [input];
  }
  if (typeof input === 'string' && input.trim()) {
    const clean = [...new Set(
      input.split(/[\s,]+/).map(Number).filter((p) => Number.isInteger(p) && p > 0 && p < 65536)
    )];
    return clean.length > 0 ? clean : fallback;
  }
  return fallback;
}

const RESPONSE_101 = Buffer.from(
  'HTTP/1.1 101 Switching Protocols\r\n' +
  'Upgrade: websocket\r\n' +
  'Connection: Upgrade\r\n\r\n'
);

const RESPONSE_200 = Buffer.from(
  'HTTP/1.1 200 Connection Established\r\n\r\n'
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
  const apiPort = options.apiPort || Number(process.env.PORT) || 3000;
  const v2rayPort = Number(options.v2rayPort ?? process.env.V2RAY_PORT) || 0;
  const rawV2Path = String(options.v2rayPath || process.env.V2RAY_PATH || '/v2ray').trim();
  const v2rayPath = rawV2Path.startsWith('/') ? rawV2Path : '/' + rawV2Path;

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

      // Si es una petición HTTP a la API, CheckUser o Panel Web (/panel), reenviar al backend Node.js (3000)
      const firstLine = headerText.split(/\r?\n/)[0] || '';
      if (/^(GET|POST|PUT|PATCH|DELETE|OPTIONS|HEAD)\s+(\/api\/|\/check|\/health|\/panel(?:\/|\?|\s|$))/i.test(firstLine)) {
        const apiSocket = net.createConnection({ port: apiPort, host: '127.0.0.1' }, () => {
          apiSocket.write(buffer);
          clientSocket.pipe(apiSocket);
          apiSocket.pipe(clientSocket);
        });
        apiSocket.on('error', () => {
          try {
            clientSocket.write('HTTP/1.1 502 Bad Gateway\r\nContent-Type: text/plain\r\nConnection: close\r\n\r\nAPI local inalcanzable.\r\n');
            clientSocket.destroy();
          } catch (_) {}
        });
        clientSocket.on('error', () => {
          try { apiSocket.destroy(); } catch (_) {}
        });
        return;
      }

      // Multiplexado opcional V2Ray / Xray WebSocket por ruta (ej. GET /v2ray HTTP/1.1 -> 127.0.0.1:V2RAY_PORT)
      if (v2rayPort > 0 && v2rayPort < 65536) {
        const reqPath = (firstLine.split(/\s+/)[1] || '').split('?')[0];
        if (reqPath === v2rayPath || reqPath.startsWith(v2rayPath + '/')) {
          const v2Socket = net.createConnection({ port: v2rayPort, host: '127.0.0.1' }, () => {
            v2Socket.setNoDelay(true);
            v2Socket.setKeepAlive(true, 15000);
            v2Socket.write(buffer);
            clientSocket.pipe(v2Socket);
            v2Socket.pipe(clientSocket);
          });
          v2Socket.on('error', () => {
            try {
              clientSocket.write('HTTP/1.1 502 Bad Gateway\r\nContent-Type: text/plain\r\nConnection: close\r\n\r\nBackend V2Ray local inalcanzable.\r\n');
              clientSocket.destroy();
            } catch (_) {}
          });
          clientSocket.on('error', () => { try { v2Socket.destroy(); } catch (_) {} });
          v2Socket.on('close', () => clientSocket.destroy());
          clientSocket.on('close', () => v2Socket.destroy());
          return;
        }
      }

      // 3. Extraer cabeceras relevantes
      let hwid = null;
      let realHost = null;

      for (const line of headerText.split(/\r?\n/)) {
        const colon = line.indexOf(':');
        if (colon === -1) continue;
        const key = line.slice(0, colon).trim().toLowerCase();
        const value = line.slice(colon + 1).trim().replace(/^["']|["']$/g, '');

        if (key === 'x-hwid' || key === 'hwid' || key === 'x-device-id') {
          hwid = value;
        } else if (key === 'x-real-host') {
          realHost = value;
        }
      }

      // 4. Validación de HWID contra SQLite si se proporcionó
      if (hwid && database) {
        try {
          const result = await database.query(
            'SELECT username, status, expiration_date FROM users WHERE hwid = ? COLLATE NOCASE OR username = ? COLLATE NOCASE',
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

        // Responder con HTTP 101 si es WebSocket o HTTP 200 Connection Established si es HTTP Proxy estándar
        const isWs = /upgrade\s*:\s*websocket/i.test(headerText) || /connection\s*:\s*upgrade/i.test(headerText);
        clientSocket.write(isWs ? RESPONSE_101 : RESPONSE_200);

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
  let proxyPorts = parsePorts(process.env.PROXY_PORTS || process.env.PROXY_PORT, [80]);
  let sshPort = Number(process.env.SSH_PORT) || 22;
  let v2rayPort = Number(process.env.V2RAY_PORT) || 0;
  let v2rayPath = process.env.V2RAY_PATH || '/v2ray';

  for (let i = 0; i < args.length; i++) {
    const arg = args[i];
    if (arg === '-p' || arg === '--port' || arg === '--ports') {
      proxyPorts = parsePorts(args[++i], proxyPorts);
    } else if (arg === '-s' || arg === '--ssh' || arg === '--target') {
      const val = Number(args[++i]);
      if (val > 0 && val < 65536) sshPort = val;
    } else if (arg === '--v2ray-port') {
      const val = Number(args[++i]);
      if (val >= 0 && val < 65536) v2rayPort = val;
    } else if (arg === '--v2ray-path') {
      if (args[i + 1]) v2rayPath = args[++i];
    } else if (/^\d+(?:,\d+)*$/.test(arg)) {
      proxyPorts = parsePorts(arg, proxyPorts);
    }
  }
  return { proxyPort: proxyPorts[0], proxyPorts, sshPort, v2rayPort, v2rayPath };
}

if (require.main === module) {
  const { proxyPorts, sshPort, v2rayPort, v2rayPath } = parseCliArgs();
  const servers = [];

  for (const port of proxyPorts) {
    const server = createProxyServer({ proxyPort: port, sshPort, v2rayPort, v2rayPath });
    server.on('error', (err) => {
      console.error(`❌ [PROXY-NODE] Error en el servidor proxy (Puerto ${port}):`, err.message);
      process.exit(1);
    });
    server.listen(port, '0.0.0.0', () => {
      console.log(`🚀 [PROXY-NODE] WebSocket Proxy activo en 0.0.0.0:${port}`);
    });
    servers.push(server);
  }

  console.log(`➡️ [PROXY-NODE] SSH -> 127.0.0.1:${sshPort} | Panel -> /panel | Puertos: ${proxyPorts.join(', ')}`);
  if (v2rayPort > 0) {
    console.log(`➡️ [PROXY-NODE] Multiplexado V2Ray/Xray activo: ${v2rayPath} -> 127.0.0.1:${v2rayPort}`);
  }

  const shutdown = () => {
    let remaining = servers.length;
    if (remaining === 0) return process.exit(0);
    for (const s of servers) {
      s.close(() => {
        remaining--;
        if (remaining <= 0) process.exit(0);
      });
    }
  };
  process.on('SIGINT', shutdown);
  process.on('SIGTERM', shutdown);
}

module.exports = { createProxyServer, parseTarget, parsePorts, RESPONSE_101 };
