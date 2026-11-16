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
      [(h/figure [(h/cls "hero-art") (h/id "hero-stage")] [(mascot/dock "leon-dock-hero" "Leon · scroll and his tail reels him up to the liana")])
       (h/div [(h/cls "stack")]
        [(l/eyebrow "ASL" "AgentSlang · agent-oriented · pre-release")
         (h/h1 [(h/cls "display")] [(h/text "AgentSlang: an agent-oriented language, shaped for ") (h/em [] [(h/text "the agents that write it.")])])
         (h/p [(h/cls "lead")] [(h/text "You describe what you want and an AI agent writes the code. AgentSlang (ASL) is the language and the toolchain we are building for that code: checked before it runs, inexpensive for an agent to read and change, and compiled for more than one runtime. It is pre-release, and its ecosystem of packages and tools is open.")])
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
           [(h/li [] [(h/el "b" [] [(h/text "MIT / Apache-2.0")]) (h/text " an open ecosystem: no account, no hosted service, nothing to buy")])
            (h/li [] [(h/el "b" [] [(h/text "( )")]) (h/text " structure, names and argument counts are checked before the run")])
            (h/li [] [(h/el "b" [] [(h/text "native + wasm")]) (h/text " one source compiles through LLVM to native code and WebAssembly")])])])])])

fn costCell n: String title: String body: String cost: String -> h/Node
  (h/div [(h/cls "cell")] [(h/span [(h/cls "n")] [(h/text n)]) (h/h3 [(h/cls "h3")] [(h/text title)]) (h/p [] [(h/text body)]) (h/span [(h/cls "cost")] [(h/text cost)])])

fn goalsSection -> h/Node
  (band " sunken" "goals" "01" "Goals" "What we are building, and where each goal stands." "Six goals, in the order we work on them. Each is marked with what works today, what is partial and what is only planned, so you can check us against the repository."
    [(h/div [(h/cls "grid three")]
      [(costCell "01 · Safe" "Mistakes stop before they run" "No nil and no exceptions: a missing value or a failure is an ordinary value the program has to handle. Unbalanced brackets, unknown names and wrong argument counts are rejected by the checker, and integer overflow or division by zero stops the program." "Works today")
       (costCell "02 · Frugal" "Less model work per change" "The asl toolbelt hands an agent one function instead of a whole file, applies exact edits and reports whether the file still parses. How much model usage this saves is not measured yet: the experiment is written down and has not been run." "Tools work · saving not measured")
       (costCell "03 · Many runtimes" "One language, several runtimes" "The same source compiles through LLVM to native code and to WebAssembly, which is how this page runs. A JavaScript target is experimental; the Python and Go targets are prototypes." "Native and wasm work · others early")
       (costCell "04 · Compiled" "A compiler written in its own language" "The ASL compiler is written in ASL and compiles itself through LLVM. It is verified on macOS; Linux seeds exist and are not verified yet, Windows is not started. We publish no speed comparison with other languages yet." "Partial · no benchmarks yet")
       (costCell "05 · Web and systems" "From a browser tab to a native tool" "The site you are reading is an ASL program compiled to WebAssembly. Native programs have files, processes and network access. Calling libraries written in other languages is planned." "Partial · foreign calls planned")
       (costCell "06 · Small footprint" "With the standard library or without it" "The WebAssembly build carries its own allocator and garbage collector and asks its host for four functions. Freestanding and embedded targets are planned." "Planned")])])

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

fn jsonPositional -> String
  "[\"cmd\",\"git\",[\"status\",\"--short\"],\"/app\",5000]"

