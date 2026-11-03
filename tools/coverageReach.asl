(module asl-tools/coverageReach
  :x [Scan Row headerName scanLines reachable unreachedRows! main]
  :i [(asl-tools/coverageRatchet :a cr)])

(schema Scan
  (:f cur String)
  (:f edges (Map String (Map String Bool))))

(schema Row
  (:f pkg String)
  (:f file String)
  (:f name String)
  (:f callers Int64))

fn words line: String -> (List String)
  (filter (fn [(w String)] -> Bool (not (stringEmpty? w))) (stringSplit line " "))

fn nameAfterBang ws: (List String) -> String
  (if (= (optionOr (listGet ws 0) "") "!") (optionOr (listGet ws 1) "") (optionOr (listGet ws 0) ""))

fn headerName line: String -> String
  (let [(ws (words line))
        (first (optionOr (listGet ws 0) ""))]
    (cond
      ((and (= first "fn") (stringStartsWith? line "fn ")) (nameAfterBang (optionOr (listSlice ws 1 (listLength ws)) (list))))
      ((and (= first "tailrec") (stringStartsWith? line "tailrec fn ") (= (optionOr (listGet ws 1) "") "fn")) (nameAfterBang (optionOr (listSlice ws 2 (listLength ws)) (list))))
      (else "")))

fn topLevel? line: String -> Bool
  (and (not (stringEmpty? line)) (not (stringStartsWith? line " ")) (not (stringStartsWith? line "\t")) (not (stringStartsWith? line ";")))

fn scanLine sc: Scan line: String -> Scan
  (let [(h (headerName line))]
    (cond
      ((not (stringEmpty? h)) (Scan :cur h :edges (if (mapHas? sc.edges h) sc.edges (mapSet sc.edges h (mapEmpty)))))
      ((topLevel? line) (with sc :cur ""))
      ((stringEmpty? sc.cur) sc)
      (else (with sc :edges (mapSet sc.edges sc.cur (cr/tokenSet line (mapGetOr sc.edges sc.cur (mapEmpty))))))))

fn scanLines edges: (Map String (Map String Bool)) src: String -> (Map String (Map String Bool))
  (let [(end (fold scanLine (Scan :cur "" :edges edges) (stringLines src)))] end.edges)

fn visit edges: (Map String (Map String Bool)) todo: (List String) seen: (Map String Bool) -> (Map String Bool)
  (match (listHead todo)
    ((none) seen)
    ((some name)
      (let [(rest (optionOr (listTail todo) (list)))
            (next (filter (fn [(k String)] -> Bool (and (mapHas? edges k) (not (mapHas? seen k)))) (mapKeys (mapGetOr edges name (mapEmpty)))))
            (seen2 (fold (fn [(m (Map String Bool)) (k String)] -> (Map String Bool) (mapSet m k true)) seen next))]
        (visit edges (listAppend next rest) seen2))))

fn reachable edges: (Map String (Map String Bool)) seeds: (Map String Bool) -> (Map String Bool)
  (let [(start (filter (fn [(k String)] -> Bool (mapHas? edges k)) (mapKeys seeds)))
        (seen (fold (fn [(m (Map String Bool)) (k String)] -> (Map String Bool) (mapSet m k true)) (mapEmpty) start))]
    (visit edges start seen))

fn callerCounts edges: (Map String (Map String Bool)) -> (Map String Int64)
  (fold (fn [(acc (Map String Int64)) (name String)] -> (Map String Int64)
          (fold (fn [(a (Map String Int64)) (k String)] -> (Map String Int64) (mapSet a k (+ 1 (mapGetOr a k 0)))) acc (mapKeys (mapGetOr edges name (mapEmpty)))))
        (mapEmpty)
        (mapKeys edges))

fn ! srcFiles! root: String pkgs: (List String) -> (List String)
  (fold (fn [(acc (List String)) (p String)] -> (List String) (listAppend acc (cr/walk! (str root "/asl/packages/" p "/src"))))
        (list (str root "/asl/prelude/prelude.asl"))
        pkgs)

fn ! pkgNames! root: String -> (List String)
  (match (dirList (str root "/asl/packages")) ((err _) (list)) ((ok names) names))

fn pkgOf root: String file: String -> String
  (optionOr (listGet (stringSplit (stringReplace file (str root "/asl/packages/") "") "/") 0) "")

fn ! unreachedRows! root: String -> (List Row)
  (let [(pkgs (pkgNames! root))
        (files (srcFiles! root pkgs))
        (sources (map (fn [(f String)] -> (Pair String String) (pair f (match (fileReadString f) ((ok s) s) ((err _) "")))) files))
        (edges (fold (fn [(e (Map String (Map String Bool))) (fs (Pair String String))] -> (Map String (Map String Bool)) (scanLines e (pairSecond fs))) (mapEmpty) sources))
        (seen (reachable edges (cr/readTokens! (cr/testFiles! root))))
        (counts (callerCounts edges))
        (rows (fold (fn [(acc (List Row)) (fs (Pair String String))] -> (List Row)
                      (listAppend acc (map (fn [(n String)] -> Row (Row :pkg (pkgOf root (pairFirst fs)) :file (stringReplace (pairFirst fs) (str root "/") "") :name n :callers (mapGetOr counts n 0)))
                                           (filter (fn [(n String)] -> Bool (and (mapHas? edges n) (not (mapHas? seen n)))) (cr/exportedFns (pairSecond fs))))))
                    (list)
                    sources))]
    (listSortBy (fn [(r Row)] -> Int64 (- 0 r.callers)) rows))

fn rowLine r: Row -> String
  (str "(:unreached :pkg " r.pkg " :file \"" r.file "\" :fn " r.name " :callers " r.callers ")")

fn argValue args: (List String) flag: String fallback: String -> String
  (match (listIndexOf args flag) ((none) fallback) ((some i) (optionOr (listGet args (+ i 1)) fallback)))

fn ! main args: (List String) -> (Result Int64 String)
  (let [(root (argValue args "--root" "."))
        (limit (optionOr (stringToInt64 (argValue args "--limit" "50")) 50))
        (rows (unreachedRows! root))]
    (do
      (map (fn [(r Row)] -> Unit (println (rowLine r))) (listTake rows limit))
      (println (str "(:coverageReach :unreached " (listLength rows) " :shown " (min limit (listLength rows)) ")"))
      (ok 0)))
