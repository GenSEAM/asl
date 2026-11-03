(module asl-tools/coverageRatchet
  :x [Count readTokens! Verdict verdict! isDelim atomEnd afterLastSeparator tokenSet exportedFns countPackage parseRow parseBaseline renderBaseline violations raised walk! testFiles! packageCounts! main]
  :i [])

(schema Count
  (:f pkg String)
  (:f exports Int64)
  (:f covered Int64))

fn cut s: String i: Int64 j: Int64 -> String
  (optionOr (stringSlice s i j) "")

fn isDelim c: Int64 -> Bool
  (or (= c 32) (= c 9) (= c 13) (= c 10) (= c 40) (= c 41) (= c 91) (= c 93) (= c 123) (= c 125) (= c 34) (= c 39) (= c 96) (= c 44) (= c 59))

fn atomEnd b: Bytes n: Int64 i: Int64 -> Int64
  (if (or (>= i n) (isDelim (bytesGet b i))) i (atomEnd b n (+ i 1)))

fn lastSeparator tok: String b: Bytes n: Int64 i: Int64 -> String
  (cond
    ((< i 0) tok)
    ((or (= (bytesGet b i) 46) (= (bytesGet b i) 47)) (cut tok (+ i 1) n))
    (else (lastSeparator tok b n (- i 1))))

fn afterLastSeparator tok: String -> String
  (let [(b (stringToBytes tok)) (n (bytesLength b))]
    (lastSeparator tok b n (- n 1)))

fn tokenLoop src: String b: Bytes n: Int64 i: Int64 acc: (Map String Bool) -> (Map String Bool)
  (cond
    ((>= i n) acc)
    ((isDelim (bytesGet b i)) (tokenLoop src b n (+ i 1) acc))
    (else
      (let [(j (atomEnd b n i)) (t (cut src i j)) (s (afterLastSeparator t))]
        (tokenLoop src b n j (mapSet (if (= s t) acc (mapSet acc s true)) t true)))))

fn tokenSet src: String acc: (Map String Bool) -> (Map String Bool)
  (let [(b (stringToBytes src))] (tokenLoop src b (bytesLength b) 0 acc))

fn lowerFirst? name: String -> Bool
  (let [(b (stringToBytes name))]
    (and (> (bytesLength b) 0) (>= (bytesGet b 0) 97) (<= (bytesGet b 0) 122)))

fn blankToSpace s: String -> String
  (stringReplace (stringReplace (stringReplace s "\n" " ") "\t" " ") "\r" " ")

fn exportBody body: String -> (List String)
  (filter lowerFirst? (filter (fn [(w String)] -> Bool (not (stringEmpty? w))) (stringSplit (blankToSpace body) " ")))

fn exportLoop src: String acc: (List String) -> (List String)
  (match (stringIndexOf src ":x [")
    ((none) acc)
    ((some at)
      (let [(rest (cut src (+ at 4) (stringLength src)))
            (close (optionOr (stringIndexOf rest "]") (stringLength rest)))]
        (exportLoop (cut rest close (stringLength rest)) (listAppend acc (exportBody (cut rest 0 close)))))))

fn exportedFns src: String -> (List String)
  (exportLoop src (list))

fn countPackage pkg: String exports: (List String) tokens: (Map String Bool) -> Count
  (Count :pkg pkg :exports (listLength exports) :covered (listLength (filter (fn [(e String)] -> Bool (mapHas? tokens e)) exports)))

fn rowLine c: Count -> String
  (str "  (:pkg " c.pkg " :exports " c.exports " :covered " c.covered ")")

fn renderBaseline date: String rows: (List Count) -> String
  (str "(:coverageBaseline :date \"" date "\" :unit COVRATCHET\n"
       "  :method \"per package under asl/packages: module :x exports whose name starts lowercase, covered when the bare name (or its part after the last . or /) is a token of any .asl under a tests/ or test/ directory; tools/coverageRatchet.asl counts it; a name that appears in a test counts, so the figures are an upper bound (a mention in a comment or a same-named function elsewhere counts); a package covered count only rises\"\n"
       (stringJoin (map rowLine rows) "\n") ")\n")

fn parseRow line: String -> (Option Count)
  (let [(w (filter (fn [(x String)] -> Bool (not (stringEmpty? x))) (stringSplit (stringReplace line ")" "") " ")))]
    (if (and (= (listLength w) 6) (= (optionOr (listGet w 0) "") "(:pkg") (= (optionOr (listGet w 2) "") ":exports") (= (optionOr (listGet w 4) "") ":covered"))
      (match (stringToInt64 (optionOr (listGet w 3) ""))
        ((none) (none))
        ((some e) (match (stringToInt64 (optionOr (listGet w 5) ""))
                    ((none) (none))
                    ((some c) (some (Count :pkg (optionOr (listGet w 1) "") :exports e :covered c))))))
      (none)))

fn parseBaseline text: String -> (List Count)
  (fold (fn [(acc (List Count)) (line String)] -> (List Count)
          (match (parseRow line) ((none) acc) ((some c) (listAppend acc (list c)))))
        (list)
        (filter (fn [(l String)] -> Bool (stringStartsWith? (stringTrim l) "(:pkg ")) (stringLines text)))

fn findRow rows: (List Count) pkg: String -> (Option Count)
  (listHead (filter (fn [(c Count)] -> Bool (= c.pkg pkg)) rows))

