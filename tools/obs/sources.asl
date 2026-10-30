(module ws/asl/tools/obs/sources
  :x [Ctx gatewayRow benchRow freshRow condRow journalObs receiptObs calRows outcomeOf finalize splitFraction]
  :i [(ws/asl/tools/obs/sx :a sx)
      (ws/asl/tools/obs/obs :a ob)
      (ws/asl/tools/obs/filter :a flt)
      (ws/asl/tools/obs/classify :a cl)])

; (:m :ref OBSCORPUS :do "one pure normaliser per source: text in, observations out, no IO; the run context carries the class table, the host label, the file time and the run label, and the only free text that survives is the filtered first error line")
(schema Ctx
  (:f table (List cl/FailClass))
  (:f host String)
  (:f mtime Int64)
  (:f run String))

fn sOf f: (List (Pair String String)) k: String -> String
  (optionOr (sx/field f k) "")

fn finalize ctx: Ctx o: ob/Obs blob: String -> ob/Obs
  (let [(text (flt/safeText blob))
        (cls (if (= o.outcome "ok") "none" (cl/classify ctx.table text)))]
    (with o :model (if (stringEmpty? o.model) "unknown" o.model) :host ctx.host :sig (cl/normSig text) :failClass cls :family (ob/familyOf (if (stringEmpty? o.family) o.model o.family))))

fn outcomeOf raw: String -> String
  (if (= raw "ok") "ok" "infra")

fn gatewayRow ctx: Ctx line: String -> (Option ob/Obs)
  (if (not (stringStartsWith? line "(:call "))
    none
    (let [(f (sx/topFields line))
          (raw (sOf f ":outcome"))]
      (some (finalize ctx
              (with (ob/blankObs) :at (sx/intField f ":at") :source "gateway" :run (if (stringEmpty? (sOf f ":session")) (sOf f ":profile") (sOf f ":session")) :turn (sx/intField f ":turn") :unitId (sOf f ":provider")
                    :model (sOf f ":alias") :family (sOf f ":model") :intent (sOf f ":intent") :card (sOf f ":sysHash")
                    :temperature (sOf f ":temperature") :tokensIn (sx/intField f ":in") :tokensOut (sx/intField f ":out")
                    :ms (sx/intField f ":ms") :outcome (outcomeOf raw))
              (str "gateway " raw)))))

fn benchRow ctx: Ctx line: String -> (Option ob/Obs)
  (if (not (stringStartsWith? line "(:benchRun "))
    none
    (let [(f (sx/topFields line))
          (pass (= (sOf f ":pass") "true"))
          (why (optionOr (listHead (sx/listItems (optionOr (sx/fieldRaw f ":why") "()"))) ""))]
      (some (finalize ctx
              (with (ob/blankObs) :at ctx.mtime :source "bench" :run ctx.run :unitId (str (sOf f ":client") "/" (sOf f ":arm"))
                    :caseId (sOf f ":case") :model (sOf f ":model") :card (str "arm" (sOf f ":arm")) :turn (sx/intField f ":turns")
                    :tokensIn (sx/intField f ":in") :tokensOut (sx/intField f ":out") :ms (* 1000 (sx/intField f ":secs"))
                    :outcome (if pass "ok" "fail") :exitCode (sx/intField f ":exit"))
              (sx/unq why)))))

fn freshRow ctx: Ctx line: String -> (Option ob/Obs)
  (if (not (stringStartsWith? line "(:fb "))
    none
    (let [(f (sx/topFields line))
          (pass (= (sOf f ":pass") "true"))]
      (some (finalize ctx
              (with (ob/blankObs) :at ctx.mtime :source "fresh" :run ctx.run :unitId (str "rep" (sOf f ":rep")) :caseId (sOf f ":case")
                    :model "unattributed" :card (sOf f ":variant") :turn (sx/intField f ":calls") :ms (sx/intField f ":wallMs")
                    :outcome (if pass "ok" "fail"))
              (str "asserts failed after round " (sOf f ":round"))))))

fn condRow ctx: Ctx line: String -> (Option ob/Obs)
  (if (not (stringStartsWith? line "(:t "))
    none
    (let [(f (sx/topFields line))
          (verdict (sOf f ":verdict"))
          (green (or (stringContains? verdict "green") (or (= verdict "ok") (or (stringContains? verdict "accept") (stringContains? verdict "pass")))))]
      (if (stringEmpty? verdict)
        none
        (some (finalize ctx
                (with (ob/blankObs) :at (sx/intField f ":at") :source "conductor" :run ctx.run :unitId (sOf f ":unit") :model (sOf f ":model")
                      :intent (sOf f ":stage") :tokensIn (sx/intField f ":tokens") :ms (sx/intField f ":ms")
                      :outcome (if green "ok" "fail"))
                verdict)))))

