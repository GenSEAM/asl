import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const webDir = process.argv[2] ? path.resolve(process.argv[2]) : path.resolve(__dirname, '..');

console.log(`=== [ASL Web Codegen] Compiling ASL models in ${webDir} ===`);

// 1. Read and parse packages.asl
const pkgContent = fs.readFileSync(path.join(webDir, 'asl-src/api/packages.asl'), 'utf8');
const pkgRegex = /\(:name\s+"([^"]+)"\s+:version\s+"([^"]+)"\s+:repo\s+"([^"]+)"\s+:desc\s+"([^"]+)"\)/g;
const packages = [...pkgContent.matchAll(pkgRegex)].map(m => ({
  name: m[1],
  version: m[2],
  repo: m[3],
  desc: m[4]
}));

// 2. Read and parse plugins.asl
const plgContent = fs.readFileSync(path.join(webDir, 'asl-src/api/plugins.asl'), 'utf8');
const plgRegex = /\(:name\s+"([^"]+)"\s+:repo\s+"([^"]+)"\s+:capability\s+"([^"]+)"\s+:description\s+"([^"]+)"\s+:author\s+"([^"]+)"\s+:stars\s+(\d+)\s+:version\s+"([^"]+)"\)/g;
const plugins = [...plgContent.matchAll(plgRegex)].map(m => ({
  name: m[1],
  repo: m[2],
  capability: m[3],
  description: m[4],
  author: m[5],
  stars: parseInt(m[6], 10),
  version: m[7]
}));

// 3. Read and parse skills.asl
const sklContent = fs.readFileSync(path.join(webDir, 'asl-src/api/skills.asl'), 'utf8');
const sklRegex = /\(:id\s+"([^"]+)"\s+:name\s+"([^"]+)"\s+:category\s+"([^"]+)"\s+:description\s+"([^"]+)"\s+:token_cost\s+(\d+)\s+:platforms\s+\[([^\]]+)\]\s+:verified\s+(true|false)\)/g;
const skills = [...sklContent.matchAll(sklRegex)].map(m => ({
  id: m[1],
  name: m[2],
  category: m[3],
  description: m[4],
  token_cost: parseInt(m[5], 10),
  platforms: [...m[6].matchAll(/"([^"]+)"/g)].map(p => p[1]),
  verified: m[7] === 'true'
}));

// 4. Read and parse version.asl
const verContent = fs.readFileSync(path.join(webDir, 'asl-src/api/version.asl'), 'utf8');
const versionData = {
  version: verContent.match(/:version\s+"([^"]+)"/)[1],
  name: verContent.match(/:name\s+"([^"]+)"/)[1],
  channel: verContent.match(/:channel\s+"([^"]+)"/)[1],
  published_at: verContent.match(/:published_at\s+"([^"]+)"/)[1],
  min_cli_version: verContent.match(/:min_cli_version\s+"([^"]+)"/)[1],
  download_urls: {
    darwin_arm64: verContent.match(/:darwin_arm64\s+"([^"]+)"/)[1],
    darwin_x64: verContent.match(/:darwin_x64\s+"([^"]+)"/)[1],
    linux_x64: verContent.match(/:linux_x64\s+"([^"]+)"/)[1],
    linux_arm64: verContent.match(/:linux_arm64\s+"([^"]+)"/)[1]
  },
  release_notes: verContent.match(/:release_notes\s+"([^"]+)"/)[1]
};

// 5. Read and parse installer.asl
const instContent = fs.readFileSync(path.join(webDir, 'asl-src/scripts/installer.asl'), 'utf8');
const installerConfig = {
  cli_name: instContent.match(/:cli_name\s+"([^"]+)"/)[1],
  repo_url: instContent.match(/:repo_url\s+"([^"]+)"/)[1],
  install_dir: instContent.match(/:install_dir\s+"([^"]+)"/)[1],
  clone_dir: instContent.match(/:clone_dir\s+"([^"]+)"/)[1],
  binary_rel: instContent.match(/:binary_rel\s+"([^"]+)"/)[1],
  bin_links: [...instContent.match(/:bin_links\s+\[([^\]]+)\]/)[1].matchAll(/"([^"]+)"/g)].map(m => m[1])
};

// Ensure target directories exist
fs.mkdirSync(path.join(webDir, 'functions/api'), { recursive: true });
fs.mkdirSync(path.join(webDir, 'public/api'), { recursive: true });

// Target 1: functions/api/packages.ts
const packagesTs = `/* GENERATED FROM AGENTSCRIPT (ASL). DO NOT EDIT MANUALLY. */
export async function onRequestGet(context: any) {
  const packages = ${JSON.stringify(packages, null, 2)};

  return new Response(JSON.stringify({ total: packages.length, packages }, null, 2), {
    headers: {
      "Content-Type": "application/json",
      "Access-Control-Allow-Origin": "*",
      "Cache-Control": "public, max-age=60, s-maxage=300"
    }
  });
}
`;
fs.writeFileSync(path.join(webDir, 'functions/api/packages.ts'), packagesTs);

