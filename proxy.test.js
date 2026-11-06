'use strict';

const { test } = require('node:test');
const assert = require('node:assert/strict');
const net = require('node:net');
const { createProxyServer, parseTarget } = require('./proxy');

test('parseTarget extracts valid local ports and falls back safely', () => {
  assert.equal(parseTarget('127.0.0.1:22', 22), 22);
  assert.equal(parseTarget('127.0.0.1:143', 22), 143);
  assert.equal(parseTarget('localhost:7300', 22), 7300);
  // Rejects external hosts or forbidden ports
  assert.equal(parseTarget('example.com:22', 22), 22);
  assert.equal(parseTarget('127.0.0.1:8080', 22), 22);
  assert.equal(parseTarget(null, 22), 22);
});

test('proxy forwards HTTP 101 payload to mock SSH server with full bidirectional data', async (t) => {
  // 1. Mock SSH server
  let sshReceived = '';
  const mockSsh = net.createServer((sock) => {
    sock.setNoDelay(true);
    sock.write('SSH-2.0-OpenSSH_9.6p1\r\n');
    sock.on('data', (d) => {
      sshReceived += d.toString();
      if (sshReceived.includes('SSH-2.0-Go')) {
        sock.write('SSH-AUTH-OK\r\n');
      }
    });
  });

  const sshPort = await new Promise((res) => {
    mockSsh.listen(0, '127.0.0.1', () => res(mockSsh.address().port));
  });

  // Mock DB (no HWID needed for general SSH connections)
  const mockDb = { query: async () => ({ rows: [], rowCount: 0 }) };

  const proxy = createProxyServer({ db: mockDb, sshPort });
  const proxyPort = await new Promise((res) => {
    proxy.listen(0, '127.0.0.1', () => res(proxy.address().port));
  });

  t.after(() => {
    proxy.close();
    mockSsh.close();
  });

  // 2. Client connects with HTTP payload
  const client = net.createConnection({ port: proxyPort, host: '127.0.0.1' });
  let clientBuffer = '';

  const connectedPromise = new Promise((resolve, reject) => {
    client.on('error', reject);
    client.on('data', (chunk) => {
      clientBuffer += chunk.toString();
      if (clientBuffer.includes('SSH-AUTH-OK')) {
        resolve();
      }
    });
  });

  await new Promise((res) => client.on('connect', res));

  // Send payload
  client.write('GET / HTTP/1.1\r\nHost: bug.operator.com\r\nUpgrade: websocket\r\nConnection: Upgrade\r\n\r\n');

  // Wait until we see HTTP 101
  await new Promise((res) => {
    const check = () => {
      if (clientBuffer.includes('101 Switching Protocols')) res();
      else setTimeout(check, 10);
    };
    check();
  });

  assert.ok(clientBuffer.includes('HTTP/1.1 101 Switching Protocols'));
  assert.ok(clientBuffer.includes('SSH-2.0-OpenSSH'));

  // Client responds with SSH greeting
  client.write('SSH-2.0-Go\r\n');
  await connectedPromise;

  assert.ok(sshReceived.includes('SSH-2.0-Go'));
  client.destroy();
});

test('proxy forwards pipelined SSH greeting immediately without byte loss', async (t) => {
  let sshGreetingReceived = '';
  const mockSsh = net.createServer((sock) => {
    sock.on('data', (d) => {
      sshGreetingReceived += d.toString();
      if (sshGreetingReceived.includes('SSH-2.0-EarlyClient')) {
        sock.write('SSH-PIPELINE-OK\r\n');
      }
    });
  });

  const sshPort = await new Promise((res) => {
    mockSsh.listen(0, '127.0.0.1', () => res(mockSsh.address().port));
  });

  const mockDb = { query: async () => ({ rows: [], rowCount: 0 }) };
  const proxy = createProxyServer({ db: mockDb, sshPort });
  const proxyPort = await new Promise((res) => {
    proxy.listen(0, '127.0.0.1', () => res(proxy.address().port));
  });

  t.after(() => {
    proxy.close();
    mockSsh.close();
  });

  const client = net.createConnection({ port: proxyPort, host: '127.0.0.1' });
  let responseData = '';

  const pipelinePromise = new Promise((resolve, reject) => {
    client.on('error', reject);
    client.on('data', (d) => {
      responseData += d.toString();
      if (responseData.includes('SSH-PIPELINE-OK')) resolve();
    });
  });

  await new Promise((res) => client.on('connect', res));

  // Send HTTP header AND SSH greeting in the EXACT SAME PACKET
  client.write(
    'GET / HTTP/1.1\r\nHost: bug.com\r\nUpgrade: websocket\r\nConnection: Upgrade\r\n\r\n' +
    'SSH-2.0-EarlyClient\r\n'
  );

  await pipelinePromise;
  assert.ok(sshGreetingReceived.includes('SSH-2.0-EarlyClient'));
  client.destroy();
});

