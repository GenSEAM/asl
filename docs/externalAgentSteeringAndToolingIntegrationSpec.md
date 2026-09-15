# Engineering Specification: External Agent Steering & Tooling Integration
**Document ID:** SPEC-2026-EXTERNAL-STEERING-v1.0  
**Classification:** Host Integration Standard & Agent Enforcement Architecture  
**Target Agents:** Claude Code, Antigravity, Cursor, Windsurf, OpenAI Codex, Gemini CLI  
**Target Languages:** Python, TypeScript/JavaScript, PHP, Rust, Go, Aslang  
**Packages:** `packages/bridge`, `packages/gates`, `packages/intel`, `packages/tools`  
**Skills (Prefixed):** `skills/asl-harness`, `skills/asl-intel`, `skills/asl-lens`

---

## 1. The Core Dilemma: Why External Agents Default to Native Tools

Modern AI coding agents (Claude 3.5/3.7 Sonnet, GPT-4o, Gemini 2.5) are heavily fine-tuned via RLHF to invoke their own built-in tools:
* **Claude Code:** `<invoke name="View">`, `<invoke name="Edit">`, `<invoke name="Bash">`, `<invoke name="Grep">`.
* **Cursor / Windsurf:** `view_file`, `str_replace_editor`, `grep_search`.

### Why "Polite Recommendations" Fail:
A system prompt that says: *"Please prefer using `asl intel` over `View`"* has a **<15% compliance rate**. In moments of high uncertainty, the model's token distribution collapses back to its training prior (`View`).

To achieve **>95% tool adherence**, the system combines:
1. **Runtime Interception (PreToolUse Hooks & Pre-conditions).**
2. **Strict Negative Constraints & Token-Tax Framing in Agent Manifests.**
3. **Turn-0 Bootstrap Verification (Self-installing `asl`).**
4. **Polyglot AST & Lockfile Engine (PHP, Python, TS, Rust, Go).**

```
+-------------------------------------------------------------------------------+
|                    EXTERNAL AGENT STEERING HIERARCHY                          |
+-------------------------------------------------------------------------------+
| Layer 1: Turn-0 Bootstrap Gate    | Verifies `asl` binary; prompts install    |
| Layer 2: PreToolUse Runtime Hooks | Intercepts `View`/`Bash` & forces ASL tool|
| Layer 3: Manifest Negative Rules  | CLAUDE.md / AGENTS.md strict prohibitions |
| Layer 4: Polyglot Lockfile Engine | composer.lock, pnpm-lock, poetry.lock RAG |
| Layer 5: Native MCP Exposure      | High-priority semantic tool registration  |
+-------------------------------------------------------------------------------+
```

---

## 2. Layer 1: Turn-0 Bootstrap Guard (Detections & One-Click Install)

When our skill/plugin is loaded in Claude Code (`CLAUDE.md`), Antigravity (`AGENTS.md`), or Cursor (`.cursorrules`), the agent is forced to execute an environment probe before touching any user files.

### 2.1. The Bootstrap Protocol
The manifest injects an immutable initialization requirement:

```markdown
### ⚠️ STEP 0: MANDATORY ENVIRONMENT PROBE (ZERO TURN)
Before executing ANY user request or inspecting ANY files:
1. Execute: `command -v asl || echo "ASL_MISSING"` via terminal.
2. IF output contains `ASL_MISSING`:
   HALT IMMEDIATELY. Do not call View, cat, or grep.
   Emit the following prompt verbatim to the user:

   "⚠️ В проекте активирован Aslang Tooling, но утилита `asl` не найдена в $PATH.
   Без неё агент расходует в 5 раз больше токенов и лишен графовой навигации по коду.
   
   Установить:
     curl -fsSL https://aslang.dev/install.sh | bash
   (Документация и сайт: https://aslang.dev)
   
   Установить утилиту прямо сейчас? [Y/n]"

3. Await explicit user consent. If approved, run `curl -fsSL https://aslang.dev/install.sh | bash`.
```

---

## 3. Layer 2: Runtime Interception (PreToolUse Hooks in Claude Code)

In Claude Code, we don't rely on the model's good will. We configure **PreToolUse hooks** in `.claude/settings.json` (or passed via `--settings`).

```
[ Model attempts to invoke "View" on large file ]
                       │
                       ▼
         ┌───────────────────────────┐
         │ PreToolUse Hook Intercept │
         └─────────────┬─────────────┘
                       │
        ┌──────────────┴──────────────┐
        ▼                             ▼
 [ File <= 50 lines ]         [ File > 50 lines ]
        │                             │
        ▼                             ▼
 [ Allow "View" ]             [ BLOCK CALL WITH EXIT 1 ]
                              "Action Blocked: File has 480 lines.
                               Calling View causes attention rot.
                               MANDATORY: Use `asl intel outline <file>`
                               or `asl intel preload <symbol>`."
```

### 3.1. Hook Configuration Matrix (`.claude/settings.json`)
```json
{
  "hooks": {
    "PreToolUse": [
      {
        "matcher": "View",
        "command": "asl hook-guard view --file \"$TOOL_ARG_path\" --lines \"$TOOL_ARG_limit\""
      },
      {
        "matcher": "Bash",
        "command": "asl hook-guard bash --cmd \"$TOOL_ARG_command\""
      }
    ]
  }
}
```

* **View Guard:** If the agent tries to `View` a file with $>50$ lines without line bounds, `asl hook-guard` rejects the call with an explanatory instruction. The agent is forced to call `asl intel outline`.
* **Bash Grep Guard:** If the agent runs `grep -rn <symbol>`, the hook rejects it: *«Raw grep produces false positives. Use `asl intel callers <symbol>` for true AST resolution»*.

---

## 4. Layer 3: Cognitive Negative Constraints in Manifests

For agents without hook surfaces (Cursor, Windsurf, Codex), compliance is enforced through **asymmetrical negative prompt constraints** in `CLAUDE.md`, `AGENTS.md`, and `.cursorrules`:

```markdown
## STRICT NEGATIVE INVARIANTS (TOKEN TAX & REGRESSION BARRIER)

1. PROHIBITION ON WHOLE-FILE DUMPING:
   - Calling `View`, `cat`, or `read_file` on whole files (>50 lines) is STRICTLY FORBIDDEN.
   - It dilutes your context window and causes catastrophic attention loss.
   - MANDATORY: Use `asl intel outline <file>` to inspect structure in 40 tokens.

2. PROHIBITION ON BLIND CODE MODIFICATIONS:
   - Modifying ANY function without verifying its blast radius is STRICTLY FORBIDDEN.
   - MANDATORY: Run `asl intel impact <symbol>` before editing. Check which downstream modules consume it.

3. PROHIBITION ON API GUESSING:
   - Using methods from external libraries without lockfile verification is STRICTLY FORBIDDEN.
   - MANDATORY: Run `asl deps-resolve <pkg> <symbol>` to fetch exact installed signatures.
