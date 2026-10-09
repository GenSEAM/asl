(module asl-parser/selfParseTest
  :x [runTests]
  :i [(asl-parser/ast :a a) (asl-parser/reader :a rd) (asl-parser/indentParser :a ip)])

(schema ClosureModule (:f path String))

fn closureModules -> (List ClosureModule)
  (list
    (ClosureModule :path "asl/packages/asl-compiler/src/compiler.asl")
    (ClosureModule :path "asl/packages/asl-parser/src/ast.asl")
    (ClosureModule :path "asl/packages/asl-checker/src/types.asl")
    (ClosureModule :path "asl/packages/asl-checker/src/check.asl")
    (ClosureModule :path "asl/packages/asl-checker/src/resolve.asl")
    (ClosureModule :path "asl/packages/asl-codegen/src/c99Emit.asl")
    (ClosureModule :path "asl/packages/asl-codegen/src/c99Mangle.asl")
    (ClosureModule :path "asl/packages/asl-target-llvm/src/main.asl")
    (ClosureModule :path "asl/packages/asl-ir/src/types.asl")
    (ClosureModule :path "asl/packages/asl-parser/src/lexer.asl")
    (ClosureModule :path "asl/packages/asl-parser/src/reader.asl")
    (ClosureModule :path "asl/packages/asl-parser/src/indentParser.asl")
    (ClosureModule :path "asl/packages/asl-checker/src/unify.asl")
    (ClosureModule :path "asl/packages/asl-codegen/src/c99Type.asl")
    (ClosureModule :path "asl/packages/asl-codegen/src/c99Expr.asl")
    (ClosureModule :path "asl/packages/asl-target-llvm/src/types.asl")
    (ClosureModule :path "asl/packages/asl-target-llvm/src/emit.asl")
    (ClosureModule :path "asl/packages/asl-parser/src/indentLexer.asl")
    (ClosureModule :path "asl/packages/asl-ir/src/verify.asl")
    (ClosureModule :path "asl/packages/asl-ir/src/anf.asl"))

fn hostCount! path: String -> (Result Int64 String)
  (let [(run (processRun (str "asl/host/out/asl-host parse " path)))]
    (if (!= run.exitCode 0)
      (err (str "asl-host parse exited " (stringFromInt64 run.exitCode) ": " run.stderr))
      (mt (stringToInt64 (optionOr (listHead (stringSplit (stringTrim run.stdout) " ")) ""))
        ((some n) (ok n))
        ((none) (err (str "asl-host parse printed " run.stdout))))))

fn testOneModule! m: ClosureModule -> Bool
  (mt (hostCount! m.path)
    ((err e) (do (assert false (str m.path ": " e)) false))
    ((ok expected)
      (mt (fileRead m.path)
        ((err e) (do (assert false (str "Failed to read " m.path ": " e)) false))
        ((ok src)
          (mt (a/parse src)
            ((err pe) (do (assert false (str "Parse failed for " m.path ": " pe.msg " at " (stringFromInt64 pe.line) ":" (stringFromInt64 pe.col))) false))
            ((ok forms)
              (do
                (assert (= (listLength forms) expected) (str m.path " parsed " (stringFromInt64 (listLength forms)) " forms, asl-host parse reads " (stringFromInt64 expected)))
                true)))))))

fn testCompilerClosureModules! -> Bool
  (let [(mods (closureModules))
        (results (map (fn [(m ClosureModule)] -> Bool (testOneModule! m)) mods))]
    (do
      (assert (= (listLength mods) 20) "Compiler closure lists exactly 20 modules")
      (assert (fold (fn [(acc Bool) (b Bool)] -> Bool (and acc b)) true results) "All 20 compiler closure modules parse with host form counts")
      true))

fn getTopDefun forms: (List a/TopForm) idx: Int64 -> (Option a/DefunNode)
  (mt (listGet forms idx)
    ((none) (none))
    ((some tf)
      (mt tf
        ((a/topDefun d) (some d))
        (_ (none)))))

