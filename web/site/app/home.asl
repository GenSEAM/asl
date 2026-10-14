(module aslSite/app/home
  :x [Stats placeholderStats installLine batchLine homeContent homePage]
  :i [(aslSite/ui/html :a h) (aslSite/app/layout :a l) (aslSite/app/msg :a m) (aslSite/app/mascot :a mascot)])

(schema Stats (:f wasmBytes Int64) (:f aslLines Int64) (:f bridgeLines Int64))

fn placeholderStats -> Stats
  (Stats :wasmBytes 0 :aslLines 0 :bridgeLines 0)

fn installLine -> String
  "curl -fsSL https://aslang.dev/install.sh | sh"

fn batchLine -> String
  "asl '(:tools)'"

fn kb bytes: Int64 -> String
  (str (stringFromInt64 (/ (+ bytes 512) 1024)) " KB")

fn shellLine line: String buttonId: String msg: m/Msg -> h/Node
  (h/div [(h/cls "cmd")] [(h/span [(h/cls "sigil") (h/attr "aria-hidden" "true")] [(h/text "$")]) (h/code [] [(h/text line)]) (l/copyButton buttonId msg)])

fn heroSection -> h/Node
  (h/section [(h/cls "hero")]
    [(h/div [(h/cls "shell hero-grid")]
      [(h/div [(h/cls "stack")]
        [(l/eyebrow "ASL" "AgentSlang")
         (h/h1 [(h/cls "display")] [(h/text "The language models write ") (h/em [] [(h/text "without repair loops.")])])
         (h/p [(h/cls "lead")] [(h/text "AgentSlang is a programming language and data notation for code that models write and models read. Structure lives in balanced parentheses, every failure is a value and every effect is marked, so a wrong program is rejected before it runs instead of three turns later.")])
         (shellLine (installLine) "copy-install" (m/copyInstall))
         (h/p [(h/cls "micro")] [(h/text "Not released yet: the installer is under development. ") (h/a [(h/href "/docs#install")] [(h/text "Details")])])
         (h/ul [(h/cls "facts")]
           [(h/li [] [(h/elem "b" [] [(h/text "( )")]) (h/text " balanced S-expressions")])
            (h/li [] [(h/elem "b" [] [(h/text "0")]) (h/text " nil, exceptions or try")])
            (h/li [] [(h/elem "b" [] [(h/text "!")]) (h/text " marks every effect")])
            (h/li [] [(h/elem "b" [] [(h/text "wasm32")]) (h/text " and native through LLVM")])])])
       (h/figure [(h/cls "hero-art")] [(mascot/chameleon true "large") (h/figcaption [(h/cls "micro")] [(h/text "Drawn in ASL: typed SVG nodes, no image file.")])])])])

fn costCell n: String title: String body: String cost: String -> h/Node
  (h/div [(h/cls "cell")] [(h/span [(h/cls "n")] [(h/text n)]) (h/h3 [(h/cls "h3")] [(h/text title)]) (h/p [] [(h/text body)]) (h/span [(h/cls "cost")] [(h/text cost)])])

fn costSection -> h/Node
  (h/section [(h/cls "band sunken") (h/attr "aria-labelledby" "cost")]
    [(h/div [(h/cls "shell")]
      [(h/div [(h/cls "head")]
        [(l/eyebrow "01" "The cost")
         (h/h2 [(h/cls "h2") (h/id "cost")] [(h/text "Most languages were designed for a person at a keyboard.")])
         (h/p [(h/cls "lead")] [(h/text "A model pays for that design on every task, in three places.")])])
       (h/div [(h/cls "grid three")]
         [(costCell "a" "Repair loops" "An indentation slip or a missing brace surfaces only when the file loads. The next turn goes to reading a traceback instead of the task." "cost: one turn per syntax error")
          (costCell "b" "A tax on every call" "JSON tool calls quote every key and punctuate every field. The model pays for the syntax before it starts reasoning about the call." "cost: 51 tokens for one git status")
          (costCell "c" "Behaviour off the page" "nil, exceptions and hidden effects mean the code a reviewer reads is not all of what runs. The difference shows up later, somewhere else." "cost: bugs found after review")])])])

fn ruleCell title: String body: String sample: String -> h/Node
  (h/div [(h/cls "cell")] [(h/h3 [(h/cls "h3")] [(h/text title)]) (h/p [] [(h/text body)]) (h/code [(h/cls "cost")] [(h/text sample)])])

fn rulesSection -> h/Node
  (h/section [(h/cls "band") (h/attr "aria-labelledby" "rules")]
    [(h/div [(h/cls "shell")]
      [(h/div [(h/cls "head")]
        [(l/eyebrow "02" "What it removes")
         (h/h2 [(h/cls "h2") (h/id "rules")] [(h/text "Each rule removes one way to be wrong.")])
         (h/p [(h/cls "lead")] [(h/text "The checker enforces all of them before anything runs. None of them asks the model to be careful; they leave it nothing to be careless with.")])])
       (h/div [(h/cls "grid four")]
         [(ruleCell "Structure you can count" "Every ( [ and { is paired. A truncated or malformed program is caught by counting delimiters, before parsing and long before running." "ERR_READ_UNBALANCED")
          (ruleCell "No nil, no exceptions" "Lookups return (some v) or (none) and failures return (err e). The unhappy path is written in the code, not discovered in a stack trace." "(mt r ((ok v) v) ((err e) 0))")
          (ruleCell "Effects are marked" "A function that prints, touches a file or runs a process says so with !. An unmarked effect is a check error, not a surprise." "ERR_EFFECT_UNMARKED")
          (ruleCell "One spelling per idea" "Whole camelCase words, predicates ending in ?, no aliases. There is one name to guess and it is the obvious one." "listLength · stringContains?")])])])

