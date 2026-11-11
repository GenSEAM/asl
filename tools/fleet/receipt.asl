(module asl-tools/fleet/receipt
  :x [gateRunner! gateReport! auditedHead? receiptRows gateAudit! gateRowComplete claimedOf main Track gateCounts redBeforeCoverage ownsPresent ownsDisjoint overlaps? validateForm checkText]
  :i [(asl-tools/fleet/model :a fm) (asl-parser/reader :a rd) (asl-tools/fleet/run :a fr)])

(schema Track
  (:f name String)
  (:f owns (List String)))

fn has? items: (List rd/SExpr) field: String -> Bool
  (or (some? (fm/kvGet items (str ":" field)))
      (and (= field "name") (some? (fm/kvGet items ":gate"))))

fn requiredOf row: (Option rd/SExpr) -> (List String)
  (match row ((none) (list)) ((some r) (fm/atomsOf (optionOr (fm/kvGet (fm/itemsOf r) ":required") (fm/makeEmpty)))))

fn kindsOf row: (Option rd/SExpr) -> (List String)
  (match row ((none) (list)) ((some r) (fm/atomsOf (optionOr (fm/kvGet (fm/itemsOf r) ":kinds") (fm/makeEmpty)))))

fn nameOf items: (List rd/SExpr) -> String
  (fm/textOf (optionOr (fm/kvGet items ":gate") (optionOr (fm/kvGet items ":suite") (optionOr (fm/kvGet items ":name") (rd/makeAtom "?")))))

fn rowsAt items: (List rd/SExpr) key: String -> (List rd/SExpr)
  (fm/itemsOf (optionOr (fm/kvGet items key) (fm/makeEmpty)))

fn intField items: (List rd/SExpr) key: String -> (Option Int64)
  (fm/intOf (fm/kvGet items key))

fn gateCounts fleet: (List rd/SExpr) items: (List rd/SExpr) -> (List String)
  (let [(gate (fm/entity fleet "Gate"))
        (required (requiredOf gate))
        (kinds (kindsOf gate))
        (gates (rowsAt items ":gates"))]
    (if (listEmpty? gates) (list "no gates")
      (fold (fn [(acc (List String)) (g rd/SExpr)] -> (List String)
              (let [(gi (fm/itemsOf g))
                    (name (nameOf gi))
                    (missing (filter (fn [(f String)] -> Bool (not (has? gi f))) required))
                    (exit (intField gi ":exit"))
                    (executed (intField gi ":executed"))
                    (kind (match (fm/kvGet gi ":kind") ((none) "") ((some k) (fm/textOf k))))]
                (listAppend acc
                  (listAppend (map (fn [(f String)] -> String (str "gate " name ": no :" f)) missing)
                    (listAppend
                      (if (and (has? gi "exit") (none? exit)) (list (str "gate " name ": :exit is not an integer")) (list))
                      (listAppend
                        (if (and (has? gi "executed") (none? executed)) (list (str "gate " name ": :executed is not an integer")) (list))
                        (listAppend
                          (if (and (= exit (some 0)) (= executed (some 0))) (list (str "gate " name ": passed with zero executed assertions")) (list))
                          (if (and (not (stringEmpty? kind)) (not (listContains? kinds kind))) (list (str "gate " name ": kind " kind " is not one of " (stringJoin kinds " "))) (list)))))))))
            (list) gates)))

fn redBeforeCoverage fleet: (List rd/SExpr) items: (List rd/SExpr) -> (List String)
  (let [(required (requiredOf (fm/entity fleet "RedBefore")))
        (proofs (rowsAt items ":redBefore"))
        (newGates (filter (fn [(g rd/SExpr)] -> Bool (= (match (fm/kvGet (fm/itemsOf g) ":new") ((none) "") ((some v) (fm/textOf v))) "true")) (rowsAt items ":gates")))]
    (fold (fn [(acc (List String)) (g rd/SExpr)] -> (List String)
            (let [(name (nameOf (fm/itemsOf g)))
                  (proof (listHead (filter (fn [(p rd/SExpr)] -> Bool (= (nameOf (fm/itemsOf p)) name)) proofs)))]
              (match proof
                ((none) (listAppend acc (list (str "new gate " name ": no red-before run"))))
                ((some p) (let [(pi (fm/itemsOf p))
                                (missing (filter (fn [(f String)] -> Bool (not (has? pi f))) required))]
                            (listAppend acc
                              (listAppend (map (fn [(f String)] -> String (str "red-before of " name ": no :" f)) missing)
                                (if (= (intField pi ":exit") (some 0)) (list (str "red-before of " name ": the gate was green before the change")) (list)))))))))
          (list) newGates))

