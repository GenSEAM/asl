#!/usr/bin/env node
/**
 * AgentScript (ASL) Multi-Agent Skills & Global Toolbelt Installer
 * Generated/Transpiled runtime artifact from pure AgentScript module: pack/src/installer.asl
 * 
 * Capabilities:
 * - Discovers all native ASL skills (asl-toolbelt, asl-mem, asl-intel, asl-codec, asl-native, etc.)
 * - Detects installed agent harnesses (Claude Code, Cursor, Windsurf, Antigravity, Factory Droid)
 * - Interactively prompts user with default "Yes" to install all skills and global directives
 * - Injects idempotent ASL Toolbelt directives into global agent instruction files:
 *   - Claude Code: ~/.claude/CLAUDE.md
 *   - Cursor: ~/.cursorrules & ~/.cursor/rules/asl-toolbelt.mdc
 *   - Windsurf: ~/.codeium/windsurf/memories/global_rules.md
 *   - Antigravity CLI: ~/.gemini/config/rules/asl-toolbelt.md & ~/.gemini/config/skills/
 *   - Factory Droid: ~/.factory/AGENTS.md
 *   - Local Workspace: ./AGENTS.md & ./.cursorrules & ./.agents/skills/
 */

import fs from 'node:fs';
import path from 'node:path';
import os from 'node:os';
import readline from 'node:readline/promises';

const WORKSPACE_ROOT = process.cwd();
const HOME = os.homedir();

const TOOLBELT_DIRECTIVE = `<!-- ASL_TOOLBELT_START -->
/asl-toolbelt
<!-- ASL_TOOLBELT_END -->`;

const SLASH_COMMANDS = [
  {
    name: 'asl.md',
    content: `---
description: Activate AgentScript (ASL) and GenSEAM toolchain
---

# /asl: Activate Native ASL Toolchain

Use the native AgentScript (\`asl\`) toolchain for all code exploration, text search, editing, and verification:
- **Batch RPC**: Execute through \`asl rpc '(:batch ...)'\` in a single roundtrip.
- **Polyglot Languages**: Use AST outlines \`(:out "file")\`, symbol search \`(:sym "sym")\`, callers \`(:callers "sym")\`, and impact \`(:impact "sym")\` across AgentScript (.asl), TypeScript/JS (.ts, .js), Python (.py), Go (.go), Rust (.rs), PHP (.php).
- **Text & Semantic Search**: Use \`(:find "pattern")\` for fast in-memory grep and \`(:q "query")\` for vector semantic search.
- **In-Memory Modifications**: Use \`(:edit "file" "old" "new")\`, \`(:repl ...)\`, review with \`(:diff)\`, commit with \`(:flush)\`.
- **Verification**: Run \`(:chk)\` or \`asl gate\` (all 7 gates), \`asl check\`, \`asl lint\`, \`asl audit\`, \`asl test\`.
`
  },
  {
    name: 'asl-build.md',
    content: `---
description: Activate ASL build, polyglot tooling, and verification mode (/asl build)
---

# /asl build: Activate ASL Native Build & Toolbelt Mode

Full activation of the native AgentScript (ASL) and GenSEAM toolchain:

## 1. Mandatory Batch RPC (\`asl rpc\`)
All code exploration, reading, text search, editing, diffing, and verification MUST run through \`asl rpc '(:batch ...)'\`:
\`\`\`bash
asl rpc '(:batch
  (:out "src/server.ts")              ; AST outline (ASL, TS, JS, Python, Go, Rust, PHP)
  (:sym "handleRequest")              ; Exact symbol definition & declaration line
  (:callers "handleRequest")          ; Call graph: all callers across workspace
  (:impact "handleRequest")           ; Blast-radius impact analysis before edits
  (:find "authHeader")                ; Fast in-memory text grep across codebase
  (:q "token validation")             ; In-memory vector semantic query
  (:read "src/server.ts" 1 40)        ; Read narrow slice of lines
  (:sec "doc.md" "Section Title")     ; Read isolated markdown section
  (:edit "src/server.ts" "old" "new") ; In-memory atomic string replacement
  (:repl "old_pat" "new_pat")         ; Mass in-memory refactor across files
  (:diff)                             ; Review staged in-memory modifications
  (:flush)                            ; Atomically persist staged edits to disk
  (:chk)                              ; Run full 7-gate verification suite
)'
\`\`\`

## 2. Polyglot Language Support
Supported source extensions: \`.asl\`, \`.asn\`, \`.ts\`, \`.tsx\`, \`.js\`, \`.jsx\`, \`.py\`, \`.go\`, \`.rs\`, \`.php\`, \`.md\`.
- Never call whole-file View/cat on files exceeding 50 lines. Use \`(:out ...)\` or \`asl intel outline <file>\` first.
- Always check callers and impact radius before changing functions or interfaces.

## 3. Fast Text & Vector Search
- Exact pattern grep: \`(:find "pattern")\` (in-memory, <50ms, zero disk thrashing).
- Semantic vector query: \`(:q "semantic query")\` or \`asl mem query "<query>"\`.

## 4. Build, Compilation & Verification
- Compile: \`asl build <file.asl> --target <wasm|rust|ts|py>\`
- Verify syntax & balance: \`asl check <file>\`
- AST quality & token lint: \`asl lint <file>\`
- 3-tier audit: \`asl audit <file>\` (Micro AST, Meso keywords, Macro module)
- Native tests: \`asl test [file]\`
- Full 7 gates: \`asl gate\` or \`asl rpc '(:batch (:chk))'\`
`
  }
];

