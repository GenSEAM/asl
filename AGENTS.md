<!-- ASL_TOOLBELT_START -->
# AgentSlang (ASL) Universal Toolbelt

Agents run workspace operations as ASN forms via `bin/asl '(<form1> <form2> ...)'` (put `bin/` on PATH to type `asl`; `bin/asl -f FILE` and `bin/asl -` read forms from a file or stdin):

- **Introspect Tool Schemas**: `asl '(:tools)'` — the operation catalogue; `asl '(:help :op read)'` explains one op, `asl '(:help :topic language)'` the language.
- **Symbol Search**: `asl '(:query "symbolName")'` — definitions and uses of a name in code; `:in` searches comments, docs, memories and data instead.
- **Targeted Reading**: `asl '(:read :file "path/to/file.ext" :symbol "funcName")'` — one symbol or a bounded slice (`:limit`, `:start`, `:end`) instead of the whole file.
- **Safe Staged Editing**:
  - `asl '(:edit :file "path/to/file.ext" :old "exactOldString" :new "exactNewString")'` — stage a replacement in the session buffer (`.asl/vfs` in the workspace, else `~/.cache/asl/vfs/`), not on the file.
  - `asl '(:diff)'` — show staged changes against disk.
  - `asl '(:flush)'` — write staged changes to disk (temp file, then rename).
  - `asl '(:discard)'` — drop staged changes.
  - `asl '(:txn :owns ("path") <form> ...)'` — stage, gate and flush in one call; every touched file is restored when a nested step fails.
- **Process Supervision**: `asl '(:manage :action <:spawn|:poll|:tail|:kill|:list> :id "taskId" ...)'`; logs go to `/tmp/asl-sessions/<id>.log`.
- **Multi-Lens Code Audit**: `asl '(:lens :file "path" :lenses ("invariants" "architecture"))'` — an ASN report; a lens it cannot evaluate is listed under `:lensesNotEvaluated`.
- **Web Distillation & Research**:
  - `asl '(:crawl :url "https://..." :distill :asn)'` — crawl a page and distill it to ASN.
  - `asl '(:search :query "query" :limit 5)'` — web search.
  - `asl '(:research :topic "topic" :depth :deep)'` — web research through the gateway; `:depth` is `:flash`, `:deep` or `:exhaustive`.
- **Batching**: several forms in one call run in order as one batch: `asl '(:query "foo") (:read :file "bar.asl")'`.

<!-- ASL_TOOLBELT_END -->

# ASL Repository Instructions

> [!CAUTION]
> ### Repository boundary
> **The GitHub repository `GenSEAM/asl` holds only the ASL package.**
> 1. Its root is this directory (grammar, host, packages, prelude, seed, tools, web and the docs beside them).
> 2. It is developed inside a larger local workspace that has no remote. `bin/asl` works in both layouts: from a plain clone, paths are repo-relative (`packages/...`); inside the workspace they are `asl/...`. Build the host first (`CC=$(command -v clang) sh host/build.sh`).
> 3. Never push the workspace or its parent tree to `GenSEAM/asl`.

Design rationale is in [`MANIFESTO.md`](MANIFESTO.md). The rules every agent follows live in `grammar/rules.asn` (goal, refuting question and check for each).

## 1. Core Technical Specifications
- The language rules are the `language` topic of `grammar/tools.asn` (`asl '(:help :topic language)'`), rendered into [`llms.txt`](llms.txt). [`docs/syntaxProjections.md`](docs/syntaxProjections.md) covers short spellings.
- `agentSpecCore.md` is the v0.2 specification written for the concept-validation experiment (`EXPERIMENT.md`); where it differs from the host, the host and the `language` topic win.
- The vocabulary is what the stage-0 host binds: the builtins in `host/src` and the public fns of `prelude/prelude.asl`, listed in `prelude/prelude.asn`. Operations are catalogued in `grammar/tools.asn`.

## 2. Verification
The stage-0 host is the reference. Build it with `sh host/build.sh`, then:

```bash
host/out/asl-host check <file.asl>    # names, arity, enums, known types, effects
host/out/asl-host test <fileTest.asl> # runs runTests; exit 0 and the executed assert count are the evidence
host/out/asl-host run <file.asl>      # calls main
host/out/asl-host eval '<expr>'
```

Through the CLI (`asl help` lists the commands):

