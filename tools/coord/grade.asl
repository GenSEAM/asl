(module asl-tools/coord/grade
  :x [Candidate Writer Source Plan planGo planRefused familyOf pickGrader receiptProblems constantProblems preChecks plan planWith planGated! gateProblems! runRow gradeRow statsProblems]
  :i [(tools/fleet/model :a fm) (tools/fleet/receipt :a rc) (asl-parser/reader :a rd) (asl-parser/ast :a ast) (asl-checker/constAssert :a ca) (asl-checker/types :a ty)])

(schema Candidate
  (:f channel String)
  (:f model String)
  (:f available Bool))

(schema Writer
  (:f unit String)
  (:f channel String)
  (:f model String))

(schema Source
  (:f path String)
  (:f text String))

(enum Plan
  (:c planGo [(grader Candidate)] "pre-checks passed and a grader is eligible; the model call may be made")
  (:c planRefused [(row String) (problems (List String))] "refused before any model call; row is the (:grade ...) reject row"))

fn anyIn? text: String needles: (List String) -> Bool
  (some? (listHead (filter (fn [(n String)] -> Bool (stringContains? text n)) needles)))

fn familyOf model: String -> String
  (let [(l (stringLower model))]
    (cond
      ((stringEmpty? l) "")
      ((anyIn? l (list "gemini" "flash" "gemma")) "google")
      ((anyIn? l (list "claude" "opus" "sonnet" "haiku")) "anthropic")
      ((anyIn? l (list "gpt" "luna" "codex")) "openai")
      ((anyIn? l (list "deepseek")) "deepseek")
      ((anyIn? l (list "glm")) "zhipu")
      ((anyIn? l (list "qwen")) "alibaba")
      (else l)))

fn reasonAgainst w: Writer c: Candidate -> (Option String)
  (cond
    ((not c.available) (some (str c.channel "/" c.model ": unavailable")))
    ((stringEmpty? (familyOf c.model)) (some (str c.channel "/" c.model ": unknown model family")))
    ((= c.channel w.channel) (some (str c.channel "/" c.model ": same channel as the writer")))
    ((= (familyOf c.model) (familyOf w.model)) (some (str c.channel "/" c.model ": same model family as the writer")))
    (else (none)))

fn reasonsAgainst w: Writer cs: (List Candidate) -> (List String)
  (fold (fn [(acc (List String)) (c Candidate)] -> (List String)
          (match (reasonAgainst w c) ((none) acc) ((some r) (listAppend acc (list r)))))
        (list) cs)

fn pickGrader w: Writer cs: (List Candidate) -> (Result Candidate String)
  (cond
    ((stringEmpty? (familyOf w.model)) (err (str "writer " w.channel "/" w.model ": unknown model family")))
    (else
      (match (listHead (filter (fn [(c Candidate)] -> Bool (none? (reasonAgainst w c))) cs))
        ((some c) (ok c))
        ((none) (err (str "no eligible grader: " (stringJoin (reasonsAgainst w cs) "; ")))))))

fn rowsAt items: (List rd/SExpr) key: String -> (List rd/SExpr)
  (fm/itemsOf (optionOr (fm/kvGet items key) (fm/makeEmpty)))

fn gateRan? g: rd/SExpr -> Bool
  (let [(gi (fm/itemsOf g))
        (exit (fm/intOf (fm/kvGet gi ":exit")))
        (executed (fm/intOf (fm/kvGet gi ":executed")))]
    (and (some? exit) (> (optionOr executed 0) 0)))

fn gateName g: rd/SExpr -> String
  (fm/textOf (optionOr (fm/kvGet (fm/itemsOf g) ":gate") (optionOr (fm/kvGet (fm/itemsOf g) ":name") (rd/makeAtom "?"))))

fn neverRan items: (List rd/SExpr) -> (List String)
  (map (fn [(g rd/SExpr)] -> String (str "gate " (gateName g) ": never ran (no exit or zero executed assertions)"))
       (filter (fn [(g rd/SExpr)] -> Bool (not (gateRan? g))) (rowsAt items ":gates")))

fn receiptProblems fleet: (List rd/SExpr) text: String -> (List String)
  (match (fm/parseForms text)
    ((err e) (list (str "receipt does not parse: " e)))
    ((ok forms)
      (match (listHead forms)
        ((none) (list "receipt holds no form"))
        ((some form)
          (let [(items (fm/itemsOf form))
                (noRed (if (listEmpty? (rowsAt items ":redBefore")) (list "no redBefore receipt") (list)))]
            (listAppend noRed
              (listAppend (neverRan items)
                (pairSecond (rc/validateForm fleet form (list))))))))))

fn constantProblems sources: (List Source) -> (List String)
  (fold (fn [(acc (List String)) (s Source)] -> (List String)
          (match (ast/parseForChecker s.text)
            ((err e) (listAppend acc (list (str s.path ": gate source does not parse"))))
            ((ok forms)
              (listAppend acc
                (map (fn [(d ty/Diagnostic)] -> String (str s.path ": constant gate assertion: " d.message))
                     (ca/constantAssertDiags forms s.text s.path))))))
        (list) sources)

