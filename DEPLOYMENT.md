# Full Stack Deployment Guide

This guide explains how to deploy your Subscription Tracker application with:

- **Frontend**: GitHub Pages (static files)
- **Backend**: Vercel (Node.js API)

---

## Part 1: Deploy Backend to Vercel

### Prerequisites

- Vercel account (free at https://vercel.com)
- GitHub account with your repository pushed

### Steps

1. **Go to Vercel Dashboard**
   - Visit https://vercel.com/dashboard
   - Click "New Project"
   - Import your GitHub repository

2. **Configure Project Settings**
   - Framework: "Other" (since it's Express.js)
   - Root Directory: `./backend`

3. **Set Environment Variables**
   - In Vercel dashboard, go to Settings → Environment Variables
   - Add the following variables:
     ```
     DB_HOST = your_database_host
     DB_PORT = 3306
     DB_USER = your_database_user
     DB_PASSWORD = your_database_password
     DB_NAME = subscription_tracker
     JWT_SECRET = generate_a_random_strong_secret
     JWT_EXPIRES_IN = 7d
     CLIENT_URL = https://yourusername.github.io/subscriptions-system
     ```

4. **Deploy**
   - Click "Deploy"
   - Wait for deployment to complete
   - You'll get a URL like: `https://your-project-name.vercel.app`
   - Test it: Visit `https://your-project-name.vercel.app/` - you should see the API info

---

## Part 2: Configure GitHub Pages for Frontend

### Steps

1. **In GitHub Repository Settings**
   - Go to Settings → Pages
   - Source: Deploy from a branch
   - Branch: `main`, folder: `/frontend`
   - Click Save

2. **Update Frontend API URL**
   - Replace `localhost:5000` with your Vercel URL
   - See Part 3 below

3. **Wait for deployment**
   - GitHub will build and deploy your frontend
   - Site will be available at: `https://yourusername.github.io/subscriptions-system/`

---

## Part 3: Update Frontend to Use Vercel Backend

Edit `frontend/js/app.js`:

```javascript
// BEFORE (local development only)
const API_BASE = "http://localhost:5000/api";

// AFTER (for production)
const API_BASE = "https://your-vercel-project-name.vercel.app/api";
```

Replace `your-vercel-project-name` with your actual Vercel project name.

### For Environment-Aware Configuration (Optional)

```javascript
const isProduction = !window.location.hostname.includes("localhost");
const API_BASE = isProduction
  ? "https://your-vercel-project-name.vercel.app/api"
  : "http://localhost:5000/api";
```

---

## Part 4: Database Setup

Your backend needs access to a MySQL database. Options:

### Option A: Cloud Database (Recommended for Production)

- **AWS RDS**: Managed MySQL hosting
- **PlanetScale**: MySQL-compatible serverless database (free tier)
- **ClearDB**: Add-on available through Vercel

Update your Vercel environment variables with the cloud database credentials.

### Option B: Local Database (Development Only)

- Keep your local MySQL running
- Use your local machine's IP address as `DB_HOST`
- Make sure your database is accessible from the internet (not recommended for production)

---

## Complete Deployment Checklist

- [ ] Backend repository pushed to GitHub
- [ ] `backend/vercel.json` created
- [ ] Vercel project created and connected
- [ ] All environment variables set in Vercel
- [ ] Database accessible from Vercel
- [ ] Backend deployed successfully (test the API URL)
- [ ] GitHub Pages enabled in repository
- [ ] Frontend folder selected in GitHub Pages settings
- [ ] `frontend/js/app.js` updated with Vercel backend URL
- [ ] Frontend deployed successfully (visit your GitHub Pages URL)

---

## Troubleshooting

### Frontend getting 404

- Verify GitHub Pages is set to serve from `/frontend`
- Clear browser cache (Ctrl+Shift+Delete)
- Wait a few minutes for GitHub to redeploy

### Frontend can't connect to backend

- Check that `API_BASE` in app.js has the correct Vercel URL
- Check browser console (F12) for error messages
- Verify CORS is enabled in backend (should be in `server.js`)
- Test backend directly: Visit your Vercel URL in browser

### Backend errors on Vercel

- Check Vercel deployment logs in dashboard
- Verify all environment variables are set
- Confirm database is accessible from Vercel IP
- Check that JWT_SECRET is set

---

## Local Development Setup

To test locally before deploying:

1. **Start Backend**

   ```bash
   cd backend
   npm install
   npm run dev
   ```

2. **Frontend API Configuration** (keep as localhost)

   ```javascript
   const API_BASE = "http://localhost:5000/api";
   ```

3. **Open Frontend**
   - Open `frontend/index.html` in your browser
   - Or use Live Server extension in VS Code

---

## Production Notes

- Never commit `.env` to GitHub (already in .gitignore)
- Use strong, unique JWT_SECRET in production
- Enable HTTPS (Vercel does this automatically)
- Monitor backend usage on Vercel dashboard
- Set up backup for your database
