(module asl-know/query
  :x [Entry Row termsOf loadEntries! answer]
  :i [(asl-know/scan :a sc) (asl-know/render :a r)])

; (:m :tags (know) :note "intent query: IDF-weighted term overlap of query words with card and symbol words, camelCase split; an exact card id or symbol name wins; output fills a bytes/3.6 token budget")

(schema Row (:f card String) (:f name String) (:f line String) (:f nameTerms (List String)) (:f textTerms (List String)))

(schema Entry (:f id String) (:f line String) (:f terms (List String)) (:f rows (List Row)))

fn lowerAlnum c: String -> String
  (let [(k (charCode c))]
    (cond
      ((and (>= k 65) (<= k 90)) (str " " (stringLower c)))
      ((or (and (>= k 97) (<= k 122)) (and (>= k 48) (<= k 57))) c)
      (else " ")))

fn stopWords -> (List String)
  (list "a" "an" "the" "to" "of" "in" "on" "for" "and" "or" "is" "it" "by" "as" "at" "be" "with" "from" "into" "that" "this" "asl" "how" "do" "use" "using" "my" "me" "i" "fn" "get" "some" "none")

fn stem w: String -> String
  (if (and (> (stringLength w) 4) (stringEndsWith? w "s") (not (stringEndsWith? w "ss"))) (optionOr (stringSlice w 0 (- (stringLength w) 1)) w) w)

fn termsOf s: String -> (List String)
  (listFlatMap expand (filter (fn [(w String)] -> Bool (and (> (stringLength w) 1) (not (listContains? (stopWords) w))))
                    (stringSplit (sc/compact (stringJoin (map lowerAlnum (stringChars s)) "")) " ")))

fn rowOf card: String line: String -> Row
  (let [(name (optionOr (sc/fieldAfter line "(:sym") ""))
        (mod (optionOr (sc/fieldAfter line ":mod") ""))]
    (Row :card card :name name :line line :nameTerms (termsOf name)
         :textTerms (termsOf (str (optionOr (sc/fieldAfter line ":doc") "") " " mod))))

fn entryOf text: String -> (Option Entry)
  (let [(lines (filter (fn [(l String)] -> Bool (not (stringEmpty? l))) (stringLines text)))
        (head (optionOr (listHead lines) ""))]
    (match (sc/fieldAfter head "(:card")
      ((none) (none))
      ((some id)
        (some (Entry :id id :line head :terms (termsOf (str id " " (optionOr (sc/fieldAfter head ":purpose") "")))
                     :rows (map (fn [(l String)] -> Row (rowOf id l)) (optionOr (listTail lines) (list))))))))

fn ! loadEntries! dir: String -> (List Entry)
  (match (dirList dir)
    ((err _) (list))
    ((ok names)
      (listFlatMap (fn [(n String)] -> (List Entry)
                     (if (or (= n "index.asn") (not (stringEndsWith? n ".asn")))
                       (list)
                       (match (fileReadString (str dir "/" n))
                         ((err _) (list))
                         ((ok t) (match (entryOf t) ((some e) (list e)) ((none) (list)))))))
                   names)))

fn hit? t: String w: String -> Bool
  (or (= t w)
      (and (>= (stringLength t) 3) (stringContains? w t))
      (and (>= (stringLength w) 4) (stringStartsWith? t w)))

fn has? ws: (List String) t: String -> Bool
  (listAny? (fn [(w String)] -> Bool (hit? t w)) ws)

fn idfOf n: Int64 df: Int64 -> Float64
  (log (/ (+ (int64ToFloat64 n) 1.0) (+ (int64ToFloat64 df) 0.5)))

