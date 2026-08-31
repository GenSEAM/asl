"""Project scaffolder for AgentScript projects (`agentscript init`)."""

import json
from pathlib import Path

DEFAULT_SKILL = """---
name: asl
description: ASL (AgentScript Language) developer instructions, syntax cheat sheet, and toolchain rules.
---

# ASL (AgentScript Language) Project Guide

This project is built with **ASL (AgentScript Language)** — the deterministic S-expression language for WebAssembly & host target ecosystems.

## Core Rules for AI Agents
1. Every file is a module starting with `(module name/path :doc "..." :export [...] :import [...])`.
2. All identifiers, function names, and module names use kebab-case (`user-id`, `parse-int`).
3. Fixed-width numeric types: `Int32`, `Int64`, `Float64`.
4. `match` is exhaustive; `if` requires both then/else; `cond` requires `:else`.
5. Host side-effects require the `!` marker: `(defun ! main [(args (List String))] -> (Result Unit IoError) ...)`.

## Key Commands
- Check semantics: `asl check src/main.agentscript`
- Build multi-target: `asl build`
- Hot-reload watch: `asl watch`
- Quick reference: `asl ref`
"""


def scaffold_project(target_dir: Path, template: str = "cli", embed_skill: bool = True) -> dict:
    """Create a complete new AgentScript project with AGENTS.md, CLAUDE.md, and starter code."""
    target_dir.mkdir(parents=True, exist_ok=True)
    raw_name = target_dir.name.replace("_", "-").lower()
    project_name = "".join(c for c in raw_name if c.isalnum() or c == "-") or "app"

    created_files: list[str] = []

    # 1. asl.json
    manifest = {
        "name": project_name,
        "version": "0.1.0",
        "description": f"{project_name} built with ASL (AgentScript Language)",
        "template": template,
        "entry": "src/main.agentscript",
        "watch": ["src/", "asl.json"],
        "targets": {
            "wasm": {"output": "dist/main.wasm"},
            "ts": {"output": "dist/main.ts"},
            "py": {"output": "dist/main.py"}
        }
    }
    manifest_path = target_dir / "asl.json"
    manifest_path.write_text(json.dumps(manifest, indent=2) + "\n")
    created_files.append(str(manifest_path))

    # 2. src/main.agentscript
    src_dir = target_dir / "src"
    src_dir.mkdir(exist_ok=True)
    main_code = f"""(module {project_name}/main
  :doc "Main application entrypoint"
  :export [Config greet calculate main]
  :import [(core/strings :as s)])

(defschema Config
  (:field name String "Project name")
  (:field debug Bool "Debug mode flag"))

(defun greet [(cfg Config)] -> String
  :doc "Construct a greeting message"
  (s/concat "Hello from AgentScript: " (.-name cfg)))

(defun calculate [(x Int64) (y Int64)] -> Int64
  :doc "Safe arithmetic computation"
  (+ (* x x) (* y y)))

(defun ! main [(args (List String))] -> (Result Unit IoError)
  :doc "Effectful entrypoint"
  (let [(cfg (Config :name "{project_name}" :debug false))]
    (println (greet cfg))
    (println (s/concat "Calculated value: " (string-from-int64 (calculate 3 4))))
    (ok ())))
"""
    main_path = src_dir / "main.agentscript"
    main_path.write_text(main_code)
    created_files.append(str(main_path))

    # 3. tests/test_main.agentscript
    tests_dir = target_dir / "tests"
    tests_dir.mkdir(exist_ok=True)
    test_code = f"""; Test fixture for {project_name}
; run: [calculate(3, 4), greet((Config :name "test" :debug false))] == [25, "Hello from AgentScript: test"]

(module {project_name}/test
  :doc "Test suite"
  :export [run-tests]
  :import [({project_name}/main :as app)])

(defun run-tests [] -> Bool
  (= (app/calculate 3 4) 25))
"""
    test_path = tests_dir / "test_main.agentscript"
    test_path.write_text(test_code)
    created_files.append(str(test_path))

    # 4. AGENTS.md
    agents_md = f"""# Agent Instructions for {project_name}

This project is written in **AgentScript** (an S-expression language designed for autonomous AI agents and WebAssembly execution).

## Developer Protocol for AI Agents
1. **Never guess syntax**: Consult `.skills/agentscript/SKILL.md` or `agentscript tokens` if in doubt.
2. **Deterministic S-Expressions**: S-expression tail expressions are the return value. Every branch in `match`, `if`, and `cond` must be exhaustive.
3. **Verification Before Commit**:
   ```bash
   agentscript check src/main.agentscript
   agentscript build src/main.agentscript --target wasm
   agentscript fmt src/
   ```

## Targets & Toolchain
- **WebAssembly**: `agentscript build src/main.agentscript --target wasm -o dist/main.wasm`
- **TypeScript**: `agentscript build src/main.agentscript --target ts`
- **Rust**: `agentscript build src/main.agentscript --target rs`
- **Go**: `agentscript build src/main.agentscript --target go`
- **Python**: `agentscript build src/main.agentscript --target py`
"""
    agents_path = target_dir / "AGENTS.md"
    agents_path.write_text(agents_md)
    created_files.append(str(agents_path))

    # 5. CLAUDE.md (Points to AGENTS.md)
    claude_md = """# Claude Code Instructions

Read `AGENTS.md` first for all project conventions, type rules, build targets, and verification commands.
ASL (AgentScript Language) rules and cheat sheet are available in `.skills/asl/SKILL.md` or via `asl ref`.

Always run `asl check` and `asl build` before finalizing any changes.
"""
    claude_path = target_dir / "CLAUDE.md"
    claude_path.write_text(claude_md)
    created_files.append(str(claude_path))

    # 6. .skills/asl/SKILL.md (if enabled)
    if embed_skill:
        skill_dir = target_dir / ".skills" / "asl"
        skill_dir.mkdir(parents=True, exist_ok=True)
        skill_path = skill_dir / "SKILL.md"
        skill_path.write_text(DEFAULT_SKILL)
        created_files.append(str(skill_path))

        # Backward compatibility alias
        legacy_dir = target_dir / ".skills" / "agentscript"
        legacy_dir.mkdir(parents=True, exist_ok=True)
        (legacy_dir / "SKILL.md").write_text(DEFAULT_SKILL)
        created_files.append(str(legacy_dir / "SKILL.md"))

    return {
        "status": "success",
        "project": project_name,
        "directory": str(target_dir.resolve()),
        "created_files": created_files
    }
