# Quick Start: Deploy to Production

## 30-Second Overview

1. **Backend** → Deployed on Vercel
2. **Frontend** → Deployed on GitHub Pages
3. **Database** → Cloud MySQL (PlanetScale, AWS RDS, etc.)

---

## Quick Steps

### 1. Deploy Backend to Vercel (5 minutes)

```bash
# Vercel will automatically detect backend/server.js
# Go to https://vercel.com → New Project → Select this repo
# Root Directory: ./backend
# Add environment variables (see DEPLOYMENT.md)
# Done! You'll get a Vercel URL
```

### 2. Update Frontend with Backend URL (1 minute)

Edit `frontend/js/app.js`:

```javascript
const API_BASE = "https://YOUR-VERCEL-URL.vercel.app/api";
```

### 3. Enable GitHub Pages (1 minute)

- Go to Repository Settings → Pages
- Source: Deploy from branch → `main`
- Folder: `/frontend`
- Save

### 4. Test

- Frontend: `https://yourusername.github.io/subscriptions-system/`
- Backend: `https://your-vercel-url.vercel.app/`

---

## Full Details

See [DEPLOYMENT.md](./DEPLOYMENT.md) for complete setup instructions.