fn ownsOf items: (List rd/SExpr) -> (List String)
  (fm/atomsOf (optionOr (fm/kvGet items ":owns") (fm/makeEmpty)))

fn ownsPresent fleet: (List rd/SExpr) items: (List rd/SExpr) -> (List String)
  (let [(fields (fm/entityFields fleet "Unit"))]
    (if (not (listContains? fields "owns")) (list "fleet.asn Unit has no owns field")
      (if (listEmpty? (ownsOf items)) (list "no :owns") (list))))

fn trimSlash p: String -> String
  (if (stringEndsWith? p "/") (optionOr (stringSlice p 0 (- (stringLength p) 1)) p) p)

fn overlaps? a: String b: String -> Bool
  (let [(x (trimSlash a)) (y (trimSlash b))]
    (or (= x y) (or (stringStartsWith? x (str y "/")) (stringStartsWith? y (str x "/")))))

fn ownsDisjoint items: (List rd/SExpr) others: (List Track) -> (List String)
  (let [(mine (ownsOf items))]
    (fold (fn [(acc (List String)) (t Track)] -> (List String)
            (listAppend acc
              (fold (fn [(acc2 (List String)) (p String)] -> (List String)
                      (listAppend acc2 (map (fn [(q String)] -> String (str ":owns " p " overlaps " q " of track " t.name))
                                            (filter (fn [(q String)] -> Bool (overlaps? p q)) t.owns))))
                    (list) mine)))
          (list) others))

fn unitOf items: (List rd/SExpr) -> String
  (fm/textOf (optionOr (listGet items 1) (rd/makeAtom "?")))

fn validateForm fleet: (List rd/SExpr) form: rd/SExpr others: (List Track) -> (Pair String (List String))
  (let [(items (fm/itemsOf form))
        (head (fm/atomText (optionOr (listHead items) (fm/makeEmpty))))
        (unit (unitOf items))
        (peers (filter (fn [(t Track)] -> Bool (!= t.name unit)) others))
        (owns (listAppend (ownsPresent fleet items) (ownsDisjoint items peers)))]
    (cond
      ((= head ":receipt")
        (let [(required (requiredOf (fm/entity fleet "Receipt")))
              (missing (map (fn [(f String)] -> String (str "receipt: no :" f)) (filter (fn [(f String)] -> Bool (not (has? items f))) required)))]
          (pair unit (listAppend missing (listAppend owns (listAppend (gateCounts fleet items) (redBeforeCoverage fleet items)))))))
      ((or (= head ":task") (= head ":brief")) (pair unit owns))
      (else (pair unit (list (str "not a receipt or brief: " head))))))

fn tracksOf forms: (List rd/SExpr) -> (List Track)
  (map (fn [(f rd/SExpr)] -> Track (Track :name (unitOf (fm/itemsOf f)) :owns (ownsOf (fm/itemsOf f)))) forms)

fn checkText fleet: (List rd/SExpr) label: String text: String others: (List Track) -> (Result (List String) String)
  (match (fm/parseForms text)
    ((err e) (err (str label " does not read: " e)))
    ((ok forms)
      (if (listEmpty? forms) (err (str label " holds no form"))
        (let [(peers (listAppend others (tracksOf forms)))]
          (ok (map (fn [(f rd/SExpr)] -> String
                     (let [(r (validateForm fleet f peers))
                           (problems (pairSecond r))]
                       (str "(:receiptCheck :file " (fm/asnQuote label) " :unit " (fm/asnQuote (pairFirst r))
                            " :problems " (fm/asnStrings problems) " :verdict " (if (listEmpty? problems) ":valid" ":invalid") ")")))
                   forms))))))

