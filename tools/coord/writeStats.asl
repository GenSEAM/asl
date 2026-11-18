(module asl-tools/coord/writeStats
  :x [Row writeClass stopWord validUtf8? parseRow classOf tally countsText statsText reportFor main]
  :i [])

; (:m :ref WRITE-OUTCOME-STATS :do "one number for how well the writers do, read from <store>/journal.asn: a row is kept only when it is valid UTF-8 and one whole (:t ...) line ending in :at N), anything else is skipped and counted; write rows classify as written, stalled, the word after :stop in the verdict, or its first word; reviews as pass, fail, other; merges as merged, red, blocked, retry; the window is the last N hours up to now")

(schema Row
  (:f unit String) (:f to String) (:f stage String) (:f model String) (:f verdict String) (:f at Int64) (:f ms Int64 :default 0))

fn utf8Ok bs: Bytes i: Int64 n: Int64 -> Bool
  (if (>= i n) true
    (let [(b (bytesGet bs i))
          (need (cond ((< b 128) 0) ((and (>= b 194) (< b 224)) 1) ((and (>= b 224) (< b 240)) 2) ((and (>= b 240) (< b 245)) 3) (else -1)))]
      (if (< need 0) false
        (if (> (+ i need) (- n 1)) (= need 0)
          (if (listAll? (fn [(k Int64)] -> Bool (let [(c (bytesGet bs (+ i k)))] (and (>= c 128) (< c 192)))) (range 1 (+ need 1)))
            (utf8Ok bs (+ i need 1) n)
            false)))))

fn validUtf8? s: String -> Bool
  (let [(bs (stringToBytes s))] (utf8Ok bs 0 (bytesLength bs)))

fn headTok head: String key: String -> String
  (match (stringIndexOf head (str key " "))
    ((none) "")
    ((some i) (let [(rest (optionOr (stringSlice head (+ i (stringLength key) 1) (stringLength head)) ""))]
                (stringReplace (optionOr (listHead (stringSplit rest " ")) "") "\"" ""))))

fn headQuoted head: String key: String -> String
  (match (stringIndexOf head (str key " \""))
    ((none) "")
    ((some i) (let [(rest (optionOr (stringSlice head (+ i (stringLength key) 2) (stringLength head)) ""))]
                (optionOr (listHead (stringSplit rest "\"")) ""))))

fn stopWord verdict: String -> String
  (match (stringIndexOf verdict ":stop ")
    ((none) "")
    ((some i) (let [(rest (optionOr (stringSlice verdict (+ i 6) (stringLength verdict)) ""))]
                (optionOr (listHead (stringSplit (stringReplace (stringReplace (stringReplace rest ")" " ") "\"" " ") "\\" " ") " ")) ""))))

fn writeClass verdict: String -> String
  (let [(v (stringTrim verdict))
        (stop (stopWord v))
        (first (stringReplace (optionOr (listHead (stringSplit v " ")) "") ":" ""))]
    (cond
      ((stringStartsWith? v "written") "written")
      ((stringStartsWith? v "stalled") "stalled")
      ((not (stringEmpty? stop)) stop)
      ((not (stringEmpty? first)) first)
      (else "other")))

fn parseRow line: String -> (Option Row)
  (let [(l (stringTrim line))
        (cut (stringIndexOf l " :verdict \""))
        (tail (stringSplit l " :ms "))
        (at (optionOr (stringToInt64 (stringReplace (optionOr (listLast (stringSplit l " :at ")) "") ")" "")) -1))]
    (match cut
      ((none) (none))
      ((some ci)
        (if (and (stringStartsWith? l "(:t :unit \"") (and (stringEndsWith? l ")") (and (>= at 0) (and (> (listLength tail) 1) (validUtf8? l)))))
          (let [(head (optionOr (stringSlice l 0 ci) ""))
                (vq (optionOr (stringSlice l (+ ci 11) (stringLength l)) ""))
                (vEnd (- (stringLength vq) (stringLength (str "\" :ms " (optionOr (listLast (stringSplit vq "\" :ms ")) "")))))]
            (some (Row :unit (headQuoted head ":unit") :to (headTok head ":to") :stage (headTok head ":stage") :model (headQuoted head ":model")
                       :verdict (optionOr (stringSlice vq 0 vEnd) "") :at at
                       :ms (optionOr (stringToInt64 (optionOr (listHead (stringSplit (optionOr (listLast tail) "") " ")) "")) 0))))
          (none)))))