fn lastSegment p: String -> String
  (optionOr (listLast (stringSplit p "/")) p)

fn countWhere ls: (List String) pre: String -> Int64
  (listLength (filter (fn [(l String)] -> Bool (stringStartsWith? l pre)) ls))

fn lastGate ls: (List String) -> (Option (List (Pair String String)))
  (match (listLast (filter (fn [(l String)] -> Bool (stringStartsWith? l "(:gate ")) ls))
    ((some l) (some (sx/topFields l)))
    ((none) none))

fn sumUsage ls: (List String) k: String -> Int64
  (listSum (map (fn [(l String)] -> Int64 (sx/intField (sx/topFields l) k)) (filter (fn [(l String)] -> Bool (stringStartsWith? l "(:liveUsage ")) ls)))

; (:m :ref OBS-GATEERR-ROW :do "the first receipt error of a session: a :gateErr row when the journal has one (its :line), else the code of the first (:turn N :error :CODE) line, else the code on the :result row; the empty string when none, so a journal without errors classifies exactly as before")
fn errAfter l: String -> String
  (optionOr (listHead (stringSplit (stringReplace (optionOr (listGet (stringSplit l " :error :") 1) "") ")" " ") " ")) "")

fn firstReceiptError ls: (List String) res: (Option String) -> String
  (match (listFind (fn [(l String)] -> Bool (stringStartsWith? l "(:gateErr ")) ls)
    ((some g) (sOf (sx/topFields g) ":line"))
    ((none)
      (match (listFind (fn [(l String)] -> Bool (and (stringStartsWith? l "(:turn ") (stringContains? l " :error :"))) ls)
        ((some t) (errAfter t))
        ((none) (match res ((some r) (errAfter r)) ((none) ""))))))

; (:m :ref OBSCORPUS :do "a Leon journal is one session: session row for model, intent and task digest, result row for status, gate rows for the last gate exit; a journal without a result row older than six hours is a failed session with sig noResult, a younger one is still running and yields nothing")
fn journalObs ctx: Ctx nowMs: Int64 text: String -> (Option ob/Obs)
  (let [(ls (stringLines text))
        (sess (listFind (fn [(l String)] -> Bool (stringStartsWith? l "(:session ")) ls))
        (res (listFind (fn [(l String)] -> Bool (stringStartsWith? l "(:result ")) ls))]
    (match sess
      ((none) none)
      ((some sl)
        (let [(sf (sx/topFields sl))
              (rf (match res ((some r) (sx/topFields r)) ((none) (list))))
              (status (stringReplace (sOf rf ":status") ":" ""))
              (gate (lastGate ls))
              (gexit (match gate ((some g) (sx/intField g ":exit")) ((none) -1)))
              (uf (sx/bodyFields (optionOr (sx/fieldRaw rf ":usage") "()")))
              (old (< ctx.mtime (- nowMs 21600000)))
              (outcome (cond ((= status "ok") "ok") ((some? res) "fail") (old "fail") (else "open")))
              (defect (listAny? (fn [(l String)] -> Bool (stringContains? l ":parse-defect true")) ls))
              (blob (str "session " (if (some? res) status "noResult") (if defect " parse-defect" "") (if (> gexit 0) " gate red" "") (let [(e (firstReceiptError ls res))] (if (stringEmpty? e) "" (str " " e)))))
              (gateCmd (match gate ((some g) (sOf g ":cmd")) ((none) "")))
              (task (sOf sf ":task"))
              (served (match (listLast (filter (fn [(l String)] -> Bool (stringStartsWith? l "(:served ")) ls)) ((some l) (sOf (sx/topFields l) ":model")) ((none) "")))]
          (if (= outcome "open")
            none
            (some (finalize ctx
                    (with (ob/blankObs) :at ctx.mtime :source "leon" :run (sOf sf ":id") :unitId (lastSegment (sOf sf ":root"))
                          :caseId (str "task-" (optionOr (stringSlice (bytesSha256 (stringToBytes task)) 0 8) ""))
                          :model (if (stringEmpty? served) (sOf sf ":model") served) :intent (sOf sf ":intent") :turn (countWhere ls "(:turn")
                          :tokensIn (if (some? res) (sx/intField uf ":input") (sumUsage ls ":input"))
                          :tokensOut (if (some? res) (sx/intField uf ":output") (sumUsage ls ":output"))
                          :outcome outcome :gate (flt/clip (flt/redact gateCmd) 80) :exitCode gexit)
                    blob)))))))

