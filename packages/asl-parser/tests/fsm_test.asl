(module asl-parser/tests/fsmTest
  :d "Unit tests for polyglot streaming FSM outline scanner under strict falsification"
  :x [testAslOutline
      testAsnOutline
      testPythonOutline
      testTsOutline
      testGoOutline
      testRustOutline
      testCommentMasking
      testStringMasking
      testDetectLang
      testFormatOutline
      runTests]
  :i [(fsm_outline :a fsm)])

(df testAslOutline [] -> Bool
  :d "Verifies ASL top-level form extraction"
  (let [(code "(module demo/sample :d \"demo\")\n\n(dfs Point\n  (:f x Int64 \"x\")\n  (:f y Int64 \"y\"))\n\n(df add-pts [(p1 Point) (p2 Point)] -> Point\n  :d \"add\")\n")
        (items (fsm/scanOutline code "asl"))]
    (assert (= (list-length items) 3) "ASL snippet must yield exactly 3 outline items")
    (let [(m (mt (list-get items 0) ((some it) it) ((none) (fsm/OutlineItem :kind "" :name "" :line 0))))
          (s (mt (list-get items 1) ((some it) it) ((none) (fsm/OutlineItem :kind "" :name "" :line 0))))
          (f (mt (list-get items 2) ((some it) it) ((none) (fsm/OutlineItem :kind "" :name "" :line 0))))]
      (assert (= (.-kind m) "module") "First item must be module")
      (assert (= (.-name m) "demo/sample") "Module name must match demo/sample")
      (assert (= (.-line m) 1) "Module line must be 1")
      (assert (= (.-kind s) "dfs") "Second item must be dfs struct")
      (assert (= (.-name s) "Point") "Struct name must be Point")
      (assert (= (.-line s) 3) "Struct line must be 3")
      (assert (= (.-kind f) "df") "Third item must be df function")
      (assert (= (.-name f) "add-pts") "Function name must be add-pts")
      (assert (= (.-line f) 7) "Function line must be 7"))
    true))

(df testAsnOutline [] -> Bool
  :d "Verifies ASN registry and module extraction"
  (let [(code "(:grammar :package my/parser :version \"0.1.0\")\n\n(module my/parser :d \"desc\")\n")
        (items (fsm/scanOutline code "asl"))]
    (assert (= (list-length items) 2) "ASN snippet must yield exactly 2 items")
    (let [(g (mt (list-get items 0) ((some it) it) ((none) (fsm/OutlineItem :kind "" :name "" :line 0))))
          (m (mt (list-get items 1) ((some it) it) ((none) (fsm/OutlineItem :kind "" :name "" :line 0))))]
      (assert (= (.-kind g) "grammar") "First item kind must be grammar")
      (assert (= (.-name g) "my/parser") "Grammar package name must match")
      (assert (= (.-line g) 1) "Grammar line must be 1")
      (assert (= (.-kind m) "module") "Second item kind must be module")
      (assert (= (.-name m) "my/parser") "Module name must match")
      (assert (= (.-line m) 3) "Module line must be 3"))
    true))

(df testPythonOutline [] -> Bool
  :d "Verifies Python class, def, and async def extraction ignoring docstrings"
  (let [(code "\"\"\"\nModule docstring\ndef ignored_inside_docstring():\n    pass\n\"\"\"\n\nclass AgentRunner:\n    def run(self):\n        pass\n\ndef execute_task(task_id):\n    return 42\n\nasync def fetch_async(url):\n    return url\n")
        (items (fsm/scanOutline code "py"))]
    (assert (= (list-length items) 4) "Python snippet must yield 4 items")
    (let [(c (mt (list-get items 0) ((some it) it) ((none) (fsm/OutlineItem :kind "" :name "" :line 0))))
          (m (mt (list-get items 1) ((some it) it) ((none) (fsm/OutlineItem :kind "" :name "" :line 0))))
          (f1 (mt (list-get items 2) ((some it) it) ((none) (fsm/OutlineItem :kind "" :name "" :line 0))))
          (f2 (mt (list-get items 3) ((some it) it) ((none) (fsm/OutlineItem :kind "" :name "" :line 0))))]
      (assert (= (.-kind c) "class") "First item must be class")
      (assert (= (.-name c) "AgentRunner") "Class name must be AgentRunner")
      (assert (= (.-line c) 7) "Class line must be 7")
      (assert (= (.-kind m) "fn") "Method kind must be fn")
      (assert (= (.-name m) "run") "Method name must be run")
      (assert (= (.-kind f1) "fn") "Function kind must be fn")
      (assert (= (.-name f1) "execute_task") "Function name must be execute_task")
      (assert (= (.-line f1) 11) "Function line must be 11")
      (assert (= (.-kind f2) "fn") "Async function kind must be fn")
      (assert (= (.-name f2) "fetch_async") "Async function name must be fetch_async")
      (assert (= (.-line f2) 14) "Async function line must be 14"))
    true))