fn testComparisonOperators -> Bool
  (let [(src (str "(module t/cmp :x [f])\n" "\n" "fn f n: Int64 -> Bool\n" "  (<= n 1)\n" "  (>= n 1)\n" "  (!= n 1)\n" "  (== n 1)\n"))
        (res (a/parse src))]
    (mt res
      ((err pe) (do (assert false (str "Parse error in comparison operators: " pe.msg)) false))
      ((ok forms)
        (mt (getTopDefun forms 1)
          ((none) (do (assert false "Expected topDefun at index 1") false))
          ((some d)
            (let [(b d.body)]
              (do
                (assert (= (listLength b) 4) "Defun has 4 body expressions")
                (assert (= (rd/sexprHead (optionOr (listGet b 0) (rd/makeAtom ""))) "<=") "<= recognized")
                (assert (= (rd/sexprHead (optionOr (listGet b 1) (rd/makeAtom ""))) ">=") ">= recognized")
                (assert (= (rd/sexprHead (optionOr (listGet b 2) (rd/makeAtom ""))) "!=") "!= recognized")
                (assert (= (rd/sexprHead (optionOr (listGet b 3) (rd/makeAtom ""))) "==") "== recognized")
                true)))))))

fn testMultilineLetAndDoBodies -> Bool
  (do
    (let [(srcLet (str "(module t/multilet :x [f])\n" "\n" "fn f x: Int64 -> Int64\n" "  (let [(y 1)]\n" "    (+ x y))\n"))
          (resLet (a/parse srcLet))]
      (mt resLet
        ((err pe) (do (assert false (str "Parse error in multi-line let: " pe.msg)) false))
        ((ok forms)
          (mt (getTopDefun forms 1)
            ((none) (do (assert false "Expected topDefun for let") false))
            ((some d)
              (let [(b d.body)]
                (do
                  (assert (= (listLength b) 1) "Multi-line let body parsed as single expression")
                  (assert (= (rd/sexprHead (optionOr (listHead b) (rd/makeAtom ""))) "let") "Body head is let")
                  true)))))))
    (let [(srcDo (str "(module t/multido :x [g])\n" "\n" "fn g x: Int64 -> Int64\n" "  (do\n" "    (let [(a 1)]\n" "      (+ a x)))\n"))
          (resDo (a/parse srcDo))]
      (mt resDo
        ((err pe) (do (assert false (str "Parse error in multi-line do: " pe.msg)) false))
        ((ok forms)
          (mt (getTopDefun forms 1)
            ((none) (do (assert false "Expected topDefun for do") false))
            ((some d)
              (let [(b d.body)]
                (do
                  (assert (= (listLength b) 1) "Multi-line do body parsed as single expression")
                  (assert (= (rd/sexprHead (optionOr (listHead b) (rd/makeAtom ""))) "do") "Body head is do")
                  true)))))))
    true)

fn testRecordConstructors -> Bool
  (let [(src (str "(module t/rec :x [p])\n" "\n" "fn p -> Point\n" "  (Point\n" "    :x 10\n" "    :y 20)\n"))
        (res (a/parse src))]
    (mt res
      ((err pe) (do (assert false (str "Parse error in record constructor: " pe.msg)) false))
      ((ok forms)
        (mt (getTopDefun forms 1)
          ((none) (do (assert false "Expected topDefun for rec") false))
          ((some d)
            (let [(b d.body)]
              (do
                (assert (= (listLength b) 1) "Record constructor parsed as single expression")
                (assert (= (rd/sexprHead (optionOr (listHead b) (rd/makeAtom ""))) "Point") "Constructor name is Point")
                true)))))))

fn testMultilineParenExpr -> Bool
  (let [(src (str "(module t/paren :x [calc])\n" "\n" "fn calc a: Int64 b: Int64 -> Int64\n" "  (+\n" "    (* a 2)\n" "    (* b 3))\n"))
        (res (a/parse src))]
    (mt res
      ((err pe) (do (assert false (str "Parse error in multi-line paren expr: " pe.msg)) false))
      ((ok forms)
        (mt (getTopDefun forms 1)
          ((none) (do (assert false "Expected topDefun for paren") false))
          ((some d)
            (let [(b d.body)]
              (do
                (assert (= (listLength b) 1) "Multi-line paren expr is a single expression")
                (let [(expr (optionOr (listHead b) (rd/makeAtom "")))
                      (items (rd/sexprToList expr))]
                  (do
                    (assert (= (rd/sexprHead expr) "+") "Outer head is +")
                    (assert (= (listLength items) 3) "Outer expression has 3 items (+ arg1 arg2)")
                    true)))))))))

