# ASL Web Showcase Deployment Guide

The ASL Showcase website is a **100% static, zero-backend, client-side WebAssembly application**. It can be deployed to any static edge provider in under 60 seconds.

---

## 1. Deploy to Cloudflare Pages (Recommended ⭐)

Cloudflare Pages provides global Anycast CDN edge delivery, automatic SSL, and instant Wasm execution.

### Option A: Via Cloudflare Dashboard (Automatic Git Deploys)
1. Push your repository to GitHub or GitLab.
2. Open [Cloudflare Dashboard](https://dash.cloudflare.com/) ➔ **Workers & Pages** ➔ **Create Application** ➔ **Pages** ➔ **Connect to Git**.
3. Set the build settings:
   * **Framework preset:** `Vite`
   * **Build command:** `npm --prefix web run build` (or `npm run build:web`)
   * **Build output directory:** `web/dist`
   * **Node.js Version:** `20`
4. Click **Save and Deploy**.

### Option B: Via Wrangler CLI (1-Click Instant Deploy)
```bash
# 1. Build the static bundle
npm run build:web

# 2. Deploy directly to Cloudflare Pages
npx wrangler pages deploy web/dist --project-name asl-showcase
```

---

## 2. Deploy to GitLab Pages

The repository already includes a preconfigured [`.gitlab-ci.yml`](../.gitlab-ci.yml).

1. Push your repository to GitLab.
2. GitLab CI will automatically execute the `pages` pipeline:
   * Installs dependencies (`npm ci && npm --prefix web ci`)
   * Builds the site (`npm run build:web`)
   * Copies `web/dist` to `public/`
3. Your site will be live at `https://<username>.gitlab.io/<project-name>`.

---

## 3. Deploy to GitHub Pages

The repository includes a ready-to-run GitHub Actions workflow in [`.github/workflows/deploy.yml`](../.github/workflows/deploy.yml).

1. Push your repository to GitHub.
2. In your GitHub repo settings ➔ **Settings** ➔ **Pages**:
   * Set **Source** to **GitHub Actions**.
3. Push to `main` — GitHub Actions will automatically build and deploy `web/dist` globally.