// Target 2: functions/api/plugins.ts
const pluginsTs = `/* GENERATED FROM AGENTSCRIPT (ASL). DO NOT EDIT MANUALLY. */
export async function onRequestGet(context: any) {
  const url = new URL(context.request.url);
  const query = (url.searchParams.get("q") || "").toLowerCase();

  const plugins = ${JSON.stringify(plugins, null, 2)};

  const filtered = query
    ? plugins.filter((p: any) => p.name.toLowerCase().includes(query) || p.description.toLowerCase().includes(query) || p.capability.toLowerCase().includes(query))
    : plugins;

  return new Response(JSON.stringify({ total: filtered.length, plugins: filtered }, null, 2), {
    headers: {
      "Content-Type": "application/json",
      "Access-Control-Allow-Origin": "*",
      "Cache-Control": "public, max-age=60, s-maxage=300"
    }
  });
}
`;
fs.writeFileSync(path.join(webDir, 'functions/api/plugins.ts'), pluginsTs);

// Target 3: functions/api/skills.ts
const skillsTs = `/* GENERATED FROM AGENTSCRIPT (ASL). DO NOT EDIT MANUALLY. */
export async function onRequestGet(context: any) {
  const url = new URL(context.request.url);
  const query = (url.searchParams.get("q") || "").toLowerCase();

  const skills = ${JSON.stringify(skills, null, 2)};

  const filtered = query
    ? skills.filter((s: any) => s.name.toLowerCase().includes(query) || s.description.toLowerCase().includes(query) || s.category.toLowerCase().includes(query))
    : skills;

  return new Response(JSON.stringify({ total: filtered.length, skills: filtered }, null, 2), {
    headers: {
      "Content-Type": "application/json",
      "Access-Control-Allow-Origin": "*",
      "Cache-Control": "public, max-age=60, s-maxage=300"
    }
  });
}
`;
fs.writeFileSync(path.join(webDir, 'functions/api/skills.ts'), skillsTs);

// Target 4: functions/api/version.ts
const versionTs = `/* GENERATED FROM AGENTSCRIPT (ASL). DO NOT EDIT MANUALLY. */
export async function onRequestGet(context: any) {
  const versionData = ${JSON.stringify(versionData, null, 2)};

  return new Response(JSON.stringify(versionData, null, 2), {
    headers: {
      "Content-Type": "application/json",
      "Access-Control-Allow-Origin": "*",
      "Cache-Control": "public, max-age=60, s-maxage=300"
    }
  });
}
`;
fs.writeFileSync(path.join(webDir, 'functions/api/version.ts'), versionTs);

// Target 5 & 6: public/version.json & public/api/version.json (RFC 8259 strict JSON)
const versionJson = JSON.stringify(versionData, null, 2) + '\n';
fs.writeFileSync(path.join(webDir, 'public/version.json'), versionJson);
fs.writeFileSync(path.join(webDir, 'public/api/version.json'), versionJson);

// Target 7: public/install.sh (POSIX Bash, set -e)
const symlinkCommands = installerConfig.bin_links
  .map(link => `ln -sf "\${CLONE_DIR}/${installerConfig.binary_rel}" "\${INSTALL_DIR}/${link}"`)
  .join('\n');

const installSh = `#!/bin/bash
# GENERATED FROM AGENTSCRIPT (ASL). DO NOT EDIT MANUALLY.
set -e

echo "🚀 Installing ASL (AgentScript Language) CLI..."
INSTALL_DIR="${installerConfig.install_dir}"
mkdir -p "\${INSTALL_DIR}"

REPO_URL="${installerConfig.repo_url}"
CLONE_DIR="${installerConfig.clone_dir}"

if [ -d "\${CLONE_DIR}" ]; then
  echo "📦 Updating existing ASL repository..."
  git -C "\${CLONE_DIR}" pull --ff-only
else
  echo "📦 Cloning ASL repository..."
  git clone "\${REPO_URL}" "\${CLONE_DIR}"
fi

${symlinkCommands}

echo "✓ ASL successfully installed to \${INSTALL_DIR}/${installerConfig.cli_name}"
echo ""
echo "👉 Add ASL to your PATH:"
echo '   export PATH="'${installerConfig.install_dir}':\${PATH}"'
echo ""
echo "⚡ Try running: ${installerConfig.cli_name} --version"
`;
fs.writeFileSync(path.join(webDir, 'public/install.sh'), installSh);
fs.chmodSync(path.join(webDir, 'public/install.sh'), 0o755);

console.log(`✓ Successfully compiled 4 Cloudflare Functions, 2 JSON endpoints, and 1 Bash installer from ASL models.`);