test('proxy validates HWID against DB: accepts active and rejects invalid/expired', async (t) => {
  const mockSsh = net.createServer((sock) => {
    sock.write('SSH-OK\r\n');
  });

  const sshPort = await new Promise((res) => {
    mockSsh.listen(0, '127.0.0.1', () => res(mockSsh.address().port));
  });

  const mockDb = {
    query: async (sql, params) => {
      const hwid = params[0];
      if (hwid === 'VALID_HWID') {
        return {
          rowCount: 1,
          rows: [{ username: 'active_user', status: 'active', expiration_date: '2099-01-01T00:00:00Z' }]
        };
      }
      if (hwid === 'EXPIRED_HWID') {
        return {
          rowCount: 1,
          rows: [{ username: 'expired_user', status: 'expired', expiration_date: '2020-01-01T00:00:00Z' }]
        };
      }
      return { rowCount: 0, rows: [] };
    }
  };

  const proxy = createProxyServer({ db: mockDb, sshPort });
  const proxyPort = await new Promise((res) => {
    proxy.listen(0, '127.0.0.1', () => res(proxy.address().port));
  });

  t.after(() => {
    proxy.close();
    mockSsh.close();
  });

  // 1. Valid HWID
  const clientValid = net.createConnection({ port: proxyPort, host: '127.0.0.1' });
  let validBuf = '';
  await new Promise((res) => clientValid.on('connect', res));
  clientValid.on('data', (d) => { validBuf += d.toString(); });
  clientValid.write('GET / HTTP/1.1\r\nHost: bug.com\r\nX-HWID: VALID_HWID\r\n\r\n');
  await new Promise((res) => {
    const check = () => { if (validBuf.includes('101 Switching Protocols')) res(); else setTimeout(check, 10); };
    check();
  });
  assert.ok(validBuf.includes('HTTP/1.1 101 Switching Protocols'));
  clientValid.destroy();

  // 2. Unknown HWID -> 403
  const clientUnknown = net.createConnection({ port: proxyPort, host: '127.0.0.1' });
  let unknownBuf = '';
  await new Promise((res) => clientUnknown.on('connect', res));
  clientUnknown.on('data', (d) => { unknownBuf += d.toString(); });
  clientUnknown.write('GET / HTTP/1.1\r\nHost: bug.com\r\nX-HWID: UNKNOWN_HWID\r\n\r\n');
  await new Promise((res) => clientUnknown.on('close', res));
  assert.ok(unknownBuf.includes('403 Forbidden'));
  assert.ok(unknownBuf.includes('Dispositivo no autorizado'));

  // 3. Expired HWID -> 403
  const clientExpired = net.createConnection({ port: proxyPort, host: '127.0.0.1' });
  let expiredBuf = '';
  await new Promise((res) => clientExpired.on('connect', res));
  clientExpired.on('data', (d) => { expiredBuf += d.toString(); });
  clientExpired.write('GET / HTTP/1.1\r\nHost: bug.com\r\nX-HWID: EXPIRED_HWID\r\n\r\n');
  await new Promise((res) => clientExpired.on('close', res));
  assert.ok(expiredBuf.includes('403 Forbidden'));
  assert.ok(expiredBuf.includes('Cuenta suspendida o expirada'));
});
