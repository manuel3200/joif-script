# 🐲 Especificación de Integración de API - JOIF Cloud (V1.5.0)

> **Documento para Desarrolladores y Agentes de IA:**  
> Esta especificación contiene toda la información necesaria para conectar e integrar cualquier aplicación web (tienda online, panel de revendedores, generador de cuentas free como `https://sv-free.joif.net/`, bot de Telegram o backend) con uno o varios nodos VPS ejecutando **JOIF Cloud**.

---

## 1. Arquitectura y Conceptos Clave

1. **Cada VPS es un Nodo Independiente:**
   - La API corre de forma nativa en cada VPS en el puerto **`3000`** (HTTP).
   - No requiere base de datos externa ni brokers pesados; utiliza SQLite local ultrarrápido y ejecuta comandos directos en el sistema Linux (`useradd`, `chpasswd`, `chage`, `pkill`, `userdel`).
2. **CORS Abierto:**
   - El backend cuenta con middleware `cors()` activo. Tu página web puede consultar la API **tanto desde el servidor (backend PHP/Node/Python) como directamente desde el navegador del cliente (frontend JavaScript/Fetch)**.
3. **Firewall:**
   - El puerto `3000` TCP viene abierto de fábrica en el script de instalación (`iptables` / `ufw`).
4. **Protocolos del Servidor:**
   - **Puerto 22:** OpenSSH nativo.
   - **Puerto 80:** Proxy WebSocket SSH de baja latencia (`proxy.js`).
   - **Puerto 443:** SSL / TLS Stunnel.
   - **Puertos 7300 / 7200:** BadVPN UDP-GW (UDP para juegos y VoIP).
   - **Puerto 3000:** API REST y validador CheckUser en tiempo real.

---

## 2. Autenticación

Todas las rutas administrativas (`/api/users*`) requieren la cabecera HTTP:

```http
x-api-key: <API_KEY>
Content-Type: application/json
```

* **Ubicación en la VPS:** `/root/joif-core/.env`
* **Valor predeterminado:** `joif2026`
* **Cambio de clave:** Puedes editar la variable `API_KEY` en el archivo `.env` de cada nodo y reiniciar con `systemctl restart joif`.

---

## 3. Tipos de Cuentas Soportadas

### Tipo A: Cuenta Estándar (Usuario y Contraseña SSH)
Para apps tradicionales donde el usuario escribe sus credenciales:
* El cliente recibe: `Host/IP`, `Puerto (80/22/443)`, `Usuario` y `Contraseña`.

### Tipo B: Cuenta HWID (Para HTTP Custom / Epro)
Para configuraciones bloqueadas con la opción **"Inicio de sesión con HWID"**:
* El usuario de la app no introduce contraseña; su teléfono envía el identificador de hardware (**HWID**) como usuario y contraseña SSH.
* En la API se envía el campo `"hwid"`. El servidor crea la cuenta de Linux con ese HWID exacto utilizando `--badname` (admite letras mayúsculas y números iniciales).
* Opcionalmente se envía `"alias"` para identificar al cliente con un nombre legible en la web.

---

## 4. Referencia Completa de Endpoints

### 4.1. Crear Usuario
Crea la cuenta en la base de datos del nodo y genera el usuario de Linux en tiempo real.

* **Método:** `POST`
* **Ruta:** `http://<IP_VPS>:3000/api/users`
* **Headers:**
  ```http
  x-api-key: <API_KEY>
  Content-Type: application/json
  ```

#### Payload Modo A (Usuario Estándar):
```json
{
  "username": "usuario123",
  "password": "PasswordSegura2026*",
  "expiration_date": "2026-12-31T23:59:59Z",
  "max_connections": 1,
  "alias": "Juan Pérez"
}
```

#### Payload Modo B (Cuenta HWID para HTTP Custom):
```json
{
  "hwid": "7CBE2AB08B4497B7908779AE4614BFBB",
  "expiration_date": "2026-12-31T23:59:59Z",
  "max_connections": 1,
  "alias": "Móvil Cliente 01"
}
```

#### Parámetros:
| Parámetro | Tipo | Obligatorio | Descripción |
| :--- | :--- | :--- | :--- |
| `username` | String | Sí (en Modo A) | 1 a 32 caracteres (`^[A-Za-z0-9_][A-Za-z0-9_-]{0,31}$`). |
| `password` | String | Sí (en Modo A) | Contraseña SSH (máx. 256 caracteres). |
| `hwid` | String | Sí (en Modo B) | Identificador HWID del dispositivo (hasta 128 caracteres, compatible con `--badname`). |
| `expiration_date` | String | Sí | Fecha futura en formato ISO 8601 (`YYYY-MM-DD` o `YYYY-MM-DDTHH:mm:ssZ`). |
| `max_connections` | Integer | No (def: 1) | Límite de conexiones simultáneas permitidas (1 a 100). |
| `alias` | String | No | Etiqueta descriptiva para identificar al cliente humano. |

