(module asl-tools/coord/planImport
  :x [PlanRow Report rowsOf importable? needOf resolve refreshable? ownsLive? staleOwns plan! report main]
  :i [(asl-tools/coord/store :a st) (tools/fleet/model :a fm) (asl-parser/reader :a rd)])

; (:m :ref COND4 :do "plan import: the ledger's (:u :id X ...) rows that are marked :auto true, or :queue conductor, and carry a :do become store tasks (:owns, :reads, :gate, :channel, :after) with the :do text as tasks/ID.txt; idempotent by row id (a unit already in the store is skipped, never rewritten); a row whose :owns or :gate is missing, or whose :after names something that will not be in the store, is parked in <store>/parked.asn with its :need and nothing is guessed; the ledger is only read")

(schema PlanRow (:f id String) (:f doc String) (:f gate String) (:f owns (List String)) (:f reads (List String)) (:f after (List String)) (:f channel String))

fn listOf v: (Option rd/SExpr) -> (List String)
  (match v
    ((none) (list))
    ((some x)
      (let [(items (fm/itemsOf x))]
        (if (listEmpty? items)
          (let [(t (fm/textOf x))] (if (stringEmpty? t) (list) (list t)))
          (map fm/textOf items)))))

fn textAt items: (List rd/SExpr) key: String -> String
  (match (fm/kvGet items key) ((none) "") ((some v) (fm/textOf v)))

; (:m :ref COND4 :do "selected rows: one-line (:u :id ...) forms, :auto true or :queue conductor, a :do, and no :status other than queued; an :auto list (the older survey rows) selects nothing")
fn rowOf line: String -> (Option PlanRow)
  (match (fm/parseForms line)
    ((err _) (none))
    ((ok forms)
      (match (listHead forms)
        ((none) (none))
        ((some form)
          (let [(items (fm/itemsOf form))
                (id (textAt items ":id"))
                (status (textAt items ":status"))
                (picked (or (= (textAt items ":auto") "true") (= (textAt items ":queue") "conductor")))]
            (if (or (stringEmpty? id) (or (not picked) (or (stringEmpty? (textAt items ":do")) (and (!= status "") (!= status "queued"))))) (none)
              (some (PlanRow :id id :doc (textAt items ":do") :gate (textAt items ":gate") :owns (listOf (fm/kvGet items ":owns"))
                             :reads (listOf (fm/kvGet items ":reads")) :after (listOf (fm/kvGet items ":after"))
                             :channel (let [(c (textAt items ":channel"))] (if (stringEmpty? c) "free" c))))))))))

fn rowsOf text: String -> (List PlanRow)
  (fold (fn [(acc (List PlanRow)) (line String)] -> (List PlanRow)
          (if (stringStartsWith? line "(:u :id ")
            (match (rowOf line) ((some r) (if (listAny? (fn [(x PlanRow)] -> Bool (= x.id r.id)) acc) acc (listAppend acc (list r)))) ((none) acc))
            acc))
        (list) (stringLines text))

fn importable? r: PlanRow -> Bool
  (and (not (listEmpty? r.owns)) (not (stringEmpty? r.gate)))

; (:m :do "why a row cannot become a task yet: owns, gate, or after (a dependency that is neither in the store nor itself importable)")
fn needOf r: PlanRow known: (List String) -> String
  (cond
    ((listEmpty? r.owns) "owns")
    ((stringEmpty? r.gate) "gate")
    ((listAny? (fn [(d String)] -> Bool (not (listContains? known d))) r.after) "after")
    (else ""))

; (:m :do "fixpoint: a row waiting on a parked row is parked too; returns the ids that stay importable")
fn resolve rows: (List PlanRow) inStore: (List String) -> (List String)
  (let [(ids (map (fn [(r PlanRow)] -> String r.id) (filter importable? rows)))
        (next (map (fn [(r PlanRow)] -> String r.id)
                   (filter (fn [(r PlanRow)] -> Bool (and (listContains? ids r.id) (stringEmpty? (needOf r (listAppend inStore ids))))) rows)))]
    (if (= (listLength next) (listLength ids)) ids (resolve (filter (fn [(r PlanRow)] -> Bool (listContains? next r.id)) rows) inStore)))

; (:m :ref ORG-GAP-20261102 :do "stale :owns: a path is live when it, or the directory it would be created in, exists under root (a glob counts by the text before its first star and needs that directory itself); a queue row whose :owns names a path with neither is reported as one (:staleOwns :id ID :paths (...)) line, a warning that never blocks an import or a start")
fn parentOf p: String -> String
  (let [(parts (stringSplit p "/"))]
    (stringJoin (listTake parts (max 0 (- (listLength parts) 1))) "/"))

