(module asl-intel/lintOp
  :x [LintRow lintHitsForFile! lintTree! runLint!]
  :i [(asl-intel/text :a t)
      (asl-intel/host :a h)
      (asl-intel/deadcode :a dc)
      (asl-intel/json :a j)
      (asl-parser/ast :a a)
      (asl-checker/lint :a lint)])

(schema LintRow (:f file String) (:f fnName String) (:f line Int64) (:f hint String))

fn escAsn s: String -> String
  (stringReplace (stringReplace s "\\" "\\\\") "\"" "\\\"")

fn rowOf path: String hit: lint/LintHit -> LintRow
  (LintRow :file path :fnName hit.fnName :line hit.line :hint hit.message)

fn ! lintHitsForFile! path: String -> (List LintRow)
  (mt (fileRead path)
    ((err _) (list))
    ((ok src) (mt (a/parseForChecker src)
                ((err _) (list))
                ((ok forms) (map (fn [(hit lint/LintHit)] -> LintRow (rowOf path hit)) (lint/lintModule forms path))))))

fn ! lintTreeStep! files: (List String) acc: (List LintRow) -> (List LintRow)
  (mt (listHead files)
    ((none) acc)
    ((some p) (lintTreeStep! (optionOr (listTail files) (list)) (listAppend acc (lintHitsForFile! p)))))

fn ! lintTree! ctx: h/Ctx -> (Result (List LintRow) String)
  (mt (dc/walkIgnoring! ctx ctx.home)
    ((err e) (err e))
    ((ok files) (ok (lintTreeStep! files (list)))))

fn formatLintAsn rows: (List LintRow) -> String
  (t/joinWith (list "(:lintAudit" "  :status :ok"
                    (str "  :count " (t/intStr (listLength rows)))
                    (if (listEmpty? rows) "  :rows []"
                      (str "  :rows [\n    "
                           (t/joinWith (map (fn [(r LintRow)] -> String (str "(:lint :code LINT_QUADRATIC_LISTGET :file \"" (escAsn r.file) "\" :fn " r.fnName " :line " (t/intStr r.line) " :hint \"" (escAsn r.hint) "\")")) rows) "\n    ")
                           "\n  ]"))
                    ")")
              "\n")

fn formatLintSummary rows: (List LintRow) -> String
  (t/joinWith (listAppend
                (list "=== ASL IDIOM LINT: LINT_QUADRATIC_LISTGET ===" (str "Sites: " (t/intStr (listLength rows))))
                (map (fn [(r LintRow)] -> String (str "  • " r.file ":" (t/intStr r.line) " " r.fnName)) rows))
              "\n")

fn lintJson rows: (List LintRow) -> j/Json
  (j/jObj (list (pair "status" (j/jStr "ok"))
                (pair "count" (j/jInt (listLength rows)))
                (pair "rows" (j/jArr (map (fn [(r LintRow)] -> j/Json (j/jObj (list (pair "code" (j/jStr "LINT_QUADRATIC_LISTGET")) (pair "file" (j/jStr r.file)) (pair "fn" (j/jStr r.fnName)) (pair "line" (j/jInt r.line)) (pair "hint" (j/jStr r.hint))))) rows)))))

fn renderRows fmt: String rows: (List LintRow) -> String
  (cond ((= fmt "json") (j/dumps (lintJson rows))) ((= fmt "summary") (formatLintSummary rows)) (else (formatLintAsn rows)))

fn ! runLint! ctx: h/Ctx fmt: String target: String -> h/Outcome
  (mt (if (stringEmpty? target) (lintTree! ctx) (ok (lintHitsForFile! (t/absPath target ctx.cwd))))
    ((err e) (h/outcome "" (str "Error: " e "\n") 1))
    ((ok rows) (h/outcome (str (renderRows fmt rows) "\n") "" 0)))
