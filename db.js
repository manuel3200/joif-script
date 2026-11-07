const sqlite3 = require('sqlite3').verbose();
const path = require('path');
const fs = require('fs');

const dbPath = path.resolve(__dirname, 'database.sqlite');
const isFirstRun = !fs.existsSync(dbPath);

const db = new sqlite3.Database(dbPath, (err) => {
  if (err) {
    console.error('[DB] Error conectando a SQLite:', err.message);
  } else {
    console.log('[DB] Conectado a SQLite exitosamente.');
    db.run('PRAGMA journal_mode = WAL;');
    db.run('PRAGMA synchronous = NORMAL;');
    db.run('ALTER TABLE users ADD COLUMN alias TEXT;', () => {});
  }
});

// Promisify SQLite methods for async/await usage in server.js
const query = (sql, params = []) => {
  return new Promise((resolve, reject) => {
    // If it's a SELECT query, use .all
    if (sql.trim().toUpperCase().startsWith('SELECT')) {
      db.all(sql, params, (err, rows) => {
        if (err) reject(err);
        else resolve({ rows, rowCount: rows.length });
      });
    } else {
      // If it's INSERT/UPDATE/DELETE, use .run
      db.run(sql, params, function (err) {
        if (err) reject(err);
        else resolve({ changes: this.changes, lastID: this.lastID, rowCount: this.changes });
      });
    }
  });
};

// Configurar el esquema inicial si la BD es nueva
const initDB = async () => {
  if (isFirstRun) {
    console.log('[DB] Inicializando tablas por primera vez...');
    try {
      await query(`
        CREATE TABLE IF NOT EXISTS users (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          username TEXT NOT NULL UNIQUE,
          password TEXT NOT NULL,
          hwid TEXT,
          alias TEXT,
          expiration_date TEXT NOT NULL,
          max_connections INTEGER DEFAULT 1,
          status TEXT DEFAULT 'active',
          created_at DATETIME DEFAULT CURRENT_TIMESTAMP
        )
      `);
      
      await query(`
        CREATE TABLE IF NOT EXISTS admin_config (
          key TEXT PRIMARY KEY,
          value TEXT
        )
      `);

      // Generar contraseña aleatoria
      const randomPassword = require('node:crypto').randomBytes(18).toString('base64url');
      await query(`INSERT INTO admin_config (key, value) VALUES ('admin_user', 'admin')`);
      await query(`INSERT INTO admin_config (key, value) VALUES ('admin_pass', ?)`, [require('./backend-security').hashPassword(randomPassword)]);
      await query(`INSERT INTO admin_config (key, value) VALUES ('needs_password_change', 'true')`);

      console.log('\n=================================================');
      console.log('✅ INSTALACIÓN COMPLETADA: PANEL WEB INICIADO');
      console.log('👤 Usuario Admin: admin');
      console.log(`🔑 Contraseña Temporal: ${randomPassword}`);
      console.log('⚠️ DEBES CAMBIAR LA CONTRASEÑA EN TU PRIMER LOGIN!');
      console.log('=================================================\n');

      console.log('[DB] Tablas creadas correctamente.');
    } catch (err) {
      console.error('[DB] Error creando tablas:', err.message);
      throw err;
    }
  }
};

const ready = initDB();

module.exports = {
  query: async (sql, params) => { await ready; return query(sql, params); },
  ready,
  db
};
