(module aslSite/app/home
  :x [Stats placeholderStats batchLine installLine homeContent homePage]
  :i [(asl-html/html :a h) (aslSite/app/layout :a l) (aslSite/app/msg :a m) (aslSite/app/mascot :a mascot)])

(schema Stats (:f wasmBytes Int64) (:f aslLines Int64) (:f bridgeLines Int64))

fn placeholderStats -> Stats
  (Stats :wasmBytes 0 :aslLines 0 :bridgeLines 0)

fn batchLine -> String
  "asl '(:tools)'"

fn installLine -> String
  "curl -fsSL https://aslang.dev/install.sh | sh"

fn kb bytes: Int64 -> String
  (str (stringFromInt64 (/ (+ bytes 512) 1024)) " KB")

fn shellLine line: String buttonId: String msg: m/Msg -> h/Node
  (h/div [(h/cls "cmd")] [(h/span [(h/cls "sigil") (h/attr "aria-hidden" "true")] [(h/text "$")]) (h/code [] [(h/text line)]) (l/copyButton buttonId msg)])

fn band tone: String anchor: String index: String label: String title: String lead: String body: (List h/Node) -> h/Node
  (h/section [(h/cls (str "band" tone)) (h/attr "aria-labelledby" anchor)]
    [(h/div [(h/cls "shell sheet")]
      [(h/div [(h/cls "head")]
        [(l/eyebrow index label)
         (h/h2 [(h/cls "h2") (h/id anchor)] [(h/text title)])
         (h/p [(h/cls "lead")] [(h/text lead)])])
       (h/div [(h/cls "body")] body)])])

fn heroSection -> h/Node
  (h/section [(h/cls "hero")]
    [(h/div [(h/cls "shell hero-grid")]
      [(h/figure [(h/cls "hero-art") (h/id "hero-stage")] [(mascot/dock "leon-dock-hero" "Leon · scroll and he climbs to the corner branch")])
       (h/div [(h/cls "stack")]
        [(l/eyebrow "ASL" "AgentSlang · pre-release")
         (h/h1 [(h/cls "display")] [(h/text "AgentSlang: a language shaped for ") (h/em [] [(h/text "the agents that write it.")])])
         (h/p [(h/cls "lead")] [(h/text "AgentSlang (ASL) is a programming language, a data notation and a set of first-party packages for coding agents. Delimiters, arity and symbols are checked before anything runs, lookups return Option and fallible calls return Result, and the asl toolbelt reads and edits a repository by symbol.")])
         (h/div [(h/cls "install")]
          [(shellLine (installLine) "copy-install" (m/copyInstall))
           (h/p [(h/cls "micro")] [(h/text "Preview · not released. The script has not been verified on a clean machine yet: ") (h/a [(h/href "/docs#install")] [(h/text "status in the docs")])])
           (shellLine (batchLine) "copy-batch" (m/copyBatch))
           (h/p [(h/cls "micro")] [(h/text "Once installed, this lists every toolbelt operation.")])])
         (h/ul [(h/cls "toc")]
           [(h/li [] [(h/a [(h/href "/docs")] [(h/text "The language on one page →")])])
            (h/li [] [(h/a [(h/href "#ecosystem")] [(h/text "Ecosystem")])])
            (h/li [] [(h/a [(h/href "/llms.txt")] [(h/text "llms.txt for your agent")])])
            (h/li [] [(h/a [(h/href "https://github.com/GenSEAM/asl")] [(h/text "Source on GitHub")])])])
         (h/ul [(h/cls "facts")]
           [(h/li [] [(h/el "b" [] [(h/text "18 / 30")]) (h/text " tokens for one git status call: positional frame against minified JSON ") (h/a [(h/href "#wire")] [(h/text "(one example)")])])
            (h/li [] [(h/el "b" [] [(h/text "( )")]) (h/text " delimiter balance, arity and symbol resolution checked before the run")])
            (h/li [] [(h/el "b" [] [(h/text "0")]) (h/text " nil or exceptions; overflow and division by zero trap")])])])])])

fn costCell n: String title: String body: String cost: String -> h/Node
  (h/div [(h/cls "cell")] [(h/span [(h/cls "n")] [(h/text n)]) (h/h3 [(h/cls "h3")] [(h/text title)]) (h/p [] [(h/text body)]) (h/span [(h/cls "cost")] [(h/text cost)])])

fn costSection -> h/Node
  (band " sunken" "cost" "01" "Why AgentSlang" "Three places model-written code goes wrong." "Mainstream languages were designed for a person at a keyboard. ASL is built around three kinds of mistake that a checker or a tool can catch before they cost a run."
    [(h/div [(h/cls "grid three")]
      [(costCell "01 · Structure" "Syntax and symbol errors stop before the run" "asl check verifies delimiter balance, arity and symbol resolution before anything executes. A truncated form is rejected with ERR_UNBALANCED, an invented name with ERR_UNKNOWN_SYMBOL." "asl check · ERR_UNBALANCED · ERR_UNKNOWN_SYMBOL")
       (costCell "02 · Semantics" "No nil and no exceptions" "The standard lookups (listHead, listGet, stringSlice, mapGet) return (some v) or (none); fallible builtins return (ok v) or (err e), taken apart with match. Integer overflow and division by zero trap." "Option · Result · match")
       (costCell "03 · Context" "Read by symbol, edit by exact text" "The asl toolbelt returns one definition with its line range instead of a whole file, stages exact replacements in a session buffer outside the working tree, and writes each file atomically on flush." "(:read :symbol) · (:edit) · (:flush)")])])

