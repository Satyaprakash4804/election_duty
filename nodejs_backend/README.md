# 🗳️ Election Management API — Node.js/Express

Production-ready Node.js/Express backend converted from Flask. Engineered for **1M+ users** and **billions of records**.

---

## 🚀 Tech Stack

| Layer        | Technology                          |
|-------------|-------------------------------------|
| Runtime     | Node.js ≥ 18                        |
| Framework   | Express 4                           |
| Database    | MySQL 8 via `mysql2` (connection pool) |
| Auth        | JWT (`jsonwebtoken`)                |
| Security    | `helmet`, `cors`, `express-rate-limit` |
| Compression | `compression` (gzip)                |
| Logging     | `morgan` + DB system_logs           |
| Firebase    | `firebase-admin` (FCM)              |

---

## ⚡ Quick Start

### 1. Install dependencies
```bash
npm install
```

### 2. Configure environment
```bash
cp .env.example .env
# Edit .env with your DB credentials and secrets
```

### 3. Start the server
```bash
# Production
npm start

# Development (auto-restart)
npm run dev
```

The server will:
- Auto-create the MySQL database if it doesn't exist
- Auto-create all tables
- Seed a `master` account (username: `master`, password: `master`)

> ⚠️ **Change the master password immediately after first login!**

---

## 📂 Project Structure

```
src/
├── server.js          # Entry point — Express app setup
├── config/
│   ├── index.js       # Centralised config (env vars)
│   └── db.js          # MySQL pool, initDb, writeLog, hashPassword
├── middleware/
│   ├── auth.js        # JWT guards: masterRequired, adminRequired, etc.
│   └── errorHandler.js
├── routes/
│   ├── auth.js        # POST /api/login, /api/logout, GET /api/me
│   ├── master.js      # /api/master/…
│   ├── superAdmin.js  # /api/super/…
│   ├── admin.js       # /api/admin/…  (largest — 600+ lines)
│   ├── hierarchy.js   # /api/admin/hierarchy/…
│   ├── staff.js       # /api/staff/…
│   └── fcm.js         # /save-token, /send-notification
└── utils/
    └── pagination.js  # pageParams(), paginated()
```

---

## 🔌 API Endpoints

### Auth
| Method | Path         | Description           |
|--------|--------------|-----------------------|
| POST   | /api/login   | Login (mobile+web)    |
| POST   | /api/logout  | Logout (clears cookie)|
| GET    | /api/me      | Current user info     |

### Master (`/api/master`)
| Method | Path                              | Description             |
|--------|-----------------------------------|-------------------------|
| GET    | /config                           | Get app config          |
| POST   | /config                           | Set config key(s)       |
| DELETE | /config/:key                      | Delete config key       |
| GET    | /super-admins                     | List super admins       |
| POST   | /super-admins                     | Create super admin      |
| PUT    | /super-admins/:id                 | Update super admin      |
| DELETE | /super-admins/:id                 | Delete super admin      |
| PATCH  | /super-admins/:id/status          | Toggle active status    |
| PATCH  | /super-admins/:id/reset-password  | Reset password          |
| GET    | /admins                           | List admins             |
| POST   | /admins                           | Create admin            |
| PUT    | /admins/:id                       | Update admin            |
| DELETE | /admins/:id                       | Delete admin            |
| PATCH  | /admins/:id/status                | Toggle admin status     |
| PATCH  | /admins/:id/reset-password        | Reset admin password    |
| GET    | /overview                         | System overview stats   |
| GET    | /system-stats                     | DB size, uptime, etc.   |
| GET    | /logs                             | System logs             |
| POST   | /db/backup                        | MySQL dump backup       |
| POST   | /db/flush-cache                   | Flush cache             |
| POST   | /migrate                          | Run DB migrations       |
| PATCH  | /change-password                  | Change master password  |
| GET    | /ping                             | Ping                    |