```bash
asl check <file>       # delimiter balance, then asl-host check for .asl; bare: every tracked file
asl test <file|dir>    # suites on asl-host; bare: every discovered suite; --changed [BASE] selects by impact
asl run <file.asl>     # load the file and call its main
asl intel <subcmd>     # coupling, deadcode, vacuity, sweep, graph, complexity, stubs, trace, lint, outline, impact, query
asl '(:audit :subcmd coupling)'   # the same audits as a toolbelt receipt
```

`asl gate`, `asl lint`, `asl mem` and `asl tool` are retired and answer ERR_RETIRED. The audits `consistency`, `gates`, `closure`, `foreign`, `steps` and `vitality` run the workspace's `scripts/audit/audit.py`, which is not part of this repository: `(:audit)` answers ERR_WORKSPACE_ONLY for them here. The gate code in `packages/asl-gates` (`auditMain.asl`) also needs the workspace's git root.

## 3. Syntax
The full rules are in the `language` topic; the points agents most often get wrong:
- **A file** is a module header, `(module ws/name :x [exports] :i [(other/module :a alias)])`, then items in column 0. A function header is a bare line, `fn name a: Int64 -> Bool`, with its body indented below.
- **Saved form**: `fn`, `(schema ...)`, `enum`, `mt` (or `match`), `:x`, `:i`, `:a`, `:f`, `:c`. `(df ...)`, `(dfs ...)`, `(defun ...)` and `(defschema ...)` are rejected with ERR_UNSUPPORTED_TOPLEVEL.
- **Types**: `Int64`, `Float64`, `String`, `Bool`, `Unit`, `(List T)`; the host also reads `I64`, `F64`, `Str`.
- **Effects**: a function that does I/O is `fn ! name ...` or ends in `!`; otherwise check fails with ERR_EFFECT_UNMARKED.
- **Docs and comments**: `:d` docstrings are rejected (ERR_READ_DOC) and so are free `;` comments (ERR_READ_COMMENT). A doc is a `(:doc :symbol "path#name" :text "...")` row in the package's `doc.asn`.
- **Positional aliasing**: a short spelling counts only in its position; `(Point :x 1)` is a record with a field named `x`, and a field reads as `p.x`.
- **Control flow**: keep nesting shallow; prefer small helper functions to deep nesting.

## 4. Agent Plane
Exploration, reads, symbol queries, staged edits and checks go through ASN forms (`asl '(:op ...)'`), several forms per call where they are independent. `asl '(:tools)'` is the authoritative catalogue. On 2026-10-14 it listed (`:tools :v 2`): `:tools :help :eval :mem :doc :manage :engine :lens :agent :intel :read :query :edit :write :tree :observe :diff :flush :discard :check :test :fix :txn :audit :crawl :search :research :doctor :note :target :pack`.

```bash
asl '(:query "handleRequest") (:read :file "src/server.asl" :symbol "handleRequest")'
```

`asl -f FILE` runs the forms in FILE, and `asl -` reads them from stdin.

### 4.1 Addressing
Commands and patches address code by path and symbol or content anchor (`:file`, `:symbol`, `:anchor`), never by line number (the `output` rule). `:read` reports the `:start`/`:end` of what it returned.

### 4.2 Process supervision (`:manage`)
- `(:manage :action :spawn :id "<id>" :cmd "<command>")`: starts the process and spools its output to `/tmp/asl-sessions/<id>.log`.
- `(:manage :action :poll :id "<id>")`: state and exit code.
- `(:manage :action :tail :id "<id>" :lines <n>)`: tail of the log.
- `(:manage :action :kill :id "<id>")`: terminates it.
- `(:manage :action :list)`: supervised sessions.

### 4.3 Failure protocol
- **Staging**: edits go `:edit -> :diff -> :flush | :discard`. If an edit is wrong, `(:discard)` drops it without touching disk.
- **Edit failure**: if `:edit` fails, do not retry blindly. Read the symbol with `(:read :file <path> :symbol <name>)` and edit against what is there.

## 5. Packages
- `packages/` holds 66 packages; each has a `manifest.asn` and a `doc.asn`.
- Package code is ASL; the other files under `packages/` are test fixtures and the browser extension's `manifest.json` and `popup.html` (`asl-browser-plugin`). The stage-0 host in `host/src` is C.
- Files in `grammar/` must pass `asl check`.
- ASL examples in documentation are fenced as ` ```asl ` and should pass `host/out/asl-host check`.