fn scaleBar tokens: String -> h/Node
  (h/svg [(h/cls "dim") (h/attr "viewBox" "0 0 51 6") (h/attr "preserveAspectRatio" "none") (h/attr "aria-hidden" "true")]
    [(h/path [(h/attr "d" (str "M0 3H" tokens "M0 0V6M" tokens " 0V6"))])])

fn countCell label: String frame: String tokens: String active: Bool -> h/Node
  (h/div [(h/cls (if active "cell active" "cell"))]
    [(h/span [(h/cls "micro")] [(h/text label)])
     (h/div [(h/cls "count")] [(h/text tokens)])
     (scaleBar tokens)
     (h/span [(h/cls "micro")] [(h/text "tokens (cl100k_base), bar to scale")])
     (h/pre [] [(h/code [] [(h/text frame)])])])

fn jsonFrame -> String
  "{\n  \"tool\": \"execute_command\",\n  \"payload\": {\n    \"binary\": \"git\",\n    \"arguments\": [\"status\", \"--short\"],\n    \"working_dir\": \"/app\",\n    \"timeout_ms\": 5000\n  }\n}"

fn jsonMinified -> String
  "{\"tool\":\"execute_command\",\"payload\":{\"binary\":\"git\",\"arguments\":[\"status\",\"--short\"],\"working_dir\":\"/app\",\"timeout_ms\":5000}}"

fn wireSection -> h/Node
  (band "" "wire" "02" "Token cost" "One tool call: 51, 30 or 18 tokens." "The same git status call, counted with cl100k_base. A positional frame does not repeat key names on every call. This is one example, not a benchmark: a positional JSON array of the same fields counts 17 tokens."
    [(h/div [(h/cls "grid three")]
      [(countCell "JSON, pretty-printed" (jsonFrame) "51" false)
       (countCell "JSON, minified" (jsonMinified) "30" false)
       (countCell "Positional frame" "(! cmd \"git\" [\"status\" \"--short\"] \"/app\" 5000)" "18" true)])])

fn ecoStat num: String label: String -> h/Node
  (h/div [(h/cls "eco-stat")] [(h/el "b" [] [(h/text num)]) (h/span [(h/cls "micro")] [(h/text label)])])

fn pkgTag name: String -> h/Node
  (h/span [(h/cls "pkg")] [(h/text name)])

fn ecoCard idx: String title: String desc: String pkgs: (List String) -> h/Node
  (h/div [(h/cls "cell")]
    [(h/span [(h/cls "n")] [(h/text idx)])
     (h/h3 [(h/cls "h3")] [(h/text title)])
     (h/p [] [(h/text desc)])
     (h/div [(h/cls "pkg-tags")] (map pkgTag pkgs))])

fn ecosystemSection -> h/Node
  (band " sunken" "ecosystem" "03" "Language & ecosystem" "One notation for code, data and tool calls." "A small core language with first-party packages for agent loops, memory ledgers, data, web UI and checks. Maturity varies: some packages are a single module."
    [(h/div [(h/cls "eco-stats")]
      [(ecoStat "ASL + ASN" "Code, data and wire notation")
       (ecoStat "Option / Result" "Explicit lookup and failure values")
       (ecoStat "doc.asn" "Docs as queryable rows")
       (ecoStat "69" "First-party packages in the tree")])
     (h/div [(h/cls "grid two")]
      [(ecoCard "Agents & memory" "Loops, code queries and ledgers" "Agent loops, worker coordination, symbol-level call-graph queries and git-tracked ASN memory ledgers." ["asl-agent" "asl-coord" "asl-mem" "asl-know" "asl-intel"])
       (ecoCard "Data & storage" "SQL, Parquet and CSV" "SQL construction for SQLite, Postgres, MySQL and ClickHouse, a Parquet reader and writer, a CSV reader and a content-addressed store." ["asl-sql" "asl-parquet" "asl-csv" "asl-cas"])
       (ecoCard "Web, UI & media" "Typed HTML5, SVG and CSS" "HTML5, SVG and CSS built as typed ASL data and escaped by construction, plus audio and image file processing." ["asl-html" "asl-vdom" "asl-ui" "asl-media"])
       (ecoCard "Network & gateways" "HTTP, model routing and S3" "HTTP client primitives, LLM provider routing, S3 request signing and web extraction." ["asl-gateway" "asl-http" "asl-s3" "asl-crawler"])
       (ecoCard "Language design" "Small, predictable, machine-legible" "Positional enums with match, immutable record updates via with, ! effect marks as a convention, and camelCase builtins." ["enums & match" "records & with" "! marks" "camelCase"])
       (ecoCard "Verification & CLI" "Checks, contracts and process control" "asl check and asl test, contract checks, process helpers and session replay." ["asl-cli" "asl-gates" "asl-contracts" "asl-proc" "asl-replay"])])])

