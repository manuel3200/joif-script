'use strict';
const crypto = require('node:crypto');
const KEY = Buffer.from("JoifVPNAppEncrypKey2026!#*123456");
function encrypt(config) {
  const iv = crypto.randomBytes(12), cipher = crypto.createCipheriv('aes-256-gcm', KEY, iv);
  const data = Buffer.concat([cipher.update(JSON.stringify(config), 'utf8'), cipher.final(), cipher.getAuthTag()]);
  return 'JOIF_VPN_V1:' + iv.toString('base64') + ':' + data.toString('base64');
}
function decrypt(data) {
  const parts = data.split(':'), iv = Buffer.from(parts[1], 'base64'), bytes = Buffer.from(parts[2], 'base64');
  if (parts[0] !== 'JOIF_VPN_V1' || parts.length !== 3 || iv.length !== 12 || bytes.length < 17) throw Error('Cifrado inválido.');
  const cipher = crypto.createDecipheriv('aes-256-gcm', KEY, iv); cipher.setAuthTag(bytes.subarray(-16));
  return JSON.parse(Buffer.concat([cipher.update(bytes.subarray(0,-16)), cipher.final()]).toString('utf8'));
}
module.exports = { encrypt, decrypt };
