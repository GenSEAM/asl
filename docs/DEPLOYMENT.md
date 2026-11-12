# Deploying aslang.dev

The site is an ASL program in `web/site`. `asl run asl/web/tools/build.asl` writes a static site into `web/dist`:
every page prerendered to HTML by `web/tools/build.asl` on the stage-0 host, `site.css` generated
from `web/site/app/theme.asl`, and `site.wasm` compiled from the same modules through
`asl-target-llvm`. There is no backend and no Node build step; any static host can serve
`web/dist`.

## Requirements

- The `asl` launcher; `asl run asl/web/tools/build.asl` runs from the checkout root (the directory that contains `asl/`).
- `llc` and `wasm-ld` from LLVM 18 or newer (Debian/Ubuntu: `clang llvm lld`; macOS: Homebrew
  `llvm lld`). `LLC` and `WASM_LD` override the lookup.

```sh
asl run asl/web/tools/build.asl                      # -> web/dist
npx --yes serve web/dist -l 4173     # preview
```

## 1. Cloudflare Pages

`wrangler.toml` already points `pages_build_output_dir` at `web/dist`.

- **Build command:** `asl run asl/web/tools/build.asl`
- **Build output directory:** `web/dist`

The Cloudflare build image must provide clang, `llc` and `wasm-ld`. If it does not, build in CI and
upload the output instead:

```sh
asl run asl/web/tools/build.asl
npx wrangler pages deploy web/dist --project-name asl
```

`web/public/_redirects` sends the retired routes (`/roadmap`, `/ecosystem`, `/playground`, …) to
`/`; unknown paths get `404.html`. `_headers` serves `*.wasm` as `application/wasm`.

## 2. GitHub Pages

No workflow is included. One that installs `clang llvm lld`, runs `asl run asl/web/tools/build.asl` and uploads
`web/dist` is enough.
