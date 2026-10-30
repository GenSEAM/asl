# Deploying aslang.dev

The site is an ASL program in `web/site`. `sh web/build.sh` writes a static site into `web/dist`:
every page prerendered to HTML by `web/tools/build.asl` on the stage-0 host, `site.css` generated
from `web/site/app/theme.asl`, and `site.wasm` compiled from the same modules through
`asl-target-llvm`. There is no backend and no Node build step; any static host can serve
`web/dist`.

## Requirements

- A C compiler for the stage-0 host (`clang` is preferred: `web/build.sh` builds `host/out/asl-host`
  with it when the host is missing).
- `llc` and `wasm-ld` from LLVM 18 or newer (Debian/Ubuntu: `clang llvm lld`; macOS: Homebrew
  `llvm lld`). `LLC` and `WASM_LD` override the lookup.

```sh
sh web/build.sh                      # -> web/dist
npx --yes serve web/dist -l 4173     # preview
```

## 1. Cloudflare Pages

`wrangler.toml` already points `pages_build_output_dir` at `web/dist`.

- **Build command:** `sh web/build.sh`
- **Build output directory:** `web/dist`

The Cloudflare build image must provide clang, `llc` and `wasm-ld`. If it does not, build in CI and
upload the output instead:

```sh
sh web/build.sh
npx wrangler pages deploy web/dist --project-name asl
```

`web/public/_redirects` sends the retired routes (`/roadmap`, `/ecosystem`, `/playground`, …) to
`/`; unknown paths get `404.html`. `_headers` serves `*.wasm` as `application/wasm`.

## 2. GitHub Pages

No workflow is included. One that installs `clang llvm lld`, runs `sh web/build.sh` and uploads
`web/dist` is enough.