#### Respuesta Exitosa (`201 Created`):
```json
{
  "message": "Usuario creado con éxito",
  "id": 1,
  "username": "usuario123",
  "alias": "Juan Pérez"
}
```

#### Respuestas de Error:
* `400 Bad Request`: Datos incompletos, fecha pasada o nombre inválido.
* `409 Conflict`: `{"error": "La cuenta ya existe."}`
* `500 Server Error`: Falla de ejecución en Linux.

---

### 4.2. Listar Todos los Usuarios
* **Método:** `GET`
* **Ruta:** `http://<IP_VPS>:3000/api/users`
* **Headers:** `x-api-key: <API_KEY>`

#### Respuesta (`200 OK`):
```json
[
  {
    "id": 1,
    "username": "usuario123",
    "expiration_date": "2026-12-31T23:59:59.000Z",
    "hwid": null,
    "alias": "Juan Pérez",
    "max_connections": 1,
    "status": "active",
    "created_at": "2026-11-07T03:30:00.000Z"
  }
]
```

---

### 4.3. Suspender / Revocar Usuario
Bloquea la cuenta inmediatamente (`usermod -L`), fuerza expiración (`chage -E 0`), termina procesos SSH activos (`pkill -u <user> sshd`) y cambia el estado a `revoked`.

* **Método:** `POST`
* **Ruta:** `http://<IP_VPS>:3000/api/users/:target/revoke`
  * `:target` puede ser el `username`, el `hwid` o el `alias`.
* **Headers:** `x-api-key: <API_KEY>`

#### Respuesta (`200 OK`):
```json
{
  "message": "Cuenta revocada."
}
```

---

### 4.4. Eliminar Usuario Definitivamente
Expulsa sesiones activas, elimina el usuario de Linux (`userdel -f`) y lo borra de SQLite.

* **Método:** `DELETE`
* **Ruta:** `http://<IP_VPS>:3000/api/users/:target`
  * `:target` puede ser el `username`, el `hwid` o el `alias`.
* **Headers:** `x-api-key: <API_KEY>`

#### Respuesta (`200 OK`):
```json
{
  "message": "Usuario eliminado con éxito."
}
```

---

### 4.5. CheckUser en Vivo (Público para Aplicaciones Móviles)
Valida la vigencia de una cuenta en vivo. Compatible con **SSHPLUS, DTunnel, HTTP Custom y Conecta4G**.

* **Método:** `GET`
* **Ruta:** `http://<IP_VPS>:3000/check/:id` (o `/api/check/:id`)
  * `:id` puede ser el `username` o el `hwid`.
* **Autenticación:** Ninguna (acceso público).

#### Respuesta (`200 OK`):
```json
{
  "count_connections": 1,
  "expiration_date": "31/12/2026",
  "expiration_days": 54,
  "limit_connections": 1,
  "time_online": "01:14:22",
  "username": "usuario123",
  "uuid": null
}
```
* Si la cuenta expiró o fue revocada: `403 Forbidden` (`{"error": "Cuenta vencida o revocada."}`)
* Si no existe: `404 Not Found` (`{"error": "Usuario no encontrado"}`)

---

### 4.6. CheckUser Global (Público)
* **Método:** `GET`
* **Ruta:** `http://<IP_VPS>:3000/check` (o `/api/check`)
* **Respuesta (`200 OK`):**
```json
["usuario123", "7CBE2AB08B4497B7908779AE4614BFBB"]
```

---

## 5. Módulo de Integración para el Shop Web (`sv-free.joif.net`)

A continuación tienes un cliente listo para producción en JavaScript / TypeScript que puedes usar directamente en tu backend (Node.js/Express, Next.js, Nuxt) o frontend (Vue, React, Vanilla JS):