fn rowScore qs: (List (Pair String Float64)) cardTerms: (List String) row: Row -> Float64
  (fold (fn [(acc Float64) (p (Pair String Float64))] -> Float64
          (let [(t (pairFirst p)) (w (pairSecond p))]
            (+ acc (* w (+ (if (has? row.nameTerms t) 3.0 0.0) (+ (if (has? row.textTerms t) 1.0 0.0) (if (has? cardTerms t) 1.5 0.0)))))))
        0.0 qs)

fn weights qs: (List String) es: (List Entry) -> (List (Pair String Float64))
  (let [(rows (listFlatMap (fn [(e Entry)] -> (List (List String)) (cons e.terms (map (fn [(r Row)] -> (List String) (listAppend r.nameTerms r.textTerms)) e.rows))) es))
        (n (listLength rows))]
    (map (fn [(t String)] -> (Pair String Float64) (pair t (idfOf n (listCount (fn [(ws (List String))] -> Bool (has? ws t)) rows)))) qs))

fn dedupe xs: (List String) acc: (List String) -> (List String)
  (match (listHead xs)
    ((none) (listReverse acc))
    ((some x) (dedupe (optionOr (listTail xs) (list)) (if (listContains? acc x) acc (cons x acc)))))

fn scored es: (List Entry) qs: (List (Pair String Float64)) -> (List (Pair Entry (Pair Float64 (List (Pair Row Float64)))))
  (map (fn [(e Entry)] -> (Pair Entry (Pair Float64 (List (Pair Row Float64))))
         (let [(rs (listSortBy (fn [(p (Pair Row Float64))] -> Float64 (- 0.0 (pairSecond p)))
                               (filter (fn [(p (Pair Row Float64))] -> Bool (> (pairSecond p) 0.0))
                                       (map (fn [(r Row)] -> (Pair Row Float64) (pair r (* (prior e.id) (rowScore qs e.terms r)))) e.rows))))
               (own (fold (fn [(acc Float64) (p (Pair String Float64))] -> Float64 (+ acc (if (has? e.terms (pairFirst p)) (* 2.0 (pairSecond p)) 0.0))) 0.0 qs))
               (best (optionOr (optionMap pairSecond (listGet rs 0)) 0.0))
               (second (optionOr (optionMap pairSecond (listGet rs 1)) 0.0))]
           (pair e (pair (+ own (+ best (* 0.5 second))) rs))))
       es)

fn fillRows rows: (List String) room: Int64 acc: (List String) -> (List String)
  (match (listHead rows)
    ((none) (listReverse acc))
    ((some l)
      (let [(t (r/tokensOf l))]
        (if (> t room) (fillRows (optionOr (listTail rows) (list)) room acc) (fillRows (optionOr (listTail rows) (list)) (- room t) (cons l acc))))))

fn exactAnswer es: (List Entry) query: String -> (Option (Pair (List Entry) (List String)))
  (let [(qq (stringTrim query))
        (byCard (filter (fn [(e Entry)] -> Bool (or (= e.id qq) (= e.id (str "asl-" qq)) (= e.id (str "core/" qq)))) es))
        (bySym (listFlatMap (fn [(e Entry)] -> (List Row) (filter (fn [(r Row)] -> Bool (= r.name qq)) e.rows)) es))]
    (cond
      ((not (listEmpty? byCard)) (some (pair (listTake byCard 1) (list))))
      ((not (listEmpty? bySym))
        (some (pair (filter (fn [(e Entry)] -> Bool (listAny? (fn [(r Row)] -> Bool (= r.card e.id)) bySym)) es)
                    (map (fn [(r Row)] -> String r.line) bySym))))
      (else (none))))

fn fillCards cs: (List Entry) room: Int64 acc: (List Entry) -> (List Entry)
  (match (listHead cs)
    ((none) (listReverse acc))
    ((some c)
      (if (> (r/tokensOf c.line) room)
        (fillCards (optionOr (listTail cs) (list)) room acc)
        (fillCards (optionOr (listTail cs) (list)) (- room (r/tokensOf c.line)) (cons c acc)))))