fn ! ownsLive? root: String p: String -> Bool
  (let [(pre (stringTrim (optionOr (listHead (stringSplit p "*")) "")))
        (bare (if (stringEndsWith? pre "/") (optionOr (stringSlice pre 0 (- (stringLength pre) 1)) "") pre))]
    (if (stringEmpty? bare) true
      (or (fileExists? (str root "/" bare)) (and (not (stringContains? p "*")) (fileExists? (str root "/" (parentOf bare)))))))

fn ! staleOwns text: String root: String -> (List String)
  (map (fn [(p (Pair String (List String)))] -> String (str "(:staleOwns :id " (st/q (pairFirst p)) " :paths " (st/qList (pairSecond p)) ")"))
       (filter (fn [(p (Pair String (List String)))] -> Bool (not (listEmpty? (pairSecond p))))
               (map (fn [(r PlanRow)] -> (Pair String (List String)) (pair r.id (filter (fn [(o String)] -> Bool (not (ownsLive? root o))) r.owns)))
                    (rowsOf text))))

fn parkedRow r: PlanRow need: String -> String
  (str "(:parked :id " (st/q r.id) " :need " need " :do " (st/q r.doc) ")")

(schema Report (:f put (List String)) (:f skipped (List String)) (:f parked (List String)) (:f bad (List String)) (:f refreshed (List String)))

fn report r: Report -> String
  (str "(:import :put " (st/qList r.put) " :skipped " (st/qList r.skipped) " :parked " (st/qList r.parked) " :bad " (st/qList r.bad) " :refreshed " (st/qList r.refreshed) ")")

; (:m :ref PLANIMPORT-PARKED-WIPE :do "parked rows of ids this ledger does not carry and the store does not hold stay, so an import from a side ledger no longer wipes the main ledger's parked rows")
fn keptParked existing: String ids: (List String) -> (List String)
  (filter (fn [(line String)] -> Bool
            (match (st/rowFields line "parked")
              ((err _) false)
              ((ok fs) (not (listContains? ids (st/textField fs "id"))))))
          (stringLines existing))

; (:m :ref CONDUCTOR-TASK-REFRESH :do "a unit already in the store whose ledger row changed (task text, :owns or :gate) is refreshed when it is not in a stage: tasks/ID.txt and the store row's owns and gate are rewritten from the row and one (:refresh :unit :changed ...) row is appended to <store>/journal.asn; a unit in writing, gating, awaitReview, reviewing, merging or merged, a unit blocked awaiting the lead or a rebase, a unit holding a lease (store put refuses it) and a row that is no longer importable are left alone; a dry import only reports")
fn refreshable? st: String await: String -> Bool
  (and (not (listContains? (list "writing" "gating" "awaitReview" "reviewing" "merging" "merged") st))
       (not (and (= st "blocked") (listContains? (list "lead" "rebase") await))))

fn ! cuField! store: String id: String key: String -> String
  (match (st/rowFields (resultOr (fileReadString (str store "/cond/" id ".asn")) "") "cu")
    ((err _) "")
    ((ok fs) (st/textField fs key)))

fn changedOf! store: String u: st/Task r: PlanRow -> (List String)
  (listAppend
    (if (= (resultOr (fileReadString (str store "/tasks/" r.id ".txt")) "") r.doc) (list) (list "task"))
    (listAppend (if (= u.owns r.owns) (list) (list "owns")) (if (= u.gate r.gate) (list) (list "gate"))))

fn ! refreshOne! store: String u: st/Task r: PlanRow changed: (List String) -> Bool
  (match (st/put! store (with u :owns r.owns :gate r.gate))
    ((err _) false)
    ((ok _)
      (let [(_ (fileWrite (str store "/tasks/" r.id ".txt") r.doc))
            (_ (fileAppend (str store "/journal.asn") (str "(:refresh :unit " (st/q r.id) " :changed (" (stringJoin changed " ") ") :at " (stringFromInt64 (/ (nowNs) 1000000)) ")\n")))]
        true)))

