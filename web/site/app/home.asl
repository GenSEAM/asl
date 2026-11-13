(module aslSite/app/home
  :x [Stats placeholderStats batchLine homeContent homePage]
  :i [(asl-html/html :a h) (aslSite/app/layout :a l) (aslSite/app/msg :a m) (aslSite/app/mascot :a mascot)])

(schema Stats (:f wasmBytes Int64) (:f aslLines Int64) (:f bridgeLines Int64))

fn placeholderStats -> Stats
  (Stats :wasmBytes 0 :aslLines 0 :bridgeLines 0)

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
         (h/h1 [(h/cls "display")] [(h/text "A language designed for ") (h/em [] [(h/text "models to write.")])])
         (h/p [(h/cls "lead")] [(h/text "AgentSlang (ASL) is a programming language and data notation for people building coding agents and agent tool protocols. Structure lives in balanced parentheses and every failure is a value, so asl check rejects a truncated or mistyped program before it runs. Fewer repair turns is the design goal; there is no benchmark for it yet.")])
         (h/p [(h/cls "status")] [(h/el "b" [] [(h/text "Not released.")]) (h/text " There is nothing to install yet: no binaries, an untested installer, and a fresh source checkout does not build its CLI today. What you can do now is read it. ") (h/a [(h/href "/docs#install")] [(h/text "Details")])])
         (h/ul [(h/cls "toc")]
           [(h/li [] [(h/a [(h/href "/docs")] [(h/text "The language on one page →")])])
            (h/li [] [(h/a [(h/href "/llms.txt")] [(h/text "llms.txt for your agent")])])
            (h/li [] [(h/a [(h/href "https://github.com/GenSEAM/asl")] [(h/text "Source on GitHub")])])])
         (h/ul [(h/cls "facts")]
           [(h/li [] [(h/el "b" [] [(h/text "18 vs 30")]) (h/text " tokens: one tool call against minified JSON ") (h/a [(h/href "#wire")] [(h/text "(one example)")])])
            (h/li [] [(h/el "b" [] [(h/text "( )")]) (h/text " balanced S-expressions")])
            (h/li [] [(h/el "b" [] [(h/text "0")]) (h/text " nil, exceptions or try")])
            (h/li [] [(h/el "b" [] [(h/text "wasm32")]) (h/text " and native through LLVM")])])])
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
          (costCell "b" "A tax on every call" "JSON tool calls name and quote every key on every call. The model pays for the envelope before it starts reasoning about the call." "cost: 51 tokens pretty-printed, 30 minified, for one git status")
          (costCell "c" "Behaviour off the page" "nil, exceptions and hidden effects mean the code a reviewer reads is not all of what runs. The difference shows up later, somewhere else." "cost: bugs found after review")])])])

fn ruleCell title: String body: String sample: String -> h/Node
  (h/div [(h/cls "cell")] [(h/h3 [(h/cls "h3")] [(h/text title)]) (h/p [] [(h/text body)]) (h/code [(h/cls "cost")] [(h/text sample)])])

fn rulesSection -> h/Node
  (h/section [(h/cls "band") (h/attr "aria-labelledby" "rules")]
    [(h/div [(h/cls "shell")]
      [(h/div [(h/cls "head")]
        [(l/eyebrow "02" "What it removes")
         (h/h2 [(h/cls "h2") (h/id "rules")] [(h/text "Each rule removes one way to be wrong.")])
         (h/p [(h/cls "lead")] [(h/text "asl check enforces the first two before anything runs, and an unknown or misspelt name is an error. Effect marks are a convention the checker does not enforce yet.")])])
       (h/div [(h/cls "grid four")]
         [(ruleCell "Structure you can count" "Every ( [ and { is paired. A truncated or malformed program is caught by counting delimiters, before parsing and long before running." "ERR_UNBALANCED")
          (ruleCell "No nil, no exceptions" "Lookups return (some v) or (none) and failures return (err e). The unhappy path is written in the code, not discovered in a stack trace." "(match r ((ok v) v) ((err e) 0))")
          (ruleCell "Effects are marked" "A function that prints, touches a file or runs a process is written with ! in its header. Today that is a convention: asl check accepts an unmarked effect." "fn ! main -> Int64")
          (ruleCell "One spelling per idea" "Whole camelCase words, predicates ending in ?, no aliases. There is one name to guess and it is the obvious one." "listLength · stringContains?")])])])