fn testEscapeNewlineInString -> Bool
  (let [(src (str "(module t/str :x [s])\n" "\n" "fn s -> String\n" "  \"hello\\nworld\"\n"))
        (res (a/parse src))]
    (mt res
      ((err pe) (do (assert false (str "Parse error in string with newline: " pe.msg)) false))
      ((ok forms)
        (mt (getTopDefun forms 1)
          ((none) (do (assert false "Expected topDefun for str") false))
          ((some d)
            (let [(b d.body)
                  (expr (optionOr (listHead b) (rd/makeAtom "")))]
              (do
                (assert (= (rd/sexprHead expr) "\"hello\\nworld\"") "the string atom keeps its source text, backslash-n included")
                (refute (= (rd/sexprHead expr) "\"hellonworld\"") "Backslash not stripped before n")
                true)))))))

fn testParamCompositeType -> Bool
  (let [(src (str "(module t/param :x [p])\n" "\n" "fn p opt: (Option Int64) -> Int64\n" "  0\n"))
        (res (a/parse src))]
    (mt res
      ((err pe) (do (assert false (str "Parse error in composite param type: " pe.msg)) false))
      ((ok forms)
        (mt (getTopDefun forms 1)
          ((none) (do (assert false "Expected topDefun for param") false))
          ((some d)
            (let [(params d.params)]
              (do
                (assert (= (listLength params) 1) "Defun has 1 parameter")
                (let [(p0 (optionOr (listHead params) (a/Param :name "" :type "")))]
                  (do
                    (assert (= p0.name "opt") "Param name is opt")
                    (assert (= p0.type "(Option Int64)") "Composite type (Option Int64) is preserved intact")
                    (refute (= p0.type "Option") "Param type is not reduced to bare Option")
                    true)))))))))

fn testMtPreservedNotRenamed -> Bool
  (do
    (let [(src (str "(module t/match :x [m])\n" "\n" "fn m o: (Option Int64) -> Int64\n" "  (mt o ((some v) v) ((none) 0))\n"))
          (res (a/parse src))]
      (mt res
        ((err pe) (do (assert false (str "Parse error in mt preservation: " pe.msg)) false))
        ((ok forms)
          (mt (getTopDefun forms 1)
            ((none) (do (assert false "Expected topDefun for mt") false))
            ((some d)
              (let [(b d.body)
                    (firstExpr (optionOr (listHead b) (rd/makeAtom "")))]
                (do
                  (assert (= (rd/sexprHead firstExpr) "mt") "Head is mt, preserved exactly as written")
                  (refute (= (rd/sexprHead firstExpr) "match") "mt is not renamed to match")
                  true)))))))
    (let [(srcParen (str "(module t/match :x [m])\n" "(fn m [o] -> Int64\n" "  (mt o ((some v) v) ((none) 0)))\n"))
          (resParen (a/parse srcParen))]
      (mt resParen
        ((err pe) (do (assert false (str "Parse error in paren mt: " pe.msg)) false))
        ((ok forms)
          (mt (getTopDefun forms 1)
            ((none) (do (assert false "Expected topDefun for paren mt") false))
            ((some d)
              (let [(b d.body)
                    (firstExpr (optionOr (listHead b) (rd/makeAtom "")))]
                (do
                  (assert (= (rd/sexprHead firstExpr) "mt") "Head is mt in paren dialect")
                  (refute (= (rd/sexprHead firstExpr) "match") "mt is not renamed to match in paren dialect")
                  true)))))))
    true)

fn posText pf: a/PosForm -> String
  (str (stringFromInt64 pf.line) ":" (stringFromInt64 pf.col))

fn bodyPosOf src: String -> (List String)
  (mt (a/parse src)
    ((err pe) (list (str "parse error " pe.msg)))
    ((ok forms) (mt (getTopDefun forms 1) ((none) (list "no defun")) ((some d) (map posText d.bodyPos)))))

