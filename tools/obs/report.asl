(module ws/asl/tools/obs/report
  :x [report parseLevers rateText groupCounts]
  :i [(ws/asl/tools/obs/sx :a sx)
      (ws/asl/tools/obs/obs :a ob)
      (ws/asl/tools/obs/classify :a cl)])

; (:m :ref OBSCORPUS :do "report matrices are pure functions of the observation list, the lever table and the date scope: groups and counts are sorted (count descending, key ascending), rates are integer permille printed as 0.xxx, so the same rows always print the same bytes")
(schema Lever
  (:f failClass String)
  (:f levers (List String)))

fn parseLevers text: String -> (List Lever)
  (map (fn [(l String)] -> Lever
         (let [(f (sx/topFields l))]
           (Lever :failClass (optionOr (sx/field f ":failClass") "")
                  :levers (map sx/unq (sx/listItems (optionOr (sx/fieldRaw f ":levers") "()"))))))
       (filter (fn [(l String)] -> Bool (stringStartsWith? l "(:lever ")) (stringLines text)))

fn n v: Int64 -> String
  (stringFromInt64 v)

fn pad3 v: Int64 -> String
  (cond ((< v 10) (str "00" (n v))) ((< v 100) (str "0" (n v))) (else (n v)))

fn rateText ok: Int64 fail: Int64 -> String
  (if (= (+ ok fail) 0)
    "none"
    (let [(pm (/ (* ok 1000) (+ ok fail)))]
      (if (= pm 1000) "1.000" (str "0." (pad3 pm)))))

fn countKeys keys: (List String) -> (List (Pair String Int64))
  (let [(m (fold (fn [(acc (Map String Int64)) (k String)] -> (Map String Int64) (mapSet acc k (+ 1 (mapGetOr acc k 0)))) (mapEmpty) keys))]
    (listSortBy (fn [(p (Pair String Int64))] -> String (str (pad9 (- 999999999 (pairSecond p))) (pairFirst p))) (mapPairs m)))

fn pad9 v: Int64 -> String
  (let [(s (n v))]
    (str (stringRepeat "0" (- 9 (stringLength s))) s))

fn groupCounts keys: (List String) -> (List (Pair String Int64))
  (countKeys keys)

fn pairsText ps: (List (Pair String Int64)) -> String
  (stringJoin (map (fn [(p (Pair String Int64))] -> String (str "(" (pairFirst p) " " (n (pairSecond p)) ")")) ps) " ")

fn groupBy keyFn: (fn [ob/Obs] -> String) xs: (List ob/Obs) -> (List (Pair String (List ob/Obs)))
  (let [(m (fold (fn [(acc (Map String (List ob/Obs))) (o ob/Obs)] -> (Map String (List ob/Obs))
                   (let [(k (keyFn o))] (mapSet acc k (cons o (mapGetOr acc k (list))))))
                 (mapEmpty) xs))]
    (listSortBy (fn [(p (Pair String (List ob/Obs)))] -> String (str (pad9 (- 999999999 (listLength (pairSecond p)))) (pairFirst p))) (mapPairs m)))

fn okN xs: (List ob/Obs) -> Int64
  (listCount (fn [(o ob/Obs)] -> Bool (= o.outcome "ok")) xs)

fn failN xs: (List ob/Obs) -> Int64
  (listCount (fn [(o ob/Obs)] -> Bool (= o.outcome "fail")) xs)

fn infraN xs: (List ob/Obs) -> Int64
  (listCount (fn [(o ob/Obs)] -> Bool (= o.outcome "infra")) xs)

fn scored xs: (List ob/Obs) -> (List ob/Obs)
  (filter (fn [(o ob/Obs)] -> Bool (!= o.outcome "agg")) xs)

fn mixOf xs: (List ob/Obs) -> String
  (pairsText (countKeys (map (fn [(o ob/Obs)] -> String o.failClass) (filter (fn [(o ob/Obs)] -> Bool (!= o.failClass "none")) xs))))

fn head xs: (List ob/Obs) -> String
  (let [(days (listSort (map (fn [(o ob/Obs)] -> String (ob/dayOf o.at)) (filter (fn [(o ob/Obs)] -> Bool (> o.at 0)) xs))))]
    (str "(:n " (n (listLength xs)) " :from " (c (listHead days)) " :to " (c (listLast days)) ")"))

fn c d: (Option String) -> String
  (str "\"" (optionOr d "none") "\"")

fn statLine xs: (List ob/Obs) -> String
  (str ":n " (n (listLength xs)) " :ok " (n (okN xs)) " :fail " (n (failN xs)) " :infra " (n (infraN xs)) " :rate " (rateText (okN xs) (failN xs))
       " :mix (" (mixOf xs) ")")

fn groupRows keyFn: (fn [ob/Obs] -> String) tag: String xs: (List ob/Obs) -> (List String)
  (map (fn [(p (Pair String (List ob/Obs)))] -> String (str "(" tag " \"" (pairFirst p) "\" " (statLine (pairSecond p)) ")"))
       (groupBy keyFn xs))