```

---

## 5. Layer 4: Polyglot Support Engine (PHP, Python, TS, Rust, Go)

The tooling operates across all major programming languages. It does not require code to be written in AgentScript:

```
┌─────────────────────────────────────────────────────────────────────────┐
│               ASL POLYGLOT PARSER & LOCKFILE MATRIX                     │
├──────────────┬──────────────────┬───────────────────┬───────────────────┤
│ Language     │ AST Extractor    │ Lockfile Source   │ Patch Strategy    │
├──────────────┼──────────────────┼───────────────────┼───────────────────┤
│ **PHP**      │ Tree-Sitter PHP  │ `composer.lock`   │ Brace-matched     │
│              │ (classes, attrs) │ `vendor/autoload` │ AST node replace  │
├──────────────┼──────────────────┼───────────────────┼───────────────────┤
│ **Python**   │ Tree-Sitter Py   │ `poetry.lock`,    │ Indentation-aware │
│              │ (def, class, @)  │ `uv.lock`, reqs   │ AST block replace │
├──────────────┼──────────────────┼───────────────────┼───────────────────┤
│ **TS / JS**  │ Tree-Sitter TS   │ `pnpm-lock.yaml`, │ S-expression /    │
│              │ (.d.ts, interfaces)`package-lock.json`│ JSX AST splice    │
├──────────────┼──────────────────┼───────────────────┼───────────────────┤
│ **Rust**     │ `syn` / Cargo    │ `Cargo.lock`      │ Item-level AST    │
│              │ (traits, impls)  │                   │ substitution      │
├──────────────┼──────────────────┼───────────────────┼───────────────────┤
│ **Go**       │ `go/parser` AST  │ `go.sum`, `go.mod`│ Function boundary │
│              │ (structs, funcs) │                   │ replacement       │
└──────────────┴──────────────────┴───────────────────┴───────────────────┘
```

### 5.1. Deep Dive: PHP Ecosystem Integration
* **`asl intel outline src/Services/OrderProcessor.php`:**
  * Extracts namespaces, classes, methods, visibility (`public`/`private`/`protected`), PHP 8 attributes (`#[Required]`), and PHPDoc types (`@param`, `@return`).
  * Emits an ultra-compact ASN outline (~45 tokens instead of reading an 800-line file).
* **`asl deps-resolve symfony/http-foundation Request`:**
  * Parses `composer.lock`, identifies the exact installed semver (e.g. `v6.4.3`), parses `vendor/symfony/http-foundation/Request.php`, and returns the verified signatures of that version.
  * Completely eliminates hallucinations where Claude Code calls Symfony 5 methods in a Symfony 6 project.
* **`asl test vendor/bin/phpunit`:**
  * Runs tests wrapped inside the **10-second Sliding Idle Watchdog** with `STDIN=/dev/null`, preventing test suites from freezing when mocks request interactive input.

---

## 6. Layer 5: Native Model Context Protocol (MCP) Registration

To make tools first-class citizens in Claude Code, Cursor, and Windsurf, `asl` exposes an in-process MCP server (`asl mcp serve`):

### 6.1. Claude Code Registration (`.mcp.json`)
```json
{
  "mcpServers": {
    "asl": {
      "command": "asl",
      "args": ["mcp", "serve"],
      "env": {
        "ASL_INTEL_MODE": "polyglot"
      }
    }
  }
}
```

### 6.2. Semantic Tool Naming & Description Weighting
To win against built-in tools in the model's tool selection distribution:
* Tool descriptions are explicitly optimized with priority trigger phrases:
  ```json
  {
    "name": "asl_code_outline",
    "description": "HIGH PRIORITY: Always use this tool instead of View or cat when exploring code files. Returns complete symbol outline, classes, and typed signatures in 95% fewer tokens."
  }
  ```

---

## 7. Automated Project Onboarding CLI (`asl init-agent-guard`)

To deploy this enforcement layer into any existing repository with zero friction:

```bash
cd my-project  # Any PHP, Python, TS, or Rust codebase
asl init-agent-guard
```

### What `asl init-agent-guard` Does Automatically:
1. Detects project languages and parses existing lockfiles (`composer.lock`, `pnpm-lock.yaml`, etc.).
2. Creates or patches `.claude/settings.json` with PreToolUse interception hooks.
3. Generates hardened `CLAUDE.md`, `AGENTS.md`, and `.cursorrules` with strict negative invariants.
4. Registers `.mcp.json` for seamless MCP server discovery.
5. Indexes the workspace into an in-memory symbol graph in background.

Any external agent entering the repository is immediately bound by the steering rules, forced to use `asl` tooling, and achieves **up to 80% token reduction and zero version-skew regressions**.