fn step command: String does: String -> h/Node
  (h/li [] [(h/code [] [(h/text command)]) (h/span [] [(h/text does)])])

fn toolbeltSection -> h/Node
  (band "" "toolbelt" "04" "The toolbelt" "One call, several operations, one flush." "Inside a git repository an agent queries symbols, reads exact definitions, stages edits, checks them and writes them, several forms to a call."
    [(h/ol [(h/cls "steps")]
      [(step "asl '(:query :text \"handleRequest\")'" "Find the definitions and uses of a symbol in code, with a count of mentions elsewhere.")
       (step "asl '(:read :file \"src/server.asl\" :symbol \"handleRequest\")'" "Read one function with its line range instead of the whole file.")
       (step "asl '(:edit :file \"src/server.asl\" :old \"…\" :new \"…\")'" "Stage an exact replacement; the receipt says whether the file still parses.")
       (step "asl '(:diff) (:check :file \"src/server.asl\")'" "Inspect the staged change and run the checker in one call.")
       (step "asl '(:flush)'" "Write the staged edits, each file atomically, or (:discard) to drop them.")])])

fn ruleCell title: String body: String sample: String -> h/Node
  (h/div [(h/cls "cell")] [(h/h3 [(h/cls "h3")] [(h/text title)]) (h/p [] [(h/text body)]) (h/code [(h/cls "cost")] [(h/text sample)])])

fn rulesSection -> h/Node
  (band " sunken" "rules" "05" "Under the hood" "Language rules and compile targets." "Each rule removes a class of ambiguity. Checked programs lower to LLVM IR for native code and WebAssembly, and to JavaScript, Python and Go."
    [(h/div [(h/cls "grid two")]
      [(ruleCell "Structure you can count" "Every ( [ and { pairs with its own closing bracket. A truncated form is rejected with ERR_UNBALANCED before anything runs." "ERR_UNBALANCED: unclosed (")
       (ruleCell "Failures are values" "Standard lookups return (some v) or (none) and fallible calls return (ok v) or (err e), unwrapped with match, optionOr or resultOr." "(match (mapGet users id) ((some u) u.name) ((none) \"guest\"))")
       (ruleCell "Docs live as data" "Documentation lives as (:doc :symbol ... :text ...) rows in doc.asn rather than prose comments inside source files." "(:doc :symbol \"app/http#serve\" :text \"...\")")
       (ruleCell "Compile targets" "asl-target-llvm emits native code through clang and wasm32 modules such as this page; the target is still marked partial. asl-target-js emits an ES module with .d.mts types, and the Python and Go targets pass their fixtures." "asl-target-llvm · wasm32 · js · py · go")])])

fn proofCell label: String value: String valueId: String live: Bool -> h/Node
  (h/div [] [(h/span [(h/cls "micro") (h/id (str valueId "-note"))] [(h/text label)]) (h/el "b" [(h/id valueId) (h/cls (if live "live" ""))] [(h/text value)])])

fn proofSection stats: Stats -> h/Node
  (band "" "proof" "06" "This page" "You are reading an ASL program." (str "The markup, styles and event handlers of this site are written in ASL and compiled through asl-target-llvm to a wasm32 module. A JavaScript bridge of " (stringFromInt64 stats.bridgeLines) " lines loads it, forwards clicks and moves Leon.")
    [(h/div [(h/cls "proof")]
      [(proofCell "wasm32 module" (kb stats.wasmBytes) "proof-wasm" false)
       (proofCell "lines of ASL (site and asl-html)" (stringFromInt64 stats.aslLines) "proof-asl" false)
       (proofCell "lines of JS bridge" (stringFromInt64 stats.bridgeLines) "proof-js" false)
       (proofCell "page re-rendered in wasm" "—" "proof-render" true)])
     (h/ul [(h/cls "toc")]
      [(h/li [] [(h/a [(h/href "/docs")] [(h/text "Read the language on one page →")])])
       (h/li [] [(h/a [(h/href "/llms.txt")] [(h/text "Give your agent llms.txt")])])
       (h/li [] [(h/a [(h/href "https://github.com/GenSEAM/asl/tree/main/web")] [(h/text "Read this site's source")])])])])

fn homeContent stats: Stats -> (List h/Node)
  [(heroSection) (costSection) (wireSection) (ecosystemSection) (toolbeltSection) (rulesSection) (proofSection stats)]

fn homePage stats: Stats -> h/Node
  (l/document (l/home) "AgentSlang (ASL): a language and ecosystem for coding agents" "AgentSlang (ASL) is a pre-release programming language, data notation and package set for coding agents: balanced S-expressions, explicit Option and Result values, a symbol-level toolbelt, and native and WebAssembly compilation." (homeContent stats))