fn preChecks fleet: (List rd/SExpr) text: String sources: (List Source) -> (List String)
  (listAppend (receiptProblems fleet text) (constantProblems sources))

fn bad? s: String -> Bool
  (anyIn? s (list " " "(" ")" "\"" ";" "\n" "\t"))

fn atom s: String -> String
  (if (or (stringEmpty? s) (bad? s)) (fm/asnQuote s) s)

fn runRow unit: String worker: String model: String outcome: String grade: String commits: Int64 exit: Int64 wallMin: Int64 note: String -> String
  (str "(:run :unit " (atom unit) " :worker " (atom worker) " :model " (fm/asnQuote model)
       (if (< wallMin 0) "" (str " :wallMin " wallMin))
       (if (< commits 0) "" (str " :commits " commits))
       (if (< exit 0) "" (str " :exit " exit))
       " :outcome " (atom outcome) " :grade " (atom grade)
       (if (stringEmpty? note) "" (str " :note " (fm/asnQuote note))) ")")

fn gradeRow unit: String graderChannel: String graderModel: String writerChannel: String verdict: String note: String -> String
  (str "(:grade :unit " (atom unit) " :worker " (atom graderChannel) " :model " (fm/asnQuote graderModel)
       " :writer " (atom writerChannel) " :verdict " (atom verdict)
       (if (stringEmpty? note) "" (str " :note " (fm/asnQuote note))) ")")

fn plan w: Writer fleet: (List rd/SExpr) receipt: String sources: (List Source) cs: (List Candidate) -> Plan
  (planWith w (preChecks fleet receipt sources) cs)

fn planWith w: Writer problems: (List String) cs: (List Candidate) -> Plan
  (if (not (listEmpty? problems))
    (planRefused (gradeRow w.unit "none" "none" w.channel "reject" (str "refused before any model call: " (stringJoin problems "; "))) problems)
    (match (pickGrader w cs)
      ((err e) (planRefused (gradeRow w.unit "none" "none" w.channel "pending" e) (list e)))
      ((ok c) (planGo c))))

; (:m :ref RECEIPT-GATE-ROW :do "the receipt is graded only after the unit's declared ledger gate was rerun through receipt gateAudit!: no declared gate, no complete gate row for it, a red or timed-out rerun, or a claimed count that differs from the rerun refuses the plan before any model call; plan stays the pure structural check")
fn ! gateProblems! receipt: String gate: String run: (fn [(String)] -> (Pair Int64 Int64)) -> (List String)
  (if (stringEmpty? gate) (list "gateMissing: the unit declares no ledger gate to rerun")
    (match (fm/parseForms receipt)
      ((err e) (list (str "gateUnparsed: " e)))
      ((ok forms)
        (match (listHead (filter (fn [(f rd/SExpr)] -> Bool (rc/auditedHead? (fm/atomText (optionOr (listHead (fm/itemsOf f)) (fm/makeEmpty))))) forms))
          ((none) (list "gateNoForm: no :receipt, :report or :done form to audit"))
          ((some f) (pairFirst (rc/gateAudit! (fm/itemsOf f) gate run)))))))

fn ! planGated! w: Writer fleet: (List rd/SExpr) receipt: String sources: (List Source) cs: (List Candidate) gate: String run: (fn [(String)] -> (Pair Int64 Int64)) -> Plan
  (planWith w (listAppend (preChecks fleet receipt sources) (gateProblems! receipt gate run)) cs)

fn oneOf? v: String allowed: (List String) -> Bool
  (listContains? allowed v)

fn missingKeys items: (List rd/SExpr) keys: (List String) -> (List String)
  (map (fn [(k String)] -> String (str "no " k))
       (filter (fn [(k String)] -> Bool (none? (fm/kvGet items k))) keys))

fn enumProblem items: (List rd/SExpr) key: String allowed: (List String) -> (List String)
  (match (fm/kvGet items key)
    ((none) (list))
    ((some v) (if (oneOf? (fm/textOf v) allowed) (list) (list (str key " " (fm/textOf v) " is not one of " (stringJoin allowed " "))))))

fn statsProblems text: String -> (List String)
  (match (fm/parseForms text)
    ((err e) (list (str "does not parse: " e)))
    ((ok forms)
      (match (listHead forms)
        ((none) (list "holds no form"))
        ((some f)
          (let [(items (fm/itemsOf f))
                (head (fm/atomText (optionOr (listHead items) (fm/makeEmpty))))
                (grades (list "accept" "acceptWithFixes" "reject" "pending"))
                (workers (list "agy" "leon" "claude" "codex"))]
            (cond
              ((= head ":run")
                (listAppend (missingKeys items (list ":unit" ":worker" ":model"))
                  (listAppend (enumProblem items ":worker" workers)
                    (listAppend (enumProblem items ":outcome" (list "done" "partial" "hung" "failed"))
                      (enumProblem items ":grade" grades)))))
              ((= head ":grade")
                (listAppend (missingKeys items (list ":unit" ":worker" ":model" ":writer" ":verdict"))
                  (listAppend (enumProblem items ":worker" (listAppend workers (list "none")))
                    (listAppend (enumProblem items ":writer" workers)
                      (enumProblem items ":verdict" grades)))))
              (else (list (str "not a :run or :grade row: " head)))))))))