fn violation base: Count current: (List Count) -> (Option String)
  (match (findRow current base.pkg)
    ((none) (some (str base.pkg ": baseline row has no package or no exports left; remove the row if the package is gone")))
    ((some c) (if (< c.covered base.covered)
                (some (str base.pkg ": covered " c.covered " of " c.exports " is below the baseline " base.covered))
                (none))))

fn violations baseline: (List Count) current: (List Count) -> (List String)
  (fold (fn [(acc (List String)) (b Count)] -> (List String)
          (match (violation b current) ((none) acc) ((some v) (listAppend acc (list v)))))
        (list)
        baseline)

fn raisedRow c: Count baseline: (List Count) -> Count
  (match (findRow baseline c.pkg)
    ((none) c)
    ((some b) (if (> c.covered b.covered) c b)))

fn raised baseline: (List Count) current: (List Count) -> (List Count)
  (map (fn [(c Count)] -> Count (raisedRow c baseline)) current)

fn skipDir? name: String -> Bool
  (or (= name "node_modules") (= name ".git") (= name ".asl"))

fn ! walkEntry! dir: String name: String -> (List String)
  (let [(path (str dir "/" name))]
    (cond
      ((skipDir? name) (list))
      ((stringEndsWith? name ".asl") (list path))
      (else (match (fileStat path)
              ((err _) (list))
              ((ok st) (if st.isDir (walk! path) (list)))))))

fn ! walk! dir: String -> (List String)
  (match (dirList dir)
    ((err _) (list))
    ((ok names) (fold (fn [(acc (List String)) (name String)] -> (List String) (listAppend acc (walkEntry! dir name))) (list) names)))

fn testPath? path: String -> Bool
  (or (stringStartsWith? path "tests/") (stringContains? path "/tests/") (stringContains? path "/test/"))

fn ! testFiles! root: String -> (List String)
  (filter testPath?
          (fold (fn [(acc (List String)) (d String)] -> (List String) (listAppend acc (walk! (str root "/" d))))
                (list)
                (list "asl/packages" "asl/prelude" "asl/agentLoop" "harness" "tools" "tests")))

fn ! readTokens! files: (List String) -> (Map String Bool)
  (fold (fn [(acc (Map String Bool)) (f String)] -> (Map String Bool)
          (match (fileReadString f) ((err _) acc) ((ok src) (tokenSet src acc))))
        (mapEmpty)
        files)

fn ! packageExports! dir: String -> (List String)
  (fold (fn [(acc (List String)) (f String)] -> (List String)
          (match (fileReadString f) ((err _) acc) ((ok src) (listAppend acc (exportedFns src)))))
        (list)
        (walk! (str dir "/src")))

fn ! packageCounts! root: String -> (List Count)
  (let [(tokens (readTokens! (testFiles! root)))
        (pkgs (match (dirList (str root "/asl/packages")) ((err _) (list)) ((ok names) names)))]
    (filter (fn [(c Count)] -> Bool (> c.exports 0))
            (map (fn [(p String)] -> Count (countPackage p (packageExports! (str root "/asl/packages/" p)) tokens)) pkgs)))

fn argValue args: (List String) flag: String fallback: String -> String
  (match (listIndexOf args flag) ((none) fallback) ((some i) (optionOr (listGet args (+ i 1)) fallback)))

fn ! show! v: String -> Unit
  (println (str "(:violation " v ")"))

fn ! main args: (List String) -> (Result Int64 String)
  (let [(root (argValue args "--root" "."))
        (path (argValue args "--baseline" (str root "/tools/coverageBaseline.asn")))
        (current (packageCounts! root))
        (exports (fold (fn [(a Int64) (c Count)] -> Int64 (+ a c.exports)) 0 current))
        (covered (fold (fn [(a Int64) (c Count)] -> Int64 (+ a c.covered)) 0 current))
        (baseline (match (fileReadString path) ((err _) (list)) ((ok text) (parseBaseline text))))
        (bad (violations baseline current))]
    (cond
      ((listContains? args "--update")
        (if (not (listEmpty? bad))
          (do (map show! bad) (err "baseline not raised: a package is below it"))
          (match (fileWrite path (renderBaseline (argValue args "--date" "") (raised baseline current)))
            ((err e) (err e))
            ((ok _) (do (println (str "(:coverageRatchet :updated " (listLength current) " :exports " exports " :covered " covered ")")) (ok 0))))))
      ((listEmpty? baseline) (err (str "no baseline at " path "; run with --update")))
      (else
        (do (map show! bad)
            (println (str "(:coverageRatchet :packages " (listLength current) " :exports " exports " :covered " covered " :violations " (listLength bad) ")"))
            (ok (if (listEmpty? bad) 0 1))))))

(schema Verdict
  (:f violations (List String))
  (:f packages Int64)
  (:f covered Int64))

fn ! verdict! root: String path: String -> Verdict
  (let [(current (packageCounts! root))
        (covered (fold (fn [(a Int64) (c Count)] -> Int64 (+ a c.covered)) 0 current))
        (baseline (match (fileReadString path) ((err _) (list)) ((ok text) (parseBaseline text))))]
    (Verdict :violations (cond ((listEmpty? current) (list)) ((listEmpty? baseline) (list (str "no baseline at " path))) (else (violations baseline current)))
             :packages (listLength current)
             :covered covered))