fn render query: String budget: Int64 cards: (List Entry) rows: (List String) how: String -> String
  (let [(cardLines (map (fn [(e Entry)] -> String e.line) cards))
        (used0 (fold (fn [(acc Int64) (l String)] -> Int64 (+ acc (r/tokensOf l))) 0 cardLines))
        (shown (fillRows (dedupe rows (list)) (- budget used0) (list)))
        (used (+ used0 (fold (fn [(acc Int64) (l String)] -> Int64 (+ acc (r/tokensOf l))) 0 shown)))
        (head (str "(:know :q " (r/q query) " :match " how " :budget " budget " :used " used " :tokensBy bytes36 :cards (" (stringJoin (map (fn [(e Entry)] -> String (r/q e.id)) cards) " ") ") :rows " (listLength shown) ")"))]
    (stringJoin (cons head (listAppend cardLines shown)) "\n"))

fn answer es: (List Entry) query: String budget: Int64 -> String
  (match (exactAnswer es query)
    ((some hit) (render query budget (fillCards (listTake (pairFirst hit) 2) budget (list)) (pairSecond hit) "exact"))
    ((none)
      (let [(qs (weights (dedupe (termsOf query) (list)) es))
            (ranked (listSortBy (fn [(p (Pair Entry (Pair Float64 (List (Pair Row Float64)))))] -> Float64 (- 0.0 (pairFirst (pairSecond p))))
                                (filter (fn [(p (Pair Entry (Pair Float64 (List (Pair Row Float64)))))] -> Bool (> (pairFirst (pairSecond p)) 0.0)) (scored es qs))))
            (top (optionOr (optionMap (fn [(p (Pair Entry (Pair Float64 (List (Pair Row Float64)))))] -> Float64 (pairFirst (pairSecond p))) (listHead ranked)) 0.0))
            (picked (filter (fn [(p (Pair Entry (Pair Float64 (List (Pair Row Float64)))))] -> Bool (>= (pairFirst (pairSecond p)) (* 0.6 top))) (listTake ranked 2)))
            (cards (fillCards (map pairFirst picked) (/ (* budget 4) 5) (list)))
            (rowsOf (fn [(p (Pair Entry (Pair Float64 (List (Pair Row Float64)))))] -> (List (Pair Row Float64)) (pairSecond (pairSecond p))))
            (allRows (listSortBy (fn [(p (Pair Row Float64))] -> Float64 (- 0.0 (pairSecond p))) (listFlatMap rowsOf (listTake ranked 6))))
            (rows (map (fn [(p (Pair Row Float64))] -> String (pairFirst p).line) (listTake allRows 12)))]
        (if (listEmpty? ranked)
          (str "(:know :q " (r/q query) " :match none :hint \"no card matches; read cards/index.asn or ask by package name\")")
          (render query budget cards rows "intent")))))

fn coverage e: Entry t: String -> Float64
  (cond
    ((listAny? (fn [(r Row)] -> Bool (has? r.nameTerms t)) e.rows) 3.0)
    ((has? e.terms t) 2.0)
    ((listAny? (fn [(r Row)] -> Bool (has? r.textTerms t)) e.rows) 1.0)
    (else 0.0))

fn prior id: String -> Float64
  (if (stringStartsWith? id "core/") 1.25 1.0)

fn synonyms -> (List (Pair String (List String)))
  [(pair "directory" ["dir"]) (pair "folder" ["dir"]) (pair "shell" ["process"]) (pair "command" ["process"])
   (pair "decompress" ["inflate" "gunzip"]) (pair "unzip" ["gunzip"]) (pair "hash" ["sha256"]) (pair "digest" ["sha256"])]

fn expand w: String -> (List String)
  (let [(s (stem w))]
    (cons s (optionOr (optionMap pairSecond (listFind (fn [(p (Pair String (List String)))] -> Bool (= (pairFirst p) s)) (synonyms))) [])))