; (:m :ref RECEIPT-GATE-ROW :do "a receipt is accepted as done only with a gate row for the unit's declared ledger gate that carries the command, :exit and :executed; the audit reruns the declared gate itself (run is runShell!+gateOut in main, so its asserts are the host verdict lines) and returns the system (:gateRun ...) row; a missing or incomplete row is gateMissing, a claimed exit or executed count that differs from the rerun is gateMismatch")
fn auditedHead? head: String -> Bool
  (listContains? (list ":receipt" ":report" ":done") head)

fn receiptRows items: (List rd/SExpr) -> (List rd/SExpr)
  (listAppend (rowsAt items ":gates") (listAppend (rowsAt items ":suites") (rowsAt items ":reruns")))
fn rowNames declared: String -> (List String)

  (let [(toks (filter (fn [(t String)] -> Bool (not (stringEmpty? t))) (stringSplit (stringTrim declared) " ")))
        (files (if (and (= (listLength toks) 3) (= (optionOr (listGet toks 1) "") "test")) (list (optionOr (listGet toks 2) "")) (list)))]
    (if (= (listLength files) 1) (list declared (optionOr (listHead files) declared)) (list declared)))

fn gateRowOf items: (List rd/SExpr) declared: String -> (Option rd/SExpr)
  (listHead (filter (fn [(g rd/SExpr)] -> Bool (listContains? (rowNames declared) (nameOf (fm/itemsOf g)))) (receiptRows items)))

fn gateRowComplete items: (List rd/SExpr) declared: String -> Bool
  (match (gateRowOf items declared)
    ((none) false)
    ((some g) (let [(gi (fm/itemsOf g))] (and (some? (intField gi ":exit")) (some? (intField gi ":executed"))))))

fn claimedOf items: (List rd/SExpr) declared: String -> (Pair Int64 Int64)
  (match (gateRowOf items declared)
    ((none) (pair -1 -1))
    ((some g) (pair (optionOr (intField (fm/itemsOf g) ":exit") -1) (optionOr (intField (fm/itemsOf g) ":executed") -1))))

fn ! gateAudit! items: (List rd/SExpr) declared: String run: (fn [(String)] -> (Pair Int64 Int64)) -> (Pair (List String) String)
  (let [(r (run declared))
        (ex (pairFirst r))
        (ks (pairSecond r))
        (claimed (claimedOf items declared))
        (row (str "(:gateRun :by system :gate " (fm/asnQuote declared) " :exit " (stringFromInt64 ex) " :executed " (stringFromInt64 ks) ")"))
        (problems (cond
                    ((not (gateRowComplete items declared)) (list (str "gateMissing: no gate row with command, exit and executed for " declared)))
                    (else (listAppend
                              (cond ((= ex -1) (list "gateTimeout: the rerun did not finish within its limit"))
                                    ((or (!= ex 0) (<= ks 0)) (list (str "gateRed: rerun exit " (stringFromInt64 ex) " executed " (stringFromInt64 ks) ", a done receipt needs exit 0 and executed above 0")))
                                    (else (list)))
                              (if (or (!= (pairFirst claimed) ex) (!= (pairSecond claimed) ks))
                                (list (str "gateMismatch: claimed exit " (stringFromInt64 (pairFirst claimed)) " executed " (stringFromInt64 (pairSecond claimed)) ", rerun exit " (stringFromInt64 ex) " executed " (stringFromInt64 ks)))
                                (list))))))]
    (pair problems row))

fn usage -> String
  "usage: bin/asl run tools/fleet/receipt.asl FILE [--other FILE]... [--fleet asl/grammar/fleet.asn]"

fn otherFiles args: (List String) -> (List String)
  (match (listHead args)
    ((none) (list))
    ((some a) (if (= a "--other")
                (cons (optionOr (listGet args 1) "") (otherFiles (listDrop args 2)))
                (otherFiles (optionOr (listTail args) (list))))))

fn optAt args: (List String) name: String -> (Option String)
  (match (listIndexOf args name) ((none) (none)) ((some i) (listGet args (+ i 1))))

