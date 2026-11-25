(module asl-tools/coord/greens
  :x [mergedOf greenRowSuites groupAfter pathsIn quotedAll failedOut? greensPath greensKeep greensRowOf greensMerge readGreens! recordGreens!]
  :i [])

; (:m :ref DEPLOY-VERIFY-REUSE-ANCESTRY :do "what a merged train proved green outlives the train: the conductor drops trains/UNIT once the unit is merged, so before that it appends one row per green receipt to STORE/greens.asn, (:green :merged M :at MS :suites (...)), with the exclusions of greenRowSuites; one row per merged tree, the newest 500 stay, and the node deploy reads them first, newest first, as receipts")

; (:m :ref DEPLOY-VERIFY-REUSE-ANCESTRY :do "the merged sha a train receipt row names, empty when it names none")
fn mergedOf row: String -> String
  (match (stringIndexOf row " :merged \"")
    ((none) "")
    ((some i) (optionOr (listHead (stringSplit (optionOr (stringSlice row (+ i 10) (stringLength row)) "") "\"")) "")))

; (:m :ref DEPLOY-VERIFY-REUSE-ANCESTRY :do "the suites one receipt row clears whatever sha it merged: none unless :red is empty and nothing is blocked, F1 exclusions applied")
fn greenRowSuites row: String -> (List String)
  (if (and (stringContains? row " :red () ") (stringContains? row " :blocked (:fresh 0 "))
    (match (stringIndexOf row " :suites (")
      ((none) (list))
      ((some i)
        (let [(rest (optionOr (stringSlice row (+ i 10) (stringLength row)) ""))
              (body (optionOr (listHead (stringSplit rest ") :")) ""))
              (bad (listAppend (listFlatMap (fn [(k String)] -> (List String) (pathsIn (groupAfter row k))) (list " :preexisting (" " :knownRed (" " :baseRedOutside (" " :flaky ("))
                               (listFlatMap (fn [(k String)] -> (List String) (quotedAll (groupAfter row k))) (list " :assertLoss (" ":unrun ("))))]
          (filter (fn [(p String)] -> Bool (not (listContains? bad p))) (quotedAll body)))))
    (list))


(schema Scan
  (:f depth Int64)
  (:f inQ Bool)
  (:f esc Bool)
  (:f n Int64)
  (:f done Bool))

; (:m :ref DEPLOY-VERIFY-REUSE :do "the balanced parenthesised text that starts at KEY (which ends with its opening paren), quotes and escapes respected; empty when KEY is absent")
fn groupAfter row: String key: String -> String
  (match (stringIndexOf row key)
    ((none) "")
    ((some i)
      (let [(rest (optionOr (stringSlice row (+ i (- (stringLength key) 1)) (stringLength row)) ""))
            (st (fold (fn [(a Scan) (c String)] -> Scan
                        (cond
                          (a.done a)
                          (a.esc (Scan :depth a.depth :inQ a.inQ :esc false :n (+ a.n 1) :done false))
                          ((and a.inQ (= c "\\")) (Scan :depth a.depth :inQ true :esc true :n (+ a.n 1) :done false))
                          ((= c "\"") (Scan :depth a.depth :inQ (not a.inQ) :esc false :n (+ a.n 1) :done false))
                          (a.inQ (Scan :depth a.depth :inQ true :esc false :n (+ a.n 1) :done false))
                          ((= c "(") (Scan :depth (+ a.depth 1) :inQ false :esc false :n (+ a.n 1) :done false))
                          ((= c ")") (Scan :depth (- a.depth 1) :inQ false :esc false :n (+ a.n 1) :done (= a.depth 1)))
                          (else (Scan :depth a.depth :inQ false :esc false :n (+ a.n 1) :done false))))
                      (Scan :depth 0 :inQ false :esc false :n 0 :done false) (stringChars rest)))]
        (optionOr (stringSlice rest 0 st.n) ""))))

; (:m :ref DEPLOY-VERIFY-REUSE :do "the first quoted string of every row of a group: the text after each opening paren and quote up to the next quote")
fn pathsIn group: String -> (List String)
  (map (fn [(t String)] -> String (optionOr (listHead (stringSplit t "\"")) "")) (listDrop (stringSplit group "(\"") 1))


