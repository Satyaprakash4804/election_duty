# Election Duty Management System — Web Frontend

Production-ready Vite + React + Tailwind web frontend for the UP Police Election Cell duty management system. Matches the Flutter mobile app theme exactly.

---

## 🎨 Theme
- **Background:** `#FDF6E3` (warm parchment)
- **Primary:** `#8B6914` (dark gold)
- **Accent:** `#B8860B` / Border: `#D4A843`
- **Dark:** `#4A3000` (deep brown — sidebar, headers)
- **Font:** Tiro Devanagari Hindi (supports Hindi script)

---

## 🚀 Quick Start

### 1. Install dependencies
```bash
npm install
```

### 2. Configure backend URL
Edit `.env`:
```
VITE_API_URL=http://your-server-ip:5000/api
```

### 3. Development
```bash
npm run dev
# Opens at http://localhost:3000
```

### 4. Production build
```bash
npm run build
# Output in /dist — deploy to nginx/apache/any static host
```

---

## 🔐 Role-Based Access

| Role | Route | Access |
|------|-------|--------|
| `MASTER` | `/master` | Super admins, admins, system logs, stats |
| `SUPER_ADMIN` | `/super` | Admin accounts, form data, overview |
| `ADMIN` | `/admin` | Staff, structure, duties, booths, dashboard |
| `STAFF` | `/staff` | Own duty card, co-staff, password change |

Login uses **HttpOnly cookie** (web platform) — the backend sets `platform: 'web'` cookie mode automatically.

---

## 📁 Project Structure

```
src/
├── api/
│   ├── client.js          # Axios instance + interceptors
│   └── endpoints.js       # All API functions (auth, admin, super, master, staff)
├── store/
│   └── authStore.js       # Zustand auth state (persisted)
├── components/
│   ├── common/
│   │   ├── index.jsx      # StatCard, Modal, Shimmer, Badge, Pagination…
│   │   └── ProtectedRoute.jsx
│   └── layout/
│       └── AppShell.jsx   # Sidebar (desktop) + bottom nav (mobile)
├── pages/
│   ├── LoginPage.jsx
│   ├── admin/             # Dashboard, Staff, Structure, Duties, Booths
│   ├── super/             # Overview, Admins, FormData
│   ├── master/            # Overview, SuperAdmins, Admins, Logs
│   └── staff/             # Dashboard, CoStaff, DutyCard, Password
├── utils/
│   └── helpers.js         # Ranks, UP districts, formatters
└── index.css              # Global theme styles
```

---

## 🌐 Nginx Deployment (SPA)

```nginx
server {
  listen 80;
  server_name your-domain.com;
  root /var/www/election-frontend/dist;
  index index.html;

  location / {
    try_files $uri $uri/ /index.html;
  }

  location /api {
    proxy_pass http://localhost:5000;
    proxy_set_header Host $host;
    proxy_set_header X-Real-IP $remote_addr;
  }
}
```

---

## 🔧 Environment Variables

| Variable | Default | Description |
|----------|---------|-------------|
| `VITE_API_URL` | `http://localhost:5000/api` | Backend API base URL |

---

## 🛠 Tech Stack

- **Vite 8** — lightning-fast dev server & build
- **React 19** — UI framework
- **React Router v6** — client-side routing
- **Tailwind CSS 3** — utility-first styling
- **Zustand** — lightweight auth state (persisted)
- **Axios** — HTTP client with JWT interceptors
- **Lucide React** — icon set
- **React Hot Toast** — notifications

---

UP Police Election Cell © 2026
