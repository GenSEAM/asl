(module asl-know/know
  :x [dropStaleIndexes! rendered! cardsDir staleFiles! ratchetRows! ratchetDiff writeCards! know! main]
  :i [(asl-know/render :a r) (asl-know/query :a qy)])

; (:m :tags (know) :note "asl know: gen writes asl-know/cards from source, check fails on any byte drift, q answers an intent query from the written cards")

fn cardsDir root: String -> String
  (str root "/asl/packages/asl-know/cards")

fn cardText c: r/Card -> String
  (str (stringJoin (cons c.line c.rows) "\n") "\n")

fn ! rendered! root: String -> (List (Pair String String))
  (let [(cards (r/allCards! root))]
    (listAppend (r/indexFiles (r/groupsOf! root) cards)
          (map (fn [(c r/Card)] -> (Pair String String) (pair (r/cardFile c.id) (cardText c))) cards)))

fn ! staleFiles! root: String -> (List String)
  (let [(want (rendered! root))
        (dir (cardsDir root))
        (names (resultOr (dirList dir) (list)))
        (drift (listFlatMap (fn [(p (Pair String String))] -> (List String)
                              (match (fileReadString (str dir "/" (pairFirst p)))
                                ((err _) (list (str (pairFirst p) " absent")))
                                ((ok t) (if (= t (pairSecond p)) (list) (list (str (pairFirst p) " differs"))))))
                            want))
        (extra (map (fn [(n String)] -> String (str n " unexpected"))
                    (filter (fn [(n String)] -> Bool (not (listAny? (fn [(p (Pair String String))] -> Bool (= (pairFirst p) n)) want))) names)))]
    (listAppend drift extra))

fn ! ratchetRows! root: String -> (List String)
  (filter (fn [(l String)] -> Bool (not (stringEmpty? l)))
    (map (fn [(l String)] -> String (optionOr (r/unquoteRow l) ""))
         (stringLines (resultOr (fileReadString (str root "/asl/packages/asl-know/missing.asn")) ""))))

fn ratchetDiff listed: (List String) computed: (List String) -> (Pair (List String) (List String))
  (pair (filter (fn [(m String)] -> Bool (not (listContains? listed m))) computed)
        (filter (fn [(m String)] -> Bool (not (listContains? computed m))) listed))

; (:m :ref KNOW-TIER-LOWS :do "gen removes an index-GROUP.asn whose group is gone: any index-*.asn in the cards dir that is not among the rendered files is deleted, so a dropped group leaves no stale file for check to report")
fn ! dropStaleIndexes! dir: String files: (List (Pair String String)) -> (Result Int64 String)
  (let [(stale (filter (fn [(n String)] -> Bool (and (stringStartsWith? n "index-") (and (stringEndsWith? n ".asn") (not (listAny? (fn [(p (Pair String String))] -> Bool (= (pairFirst p) n)) files)))))
                       (resultOr (dirList dir) (list))))
        (failed (filter (fn [(n String)] -> Bool (err? (pathRemove (str dir "/" n)))) stale))]
    (if (listEmpty? failed) (ok (listLength files)) (err (str "cannot remove " (optionOr (listHead failed) "")))))

fn ! writeCards! root: String -> (Result Int64 String)
  (let [(files (rendered! root)) (dir (cardsDir root))]
    (match (dirCreate dir)
      ((err e) (err e))
      ((ok _)
        (let [(bad (filter (fn [(p (Pair String String))] -> Bool (err? (fileWrite (str dir "/" (pairFirst p)) (pairSecond p)))) files))]
          (if (listEmpty? bad) (dropStaleIndexes! dir files) (err (str "cannot write " (pairFirst (optionOr (listHead bad) (pair "" ""))))))))))

fn ! writeRatchet! root: String -> (Result Int64 String)
  (let [(rows (r/missingOf (r/allCards! root)))]
    (match (fileWrite (str root "/asl/packages/asl-know/missing.asn")
                   (str "(:knowMissing :rule \"an exported symbol without a declaration (nodecl) or doc.asn contract (nodoc); knowCardsTest fails when a row is added or a listed row is fixed, so this list only shrinks\" :count " (listLength rows) ")\n"
                        (stringJoin (map r/q rows) "\n") "\n"))
      ((err e) (err e))
      ((ok _) (ok (listLength rows)))))

fn ! know! root: String query: String budget: Int64 -> String
  (qy/answer (qy/loadEntries! (cardsDir root)) query budget)

fn indexFileOf group: (Option String) -> String
  (match group
    ((some g) (if (or (stringContains? g "/") (stringContains? g "..")) "index.asn" (str "index-" g ".asn")))
    ((none) "index.asn"))

fn budgetArg args: (List String) -> Int64
  (match (listIndexOf args "--budget")
    ((none) 1200)
    ((some i) (optionOr (match (listGet args (+ i 1)) ((some s) (stringToInt64 s)) ((none) (none))) 1200)))

fn ! main args: (List String) -> (Result Int64 String)
  (let [(cmd (optionOr (listGet args 0) "help"))
        (root (resultOr (realPath (optionOr (listGet args 1) ".")) "."))]
    (cond
      ((= cmd "gen") (match (writeCards! root) ((err e) (err e)) ((ok n) (do (println (str "(:know :gen :files " n ")")) (ok 0)))))
      ((= cmd "ratchet") (match (writeRatchet! root) ((err e) (err e)) ((ok n) (do (println (str "(:know :ratchet :rows " n ")")) (ok 0)))))
      ((= cmd "check")
        (let [(stale (staleFiles! root))]
          (if (listEmpty? stale)
            (do (println "(:know :check :status ok)") (ok 0))
            (do (println (str "(:know :check :status stale :files (" (stringJoin (map r/q stale) " ") "))")) (ok 1)))))
      ((= cmd "q") (do (println (know! root (stringJoin (listTake (listDrop args 2) (optionOr (optionMap (fn [(i Int64)] -> Int64 (- i 2)) (listIndexOf args "--budget")) (listLength args))) " ") (budgetArg args))) (ok 0)))
      ((= cmd "index") (do (println (resultOr (fileReadString (str (cardsDir root) "/" (indexFileOf (listGet args 2)))) "(:know :error \"no such index; run gen, groups are listed in index.asn\")")) (ok 0)))
      (else (do (println "(:know :usage \"gen ROOT | check ROOT | ratchet ROOT | index ROOT [GROUP] | q ROOT words... [--budget N]\")") (ok 2)))))