fn mergeClass r: Row -> String
  (cond
    ((= r.to "merged") "merged")
    ((= r.to "blocked") "blocked")
    ((or (stringStartsWith? r.verdict "mergeRedFix") (stringContains? r.verdict "train red")) "red")
    (else "retry"))

fn reviewClass r: Row -> String
  (cond
    ((= r.verdict "pass") "pass")
    ((= r.verdict "start") "start")
    ((stringStartsWith? r.verdict "fail") "fail")
    (else "other"))

fn classOf r: Row -> String
  (if (= r.stage "write") (writeClass r.verdict)
    (if (= r.stage "review") (reviewClass r)
      (if (= r.stage "merge") (mergeClass r) "")))

fn tally keys: (List String) -> (List (Pair String Int64))
  (listSortBy (fn [(p (Pair String Int64))] -> Int64 (- 0 (pairSecond p)))
    (map (fn [(k String)] -> (Pair String Int64) (pair k (listCount (fn [(x String)] -> Bool (= x k)) keys))) (listSort (distinct keys))))

fn n x: Int64 -> String
  (stringFromInt64 x)

fn countsText pairs: (List (Pair String Int64)) -> String
  (stringJoin (map (fn [(p (Pair String Int64))] -> String (str "(" (pairFirst p) " " (n (pairSecond p)) ")")) pairs) " ")

fn countOf keys: (List String) k: String -> Int64
  (listCount (fn [(x String)] -> Bool (= x k)) keys)

fn inWindow r: Row from: Int64 to: Int64 -> Bool
  (and (>= r.at from) (<= r.at to))

; (:m :ref REVIEW-CLIP-FALSE-FAIL :do "a review row with verdict start marks entering the stage, not a review, and was counted under other (30 of 62); a written row with :ms 0 is a write stage in which the model wrote nothing because the work was already on the branch (claim, written 0 ms, gates, review fail, again): it is a rewrite, counted apart, outside :written and :pct")
fn writeClasses writes: (List Row) -> (List String)
  (map (fn [(r Row)] -> String (let [(c (writeClass r.verdict))] (if (and (= c "written") (= r.ms 0)) "rewrite" c))) writes)

