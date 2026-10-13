# ASL Web Showcase Deployment Guide

The ASL Showcase website is a static site built by Vite (`web/package.json`: `vite build`) into `web/dist`, with no backend. Any static host can serve it.

---

## 1. Deploy to Cloudflare Pages (Recommended ⭐)

Cloudflare Pages serves static files from its CDN with automatic TLS.

### Option A: Via Cloudflare Dashboard (Automatic Git Deploys)
1. Push your repository to GitHub or GitLab.
2. Open [Cloudflare Dashboard](https://dash.cloudflare.com/) ➔ **Workers & Pages** ➔ **Create Application** ➔ **Pages** ➔ **Connect to Git**.
3. Set the build settings:
   * **Framework preset:** `Vite`
   * **Build command:** `npm --prefix web run build` (or `npm run build:web`)
   * **Build output directory:** `web/dist`
   * **Node.js Version:** `20`
4. Click **Save and Deploy**.

### Option B: Via Wrangler CLI
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

## 3. GitHub Pages

No GitHub Actions workflow is included (`asl/.github/` does not exist). To publish there, add a workflow that runs `npm ci && npm --prefix web ci && npm run build:web` and uploads `web/dist`.