(df testTsOutline [] -> Bool
  :d "Verifies TypeScript export modifiers and type forms"
  (let [(code "export interface Config {\n  port: number;\n}\n\nexport class Server {\n  start() {}\n}\n\nexport async function listen(port: number) {\n  return port;\n}\n\nexport type Handler = (req: any) => void;\n\nexport enum Status {\n  Ready,\n  Busy\n}\n")
        (items (fsm/scanOutline code "ts"))]
    (assert (= (list-length items) 5) "TypeScript snippet must yield 5 items")
    (let [(it0 (mt (list-get items 0) ((some it) it) ((none) (fsm/OutlineItem :kind "" :name "" :line 0))))
          (it1 (mt (list-get items 1) ((some it) it) ((none) (fsm/OutlineItem :kind "" :name "" :line 0))))
          (it2 (mt (list-get items 2) ((some it) it) ((none) (fsm/OutlineItem :kind "" :name "" :line 0))))
          (it3 (mt (list-get items 3) ((some it) it) ((none) (fsm/OutlineItem :kind "" :name "" :line 0))))
          (it4 (mt (list-get items 4) ((some it) it) ((none) (fsm/OutlineItem :kind "" :name "" :line 0))))]
      (assert (= (.-kind it0) "interface") "Item 0 must be interface")
      (assert (= (.-name it0) "Config") "Interface name must be Config")
      (assert (= (.-kind it1) "class") "Item 1 must be class")
      (assert (= (.-name it1) "Server") "Class name must be Server")
      (assert (= (.-kind it2) "fn") "Item 2 must be fn")
      (assert (= (.-name it2) "listen") "Function name must be listen")
      (assert (= (.-kind it3) "type") "Item 3 must be type")
      (assert (= (.-name it3) "Handler") "Type name must be Handler")
      (assert (= (.-kind it4) "enum") "Item 4 must be enum")
      (assert (= (.-name it4) "Status") "Enum name must be Status"))
    true))

(df testGoOutline [] -> Bool
  :d "Verifies Go package, func with receiver, and type struct forms"
  (let [(code "package worker\n\ntype TaskQueue struct {\n  capacity int\n}\n\nfunc (q *TaskQueue) Push(id string) error {\n  return nil\n}\n\nfunc NewQueue(cap int) *TaskQueue {\n  return &TaskQueue{capacity: cap}\n}\n")
        (items (fsm/scanOutline code "go"))]
    (assert (= (list-length items) 4) "Go snippet must yield 4 items")
    (let [(p (mt (list-get items 0) ((some it) it) ((none) (fsm/OutlineItem :kind "" :name "" :line 0))))
          (t (mt (list-get items 1) ((some it) it) ((none) (fsm/OutlineItem :kind "" :name "" :line 0))))
          (m (mt (list-get items 2) ((some it) it) ((none) (fsm/OutlineItem :kind "" :name "" :line 0))))
          (f (mt (list-get items 3) ((some it) it) ((none) (fsm/OutlineItem :kind "" :name "" :line 0))))]
      (assert (= (.-kind p) "module") "Item 0 must be module")
      (assert (= (.-name p) "worker") "Package name must be worker")
      (assert (= (.-kind t) "struct") "Item 1 must be struct")
      (assert (= (.-name t) "TaskQueue") "Struct name must be TaskQueue")
      (assert (= (.-kind m) "fn") "Item 2 must be fn")
      (assert (= (.-name m) "Push") "Method name must be Push")
      (assert (= (.-kind f) "fn") "Item 3 must be fn")
      (assert (= (.-name f) "NewQueue") "Function name must be NewQueue"))
    true))