fn wireSection -> h/Node
  (band "" "wire" "02" "Honest numbers" "One tool call, counted four ways." "The same git status call in four encodings, counted with cl100k_base. Most of the saving comes from dropping whitespace and repeated key names, which JSON can do as well: the like-for-like comparison is a positional JSON array, and it counts 17 tokens against our 18. For program code ASL currently costs more tokens than typed Python: about 1.8 times in our own comparison of nine modules (o200k_base; the Python versions were not run against the tests)."
    [(h/div [(h/cls "grid two")]
      [(countCell "JSON, pretty-printed" (jsonFrame) "51" false)
       (countCell "JSON, minified" (jsonMinified) "30" false)
       (countCell "JSON, positional array" (jsonPositional) "17" false)
       (countCell "ASL positional frame" "(! cmd \"git\" [\"status\" \"--short\"] \"/app\" 5000)" "18" true)])])

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
  (band " sunken" "ecosystem" "03" "Language & ecosystem" "One notation for code, data and tool calls." "A small core language with first-party packages for agent loops, memory, data, web UI and checks, all in one public repository. Maturity varies: some packages are a single module."
    [(h/div [(h/cls "eco-stats")]
      [(ecoStat "69" "First-party packages in the tree")
       (ecoStat "1" "Notation for code, data and tool calls")
       (ecoStat "MIT / Apache-2.0" "Dual licence")
       (ecoStat "0" "Accounts, servers or fees")])
     (h/div [(h/cls "grid two")]
      [(ecoCard "Agents & memory" "Loops, code queries and ledgers" "Agent loops, worker coordination, symbol-level call-graph queries and git-tracked ASN memory ledgers." ["asl-agent" "asl-coord" "asl-mem" "asl-know" "asl-intel"])
       (ecoCard "Data & storage" "SQL, Parquet and CSV" "SQL construction for SQLite, Postgres, MySQL and ClickHouse, a Parquet reader and writer, a CSV reader and a content-addressed store." ["asl-sql" "asl-parquet" "asl-csv" "asl-cas"])
       (ecoCard "Web, UI & media" "Typed HTML5, SVG and CSS" "HTML5, SVG and CSS built as typed ASL data and escaped by construction, plus audio and image file processing." ["asl-html" "asl-vdom" "asl-ui" "asl-media"])
       (ecoCard "Network & gateways" "HTTP, model routing and S3" "HTTP client primitives, LLM provider routing, S3 request signing and web extraction." ["asl-gateway" "asl-http" "asl-s3" "asl-crawler"])
       (ecoCard "Compile targets" "Native, WebAssembly and early ports" "asl-target-llvm emits native code and wasm32 modules. The JavaScript target is experimental; the Python and Go targets are prototypes." ["asl-target-llvm" "asl-target-js" "asl-target-py" "asl-target-go"])
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

fn communitySection -> h/Node
  (band " sunken" "community" "05" "Open ecosystem" "A project and a community, not a product." "There is no company service behind this page. The compiler, the packages, the tools and this site form an open ecosystem in one public repository under MIT or Apache-2.0, and the work is planned in the open."
    [(h/div [(h/cls "grid two")]
      [(costCell "01 · Read" "Start with one page" "The language fits on one page, and llms.txt gives the same to your agent." "/docs · /llms.txt")
       (costCell "02 · Try" "Run it and tell us what broke" "This is a pre-release: there are no binaries and a clean clone does not build yet. A report of what failed on your machine is the most useful contribution right now." "github.com/GenSEAM/asl")
       (costCell "03 · Build" "Pick a package or a target" "69 first-party packages at different levels of maturity, and targets that need work: Linux verification, the JavaScript target, calls into other languages." "ROADMAP.md")
       (costCell "04 · Measure" "Help us check our own claims" "The experiment that compares ASL with Python and TypeScript on the same tasks is specified and has not been run. If it fails, we will say so and change course." "EXPERIMENT.md")])])

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
  [(heroSection) (goalsSection) (wireSection) (ecosystemSection) (toolbeltSection) (communitySection) (proofSection stats)]

fn homePage stats: Stats -> h/Node
  (l/document (l/home) "AgentSlang (ASL): an agent-oriented language and an open ecosystem" "AgentSlang (ASL) is a pre-release, agent-oriented programming language with an open ecosystem of tools and packages for code written by AI agents: checked before it runs, a toolbelt that reads and edits by symbol, and compilation through LLVM to native code and WebAssembly." (homeContent stats))
