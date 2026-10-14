(module aslSite/app/docs
  :x [docsPage]
  :i [(aslSite/ui/html :a h) (aslSite/app/layout :a l)])

fn para s: String -> h/Node
  (h/p [] [(h/text s)])

fn listing lines: (List String) -> h/Node
  (h/pre [] [(h/code [] [(h/text (stringJoin lines "\n"))])])

fn topic anchor: String heading: String body: (List h/Node) -> (List h/Node)
  (cons (h/h2 [(h/id anchor)] [(h/text heading)]) body)

fn topics -> (List (Pair String String))
  [(pair "install" "Install") (pair "files" "Files and modules") (pair "functions" "Functions") (pair "data" "Enums and records")
   (pair "failure" "No nil, no exceptions") (pair "effects" "Effects") (pair "tests" "Tests")
   (pair "toolbelt" "The toolbelt") (pair "wasm" "WebAssembly")]

fn toc -> h/Node
  (h/ul [(h/cls "toc") (h/attr "aria-label" "On this page")]
    (map (fn [(t (Pair String String))] -> h/Node (h/li [] [(h/a [(h/href (str "#" (pairFirst t)))] [(h/text (pairSecond t))])])) (topics)))

fn install -> (List h/Node)
  (topic "install" "Install"
    [(para "AgentSlang has not been released yet. The installer is under development: there are no release binaries, and the script below is the one that will ship.")
     (listing ["curl -fsSL https://aslang.dev/install.sh | sh"])
     (para "To try the language before then, clone the repository and build the stage-0 host with host/build.sh; host/out/asl-host check, test and run work on it directly.")])

fn body -> (List h/Node)
  (listAppend
    [(l/eyebrow "DOCS" "The language on one page")
     (h/h1 [] [(h/text "AgentSlang in ten minutes")])
     (para "ASL source (.asl) and data (.asn) files are S-expressions with balanced parentheses. A malformed program is caught by counting delimiters rather than by running it, and whitespace carries no meaning inside a form. The complete rules an agent needs are in llms.txt; this page is the same material for a person.")
     (toc)]
    (listAppend (install) (listAppend
      (topic "files" "Files and modules"
        [(para "A file is a module header, then items starting in column 0. Imports name the module a file declares, not its path. Each bracket kind pairs exactly: ( ) forms, [ ] lists, { } records.")
         (listing ["(module demo/shapes :x [area runTests] :i [(other/module :a alias)])"])
         (para "Documentation is not in source: each symbol's doc lives as a (:doc :symbol \"path#name\" :text \"...\") row in the package doc.asn, and the reader rejects prose comments.")])
      (listAppend
        (topic "functions" "Functions"
          [(para "A function header is a bare line in column 0; its body is indented below and closes only its own parentheses. (let [(a 1) (b (+ a 1))] body) binds in sequence, (fn [x] body) is a value and cond ends with (else v).")
           (listing ["fn area s: Shape -> Int64" "  (mt s ((circle r) (* 3 (* r r))) ((square a) (* a a)))"])
           (para "Names are camelCase whole words and predicates end in ?: listLength, stringContains?, some?. len and head do not exist; + is not a value. Int and Float never mix; overflow and division by zero trap.")])
        (listAppend
          (topic "data" "Enums and records"
            [(para "enum makes positional constructors, taken apart with mt; patterns nest one level. A record field reads as x.f, chains as a.b.c, and (with x :k v) is a copy of x with field k set to v.")
             (listing ["enum Shape (circle r: Int64) (square side: Int64)" "" "(schema Point (:f x Int64) (:f y Int64))" "(with p :x 3)"])])
          (listAppend
            (topic "failure" "No nil, no exceptions"
              [(para "There is no nil, exception or try. listHead, listGet, stringSlice and mapGet return (some v) or (none); a failure is (err e). They are unwrapped with mt, optionOr or resultOr, so the unhappy path is visible where it happens.")
               (listing ["(mt (fileRead path)" "  ((ok text) (stringLength text))" "  ((err e) 0))"])])
            (listAppend
              (topic "effects" "Effects"
                [(para "A function that prints, reads a file or runs a process marks it, either with ! after fn or as a name ending in !. The checker rejects an unmarked effect:")
                 (listing ["fn ! main -> Int64" "  (do (print \"hello\") 0)" "" "ERR_EFFECT_UNMARKED fn main names effectful print: mark it (fn ! main ...) or rename it main!"])])
              (listAppend
                (topic "tests" "Tests"
                  [(para "A test module exports runTests, which returns true after at least one (assert cond \"msg\") or refute. The stage-0 host is the strict reference: it checks names, arity and enums before running anything.")
                   (listing ["fn runTests -> Bool" "  (do (assert (= (area (square 3)) 9) \"square\") true)" "" "host/out/asl-host check fileTest.asl" "host/out/asl-host test fileTest.asl"])])
                (listAppend
                  (topic "toolbelt" "The toolbelt"
                    [(para "asl '<form> <form> ...' runs file operations on the git repository that holds the working directory. The forms of one call run as one batch, and every form answers with an ASN receipt.")
                     (listing ["asl '(:tools)'" "asl '(:query \"handleRequest\")'" "asl '(:read :file \"src/app.asl\" :symbol \"greet\")'" "asl '(:edit :file \"src/app.asl\" :old \"a\" :new \"b\") (:diff)'" "asl '(:flush)'   # or (:discard)"])
                     (para "Edits are staged outside the working tree until (:flush) writes them atomically; (:txn :owns (...) ...) stages, gates and flushes in one call and restores every touched file when a step fails.")])
                  (topic "wasm" "WebAssembly"
                    [(para "asl-target-llvm lowers a linked program to LLVM IR for wasm32-unknown-unknown with its own collector and allocator. The module imports four host functions (asl.write, asl.exit, asl.nowNs and asl.trap) and nothing else; a builtin the target cannot provide, such as tcpListen or a clock read, is a compile error rather than a runtime surprise.")
                     (para "This site is built that way. Its markup, styles and event handlers are ASL in web/site; web/tools/build.asl prerenders every page and compiles the same modules into site.wasm, and a short JavaScript bridge forwards clicks to the module's update export.")
                     (listing ["fn ! update code: Int64 model: Int64 -> Int64" "  (let [(r (u/step (m/msgOf code) model))]" "    (do (print (b/encodeOps (pairSecond r))) (pairFirst r)))"])]))))))))))

fn docsPage -> h/Node
  (l/document (l/docs) "AgentSlang docs: the language on one page" "The AgentSlang (ASL) language on one page: modules, functions, enums, no nil or exceptions, marked effects, tests, the agent toolbelt and WebAssembly."
    [(h/div [(h/cls "shell page")] [(h/article [(h/cls "prose")] (body))])])