(df testRustOutline [] -> Bool
  :d "Verifies Rust pub fn, struct, enum, and trait forms"
  (let [(code "pub mod parser;\n\npub struct Scanner {\n  pos: usize,\n}\n\npub enum TokenKind {\n  Ident,\n  Eof,\n}\n\npub trait TokenStream {\n  fn next_token(&mut self);\n}\n\npub async fn tokenize_all(src: &str) -> Vec<TokenKind> {\n  Vec::new()\n}\n")
        (items (fsm/scanOutline code "rs"))]
    (assert (= (list-length items) 5) "Rust snippet must yield 5 items")
    (let [(m (mt (list-get items 0) ((some it) it) ((none) (fsm/OutlineItem :kind "" :name "" :line 0))))
          (s (mt (list-get items 1) ((some it) it) ((none) (fsm/OutlineItem :kind "" :name "" :line 0))))
          (e (mt (list-get items 2) ((some it) it) ((none) (fsm/OutlineItem :kind "" :name "" :line 0))))
          (t (mt (list-get items 3) ((some it) it) ((none) (fsm/OutlineItem :kind "" :name "" :line 0))))
          (f (mt (list-get items 4) ((some it) it) ((none) (fsm/OutlineItem :kind "" :name "" :line 0))))]
      (assert (= (.-kind m) "module") "Item 0 must be module")
      (assert (= (.-name m) "parser") "Mod name must be parser")
      (assert (= (.-kind s) "struct") "Item 1 must be struct")
      (assert (= (.-name s) "Scanner") "Struct name must be Scanner")
      (assert (= (.-kind e) "enum") "Item 2 must be enum")
      (assert (= (.-name e) "TokenKind") "Enum name must be TokenKind")
      (assert (= (.-kind t) "interface") "Item 3 must be interface")
      (assert (= (.-name t) "TokenStream") "Trait name must be TokenStream")
      (assert (= (.-kind f) "fn") "Item 4 must be fn")
      (assert (= (.-name f) "tokenize_all") "Function name must be tokenize_all"))
    true))

(df testCommentMasking [] -> Bool
  :d "Verifies that declarations inside comments are ignored"
  (let [(code "// export function fake1() {}\n/*\nexport class Fake2 {}\n*/\n# def fake3():\n; (df fake4)\nexport function realFn() {\n  return 1;\n}\n")
        (items (fsm/scanOutline code "ts"))]
    (assert (= (list-length items) 1) "Only realFn should be extracted, comments must be masked")
    (let [(firstIt (mt (list-get items 0) ((some it) it) ((none) (fsm/OutlineItem :kind "" :name "" :line 0))))]
      (assert (= (.-name firstIt) "realFn") "Extracted item must be realFn"))
    true))

(df testStringMasking [] -> Bool
  :d "Verifies that declarations inside string literals are ignored"
  (let [(code "const script = \"export function fakeString() {}\";\nexport function actualTarget() {\n  return 1;\n}\n")
        (items (fsm/scanOutline code "ts"))]
    (assert (= (list-length items) 1) "Only actualTarget should be extracted")
    (let [(firstIt (mt (list-get items 0) ((some it) it) ((none) (fsm/OutlineItem :kind "" :name "" :line 0))))]
      (assert (= (.-name firstIt) "actualTarget") "Extracted item must be actualTarget"))
    true))

(df testDetectLang [] -> Bool
  :d "Verifies language extension detection"
  (assert (= (fsm/detectLang "src/compiler.asl") "asl") "asl file extension must map to asl")
  (assert (= (fsm/detectLang "grammar.asn") "asl") "asn file extension must map to asl")
  (assert (= (fsm/detectLang "scripts/harbor.py") "py") "py file extension must map to py")
  (assert (= (fsm/detectLang "src/index.ts") "ts") "ts file extension must map to ts")
  (assert (= (fsm/detectLang "src/app.tsx") "ts") "tsx file extension must map to ts")
  (assert (= (fsm/detectLang "main.go") "go") "go file extension must map to go")
  (assert (= (fsm/detectLang "lib.rs") "rs") "rs file extension must map to rs")
  true)

(df testFormatOutline [] -> Bool
  :d "Verifies outline canonical wire formatting"
  (let [(items (list (fsm/OutlineItem :kind "fn" :name "demo" :line 10)))
        (fmt (fsm/formatOutline items))]
    (assert (string-contains? fmt "(:outline [") "Format must contain (:outline [")
    (assert (string-contains? fmt "(:item :kind \"fn\" :name \"demo\" :line 10)") "Format must contain canonical item")
    true))

(df runTests [] -> Bool
  :d "Executes all unit tests in test suite"
  (assert (testAslOutline) "test-asl-outline must pass")
  (assert (testAsnOutline) "test-asn-outline must pass")
  (assert (testPythonOutline) "test-python-outline must pass")
  (assert (testTsOutline) "test-ts-outline must pass")
  (assert (testGoOutline) "test-go-outline must pass")
  (assert (testRustOutline) "test-rust-outline must pass")
  (assert (testCommentMasking) "test-comment-masking must pass")
  (assert (testStringMasking) "test-string-masking must pass")
  (assert (testDetectLang) "test-detect-lang must pass")
  (assert (testFormatOutline) "test-format-outline must pass")
  true)
