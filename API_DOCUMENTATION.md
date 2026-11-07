# 🐲 JOIF Cloud - Documentación Oficial de la API REST

Esta documentación detalla cómo conectar cualquier **sitio web, panel administrativo, bot de Telegram, plataforma de facturación (WHMCS/WordPress) o aplicación móvil** con una VPS que ejecute **JOIF Cloud**, permitiendo la creación, revocación, validación y administración automatizada de usuarios SSH y cuentas HWID.

---

## 📌 Tabla de Contenidos
1. [Arquitectura y Requisitos](#-arquitectura-y-requisitos)
2. [Instalación y Puesta en Marcha en la VPS](#-instalación-y-puesta-en-marcha-en-la-vps)
3. [Seguridad y Autenticación](#-seguridad-y-autenticación)
4. [Referencia de Endpoints](#-referencia-de-endpoints)
   - [1. Crear Usuario (SSH / HWID)](#1-crear-usuario-post-apiusers)
   - [2. Listar Todos los Usuarios](#2-listar-todos-los-usuarios-get-apiusers)
   - [3. Suspender / Revocar Usuario](#3-suspender--revocar-usuario-post-apiusersusernamerevoke)
   - [4. Eliminar Usuario Definitivamente](#4-eliminar-usuario-definitivamente-delete-apiusersusername)
   - [5. Eliminar Todos los Usuarios](#5-eliminar-todos-los-usuarios-delete-apiusers)
   - [6. CheckUser API (Validación en Vivo)](#6-checkuser-api-get-apicheckid)
   - [7. CheckUser Global (Array Simple)](#7-checkuser-global-get-apicheck)
   - [8. Generar Perfil Cifrado JOIF](#8-generar-perfil-cifrado-joif-post-apiusersusernameconfig)
5. [Ejemplos de Integración](#-ejemplos-de-integración)
   - [Ejemplo en PHP](#-ejemplo-en-php-curl)
   - [Ejemplo en JavaScript (Node.js / Frontend)](#-ejemplo-en-javascript-fetch--axios)
   - [Ejemplo en Python](#-ejemplo-en-python-requests)
   - [Ejemplo en cURL](#-ejemplo-en-curl-bash)
6. [Códigos de Respuesta HTTP](#-códigos-de-respuesta-http)

---

## 🌐 Arquitectura y Requisitos

* **Puerto por defecto de la API:** `3000` (TCP)
* **Base de datos:** SQLite local transaccional (`/root/joif-core/mivpn.sqlite`)
* **Sincronización:** Cada usuario creado en la API se crea **inmediatamente como cuenta del sistema Linux** con shell `/bin/false` y fecha de caducidad en `/etc/shadow`.
* **Soporte CORS:** Habilitado para permitir peticiones desde aplicaciones web basadas en navegador (`Vue`, `React`, `HTML/JS`).

---

## 🚀 Instalación y Puesta en Marcha en la VPS

### 1. Instalación en nueva VPS (Ubuntu 20.04/22.04/24.04/26.04 o Debian 10/11/12):
```bash
curl -fsSL https://raw.githubusercontent.com/manuel3200/joif-script/main/setup -o setup && chmod +x setup && ./setup
```

### 2. Configuración de API Key:
El archivo de variables de entorno se encuentra en:
```bash
/root/joif-core/.env
```
Contenido predeterminado:
```env
PORT=3000
API_KEY=joif2026
NODE_API_SECRET=joif2026
```
> 💡 **Recomendación:** Puedes cambiar `API_KEY` por una cadena segura y reiniciar el servicio:
> ```bash
> systemctl restart joif
> ```

---

## 🔐 Seguridad y Autenticación

Todas las llamadas de gestión (creación, edición, eliminación) requieren autenticación.

### Método 1: Header `x-api-key` (Recomendado para Paneles y Bots)
Incluye en los encabezados HTTP:
```http
x-api-key: tu_api_key_aqui
Content-Type: application/json
```

### Método 2: JWT Bearer Token (Para paneles con Login de Administrador)
1. Obtén el token mediante: `POST /api/auth/login` con `{ "username": "admin", "password": "..." }`.
2. Envía el token en cada petición:
```http
Authorization: Bearer <TOKEN_RECIBIDO>
Content-Type: application/json
```

---

## 📡 Referencia de Endpoints

### 1. Crear Usuario (`POST /api/users`)
Crea una cuenta en la base de datos y la registra de forma nativa en Linux (`useradd`, `chpasswd`, `chage`).

* **URL:** `http://<IP_VPS>:3000/api/users`
* **Método:** `POST`
* **Headers:**
  * `x-api-key`: `<TU_API_KEY>`
  * `Content-Type`: `application/json`

#### Modo A: Cuenta Estándar (Usuario y Contraseña SSH)
```json
{
  "username": "usuario_prueba",
  "password": "Password123*",
  "expiration_date": "2026-12-31T23:59:59Z",
  "max_connections": 1,
  "alias": "Juan Pérez"
}
```

#### Modo B: Cuenta por HWID (Para HTTP Custom / Epro)
> 📱 *En HTTP Custom con la opción "Inicio de sesión con HWID", el HWID actúa automáticamente como usuario y contraseña SSH.*
```json
{
  "hwid": "7CBE2AB08B4497B7908779AE4614BFBB",
  "expiration_date": "2026-12-31T23:59:59Z",
  "max_connections": 1,
  "alias": "Cliente Móvil 01"
}
```

#### Parámetros del Body:
| Campo | Tipo | Obligatorio | Descripción |
| :--- | :--- | :--- | :--- |
| `username` | String | Sí (en Modo A) | Nombre del usuario (1-32 caracteres alfanuméricos, guiones y guión bajo). |
| `password` | String | Sí (en Modo A) | Contraseña SSH de la cuenta (máx. 256 caracteres). |
| `hwid` | String | Sí (en Modo B) | Identificador de hardware del dispositivo (admite mayúsculas y dígitos iniciales mediante `--badname`). |
| `expiration_date` | String | Sí | Fecha de expiración en formato ISO 8601 (`YYYY-MM-DD` o `YYYY-MM-DDTHH:mm:ssZ`). Debe ser futura. |
| `max_connections` | Integer | No (default: 1) | Límite de conexiones simultáneas permitidas (1 a 100). |
| `alias` | String | No | Nombre o etiqueta humana para identificar al cliente. |

#### Respuesta Exitosa (`201 Created`):
```json
{
  "message": "Usuario creado con éxito",
  "id": 1,
  "username": "usuario_prueba",
  "alias": "Juan Pérez"
}
```

#### Errores Posibles:
* `400 Bad Request`: Parámetros inválidos (fecha pasada, caracteres no permitidos).
* `409 Conflict`: `{"error": "La cuenta ya existe."}`
* `500 Internal Server Error`: Falla a nivel de sistema operativo Linux.

---

### 2. Listar Todos los Usuarios (`GET /api/users`)
Devuelve la lista completa de usuarios registrados en el clúster.

* **URL:** `http://<IP_VPS>:3000/api/users`
* **Método:** `GET`
* **Headers:** `x-api-key: <TU_API_KEY>`

#### Respuesta Exitosa (`200 OK`):
```json
[
  {
    "id": 1,
    "username": "usuario_prueba",
    "expiration_date": "2026-12-31T23:59:59.000Z",
    "hwid": null,
    "alias": "Juan Pérez",
    "max_connections": 1,
    "status": "active",
    "created_at": "2026-11-07T03:30:00.000Z"
  },
  {
    "id": 2,
    "username": "7CBE2AB08B4497B7908779AE4614BFBB",
    "expiration_date": "2026-12-31T23:59:59.000Z",
    "hwid": "7CBE2AB08B4497B7908779AE4614BFBB",
    "alias": "Cliente Móvil 01",
    "max_connections": 1,
    "status": "active",
    "created_at": "2026-11-07T03:35:00.000Z"
  }
]
```

---

### 3. Suspender / Revocar Usuario (`POST /api/users/:target/revoke`)
Bloquea temporalmente al usuario: bloquea la contraseña en Linux (`usermod -L`), expira la cuenta (`chage -E 0`), termina sus sesiones SSH activas en vivo (`pkill -u <user> sshd`) y cambia su estado a `revoked`.

* **URL:** `http://<IP_VPS>:3000/api/users/:target/revoke`
  * `:target` puede ser el `username`, el `hwid` o el `alias`.
* **Método:** `POST`
* **Headers:** `x-api-key: <TU_API_KEY>`

#### Respuesta Exitosa (`200 OK`):
```json
{
  "message": "Cuenta revocada."
}
```

---

### 4. Eliminar Usuario Definitivamente (`DELETE /api/users/:target`)
Expulsa los procesos activos del usuario, elimina el usuario de Linux (`userdel -f`) y purga su registro de la base de datos.

* **URL:** `http://<IP_VPS>:3000/api/users/:target`
  * `:target` puede ser el `username`, el `hwid` o el `alias`.
* **Método:** `DELETE`
* **Headers:** `x-api-key: <TU_API_KEY>`

#### Respuesta Exitosa (`200 OK`):
```json
{
  "message": "Usuario eliminado con éxito."
}
```

---

### 5. Eliminar Todos los Usuarios (`DELETE /api/users`)
Elimina todas las cuentas del sistema Linux y vacía la tabla de usuarios.

* **URL:** `http://<IP_VPS>:3000/api/users`
* **Método:** `DELETE`
* **Headers:** `x-api-key: <TU_API_KEY>`

#### Respuesta Exitosa (`200 OK`):
```json
{
  "message": "Todos los usuarios han sido eliminados por completo."
}
```

---

### 6. CheckUser API (`GET /api/check/:id` o `GET /check/:id`)
Endpoint público y ultrarrápido compatible con aplicaciones clientes tipo **SSHPLUS, DTunnel, HTTP Custom, Conecta4G, etc.**

* **URL:** `http://<IP_VPS>:3000/check/:id`
  * `:id` puede ser el `username` o el `hwid`.
* **Método:** `GET`
* **Autenticación:** No requerida (Acceso libre para la app del cliente).

#### Respuesta Exitosa (`200 OK`):
```json
{
  "count_connections": 1,
  "expiration_date": "31/12/2026",
  "expiration_days": 54,
  "limit_connections": 1,
  "time_online": "01:14:22",
  "username": "usuario_prueba",
  "uuid": null
}
```

#### Respuestas de Estado:
* `200 OK`: Cuenta activa y con días de vigencia.
* `403 Forbidden`: `{"error": "Cuenta vencida o revocada."}`
* `404 Not Found`: `{"error": "Usuario no encontrado"}`

---

### 7. CheckUser Global (`GET /check` o `GET /api/check`)
Devuelve un array simple con los nombres de todos los usuarios actualmente activos y vigentes.

* **URL:** `http://<IP_VPS>:3000/check`
* **Método:** `GET`

#### Respuesta:
```json
["usuario_prueba", "7CBE2AB08B4497B7908779AE4614BFBB"]
```

---

### 8. Generar Perfil Cifrado JOIF (`POST /api/users/:username/config`)
Genera la carga cifrada del perfil listo para importar en clientes compatibles con JOIF VPN.

* **URL:** `http://<IP_VPS>:3000/api/users/:username/config`
* **Método:** `POST`
* **Body:**
```json
{
  "host": "144.22.167.150"
}
```
* **Respuesta:**
```json
{
  "data": "JOIF_VPN_V1:a1b2c3d4..."
}
```

---

## 💻 Ejemplos de Integración

### 🐘 Ejemplo en PHP (cURL)
Ideal para WordPress, WHMCS, Laravel o sistemas PHP personalizados:

```php
<?php
function crearUsuarioJOIF($vpsIp, $apiKey, $username, $password, $diasValidez, $limiteConexiones = 1, $alias = '') {
    $url = "http://{$vpsIp}:3000/api/users";
    
    // Calcular fecha futura ISO 8601
    $fechaExpiracion = date('Y-m-d\TH:i:s\Z', strtotime("+{$diasValidez} days"));
    
    $payload = json_encode([
        'username' => $username,
        'password' => $password,
        'expiration_date' => $fechaExpiracion,
        'max_connections' => (int)$limiteConexiones,
        'alias' => $alias ?: $username
    ]);

    $ch = curl_init($url);
    curl_setopt($ch, CURLOPT_RETURNTRANSFER, true);
    curl_setopt($ch, CURLOPT_POST, true);
    curl_setopt($ch, CURLOPT_POSTFIELDS, $payload);
    curl_setopt($ch, CURLOPT_HTTPHEADER, [
        "x-api-key: {$apiKey}",
        "Content-Type: application/json"
    ]);
    curl_setopt($ch, CURLOPT_TIMEOUT, 10);

    $response = curl_exec($ch);
    $httpCode = curl_getinfo($ch, CURLINFO_HTTP_CODE);
    curl_close($ch);

    return [
        'status' => $httpCode,
        'data' => json_decode($response, true)
    ];
}

// Ejemplo de uso:
$resultado = crearUsuarioJOIF('144.22.167.150', 'joif2026', 'cliente_vip', 'ClaveSegura2026', 30, 1, 'Carlos M.');
if ($resultado['status'] === 201) {
    echo "Usuario creado con éxito en la VPS!";
} else {
    echo "Error: " . json_encode($resultado['data']);
}
?>
```

---

### 🟨 Ejemplo en JavaScript (Fetch / Axios)
Ideal para Node.js (Bots de Telegram/Discord) o paneles frontend en Vue / React:

```javascript
async function crearUsuario(vpsIp, apiKey, { username, password, hwid, dias = 30, alias }) {
  const url = `http://${vpsIp}:3000/api/users`;
  
  // Calcular fecha de vencimiento
  const fecha = new Date();
  fecha.setDate(fecha.getDate() + dias);

  const body = {
    expiration_date: fecha.toISOString(),
    max_connections: 1,
    alias: alias || username || hwid
  };

  if (hwid) {
    body.hwid = hwid; // Modo HWID (HTTP Custom)
  } else {
    body.username = username;
    body.password = password;
  }

  const res = await fetch(url, {
    method: 'POST',
    headers: {
      'x-api-key': apiKey,
      'Content-Type': 'application/json'
    },
    body: JSON.stringify(body)
  });

  const data = await res.json();
  if (!res.ok) throw new Error(data.error || 'Error al conectar con la VPS');
  return data;
}

// Ejemplo de uso:
// crearUsuario('144.22.167.150', 'joif2026', { username: 'juan2026', password: 'secretpassword', dias: 30 })
//   .then(console.log)
//   .catch(console.error);
```

---

### 🐍 Ejemplo en Python (Requests)
Ideal para scripts de automatización o bots de Telegram basados en Python:

```python
import requests
from datetime import datetime, timedelta

def crear_usuario(vps_ip, api_key, username, password, dias=30, alias=None):
    url = f"http://{vps_ip}:3000/api/users"
    exp_date = (datetime.utcnow() + timedelta(days=dias)).strftime('%Y-%m-%dT%H:%M:%SZ')
    
    headers = {
        "x-api-key": api_key,
        "Content-Type": "application/json"
    }
    
    payload = {
        "username": username,
        "password": password,
        "expiration_date": exp_date,
        "max_connections": 1,
        "alias": alias or username
    }
    
    res = requests.post(url, json=payload, headers=headers, timeout=10)
    return res.status_code, res.json()

# Ejemplo de uso:
# code, resp = crear_usuario('144.22.167.150', 'joif2026', 'pedro1', 'Pass456', 30)
# print(code, resp)
```

---

### 💻 Ejemplo en cURL (Bash)
Pruébalo directamente desde cualquier terminal:

```bash
# Crear usuario estándar
curl -X POST http://144.22.167.150:3000/api/users \
  -H "x-api-key: joif2026" \
  -H "Content-Type: application/json" \
  -d '{
    "username": "usuario_terminal",
    "password": "MiPassword999",
    "expiration_date": "2026-12-31T23:59:59Z",
    "max_connections": 1,
    "alias": "Prueba cURL"
  }'

# Consultar usuarios activos
curl -X GET http://144.22.167.150:3000/api/users \
  -H "x-api-key: joif2026"

# CheckUser de un usuario
curl http://144.22.167.150:3000/check/usuario_terminal
```

---

## 🚦 Códigos de Respuesta HTTP

| Código | Significado | Descripción |
| :---: | :--- | :--- |
| **`200 OK`** | Petición exitosa | La operación de consulta, revocación o borrado se completó. |
| **`201 Created`** | Creado | El usuario ha sido dado de alta tanto en SQLite como en Linux. |
| **`400 Bad Request`** | Datos inválidos | Faltan campos, formato de fecha inválido o nombre fuera de norma. |
| **`401 Unauthorized`** | No autorizado | Falta la cabecera `x-api-key` o el token JWT. |
| **`403 Forbidden`** | Prohibido / Vencido | Clave de API errónea o cuenta de usuario expirada/revocada. |
| **`404 Not Found`** | No encontrado | El usuario solicitado no existe en la base de datos. |
| **`409 Conflict`** | Conflicto | El nombre de usuario o HWID ya está registrado en el sistema. |
| **`500 Server Error`** | Error interno | Error al ejecutar comandos de sistema operativo en Linux. |

---
**JOIF Cloud © 2026 - Documentación de Integración Central**