fn docOf src: String -> String
  (mt (a/parse src) ((err pe) (str "parse error " pe.msg)) ((ok forms) (mt (getTopDefun forms 1) ((none) "no defun") ((some d) d.docstring))))

fn testBodySourcePositions -> Bool
  (let [(indented (str "(module t/pos :x [p])\n" "\n" "fn p x: Int64 -> Int64\n" "  (let [(y 1)]\n" "    (+ x y))\n" "  (+ x\n" "     2)\n" "  x\n"))
        (paren (str "(module t/pos :x [q])\n" "(fn q [(x Int64)] -> Int64\n" "  (+ x\n" "     1)\n" "  x)\n"))]
    (do
      (assert (= (bodyPosOf indented) (list "4:3" "6:3" "8:3")) (str "indented body forms sit at 4:3 6:3 8:3, got " (stringJoin (bodyPosOf indented) " ")))
      (assert (stringStartsWith? (docOf (str "(module t/pos :x [p])\n\nfn p x: Int64 -> Int64\n  :d \"Doc line\"\n  x\n")) "parse error ERR_READ_DOC") (str "a :d first body line is a read error, got " (docOf indented)))
      (assert (= (bodyPosOf paren) (list "3:3" "5:3")) (str "paren body forms sit at 3:3 5:3, got " (stringJoin (bodyPosOf paren) " ")))
      true))

fn declLineCount src: String -> Int64
  (listLength (filter (fn [(l String)] -> Bool (or (stringStartsWith? l "fn ") (or (stringStartsWith? l "enum ") (stringStartsWith? l "schema ")))) (stringSplit src "\n")))

fn testPreludeParses! -> Bool
  (mt (fileRead "asl/prelude/prelude.asl")
    ((err e) (do (assert false (str "read prelude: " e)) false))
    ((ok src)
      (mt (a/parse src)
        ((err pe) (do (assert false (str "prelude.asl:" (stringFromInt64 pe.line) ":" (stringFromInt64 pe.col) ": " pe.msg)) false))
        ((ok forms)
          (do
            (assert (= (- (listLength forms) 1) (declLineCount src)) (str "prelude: one declaration per column-0 fn/enum/schema line (" (stringFromInt64 (declLineCount src)) "), got " (stringFromInt64 (- (listLength forms) 1))))
            true)))))

fn testNonAsciiStringKeepsLine -> Bool
  (let [(src (str "(module t/u :x [f g])\n" "\n" "fn f -> String\n" "  (str \"À\" \"¿\")\n" "\n" "fn g -> Int64\n" "  1\n"))]
    (mt (a/parse src)
      ((err pe) (do (assert false (str "non-ASCII string: " pe.msg)) false))
      ((ok forms)
        (do
          (assert (= (listLength forms) 3) (str "a line with multi-byte characters is read to its end, forms " (stringFromInt64 (listLength forms))))
          (mt (getTopDefun forms 1)
            ((none) (assert false "f is a defun"))
            ((some d) (assert (= (rd/renderSexpr (optionOr (listHead d.body) (rd/makeAtom ""))) "(str \"À\" \"¿\")") "the multi-byte string literals survive intact")))
          true))))

fn ! runTests -> Bool
  (do
    (assert (testCompilerClosureModules!) "testCompilerClosureModules")
    (assert (testComparisonOperators) "testComparisonOperators")
    (assert (testMultilineLetAndDoBodies) "testMultilineLetAndDoBodies")
    (assert (testRecordConstructors) "testRecordConstructors")
    (assert (testMultilineParenExpr) "testMultilineParenExpr")
    (assert (testEscapeNewlineInString) "testEscapeNewlineInString")
    (assert (testParamCompositeType) "testParamCompositeType")
    (assert (testMtPreservedNotRenamed) "testMtPreservedNotRenamed")
    (assert (testBodySourcePositions) "testBodySourcePositions")
    (assert (testPreludeParses!) "testPreludeParses")
    (assert (testNonAsciiStringKeepsLine) "testNonAsciiStringKeepsLine")
    true)