fn statsText rows: (List Row) hours: Int64 from: Int64 to: Int64 skipped: Int64 -> String
  (let [(win (filter (fn [(r Row)] -> Bool (inWindow r from to)) rows))
        (writes (filter (fn [(r Row)] -> Bool (= r.stage "write")) win))
        (wClass (writeClasses writes))
        (written (countOf wClass "written"))
        (repeats (countOf wClass "rewrite"))
        (stops (filter (fn [(p (Pair String Int64))] -> Bool (and (!= (pairFirst p) "written") (!= (pairFirst p) "rewrite"))) (tally wClass)))
        (writeWith (listFlatMap (fn [(i Int64)] -> (List (Pair Row String)) (match (listGet writes i) ((some r) (list (pair r (optionOr (listGet wClass i) "")))) ((none) (list)))) (range 0 (listLength writes))))
        (models (listSort (distinct (map (fn [(r Row)] -> String (if (stringEmpty? r.model) "unknown" r.model)) writes))))
        (modelRow (fn [(m String)] -> String
                    (let [(mine (filter (fn [(r (Pair Row String))] -> Bool (= (if (stringEmpty? (pairFirst r).model) "unknown" (pairFirst r).model) m)) writeWith))
                          (ok (listCount (fn [(r (Pair Row String))] -> Bool (= (pairSecond r) "written")) mine))]
                      (str "(:m \"" m "\" :ok " (n ok) " :fail " (n (- (listLength mine) ok)) ")"))))
        (rv (map (fn [(r Row)] -> String (reviewClass r)) (filter (fn [(r Row)] -> Bool (and (= r.stage "review") (!= r.verdict "start"))) win)))
        (started (listCount (fn [(r Row)] -> Bool (and (= r.stage "review") (= r.verdict "start"))) win))
        (mg (map mergeClass (filter (fn [(r Row)] -> Bool (= r.stage "merge")) win)))
        (units (listSort (distinct (map (fn [(r Row)] -> String r.unit) (filter (fn [(r Row)] -> Bool (= r.to "merged")) win)))))
        (total (listLength writes))]
    (str "(:writeStats :hours " (n hours) " :from " (n from) " :to " (n to) " :skipped " (n skipped) "\n"
         "  (:write :n " (n total) " :written " (n written) " :pct " (n (if (= total 0) 0 (/ (* written 100) total))) " (:stop " (countsText stops) "))\n"
         "  (:byModel " (stringJoin (map modelRow models) " ") ")\n"
         "  (:review :n " (n (listLength rv)) " :pass " (n (countOf rv "pass")) " :fail " (n (countOf rv "fail")) " :other " (n (countOf rv "other")) ")\n"
         "  (:started :review " (n started) ")\n"
         "  (:rewrites :n " (n repeats) ")\n"
         "  (:merge :n " (n (listLength mg)) " :merged " (n (countOf mg "merged")) " :red " (n (countOf mg "red")) " :blocked " (n (countOf mg "blocked")) " :retry " (n (countOf mg "retry")) ")\n"
         "  (:units :merged " (n (listLength units)) "))"))

fn reportFor store: String hours: Int64 now: Int64 -> (Result String String)
  (match (fileReadString (str store "/journal.asn"))
    ((err e) (err (str "(:writeStats :error \"journal unreadable\" :store \"" store "\")")))
    ((ok text)
      (let [(lines (filter (fn [(l String)] -> Bool (not (stringEmpty? (stringTrim l)))) (stringLines text)))
            (parsed (map parseRow lines))
            (rows (listFlatMap (fn [(o (Option Row))] -> (List Row) (match o ((some r) (list r)) ((none) (list)))) parsed))
            (skipped (- (listLength lines) (listLength rows)))]
        (ok (statsText rows hours (- now (* hours 3600000)) now skipped)))))

fn flagVal args: (List String) name: String -> String
  (match (listIndexOf args name)
    ((some i) (optionOr (listGet args (+ i 1)) ""))
    ((none) ""))

fn ! main args: (List String) -> (Result Int64 String)
  (let [(store (flagVal args "--store"))
        (hoursText (flagVal args "--hours"))
        (hours (if (stringEmpty? hoursText) (some 24) (stringToInt64 hoursText)))
        (nowText (flagVal args "--now"))
        (now (if (stringEmpty? nowText) (some (/ (nowNs) 1000000)) (stringToInt64 nowText)))]
    (match hours
      ((none) (let [(_ (println "(:writeStats :usage \"run writeStats.asl --store DIR [--hours N] [--now MS]\")"))] (ok 2)))
      ((some h)
        (match now
          ((none) (let [(_ (println "(:writeStats :usage \"run writeStats.asl --store DIR [--hours N] [--now MS]\")"))] (ok 2)))
          ((some nw)
            (if (stringEmpty? store)
              (let [(_ (println "(:writeStats :usage \"run writeStats.asl --store DIR [--hours N] [--now MS]\")"))] (ok 2))
              (match (reportFor store h nw)
                ((ok t) (let [(_ (println t))] (ok 0)))
                ((err e) (let [(_ (println e))] (ok 1))))))))))

fn distinct xs: (List String) -> (List String)
  (fold (fn [(acc (List String)) (x String)] -> (List String) (if (listContains? acc x) acc (listAppend acc (list x)))) (list) xs)