fn caseRows xs: (List ob/Obs) -> (List String)
  (map (fn [(p (Pair String (List ob/Obs)))] -> String
         (let [(rows (pairSecond p))
               (models (groupBy (fn [(o ob/Obs)] -> String o.model) rows))]
           (str "(:case \"" (pairFirst p) "\" :n " (n (listLength rows)) " :models " (n (listLength models)) " :tried ("
                (stringJoin (map (fn [(m (Pair String (List ob/Obs)))] -> String
                                   (str "(\"" (pairFirst m) "\" :ok " (n (okN (pairSecond m))) " :fail " (n (failN (pairSecond m))) " :infra " (n (infraN (pairSecond m)))
                                        " :agg " (n (listCount (fn [(o ob/Obs)] -> Bool (= o.outcome "agg")) (pairSecond m))) ")"))
                                 models) " ") "))")))
       (groupBy (fn [(o ob/Obs)] -> String o.caseId) (filter (fn [(o ob/Obs)] -> Bool (!= o.caseId "")) xs)))

fn cardRows xs: (List ob/Obs) -> (List String)
  (let [(withCard (filter (fn [(o ob/Obs)] -> Bool (and (!= o.card "") (!= o.caseId ""))) xs))
        (cardsPerCase (fold (fn [(acc (Map String (List String))) (o ob/Obs)] -> (Map String (List String))
                              (if (listContains? (mapGetOr acc o.caseId (list)) o.card) acc (mapSet acc o.caseId (cons o.card (mapGetOr acc o.caseId (list))))))
                            (mapEmpty) (filter (fn [(o ob/Obs)] -> Bool (!= o.caseId "")) withCard)))
        (shared (fn [(o ob/Obs)] -> Bool (> (listLength (mapGetOr cardsPerCase o.caseId (list))) 1)))]
    (map (fn [(p (Pair String (List ob/Obs)))] -> String
           (let [(rows (pairSecond p))
                 (onShared (filter shared rows))]
             (str "(:card \"" (pairFirst p) "\" " (statLine rows) " :cases " (n (listLength (groupBy (fn [(o ob/Obs)] -> String o.caseId) rows)))
                  " :onSharedCases (:n " (n (listLength onShared)) " :rate " (rateText (okN onShared) (failN onShared)) "))")))
         (groupBy (fn [(o ob/Obs)] -> String o.card) withCard)))

fn leversFor lv: (List Lever) cls: String -> String
  (match (listFind (fn [(l Lever)] -> Bool (= l.failClass cls)) lv)
    ((some l) (stringJoin (map sx/quoteText l.levers) " "))
    ((none) ""))

fn classRows lv: (List Lever) xs: (List ob/Obs) -> (List String)
  (let [(bad (filter (fn [(o ob/Obs)] -> Bool (and (!= o.failClass "none") (!= o.outcome "agg"))) xs))]
    (map (fn [(p (Pair String (List ob/Obs)))] -> String
           (let [(rows (pairSecond p))
                 (top (listTake (countKeys (map (fn [(o ob/Obs)] -> String o.model) rows)) 5))]
             (str "(:failClass " (pairFirst p) " :n " (n (listLength rows)) " :share " (rateText (listLength rows) (- (listLength bad) (listLength rows)))
                  " :topModels (" (pairsText top) ") :sig \"" (optionOr (listHead (listSort (map (fn [(o ob/Obs)] -> String o.sig) rows))) "") "\" :levers (" (leversFor lv (pairFirst p)) "))")))
         (groupBy (fn [(o ob/Obs)] -> String o.failClass) bad)))

fn report by: String lv: (List Lever) xs: (List ob/Obs) -> String
  (let [(sc (scored xs))
        (bad (filter (fn [(o ob/Obs)] -> Bool (and (!= o.outcome "ok") (!= o.outcome "agg"))) xs))
        (unc (listCount (fn [(o ob/Obs)] -> Bool (= o.failClass (cl/unclassifiedId))) bad))
        (rows (cond
                ((= by "model") (groupRows (fn [(o ob/Obs)] -> String o.model) ":model" sc))
                ((= by "case") (caseRows xs))
                ((= by "card") (cardRows sc))
                ((= by "intent") (groupRows (fn [(o ob/Obs)] -> String o.intent) ":intent" sc))
                ((= by "failClass") (classRows lv xs))
                (else (list))))]
    (if (listEmpty? rows)
      (str "(:obsReport :by \"" by "\" :err \"no rows or unknown dimension; by = model|case|card|intent|failClass\")")
      (str "(:obsReport :v 1 :by \"" by "\" :scope " (head xs) " :scored " (n (listLength sc)) " :nonOk " (n (listLength bad))
           " :unclassified (:n " (n unc) " :of " (n (listLength bad)) " :share " (rateText unc (- (listLength bad) unc)) ")\n  :rows (\n    "
           (stringJoin rows "\n    ") "))")))
