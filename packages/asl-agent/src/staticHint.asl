(module aslAgent/staticHint
  :x [staticHint]
  :i [(aslAgent/diff :a diff)])

; (:m :do "one turn's op receipts become one ASN hint form, or none")

fn quoteChar -> String
  "\""

fn quotedField line: String key: String -> (Option String)
  (match (listGet (stringSplit line (stringConcat key " \"")) 1)
    ((none) (none))
    ((some tail) (listHead (stringSplit tail "\""))))

fn baseName p: String -> String
  (optionOr (listLast (stringSplit p "/")) p)

fn dirName p: String -> String
  (let [(parts (stringSplit p "/"))
        (n (listLength parts))]
    (if (<= n 1)
      ""
      (stringJoin (listTake parts (- n 1)) "/")))

fn ! score1 base: String n: String -> Int64
  (- 0 (optionOr (float64ToInt64 (* 1000.0 (diff/ratio base n))) 0))

fn ! scoreNames base: String names: (List String) -> (List (Pair Int64 String))
  (map (fn [n] (pair (score1 base n) n)) names)

fn ! nearIn root: String dir: String base: String -> (List String)
  (let [(full (if (stringEmpty? dir) root (stringConcat (stringConcat root "/") dir)))
        (names (resultOr (dirList full) (list)))
        (scored (listSortBy (fn [p] (pairFirst p)) (scoreNames base names)))]
    (listTake (map (fn [p] (pairSecond p)) scored) 5))

fn ! nearFiles root: String f: String -> (List String)
  (let [(ns (nearIn root (dirName f) (baseName f)))]
    (if (listEmpty? ns)
      (nearIn root (dirName (dirName f)) (baseName f))
      ns))

fn missingForm f: String names: (List String) -> String
  (let [(q (quoteChar))
        (quoted (map (fn [n] (str q n q)) names))
        (joined (stringJoin quoted " "))]
    (str "(:hint :missing " q f q " :near (" joined "))"))

fn ! missingHint line: String root: String -> (Option String)
  (if (stringContains? line "ERR_NOT_FOUND")
    (optionMap (fn [f] (missingForm f (nearFiles root f))) (quotedField line ":file"))
    (none))

fn rawMissing? line: String -> Bool
  (or (stringContains? line "ERR_RAW_MISSING")
    (and (stringContains? line "missing") (stringContains? line ":raw")))

fn writeOrEdit? line: String -> Bool
  (or (stringContains? line ":op \"write\"")
    (stringContains? line ":op \"edit\""))

fn writeShapeHint line: String -> (Option String)
  (let [(q (quoteChar))
        (hit (and (stringContains? line ":status :rejected") (and (writeOrEdit? line) (rawMissing? line))))]
    (if hit
      (optionMap (fn [f] (str "(:hint :writeShape " q "(:write :file " f " :raw [[...]])" q ")")) (quotedField line ":file"))
      (none)))

fn gateFailed? line: String -> Bool
  (and (stringContains? line ":op \"gate\"")
    (or (stringContains? line ":status :failed") (stringContains? line ":status :error")))

fn ! lineHint line: String root: String -> (Option String)
  (match (missingHint line root)
    ((some h) (some h))
    ((none) (writeShapeHint line)))

fn ! scanLines lines: (List String) root: String -> (Option String)
  (fold (fn [acc l] (if (some? acc) acc (lineHint l root))) (none) lines)

fn ! staticHint receipts: String root: String -> (Option String)
  (let [(lines (stringLines receipts))
        (firstHit (scanLines lines root))
        (red (listAny? (fn [l] (gateFailed? l)) lines))
        (changed (stringContains? receipts ":persisted true"))]
    (if (some? firstHit)
      firstHit
      (if (and red (not changed))
        (some (str "(:hint :editFirst " (quoteChar) "the gate is red and nothing changed; edit before re-running it" (quoteChar) ")"))
        (none))))