fn quotedAll text: String -> (List String)
  (quotedOdd (listDrop (stringSplit text "\"") 1))

fn quotedOdd parts: (List String) -> (List String)
  (match (listHead parts)
    ((none) (list))
    ((some w) (cons w (quotedOdd (listDrop parts 2)))))


; (:m :ref DEPLOY-VERIFY-REUSE-ANCESTRY :do "a train that failed (a :status :failed row, among them the silentSuites verdict of a broken job launch) vouches for nothing: a file holding one is not a receipt, whatever green rows it also prints")
fn failedOut? out: String -> Bool
  (or (stringContains? out "(:train :status :failed") (stringContains? out ":silentSuites"))

fn greensPath store: String -> String
  (str store "/greens.asn")

fn greensKeep -> Int64
  500

; (:m :ref DEPLOY-VERIFY-REUSE-ANCESTRY :do "the green row of one train receipt row: empty unless it names a merged tree and clears at least one suite")
fn greensRowOf row: String atMs: Int64 -> String
  (let [(m (mergedOf row))
        (suites (greenRowSuites row))]
    (if (or (stringEmpty? m) (listEmpty? suites)) ""
      (str "(:green :merged \"" m "\" :at " (stringFromInt64 atMs) " :suites (" (stringJoin (map (fn [(p String)] -> String (str "\"" p "\"")) suites) " ") "))")))

; (:m :ref DEPLOY-VERIFY-REUSE-ANCESTRY :do "the rows after FRESH joined the OLD ones: a fresh row replaces the old row of the same merged tree, and only the newest KEEP rows stay")
fn greensMerge old: (List String) fresh: (List String) keep: Int64 -> (List String)
  (let [(ms (map mergedOf fresh))
        (kept (filter (fn [(l String)] -> Bool (and (stringStartsWith? l "(:green ") (not (listContains? ms (mergedOf l))))) old))
        (all (listAppend kept fresh))]
    (listDrop all (max 0 (- (listLength all) keep))))

; (:m :ref DEPLOY-VERIFY-REUSE-ANCESTRY :do "every green row kept, newest first, as (merged, suites)")
fn ! readGreens! store: String -> (List (Pair String (List String)))
  (listReverse
    (filter (fn [(r (Pair String (List String)))] -> Bool (not (listEmpty? (pairSecond r))))
            (map (fn [(l String)] -> (Pair String (List String)) (pair (mergedOf l) (quotedAll (groupAfter l " :suites ("))))
                 (filter (fn [(l String)] -> Bool (stringStartsWith? l "(:green :merged ")) (map stringTrim (stringLines (resultOr (fileReadString (greensPath store)) "")))))))

; (:m :ref DEPLOY-VERIFY-REUSE-ANCESTRY :do "before a merged unit's trains dir is removed: its green receipts, whole attempt files that failed skipped, are appended to greens.asn; answers how many rows were written")
fn ! recordGreens! store: String id: String atMs: Int64 -> Int64
  (let [(dir (str store "/trains/" id))
        (fresh (listFlatMap (fn [(f String)] -> (List String)
                              (if (stringEndsWith? f ".out")
                                (let [(out (resultOr (fileReadString (str dir "/" f)) ""))]
                                  (if (failedOut? out) (list)
                                    (filter (fn [(r String)] -> Bool (not (stringEmpty? r)))
                                            (map (fn [(l String)] -> String (greensRowOf l atMs))
                                                 (filter (fn [(l String)] -> Bool (stringStartsWith? l "(:train :head ")) (map stringTrim (stringLines out)))))))
                                (list)))
                            (listSort (resultOr (dirList dir) (list)))))]
    (if (listEmpty? fresh) 0
      (let [(old (map stringTrim (stringLines (resultOr (fileReadString (greensPath store)) ""))))
            (rows (greensMerge old fresh (greensKeep)))
            (_ (dirCreate store))
            (tmp (str (greensPath store) ".tmp." (stringFromInt64 (procSelf))))
            (saved (match (fileWrite tmp (str (stringJoin rows "\n") "\n"))
                     ((err _) false)
                     ((ok _) (match (pathRename tmp (greensPath store)) ((ok _) true) ((err _) (do (pathRemove tmp) false))))))]
        (if saved (listLength fresh) 0))))