```javascript
/**
 * Cliente de Integración JOIF Cloud
 * Compatible con múltiples servidores/nodos
 */
class JoifNodeClient {
  constructor(vpsIp, apiKey = 'joif2026', port = 3000) {
    this.baseUrl = `http://${vpsIp}:${port}`;
    this.apiKey = apiKey;
  }

  async _request(path, method = 'GET', data = null) {
    const headers = {
      'x-api-key': this.apiKey,
      'Content-Type': 'application/json'
    };

    const options = { method, headers };
    if (data && method !== 'GET') {
      options.body = JSON.stringify(data);
    }

    const res = await fetch(`${this.baseUrl}${path}`, options);
    const json = await res.json().catch(() => ({}));
    if (!res.ok) {
      const err = new Error(json.error || `HTTP ${res.status}`);
      err.status = res.status;
      throw err;
    }
    return json;
  }

  /**
   * Crear cuenta de usuario SSH clásica
   */
  async crearUsuarioSSH(username, password, diasValidez = 3, alias = '') {
    const fecha = new Date();
    fecha.setDate(fecha.getDate() + diasValidez);

    return await this._request('/api/users', 'POST', {
      username,
      password,
      expiration_date: fecha.toISOString(),
      max_connections: 1,
      alias: alias || username
    });
  }

  /**
   * Crear cuenta por HWID (Para HTTP Custom)
   */
  async crearUsuarioHWID(hwid, diasValidez = 3, alias = '') {
    const fecha = new Date();
    fecha.setDate(fecha.getDate() + diasValidez);

    return await this._request('/api/users', 'POST', {
      hwid,
      expiration_date: fecha.toISOString(),
      max_connections: 1,
      alias: alias || hwid
    });
  }

  /**
   * Listar todos los usuarios en el servidor
   */
  async listarUsuarios() {
    return await this._request('/api/users', 'GET');
  }

  /**
   * Suspender usuario
   */
  async suspenderUsuario(target) {
    return await this._request(`/api/users/${encodeURIComponent(target)}/revoke`, 'POST');
  }

  /**
   * Eliminar usuario definitivamente
   */
  async eliminarUsuario(target) {
    return await this._request(`/api/users/${encodeURIComponent(target)}`, 'DELETE');
  }

  /**
   * Consultar estado en vivo de un usuario (CheckUser)
   */
  async consultarCheckUser(id) {
    const res = await fetch(`${this.baseUrl}/check/${encodeURIComponent(id)}`);
    return await res.json();
  }
}

// ============================================
// Ejemplo de uso para sv-free.joif.net
// ============================================
// const nodo1 = new JoifNodeClient('144.22.167.150', 'joif2026');
// nodo1.crearUsuarioSSH('free_demo', '123456', 3, 'Demo Gratuita Web')
//   .then(r => console.log('Cuenta creada:', r))
//   .catch(err => console.error('Error:', err.message));
```

---

## 6. Ejemplo en PHP (Para tiendas WooCommerce / WHMCS / Scripts PHP)

```php
<?php
class JoifNodeAPI {
    private $vpsIp;
    private $apiKey;
    private $port;

    public function __construct($vpsIp, $apiKey = 'joif2026', $port = 3000) {
        $this->vpsIp = $vpsIp;
        $this->apiKey = $apiKey;
        $this->port = $port;
    }

    private function call($endpoint, $method = 'GET', $data = []) {
        $url = "http://{$this->vpsIp}:{$this->port}{$endpoint}";
        $ch = curl_init($url);
        
        $headers = [
            "x-api-key: {$this->apiKey}",
            "Content-Type: application/json"
        ];

        curl_setopt($ch, CURLOPT_RETURNTRANSFER, true);
        curl_setopt($ch, CURLOPT_CUSTOMREQUEST, $method);
        curl_setopt($ch, CURLOPT_HTTPHEADER, $headers);
        curl_setopt($ch, CURLOPT_TIMEOUT, 8);

        if (!empty($data) && $method !== 'GET') {
            curl_setopt($ch, CURLOPT_POSTFIELDS, json_encode($data));
        }

        $response = curl_exec($ch);
        $status = curl_getinfo($ch, CURLINFO_HTTP_CODE);
        curl_close($ch);

        return [
            'status' => $status,
            'data' => json_decode($response, true)
        ];
    }

    public function crearCuentaSSH($user, $pass, $dias = 3, $alias = '') {
        $exp = date('Y-m-d\TH:i:s\Z', strtotime("+{$dias} days"));
        return $this->call('/api/users', 'POST', [
            'username' => $user,
            'password' => $pass,
            'expiration_date' => $exp,
            'max_connections' => 1,
            'alias' => $alias ?: $user
        ]);
    }

    public function crearCuentaHWID($hwid, $dias = 3, $alias = '') {
        $exp = date('Y-m-d\TH:i:s\Z', strtotime("+{$dias} days"));
        return $this->call('/api/users', 'POST', [
            'hwid' => $hwid,
            'expiration_date' => $exp,
            'max_connections' => 1,
            'alias' => $alias ?: $hwid
        ]);
    }
}
?>
```