; (:m :ref OBSCORPUS :do "an agentEval run dir name is YYYYMMDD-HHMMSS-<model>-<effort>; the model label is the part after the timestamp")
fn modelOfRun run: String -> String
  (stringJoin (listDrop (stringSplit run "-") 2) "-")

fn receiptObs ctx: Ctx caseName: String text: String -> (Option ob/Obs)
  (let [(row (optionOr (listHead (stringLines text)) ""))
        (outer (sx/topFields row))
        (rec (sx/topFields (optionOr (sx/fieldRaw outer ":receipt") "()")))
        (status (stringReplace (sOf rec ":status") ":" ""))
        (usage (sx/bodyFields (optionOr (sx/fieldRaw rec ":usage") "()")))
        (gates (sx/listItems (optionOr (sx/fieldRaw rec ":gates") "()")))
        (g0 (sx/bodyFields (optionOr (listHead gates) "()")))
        (secs (optionOr (stringToFloat64 (sOf rec ":execSec")) 0.0))]
    (if (stringEmpty? status)
      none
      (some (finalize ctx
              (with (ob/blankObs) :at ctx.mtime :source "agentEval" :run ctx.run :unitId (sOf rec ":session") :caseId caseName
                    :model (modelOfRun ctx.run) :intent (sOf rec ":mode") :turn (sx/intField rec ":turns")
                    :tokensIn (sx/intField usage ":input") :tokensOut (sx/intField usage ":output")
                    :ms (optionOr (float64ToInt64 (* secs 1000.0)) 0) :outcome (if (= status "ok") "ok" "fail"))
              (str status (if (> (sx/intField g0 ":exit") 0) " gate red" ""))))))

fn leadInt s: String -> Int64
  (let [(bs (stringToBytes s))
        (k (fold (fn [(acc Int64) (i Int64)] -> Int64 (if (and (= acc i) (and (>= (bytesGet bs i) 48) (<= (bytesGet bs i) 57))) (+ acc 1) acc)) 0 (range 0 (bytesLength bs))))]
    (if (= k 0) -1 (optionOr (stringToInt64 (optionOr (stringSlice s 0 k) "")) -1)))

fn splitFraction s: String -> (Pair Int64 Int64)
  (let [(p (stringSplit s "/"))]
    (pair (leadInt (optionOr (listGet p 0) "")) (leadInt (optionOr (listGet p 1) ""))))

fn keepSome xs: (List (Option ob/Obs)) -> (List ob/Obs)
  (listFlatMap (fn [(x (Option ob/Obs))] -> (List ob/Obs) (match x ((some v) (list v)) ((none) (list)))) xs)

; (:m :ref OBSCORPUS :do "CAL ledgers are hand-written aggregates: a line with a named row and :pass a/b becomes one agg observation with :turn = trials and :asserts = passes; no per-trial failure text exists there, so none is invented")
fn calRow ctx: Ctx l: String -> (Option ob/Obs)
  (let [(t (stringTrim l))
        (f (sx/topFields (if (stringStartsWith? t "(") (str "(:row " (optionOr (stringSlice t 1 (stringLength t)) "")) t)))
        (frac (splitFraction (sOf f ":pass")))
        (name (cond ((not (stringEmpty? (sOf f ":id"))) (sOf f ":id")) ((not (stringEmpty? (sOf f ":variant"))) (sOf f ":variant")) (else (sOf f ":route"))))]
    (if (or (< (pairSecond frac) 1) (stringEmpty? name))
      none
      (some (finalize ctx
              (with (ob/blankObs) :at ctx.mtime :source "cal" :run ctx.run :caseId name :model (sOf f ":what")
                    :turn (pairSecond frac) :asserts (pairFirst frac) :outcome "agg")
              ""))))

fn calRows ctx: Ctx text: String -> (List ob/Obs)
  (keepSome (map (fn [(l String)] -> (Option ob/Obs) (calRow ctx l)) (filter (fn [(l String)] -> Bool (stringContains? l ":pass \"")) (stringLines text))))