### Super Admin (`/api/super`)
| Method | Path                          | Description          |
|--------|-------------------------------|----------------------|
| GET    | /admins                       | List admins          |
| POST   | /admins                       | Create admin         |
| GET    | /admins/:id                   | Get admin            |
| PUT    | /admins/:id                   | Update admin         |
| DELETE | /admins/:id                   | Delete admin         |
| PATCH  | /admins/:id/toggle            | Toggle active        |
| PATCH  | /admins/:id/reset-password    | Reset password       |
| DELETE | /admins/bulk                  | Bulk delete admins   |
| GET    | /overview                     | Overview stats       |

### Admin (`/api/admin`)
Full CRUD for: super-zones, zones, sectors, gram-panchayats, centers, rooms, staff, duties, booth-rules, auto-assign.

Key endpoints:
- `GET /api/admin/overview`
- `GET /api/admin/staff?q=&assigned=yes|no&rank=SI&page=1&limit=50`
- `POST /api/admin/staff/bulk` — SSE streaming bulk upload
- `POST /api/admin/staff/bulk-assign`
- `POST /api/admin/auto-assign/:centerId`
- `GET /api/admin/duties`
- `GET /api/admin/centers/all`

### Staff (`/api/staff`)
| Method | Path              | Description          |
|--------|-------------------|----------------------|
| GET    | /my-duty          | Get own duty details |
| GET    | /profile          | Get profile          |
| POST   | /change-password  | Change password      |

### Hierarchy (`/api/admin/hierarchy`)
| Method | Path       | Description                  |
|--------|------------|------------------------------|
| GET    | /full      | Full tree (Flutter app)      |
| GET    | /full/h    | Full tree (web frontend)     |
| PATCH  | /update    | Generic update any table     |

### FCM
| Method | Path                 | Description              |
|--------|----------------------|--------------------------|
| POST   | /save-token          | Save FCM device token    |
| GET    | /send-notification   | Send push to all tokens  |

---

## 🔒 Security Features

- **JWT** with `HS256` and configurable expiry
- **HttpOnly cookies** for web platform login
- **Role-based guards**: `masterRequired`, `superAdminRequired`, `adminRequired`, `loginRequired`
- **Helmet** — sets secure HTTP headers
- **Rate limiting** — global (500 req/15min) + login (20 req/min)
- **CORS** — configurable origin whitelist
- **Parameterized queries** — zero SQL injection risk (mysql2 prepared statements)
- **Password hashing** — SHA-256 + server-side salt

---

## 🏗️ Production Deployment

### Environment variables
```
NODE_ENV=production
PORT=5000
DB_HOST=...
DB_PASS=...
JWT_SECRET=<64+ char random string>
CORS_ORIGINS=https://yourdomain.com
```

### Recommended: PM2
```bash
npm install -g pm2
pm2 start src/server.js --name election-api -i max
pm2 save
pm2 startup
```

### Nginx reverse proxy
```nginx
upstream election_api {
    server 127.0.0.1:5000;
}
server {
    listen 443 ssl;
    location /api {
        proxy_pass http://election_api;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
    }
}
```

---

## 🗄️ Database

- All tables auto-created on startup
- Connection pool: 5 min, 50 max (configurable)
- `utf8mb4` charset — full Unicode + emoji support
- Indexed for high-read performance

---

## ⚡ Performance at Scale

- **Connection pooling** — `mysql2` pool with keep-alive
- **Async/await** throughout — non-blocking I/O
- **Parallel queries** via `Promise.all` where independent
- **Paginated endpoints** — default 50, max 200 rows
- **SSE streaming** for bulk upload — no timeout on large batches
- **Gzip compression** — `compression` middleware
- **N+1 eliminated** — batch fetching for hierarchy queries

---

## 🔥 Firebase (Optional)

Place `serviceAccountKey.json` in the project root.  
If the file doesn't exist, `/save-token` and `/send-notification` will return a 503.