fn ! readTracks paths: (List String) -> (Result (List Track) String)
  (fold (fn [(acc (Result (List Track) String)) (p String)] -> (Result (List Track) String)
          (match acc
            ((err e) (err e))
            ((ok ts) (match (fileReadString p)
                       ((err e) (err (str "--other " p ": " e)))
                       ((ok text) (match (fm/parseForms text)
                                    ((err e) (err (str "--other " p " does not read: " e)))
                                    ((ok forms) (ok (listAppend ts (tracksOf forms))))))))))
        (ok (list)) paths)

; (:m :ref RECEIPT-GATE-ROW :do "the production rerun: runShell! (declared form only, host verdict lines) under a wall limit of sec seconds, a run killed by its limit answers exit -1 executed -1, which gateAudit! names gateTimeout")
fn ! gateRunner! cwd: String sec: Int64 -> (fn [(String)] -> (Pair Int64 Int64))
  (fn [(c String)] -> (Pair Int64 Int64)
    (let [(d (fr/runShell! c cwd (fr/childEnv (list)) (fr/limits sec 200)))]
      (if (or (= d.verdict "timeout") (= d.verdict "runaway")) (pair -1 -1) (pair d.exit (optionOr (fr/executedOf d.out) 0)))))

fn ! gateReport! text: String gate: String cwd: String sec: Int64 -> Int64
  (if (stringEmpty? gate) 0
    (match (fm/parseForms text)
      ((err e) (do (println (str "(:receiptGate :problems " (fm/asnStrings (list (str "gateUnparsed: " e))) " :verdict :rejected)")) 1))
      ((ok forms)
        (let [(audited (filter (fn [(f rd/SExpr)] -> Bool (auditedHead? (fm/atomText (optionOr (listHead (fm/itemsOf f)) (fm/makeEmpty))))) forms))]
          (if (listEmpty? audited)
            (do (println (str "(:receiptGate :problems " (fm/asnStrings (list "gateNoForm: no :receipt, :report or :done form to audit")) " :verdict :rejected)")) 1)
            (fold (fn [(acc Int64) (f rd/SExpr)] -> Int64
                    (let [(items (fm/itemsOf f))
                          (a (gateAudit! items gate (gateRunner! cwd sec)))]
                      (do (println (str "(:receiptGate :unit " (fm/asnQuote (unitOf items)) " :problems " (fm/asnStrings (pairFirst a)) " :run " (pairSecond a) " :verdict " (if (listEmpty? (pairFirst a)) ":accepted" ":rejected") ")"))
                          (if (listEmpty? (pairFirst a)) acc (+ acc 1)))))
                  0 audited))))))


fn ! main args: (List String) -> (Result Int64 String)
  (let [(file (optionOr (listHead args) ""))
        (fleetFile (optionOr (optAt args "--fleet") (fm/fleetPath)))
        (fail (fn [(msg String)] -> (Result Int64 String) (do (eprintln (str "receipt: " msg)) (eprintln (usage)) (ok 2))))
        (secRaw (optionOr (optAt args "--gate-sec") ""))
        (gateSec (if (stringEmpty? secRaw) 600 (optionOr (stringToInt64 secRaw) 0)))]
    (if (or (stringEmpty? file) (stringStartsWith? file "--")) (fail "FILE is required")
    (if (or (< gateSec 1) (> gateSec 3600)) (fail (str "--gate-sec must be an integer in 1..3600, got " secRaw))
      (match (fm/load fleetFile)
        ((err e) (fail e))
        ((ok fleet) (match (readTracks (otherFiles args))
          ((err e) (fail e))
          ((ok others) (match (fileReadString file)
            ((err e) (fail (str file ": " e)))
            ((ok text) (match (checkText fleet file text others)
              ((err e) (if (stringEmpty? (optionOr (optAt args "--gate") "")) (fail e) (do (println (str "(:receiptGate :problems " (fm/asnStrings (list (str "gateUnparsed: " e))) " :verdict :rejected)")) (ok 1))))
              ((ok lines) (let [(bad (gateReport! text (optionOr (optAt args "--gate") "") (optionOr (optAt args "--cwd") ".") gateSec))]
                            (do (println (stringJoin lines "\n"))
                              (ok (if (or (> bad 0) (some? (listHead (filter (fn [(l String)] -> Bool (stringContains? l ":verdict :invalid")) lines)))) 1 0)))))))))))))))