fn countCell label: String frame: String tokens: String live: Bool -> h/Node
  (h/div [(h/cls "cell")]
    [(h/div [(h/cls "count")] [(h/span [(h/cls "micro")] [(h/text label)]) (h/span [(h/cls (if live "big on" "big"))] [(h/text tokens)])])
     (h/pre [(h/cls (if live "frame live" "frame"))] [(h/text frame)])])

fn jsonFrame -> String
  (stringJoin ["{" "  \"action\": \"execute_command\"," "  \"payload\": {" "    \"binary\": \"git\"," "    \"arguments\": [\"status\", \"--short\"]," "    \"working_dir\": \"/app\"," "    \"timeout_ms\": 5000" "  }" "}"] "\n")

fn wireSection -> h/Node
  (h/section [(h/cls "band sunken") (h/attr "aria-labelledby" "wire")]
    [(h/div [(h/cls "shell")]
      [(h/div [(h/cls "head")]
        [(l/eyebrow "03" "On the wire")
         (h/h2 [(h/cls "h2") (h/id "wire")] [(h/text "The same call in about a third of the tokens.")])
         (h/p [(h/cls "lead")] [(h/text "ASN, the data notation, keeps keys bare and structure in delimiters. One tool call, counted with cl100k_base.")])])
       (h/div [(h/cls "grid two")]
         [(countCell "JSON" (jsonFrame) "51" false)
          (countCell "ASL positional frame" "(! cmd \"git\" [\"status\" \"--short\"] \"/app\" 5000)" "18" true)])
       (h/p [(h/cls "note")] [(h/text "One example, not a benchmark. The (! …) frame is the target wire described in docs/agenticProtocol.md.")])])])

fn step command: String does: String -> h/Node
  (h/li [] [(h/code [] [(h/text command)]) (h/span [] [(h/text does)])])

fn toolbeltSection -> h/Node
  (h/section [(h/cls "band") (h/attr "aria-labelledby" "toolbelt")]
    [(h/div [(h/cls "shell")]
      [(h/div [(h/cls "head")]
        [(l/eyebrow "04" "The toolbelt")
         (h/h2 [(h/cls "h2") (h/id "toolbelt")] [(h/text "One call, many operations, nothing written until you say so.")])
         (h/p [(h/cls "lead")] [(h/text "asl is also the toolbelt an agent uses inside a git repository. The forms of one call run as one batch; edits are staged, inspected, then flushed or dropped.")])])
       (h/ol [(h/cls "steps")]
         [(step "asl '(:query \"handleRequest\")'" "Find the definitions and uses of a name.")
          (step "asl '(:read :file \"src/server.asl\" :symbol \"handleRequest\")'" "Read one symbol, not the whole file.")
          (step "asl '(:edit :file \"src/server.asl\" :old \"…\" :new \"…\")'" "Stage a replacement in the session buffer.")
          (step "asl '(:diff) (:check :file \"src/server.asl\")'" "See the staged change and check it, in one call.")
          (step "asl '(:flush)'" "Write every staged change at once, or (:discard) to drop them.")])
       (h/div [(h/cls "stack gap-top")] [(shellLine (batchLine) "copy-batch" (m/copyBatch))])])])

fn proofCell label: String value: String valueId: String live: Bool -> h/Node
  (h/div [] [(h/span [(h/cls "micro") (h/id (str valueId "-note"))] [(h/text label)]) (h/elem "b" [(h/id valueId) (h/cls (if live "live" ""))] [(h/text value)])])

fn proofSection stats: Stats -> h/Node
  (h/section [(h/cls "band sunken") (h/attr "aria-labelledby" "proof")]
    [(h/div [(h/cls "shell")]
      [(h/div [(h/cls "head")]
        [(l/eyebrow "05" "This page")
         (h/h2 [(h/cls "h2") (h/id "proof")] [(h/text "You are reading an ASL program.")])
         (h/p [(h/cls "lead")] [(h/text (str "The markup, the styles and the handler behind every button on this site are ASL, compiled through asl-target-llvm to a wasm32 module. The JavaScript is a " (stringFromInt64 stats.bridgeLines) "-line bridge that hands the browser the DOM operations the module returns."))])])
       (h/div [(h/cls "proof")]
         [(proofCell "wasm32 module" (kb stats.wasmBytes) "proof-wasm" false)
          (proofCell "lines of ASL" (stringFromInt64 stats.aslLines) "proof-asl" false)
          (proofCell "lines of JS bridge" (stringFromInt64 stats.bridgeLines) "proof-js" false)
          (proofCell "page re-rendered in wasm" "—" "proof-render" true)])
       (h/ul [(h/cls "toc gap-top")]
         [(h/li [] [(h/a [(h/href "/docs")] [(h/text "Read the language on one page →")])])
          (h/li [] [(h/a [(h/href "/llms.txt")] [(h/text "Give your agent llms.txt")])])
          (h/li [] [(h/a [(h/href "https://github.com/GenSEAM/asl/tree/main/web")] [(h/text "Read this site's source")])])])])])

fn homeContent stats: Stats -> (List h/Node)
  [(heroSection) (costSection) (rulesSection) (wireSection) (toolbeltSection) (proofSection stats)]

fn homePage stats: Stats -> h/Node
  (l/document (l/home) "AgentSlang (ASL): the language models write without repair loops" "AgentSlang is a programming language and data notation for code written by models: balanced S-expressions, no nil or exceptions, marked effects, compiled to native code and WebAssembly." (homeContent stats))
