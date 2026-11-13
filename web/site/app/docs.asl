(module aslSite/app/docs
  :x [docsPage]
  :i [(asl-html/html :a h) (aslSite/app/layout :a l)])

fn para s: String -> h/Node
  (h/p [] [(h/text s)])

fn listing lines: (List String) -> h/Node
  (h/pre [] [(h/code [] [(h/text (stringJoin lines "\n"))])])

fn topic anchor: String heading: String body: (List h/Node) -> (List h/Node)
  (cons (h/h2 [(h/id anchor)] [(h/text heading)]) body)

fn topics -> (List (Pair String String))
  [(pair "install" "Install") (pair "files" "Files and modules") (pair "functions" "Functions") (pair "data" "Enums and records")
   (pair "failure" "No nil, no exceptions") (pair "effects" "Effects") (pair "tests" "Tests")
   (pair "toolbelt" "The toolbelt") (pair "wasm" "WebAssembly") (pair "targets" "JavaScript, TypeScript, HTML and CSS")]

fn toc -> h/Node
  (h/ul [(h/cls "toc") (h/attr "aria-label" "On this page")]
    (map (fn [(t (Pair String String))] -> h/Node (h/li [] [(h/a [(h/href (str "#" (pairFirst t)))] [(h/text (pairSecond t))])])) (topics)))

fn install -> (List h/Node)
  (topic "install" "Install"
    [(para "AgentSlang has not been released. There are no release binaries, the script at /install.sh has not been run end to end on a fresh machine and should not be relied on yet, and Windows is not supported.")
     (para "Building from source is not ready either. The launcher asl/bin/asl builds the native CLI from a committed seed with clang, but on a clean copy of the published tree that build stops at an unresolved import (checked on macOS, 2026-11-13). Until that is fixed there is no supported way to run ASL outside the project's own workspace.")
     (para "The commands on this page are the ones that work in that workspace, where asl is the launcher. Each example below was run there with asl check, asl test or asl run before this page was built.")])

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
           (listing ["fn area s: Shape -> Int64" "  (match s ((circle r) (* 3 (* r r))) ((square a) (* a a)))"])
           (para "Names are camelCase whole words and predicates end in ?: listLength, stringContains?, some?. len and head do not exist; + is not a value. Int and Float never mix; overflow and division by zero trap.")])
        (listAppend
          (topic "data" "Enums and records"
            [(para "enum makes positional constructors, taken apart with match; patterns nest one level. A record field reads as x.f, chains as a.b.c, and (with x :k v) is a copy of x with field k set to v.")
             (listing ["enum Shape (circle r: Int64) (square side: Int64)" "" "(schema Point (:f x Int64) (:f y Int64))" "(with p :x 3)"])])
          (listAppend
            (topic "failure" "No nil, no exceptions"
              [(para "There is no nil, exception or try. listHead, listGet, stringSlice and mapGet return (some v) or (none); a failure is (err e). They are unwrapped with match, optionOr or resultOr, so the unhappy path is visible where it happens.")
               (listing ["(match (fileReadString path)" "  ((ok text) (stringLength text))" "  ((err e) 0))"])])
            (listAppend
              (topic "effects" "Effects"
                [(para "A function that prints, reads a file or runs a process is marked, either with ! after fn or with a name ending in !, so a reader sees from the header that it does more than compute.")
                 (listing ["fn ! main -> Int64" "  (do (print \"hello\") 0)"])
                 (para "This is a convention today, not a check: asl check accepts the same function without the mark. Rejecting an unmarked effect is planned.")])
              (listAppend
                (topic "tests" "Tests"
                  [(para "A test module exports runTests, which returns true after at least one (assert cond \"msg\") or refute. asl check resolves names and checks call arity before anything runs (ERR_UNKNOWN_SYMBOL, ERR_ARITY); a file with an unclosed delimiter fails first with ERR_UNBALANCED and a proposed (:fix). asl test prints the number of assertions executed and exits non-zero on a failure.")
                   (listing ["fn runTests -> Bool" "  (do (assert (= (area (square 3)) 9) \"square\") true)" "" "asl check fileTest.asl" "asl test fileTest.asl"])])
                (listAppend
                  (topic "toolbelt" "The toolbelt"
                    [(para "asl '<form> <form> ...' runs file operations on the git repository that holds the working directory. The forms of one call run as one batch, and every form answers with an ASN receipt.")
                     (listing ["asl '(:tools)'" "asl '(:query \"handleRequest\")'" "asl '(:read :file \"src/app.asl\" :symbol \"greet\")'" "asl '(:edit :file \"src/app.asl\" :old \"a\" :new \"b\") (:diff)'" "asl '(:flush)'   # or (:discard)"])
                     (para "Edits are staged outside the working tree until (:flush) writes them atomically; (:txn :owns (...) ...) stages, gates and flushes in one call and restores every touched file when a step fails.")])
                  (listAppend (topic "wasm" "WebAssembly"
                    [(para "asl-target-llvm lowers a linked program to LLVM IR for wasm32-unknown-unknown with its own collector and allocator. The module imports four host functions (asl.write, asl.exit, asl.nowNs and asl.trap) and nothing else; a builtin the target cannot provide, such as tcpListen or a clock read, is a compile error rather than a runtime surprise.")
                     (para "This site is built that way. Its markup, styles and event handlers are ASL in web/site; web/tools/build.asl prerenders every page and compiles the same modules into site.wasm, and a short JavaScript bridge forwards clicks to the module's update export.")
                     (listing ["fn ! update code: Int64 model: Int64 -> Int64" "  (let [(r (u/step (m/msgOf code) model))]" "    (do (print (b/encodeOps (pairSecond r))) (pairFirst r)))"])])
                  (topic "targets" "JavaScript, TypeScript, HTML and CSS"
                    [(para "asl-target-js lowers the same linked program to one ES module: Int is BigInt and traps on int64 overflow, strings keep their UTF-8 byte semantics, and its test fixtures compare output, exit codes and trap codes with the native build. Unlike wasm32 it can read clocks; files, processes and the environment are refused at compile time.")
                     (para "TypeScript callers get declarations generated from the module's signatures: a schema becomes a readonly interface, an enum a union tagged by variant name, Int bigint, and type variables generics. A test checks a consumer against tsc --strict.")
                     (listing ["ENTRY=asl/examples/fib.asl OUT=app.mjs asl run asl/web/tools/jsc.asl" "# app.mjs and app.d.mts"])
                     (para "asl-html is typed HTML5 and CSS: one constructor per element, escaping by construction, styles as data with media, supports, layer, container, keyframes and font-face rules. This site is written with it.")])))))))))))

fn docsPage -> h/Node
  (l/document (l/docs) "AgentSlang docs: the language on one page" "The AgentSlang (ASL) language on one page: modules, functions, enums, no nil or exceptions, effect marks, tests, the agent toolbelt and WebAssembly."
    [(h/div [(h/cls "shell page")] [(h/article [(h/cls "prose")] (body))])])