; (:m :ref COND4 :do "plan! LEDGER-TEXT STORE BASE DRY: rows to tasks; parked.asn is rewritten from the rows still parked, so a row that gained :owns leaves it at the next import")
fn ! plan! text: String store: String base: String dry: Bool -> (Result Report String)
  (match (match (st/readUnits! store) ((ok us) (ok us)) ((err _) (ok (list))))
    ((err e) (err e))
    ((ok units)
      (let [(inStore (map (fn [(u st/Task)] -> String u.id) units))
            (rows (rowsOf text))
            (fresh (filter (fn [(r PlanRow)] -> Bool (not (listContains? inStore r.id))) rows))
            (keep (resolve fresh inStore))
            (parked (filter (fn [(r PlanRow)] -> Bool (not (listContains? keep r.id))) fresh))
            (needs (map (fn [(r PlanRow)] -> (Pair PlanRow String) (pair r (let [(n (needOf r (listAppend inStore keep)))] (if (stringEmpty? n) "after" n)))) parked))
            (_ (if dry () (let [(_ (dirCreate (str store "/tasks")))] ())))
            (results (map (fn [(r PlanRow)] -> (Pair String (Result String String))
                            (pair r.id
                                  (if dry (ok "dry")
                                    (let [(_ (if (fileExists? (str store "/tasks/" r.id ".txt")) (ok ()) (fileWrite (str store "/tasks/" r.id ".txt") r.doc)))]
                                      (st/put! store (st/Task :id r.id :owns r.owns :reads r.reads :gate r.gate :channel r.channel :model "" :base base :after r.after :st "queued" :epoch 0 :receipt ""))))))
                          (filter (fn [(r PlanRow)] -> Bool (listContains? keep r.id)) fresh)))
            (parkedLines (listAppend (keptParked (resultOr (fileReadString (str store "/parked.asn")) "") (listAppend inStore (map (fn [(r PlanRow)] -> String r.id) rows)))
                                     (map (fn [(p (Pair PlanRow String))] -> String (parkedRow (pairFirst p) (pairSecond p))) needs)))
            (known (filter (fn [(p (Pair PlanRow st/Task))] -> Bool (and (importable? (pairFirst p)) (and (refreshable? (cuField! store (pairFirst p).id "st") (cuField! store (pairFirst p).id "await")) (and (!= (pairSecond p).st "done") (not (listEmpty? (changedOf! store (pairSecond p) (pairFirst p)))))))) 
                           (fold (fn [(acc (List (Pair PlanRow st/Task))) (r PlanRow)] -> (List (Pair PlanRow st/Task)) (match (listFind (fn [(u st/Task)] -> Bool (= u.id r.id)) units) ((some u) (listAppend acc (list (pair r u)))) ((none) acc))) (list) rows)))
            (refreshed (if dry (map (fn [(p (Pair PlanRow st/Task))] -> String (pairFirst p).id) known)
                         (map (fn [(p (Pair PlanRow st/Task))] -> String (pairFirst p).id)
                              (filter (fn [(p (Pair PlanRow st/Task))] -> Bool (refreshOne! store (pairSecond p) (pairFirst p) (changedOf! store (pairSecond p) (pairFirst p)))) known))))
            (_ (if dry (ok ()) (fileWrite (str store "/parked.asn") (str (stringJoin parkedLines "\n") (if (listEmpty? parkedLines) "" "\n")))))]
        (ok (Report :put (map pairFirst (filter (fn [(p (Pair String (Result String String)))] -> Bool (ok? (pairSecond p))) results))
                    :skipped (filter (fn [(i String)] -> Bool (listContains? inStore i)) (map (fn [(r PlanRow)] -> String r.id) rows))
                    :parked (map (fn [(p (Pair PlanRow String))] -> String (str (let [(r (pairFirst p))] r.id) ":" (pairSecond p))) needs)
                    :bad (map pairFirst (filter (fn [(p (Pair String (Result String String)))] -> Bool (not (ok? (pairSecond p)))) results))
                    :refreshed refreshed)))))

; (:m :ref COND4 :do "import --ledger FILE --store DIR [--base REF] [--dry]: prints the (:import ...) report; the ledger is read, never written")
fn ! main args: (List String) -> (Result Int64 String)
  (let [(cmd (optionOr (listHead args) ""))
        (ledger (st/opt args "ledger" ""))
        (store (st/opt args "store" ""))
        (base (st/opt args "base" "HEAD"))
        (dry (listContains? args "--dry"))]
    (if (or (!= cmd "import") (or (stringEmpty? ledger) (stringEmpty? store)))
      (do (eprintln "usage: planImport import --ledger FILE --store DIR [--base REF] [--dry]") (ok 2))
      (match (fileReadString ledger)
        ((err e) (do (eprintln e) (ok 1)))
        ((ok text)
          (match (plan! text store base dry)
            ((err e) (do (eprintln e) (ok 1)))
            ((ok r) (do (println (report r)) (ok 0))))))))