const SOURCE_SKILLS_DIRS = [
  path.join(WORKSPACE_ROOT, '.agents', 'skills'),
  path.join(HOME, '.gemini', 'config', 'skills'),
  path.join(WORKSPACE_ROOT, 'asl', 'skills')
];

function getSourceSkills() {
  const skills = new Map();
  for (const dir of SOURCE_SKILLS_DIRS) {
    if (fs.existsSync(dir)) {
      try {
        const entries = fs.readdirSync(dir, { withFileTypes: true });
        for (const entry of entries) {
          if (entry.isDirectory() || entry.isSymbolicLink()) {
            const skillPath = path.join(dir, entry.name);
            const mdPath = path.join(skillPath, 'SKILL.md');
            if (fs.existsSync(mdPath)) {
              skills.set(entry.name, skillPath);
            }
          }
        }
      } catch {}
    }
  }
  return skills;
}

function injectDirective(filePath, directive) {
  let content = '';
  if (fs.existsSync(filePath)) {
    try {
      content = fs.readFileSync(filePath, 'utf8');
    } catch {
      content = '';
    }
  }

  // Sanitize any legacy tokensave section
  if (content.toLowerCase().includes('tokensave')) {
    content = content.replace(/##\s+tokensave[\s\S]*?(?=\n##|\n<!--|$)/gi, '');
  }

  const startMarker = '<!-- ASL_TOOLBELT_START -->';
  const endMarker = '<!-- ASL_TOOLBELT_END -->';

  if (content.includes(startMarker) && content.includes(endMarker)) {
    const regex = new RegExp(`${startMarker}[\\s\\S]*?${endMarker}`, 'g');
    content = content.replace(regex, directive);
  } else {
    content = content.trim() ? `${content}\n\n${directive}\n` : `${directive}\n`;
  }

  const dir = path.dirname(filePath);
  if (!fs.existsSync(dir)) {
    fs.mkdirSync(dir, { recursive: true });
  }
  fs.writeFileSync(filePath, content, 'utf8');
}

function copyDirectory(src, dest) {
  try {
    const st = fs.lstatSync(dest);
    if (st.isSymbolicLink()) {
      fs.unlinkSync(dest);
    }
  } catch {}
  if (!fs.existsSync(dest)) {
    fs.mkdirSync(dest, { recursive: true });
  }
  const entries = fs.readdirSync(src, { withFileTypes: true });
  for (const entry of entries) {
    if (entry.isSocket() || entry.isFIFO()) continue;
    const srcPath = path.join(src, entry.name);
    const destPath = path.join(dest, entry.name);
    if (entry.isDirectory()) {
      copyDirectory(srcPath, destPath);
    } else {
      try {
        try {
          if (fs.lstatSync(destPath).isSymbolicLink()) {
            fs.unlinkSync(destPath);
          }
        } catch {}
        fs.copyFileSync(srcPath, destPath);
      } catch {}
    }
  }
}

export function detectAgents() {
  const agents = [
    {
      id: 'claude',
      name: 'Claude Code',
      skillsDirs: [path.join(HOME, '.claude', 'skills')],
      rulesFiles: [path.join(HOME, '.claude', 'CLAUDE.md')],
      commandsDirs: [path.join(HOME, '.claude', 'commands')],
      detected: fs.existsSync(path.join(HOME, '.claude'))
    },
    {
      id: 'cursor',
      name: 'Cursor',
      skillsDirs: [path.join(HOME, '.cursor', 'skills')],
      rulesFiles: [
        path.join(HOME, '.cursorrules'),
        path.join(HOME, '.cursor', 'rules', 'asl-toolbelt.mdc')
      ],
      detected: fs.existsSync(path.join(HOME, '.cursor')) || fs.existsSync(path.join(HOME, '.cursorrules'))
    },
    {
      id: 'windsurf',
      name: 'Windsurf',
      skillsDirs: [path.join(HOME, '.codeium', 'windsurf', 'skills')],
      rulesFiles: [path.join(HOME, '.codeium', 'windsurf', 'memories', 'global_rules.md')],
      detected: fs.existsSync(path.join(HOME, '.codeium', 'windsurf'))
    },
    {
      id: 'antigravity',
      name: 'Antigravity / Gemini',
      skillsDirs: [
        path.join(HOME, '.gemini', 'config', 'skills'),
        path.join(HOME, '.gemini', 'skills')
      ],
      rulesFiles: [
        path.join(HOME, '.gemini', 'config', 'AGENTS.md'),
        path.join(HOME, '.gemini', 'AGENTS.md'),
        path.join(HOME, '.gemini', 'config', 'rules', 'asl-toolbelt.md')
      ],
      detected: fs.existsSync(path.join(HOME, '.gemini'))
    },
    {
      id: 'factory',
      name: 'Factory Droid',
      skillsDirs: [path.join(HOME, '.factory', 'skills')],
      rulesFiles: [path.join(HOME, '.factory', 'AGENTS.md')],
      detected: fs.existsSync(path.join(HOME, '.factory'))
    },
    {
      id: 'agents',
      name: 'Universal Agents Standard (~/.agents)',
      skillsDirs: [path.join(HOME, '.agents', 'skills')],
      rulesFiles: [path.join(HOME, '.agents', 'rules', 'asl-toolbelt.md')],
      detected: fs.existsSync(path.join(HOME, '.agents'))
    },
    {
      id: 'codex',
      name: 'Codex / OpenAI',
      skillsDirs: [path.join(HOME, '.codex', 'skills')],
      rulesFiles: [path.join(HOME, '.codex', 'AGENTS.md')],
      detected: fs.existsSync(path.join(HOME, '.codex'))
    }
  ];
  return agents;
}

export function installSkills(options = {}) {
  const isGlobal = options.global !== false;
  const force = options.force || false;
  const selectedAgents = options.agents || 'all';
  const injectInstructions = options.injectInstructions !== false; // default true

  const sourceSkills = getSourceSkills();
  console.log(`--> Discovered ${sourceSkills.size} native skills: ${Array.from(sourceSkills.keys()).join(', ')}`);

  const results = {
    installedAgents: [],
    updatedFiles: [],
    skipped: []
  };

  // 1. Local Workspace Installation
  const localSkillsDir = path.join(WORKSPACE_ROOT, '.agents', 'skills');
  try {
    if (!fs.existsSync(localSkillsDir)) {
      fs.mkdirSync(localSkillsDir, { recursive: true });
    }
    for (const [name, srcPath] of sourceSkills.entries()) {
      const dest = path.join(localSkillsDir, name);
      if (!fs.existsSync(dest) || force) {
        if (fs.existsSync(dest) && fs.lstatSync(dest).isSymbolicLink()) {
          fs.unlinkSync(dest);
        }
        copyDirectory(srcPath, dest);
      }
    }
  } catch (err) {
    results.skipped.push(`${localSkillsDir}: ${err.message}`);
  }

  // Inject into local workspace rules if instructions enabled
  if (injectInstructions) {
    const localTargets = [
      path.join(WORKSPACE_ROOT, 'AGENTS.md'),
      path.join(WORKSPACE_ROOT, '.cursorrules')
    ];

    for (const t of localTargets) {
      try {
        injectDirective(t, TOOLBELT_DIRECTIVE);
        results.updatedFiles.push(path.relative(WORKSPACE_ROOT, t));
      } catch (err) {
        results.skipped.push(`${t} (${err.message})`);
      }
    }
  }

  // 2. Global Agent Targets
  if (isGlobal) {
    const allAgents = detectAgents();

    for (const agent of allAgents) {
      if (selectedAgents !== 'all' && !selectedAgents.includes(agent.id)) {
        continue;
      }

      let agentUpdated = false;

      // Copy skills if agent supports skills folder(s)
      const targetSkillDirs = agent.skillsDirs || (agent.skillsDir ? [agent.skillsDir] : []);
      for (const sDir of targetSkillDirs) {
        try {
          if (!fs.existsSync(sDir)) fs.mkdirSync(sDir, { recursive: true });
          for (const [name, srcPath] of sourceSkills.entries()) {
            const dest = path.join(sDir, name);
            if (!fs.existsSync(dest) || force) {
              if (fs.existsSync(dest) && fs.lstatSync(dest).isSymbolicLink()) {
                fs.unlinkSync(dest);
              }
              copyDirectory(srcPath, dest);
            }
          }
          agentUpdated = true;
        } catch (err) {
          results.skipped.push(`${sDir}: ${err.message}`);
        }
      }

      // Inject global instructions / rules
      if (injectInstructions) {
        const targetRuleFiles = agent.rulesFiles || (agent.rulesFile ? [agent.rulesFile] : []);
        if (agent.rulesMdc && !targetRuleFiles.includes(agent.rulesMdc)) {
          targetRuleFiles.push(agent.rulesMdc);
        }

        for (const rFile of targetRuleFiles) {
          try {
            injectDirective(rFile, TOOLBELT_DIRECTIVE);
            results.updatedFiles.push(rFile.replace(HOME, '~'));
            agentUpdated = true;
          } catch (err) {
            results.skipped.push(`${rFile.replace(HOME, '~')}: ${err.message}`);
          }
        }
      }

      // Install slash commands if agent supports custom commands
      if (agent.commandsDirs) {
        for (const cDir of agent.commandsDirs) {
          try {
            if (!fs.existsSync(cDir)) fs.mkdirSync(cDir, { recursive: true });
            for (const cmd of SLASH_COMMANDS) {
              const cmdFile = path.join(cDir, cmd.name);
              fs.writeFileSync(cmdFile, cmd.content, 'utf8');
              results.updatedFiles.push(cmdFile.replace(HOME, '~'));
            }
            agentUpdated = true;
          } catch (err) {
            results.skipped.push(`${cDir}: ${err.message}`);
          }
        }
      }

      if (agentUpdated) {
        results.installedAgents.push(agent.name);
      }
    }
  }

  return results;
}

// --- CLI Execution ---
async function main() {
  const args = process.argv.slice(2);
  const isNoGlobal = args.includes('--no-global') || args.includes('--local');
  const isForce = args.includes('--force');
  const isYes = args.includes('-y') || args.includes('--yes') || args.includes('--all');
  let agentFilter = args.find(a => a.startsWith('--agents='))?.split('=')[1] || 'all';
  let injectInstructions = true;

  console.log("================================================================================");
  console.log("          AgentScript (ASL) Multi-Agent Toolbelt & Skills Setup                 ");
  console.log("================================================================================");

  const detected = detectAgents();
  const found = detected.filter(a => a.detected);
  console.log(`Detected agent environments on this system:`);
  for (const a of detected) {
    console.log(`  [${a.detected ? '✓' : ' '}] ${a.name} (${a.id})`);
  }

  // Interactive prompts if running in interactive terminal and not passed --yes
  if (process.stdin.isTTY && !isYes) {
    const rl = readline.createInterface({
      input: process.stdin,
      output: process.stdout
    });

    try {
      const qAll = await rl.question(`\nInstall skills for all available agents by default? [Y/n]: `);
      if (qAll.trim().toLowerCase() === 'n' || qAll.trim().toLowerCase() === 'no') {
        const qSelect = await rl.question(`Enter comma-separated agent IDs [${detected.map(a => a.id).join(',')}]: `);
        if (qSelect.trim()) {
          agentFilter = qSelect.trim().split(',').map(s => s.trim());
        }
      }

      const qInstr = await rl.question(`Inject ASL Toolbelt directives into global instructions (CLAUDE.md, .cursorrules, etc.)? [Y/n]: `);
      if (qInstr.trim().toLowerCase() === 'n' || qInstr.trim().toLowerCase() === 'no') {
        injectInstructions = false;
      }
    } finally {
      rl.close();
    }
  } else {
    console.log(`\nMode: Automatic setup (all available agents enabled, global instructions enabled).`);
  }

  const res = installSkills({
    global: !isNoGlobal,
    force: isForce,
    agents: agentFilter,
    injectInstructions: injectInstructions
  });

  if (res.updatedFiles.length > 0) {
    console.log(`\n✓ Injected toolbelt directives into instructions:`);
    for (const f of res.updatedFiles) {
      console.log(`  - ${f}`);
    }
  }

  if (res.installedAgents.length > 0) {
    console.log(`\n✓ Configured global toolbelt for agents:`);
    for (const a of res.installedAgents) {
      console.log(`  - ${a}`);
    }
  }

  if (res.skipped.length > 0) {
    console.log(`\nNotice (restricted by sandbox or non-existent paths):`);
    for (const s of res.skipped) {
      console.log(`  • ${s}`);
    }
    console.log(`  To install globally with full user permissions outside sandbox, execute:\n    npx @genseam/asl-skills\n  or:\n    asl skill install --global`);
  }

  console.log("\n✓ [asl-skills] Setup complete. Native toolbelt is registered.");
}

if (process.argv[1] && path.resolve(process.argv[1]) === path.resolve(import.meta.filename || '')) {
  main().catch(err => {
    console.error('Installer error:', err);
    process.exit(1);
  });
}
