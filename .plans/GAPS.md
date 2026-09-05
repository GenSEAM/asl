# Gap Audit: Multi-Repository Naming & Workspace Mapping

**Verdict**: `APPROVE-WITH-AMENDMENTS`
**Focus**: Repository directory naming alignment (`search` -> `web-search`), submodule mapping integrity, and backward compatibility.

---

## 1. Gap Analysis (Completeness & Edge Cases)

| Target Area | Identified Gap / Risk | Architectural Remedy |
|---|---|---|
| **Directory Ambiguity** | `search/` conflicts semantically with local code search (`asl intel --search`) while declaring `@genseam/asl-web-search` in `manifest.asn`. | Rename directory `search` -> `web-search`. |
| **Path Breakage Risk** | Hardcoded paths in existing developer scripts or editor bookmarks targeting `projects/asex/search`. | Leave a backward-compatible filesystem symlink: `search -> web-search`. |
| **Submodule Mapping Drift** | If directory `search` is renamed without updating root `.gitmodules`, `git submodule status/update` fails. | Update `.gitmodules` entry `path = web-search` alongside the rename. |
| **Sync Tool Desync** | `tools/sync_workspace.py` hardcodes `search` in `REPOS` list. | Update `REPOS` list to `"web-search"`. |
| **Orphaned Local Repos** | `pack/` and `intel/` exist as local Git repos but are not registered in root `.gitmodules`. | Register `pack` and `intel` in root `.gitmodules` for uniform workspace tracking. |

---

## 2. Consistency Analysis (Invariants)

* **Invariant: Package Name <-> Repository Semantic Parity**:
  - `manifest.asn`: `(:package @genseam/asl-web-search ...)`
  - Directory: `web-search/`
  - Eliminates cognitive friction between web search and local code search.
* **Invariant: Effective Decision Mode**:
  - Only rename what has real semantic divergence; do not rename 15 repos for cosmetic reasons.

---

## 3. Anti-Overengineering (Critic Filter)

* **Rejection of Mass Rename (Variant 2)**:
  - Renaming all 15 repositories to add `asl-*` prefix (`asl-mem`, `asl-vdom`, `asl-voice`, etc.) is **REJECTED**:
    1. Causes massive churn across `.gitmodules`, CI configs, and git submodules.
    2. Zero functional or token-saving benefit.
* **Approval of Targeted Rename (Variant 1)**:
  - Only `search` -> `web-search` is changed because it solves an actual semantic conflict.
  - Shortest working diff wins.