fn countCell label: String frame: String tokens: String live: Bool -> h/Node
  (h/div [(h/cls "cell")]
    [(h/div [(h/cls "count")] [(h/span [(h/cls "micro")] [(h/text label)]) (h/span [(h/cls (if live "big on" "big"))] [(h/text tokens)])])
     (h/pre [(h/cls (if live "frame live" "frame"))] [(h/text frame)])])

fn jsonFrame -> String
  (stringJoin ["{" "  \"action\": \"execute_command\"," "  \"payload\": {" "    \"binary\": \"git\"," "    \"arguments\": [\"status\", \"--short\"]," "    \"working_dir\": \"/app\"," "    \"timeout_ms\": 5000" "  }" "}"] "\n")

fn jsonMinified -> String
  "{\"action\":\"execute_command\",\"payload\":{\"binary\":\"git\",\"arguments\":[\"status\",\"--short\"],\"working_dir\":\"/app\",\"timeout_ms\":5000}}"

fn wireSection -> h/Node
  (h/section [(h/cls "band sunken") (h/attr "aria-labelledby" "wire")]
    [(h/div [(h/cls "shell")]
      [(h/div [(h/cls "head")]
        [(l/eyebrow "03" "On the wire")
         (h/h2 [(h/cls "h2") (h/id "wire")] [(h/text "One tool call: 51, 30 or 18 tokens.")])
         (h/p [(h/cls "lead")] [(h/text "The same git status call, counted with cl100k_base. Against minified JSON the positional frame is 40% smaller, and the saving comes from sending fields by position instead of by name, not from the parentheses.")])])
       (h/div [(h/cls "grid three")]
         [(countCell "JSON, pretty-printed" (jsonFrame) "51" false)
          (countCell "JSON, minified" (jsonMinified) "30" false)
          (countCell "ASL positional frame" "(! cmd \"git\" [\"status\" \"--short\"] \"/app\" 5000)" "18" true)])
       (h/p [(h/cls "note")] [(h/text "One example, not a benchmark (tiktoken, cl100k_base, recounted 2026-11-13). A positional JSON array of the same call is 17 tokens, and a keyed ASN frame is about the size of minified JSON. ASL source is not cheaper than mainstream code either: across 9 module pairs it took 1.84 times the tokens of typed Python (o200k_base, 2026-10-09). The (! …) frame is the target wire described in docs/agenticProtocol.md.")])])])

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
  (h/div [] [(h/span [(h/cls "micro") (h/id (str valueId "-note"))] [(h/text label)]) (h/el "b" [(h/id valueId) (h/cls (if live "live" ""))] [(h/text value)])])

fn proofSection stats: Stats -> h/Node
  (h/section [(h/cls "band sunken") (h/attr "aria-labelledby" "proof")]
    [(h/div [(h/cls "shell")]
      [(h/div [(h/cls "head")]
        [(l/eyebrow "05" "This page")
         (h/h2 [(h/cls "h2") (h/id "proof")] [(h/text "You are reading an ASL program.")])
         (h/p [(h/cls "lead")] [(h/text (str "The markup, the styles and the handler behind every button on this site are ASL, compiled through asl-target-llvm to a wasm32 module. The JavaScript is a " (stringFromInt64 stats.bridgeLines) "-line bridge that hands the browser the DOM operations the module returns."))])])
       (h/div [(h/cls "proof")]
         [(proofCell "wasm32 module" (kb stats.wasmBytes) "proof-wasm" false)
          (proofCell "lines of ASL (site and asl-html)" (stringFromInt64 stats.aslLines) "proof-asl" false)
          (proofCell "lines of JS bridge" (stringFromInt64 stats.bridgeLines) "proof-js" false)
          (proofCell "page re-rendered in wasm" "—" "proof-render" true)])
       (h/ul [(h/cls "toc gap-top")]
         [(h/li [] [(h/a [(h/href "/docs")] [(h/text "Read the language on one page →")])])
          (h/li [] [(h/a [(h/href "/llms.txt")] [(h/text "Give your agent llms.txt")])])
          (h/li [] [(h/a [(h/href "https://github.com/GenSEAM/asl/tree/main/web")] [(h/text "Read this site's source")])])])])])

fn homeContent stats: Stats -> (List h/Node)
  [(heroSection) (costSection) (rulesSection) (wireSection) (toolbeltSection) (proofSection stats)]

fn homePage stats: Stats -> h/Node
  (l/document (l/home) "AgentSlang (ASL): a language designed for models to write" "AgentSlang is a programming language and data notation for people building coding agents: balanced S-expressions, no nil or exceptions, checked before it runs, compiled to native code and WebAssembly. Not released yet." (homeContent stats))
