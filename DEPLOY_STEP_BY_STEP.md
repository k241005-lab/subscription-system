# Step-by-Step Deployment Guide

Follow these steps in order. Each section should take 5-10 minutes.

---

## Step 1: Set Up Free Cloud Database (PlanetScale) - 10 min

PlanetScale is MySQL-compatible and has a generous free tier.

### 1.1 Create PlanetScale Account

- Go to https://planetscale.com
- Sign up (free)
- Verify your email

### 1.2 Create a Database

1. Click "Create a new database"
2. Database name: `subscription_tracker`
3. Region: Choose closest to you
4. Click "Create database"

### 1.3 Get Connection String

1. Click on your database
2. Click "Connect"
3. Select "Node.js" from dropdown
4. Copy the connection string - looks like:
   ```
   mysql://user:password@aws.connect.psdb.cloud/subscription_tracker?sslaccept=strict
   ```

### 1.4 Run Your Schema

1. Download MySQL Workbench or use PlanetScale web console
2. Run the SQL files in order:
   - `database/01_schema.sql`
   - `database/02_sample_data.sql`
   - `database/03_triggers.sql`
   - `database/04_stored_procedures.sql`

Now you have: **DB credentials ready** ✅

---

## Step 2: Deploy Backend to Vercel - 5 min

### 2.1 Create Vercel Account

- Go to https://vercel.com
- Sign up with GitHub (use "Continue with GitHub")
- Authorize GitHub access

### 2.2 Add Your Repository

1. Click "New Project"
2. Find and click your `subscription-system` repository
3. Click "Import"

### 2.3 Configure Project

1. **Framework Preset**: Select "Other" (it's Express.js)
2. **Root Directory**: Click "Edit" and select `./backend`
3. Click "Continue"

### 2.4 Add Environment Variables

On the "Environment Variables" page, add:

```
DB_HOST = extract from PlanetScale connection string
DB_PORT = 3306
DB_USER = extract from PlanetScale connection string
DB_PASSWORD = extract from PlanetScale connection string
DB_NAME = subscription_tracker
JWT_SECRET = (generate random: use https://generate-random.org or any random string)
JWT_EXPIRES_IN = 7d
CLIENT_URL = https://yourusername.github.io/subscriptions-system
```

**How to extract from PlanetScale connection string:**

```
mysql://user:password@aws.connect.psdb.cloud/subscription_tracker?sslaccept=strict
         ^^^^  ^^^^^^^^        ^^^^^^^^^^^^^^^^^^^                    ^^^^^^^^^^^^^^^
         USER  PASSWORD        DB_HOST                                DB_NAME
```

### 2.5 Deploy

1. Click "Deploy"
2. Wait for deployment (2-3 minutes)
3. When done, you'll see "Congratulations"
4. **Copy your Vercel URL** - you'll need it next!
   Example: `https://subscription-system-iota.vercel.app`

Now you have: **Backend deployed** ✅

---

## Step 3: Update Frontend with Backend URL - 2 min

### 3.1 Edit app.js

1. Open `frontend/js/app.js` in VS Code
2. Find this line (around line 6):
   ```javascript
   const API_BASE = "https://YOUR-VERCEL-URL.vercel.app/api";
   ```
3. Replace `YOUR-VERCEL-URL` with your actual Vercel URL from Step 2.4

   Example:

   ```javascript
   const API_BASE = "https://subscription-system-iota.vercel.app/api";
   ```

### 3.2 Save & Push

```bash
git add frontend/js/app.js
git commit -m "Update backend URL for production"
git push
```

Now you have: **Frontend updated** ✅

---

## Step 4: Enable GitHub Pages for Frontend - 2 min

### 4.1 Go to Repository Settings

1. On GitHub, go to your repository
2. Click "Settings" (top right)
3. Click "Pages" in left menu

### 4.2 Configure Pages

1. Under "Source", select "Deploy from a branch"
2. Branch: `main`
3. Folder: `/frontend` ← Important!
4. Click "Save"

### 4.3 Wait for Deployment

- GitHub will now deploy your frontend
- You'll see "Your site is live at: https://yourusername.github.io/subscriptions-system/"
- Takes 1-2 minutes

Now you have: **Frontend deployed** ✅

---

## Step 5: Test Everything

### 5.1 Test Backend API

Visit your Vercel URL in a browser:

```
https://your-vercel-url.vercel.app/
```

You should see:

```json
{
  "message": "🚀 Subscription Tracker API is running",
  "version": "1.0.0",
  "endpoints": "..."
}
```

If you see an error, check:

- Environment variables in Vercel (Settings → Environment Variables)
- Database is accessible (PlanetScale connection test)

### 5.2 Test Frontend

Visit your GitHub Pages URL:

```
https://yourusername.github.io/subscriptions-system/
```

You should see your login page.

### 5.3 Test Login (optional)

Try logging in with sample credentials from your database.

---

## Troubleshooting

### Backend shows 502 Bad Gateway on Vercel

- Check environment variables are all set correctly
- Check database connection string is correct
- Check logs: Vercel dashboard → your project → Deployments → latest → Logs

### Frontend shows 404

- Wait 1-2 more minutes for GitHub Pages to build
- Clear browser cache (Ctrl+Shift+Delete)
- Check GitHub Pages settings are correct (Settings → Pages)

### Frontend can't connect to backend

- Check that `API_BASE` in `frontend/js/app.js` is correct
- Open browser console (F12) and check for error messages
- Make sure the Vercel URL doesn't have a trailing slash

### Can't create account/login

- Check database was populated with `02_sample_data.sql`
- Check backend logs on Vercel dashboard

---

## Summary

✅ Database: PlanetScale (MySQL)
✅ Backend: Deployed to Vercel
✅ Frontend: Deployed to GitHub Pages
✅ Connected: Frontend talks to Vercel backend

Your app is live! 🎉
