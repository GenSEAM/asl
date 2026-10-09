(module asl-forms/tests/extractParityTest
  :x [runTests]
  :i [(asl-forms/kernel :a k) (asl-forms/ops :a ops) (asl-forms/extract :a ex)])

fn expectedReceipt output: String -> String
  (let [(marker ":receipt ")
        (found (stringIndexOf output marker))]
    (mt found
      ((none) output)
      ((some at)
        (let [(start (+ at (stringLength marker)))
              (tail (optionOr (stringSlice output start (stringLength output)) ""))]
          (optionOr (stringSlice tail 0 (max 0 (- (stringLength tail) 1))) "")))))

fn lineNumber text: String offset: Int64 -> Int64
  (listLength (stringSplit (optionOr (stringSlice text 0 (max 0 (min offset (stringLength text)))) "") "\n"))

fn ! symbolPass source: String lang: String symbol: String legacy: String -> Bool
  (let [(found (ex/findSymbol source lang symbol))
        (kw (k/parseStep legacy).kwargs)
        (error (optionOr (mapGet kw "error") ""))]
    (if (= error "ERR_SYMBOL_NOT_FOUND")
      (none? (pairFirst found))
      (mt (pairFirst found)
        ((none) false)
        ((some d)
          (and (= d.name symbol)
               (= d.kind (optionOr (mapGet kw "kind") ""))
               (= (stringFromInt64 (lineNumber source d.start)) (optionOr (mapGet kw "start") ""))
               (= (stringFromInt64 (lineNumber source (max d.start (- d.end 1)))) (optionOr (mapGet kw "end") "")))))))

fn ! outlinePass root: String file: String source: String legacy: String -> Bool
  (let [(form (str "(:intel :op outline :file \"" file "\")"))
        (out (ops/runStep! root 1 form))
        (actual (optionOr (listHead out.lines) ""))
        (expected (str "  (:step :id 1 :op \"intel\" :status \"ok\" :subop \"outline\" :receipt\n" (expectedReceipt legacy) ")"))]
    (let [(ok (and (= out.errCount 0) (= actual expected) (not (stringContains? actual "ERR_NOT_PORTED"))))]
      (if (not ok) (println (str "(:outlineMismatch :file \"" file "\" :actual \"" (k/escapeAsnVal actual) "\" :legacy \"" (k/escapeAsnVal (expectedReceipt legacy)) "\")")) (print ""))
      ok))

fn ! casePass root: String rows: (List String) -> Bool
  (if (listEmpty? rows)
    true
    (let [(row (optionOr (listHead rows) ""))
          (kw (k/parseStep row).kwargs)
          (rest (optionOr (listTail rows) (list)))
          (file (optionOr (mapGet kw "file") ""))
          (source (optionOr (mapGet kw "source") ""))
          (symbol (optionOr (mapGet kw "symbol") ""))
          (outline (optionOr (mapGet kw "outline") ""))
          (read (optionOr (mapGet kw "read") ""))
          (writeOk (mt (fileWrite (str root "/" file) source) ((ok _) true) ((err _) false)))
          (outlineOk (outlinePass root file source outline))
          (symbolOk (or (stringEmpty? symbol) (symbolPass source (ex/languageOf file source) symbol read)))]
      (do
        (if (not symbolOk) (println (str "(:symbolMismatch :file \"" file "\")")) (print ""))
        (let [(restOk (casePass root rest))]
          (and writeOk outlineOk symbolOk restOk)))))

fn braceStringsPass -> Bool
  (let [(source "func alpha() {\n  value := \"}\"\n  if ready { return value }\n}\nfunc beta() {}\n")
        (next (optionOr (stringIndexOf source "\nfunc beta") -1))]
    (and (>= next 0) (= (ex/braceBlockEnd source 0 "go") next)))

fn semicolonEndsStatementPass -> Bool
  (let [(source "x = 1;\n.chain()\nfunc nextFn() {}\n")]
    (= (ex/braceBlockEnd source 0 "go") (+ (optionOr (stringIndexOf source ";") -1) 1)))

fn closeEndTrailingPass -> Bool
  (let [(source "Pair{1, 2};")]
    (= (ex/braceBlockEnd source 0 "go") (stringLength source)))

fn tripleQuoteBodyPass -> Bool
  (let [(source "def f():\n    s = \"\"\"\nclosing at col0\n\"\"\"\n    return 1\ndef g():\n    pass\n")
        (expected (+ (optionOr (stringIndexOf source "return 1") -1) (stringLength "return 1")))]
    (= (ex/pythonBlockEnd source 0) expected))

fn ! runTests -> Bool
  (let [(data (resultOr (fileReadString "asl/packages/asl-forms/tests/fixtures/recorded/outline.asn") ""))
        (rows (filter (fn [(line String)] -> Bool (stringStartsWith? line "(:case")) (stringSplit data "\n")))
        (tmp (optionOr (envGet "TMPDIR") "/tmp"))
        (tempPath (str tmp "/aslForms1-outline-" (stringFromInt64 (monotonicNs))))
        (made (mt (dirCreate tempPath) ((ok _) true) ((err _) false)))
        (temp (if made (resultOr (realPath tempPath) tempPath) tempPath))
        (casesOk (and made (casePass temp rows)))
        (removed (mt (pathRemove temp) ((ok _) true) ((err _) false)))
        (langMap (= (stringJoin
                      (map (fn [(p String)] -> String (ex/languageOf p "#!/usr/bin/env python3\ndef alpha():\n  pass\n"))
                        (list "x.asl" "x.asn" "x.ts" "x.tsx" "x.mts" "x.cts" "x.js" "x.jsx" "x.mjs" "x.cjs"
                              "x.py" "x.go" "x.rs" "x.c" "x.h" "x.java" "x.sh" "x.bash" "x.md" "x.json" "x.yaml" "x.yml" "x.toml" "x.pyw" "x.zsh")) " ")
                    "asl asn typescript typescript typescript typescript javascript javascript javascript javascript python go rust c c java shell shell markdown json yaml yaml toml text text"))
        (shebangMap (= (stringJoin (list (ex/languageOf "script" "#!/usr/bin/env python3\n")
                                         (ex/languageOf "script" "#!/bin/sh\n")
                                         (ex/languageOf "script" "#!/usr/bin/env node\n")
                                         (ex/languageOf "script" "#!/usr/bin/env ruby\n")) " ")
                           "python shell javascript text"))]
    (do
      (assert made "create isolated parity fixture root under TMPDIR")
      (assert (>= (listLength rows) 34) "recorded corpus covers extension, shebang, heredoc, Rust-attribute, shell-brace, bracketed and commented Python variable, generic Rust impl, Rust array type, shell variable, Go comment, masked Go/Rust comment-and-string definitions, dash-named shell functions and indentation-only Python block end cases")
      (assert casesOk "outline and symbol receipts match every recorded legacy output byte for byte")
      (assert langMap "legacy extension map leaves .pyw and .zsh as text and names JSON, YAML and TOML")
      (assert shebangMap "extensionless shebangs map Python, shell and Node, with unknown interpreters as text")
      (assert (braceStringsPass) "a closing brace inside a string does not truncate a brace-language block")
      (assert (semicolonEndsStatementPass) "a bodiless Go statement still ends at its ;")
      (assert (closeEndTrailingPass) "a trailing ; or , right after a closing brace is folded into the block")
      (assert (tripleQuoteBodyPass) "a triple-quoted string keeps a Python def body open across low-indentation lines")
      (assert removed "remove the isolated TMPDIR parity fixtures")
      true))
