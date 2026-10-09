(module asl/agentLoop/tests/gitOpsTest
  :x [runTests]
  :i [(asl/agentLoop/gitOps :a g) (asl/agentLoop/core :a c)])

fn kvGet kv: (List (Pair String c/KvVal)) k: String -> (Option c/KvVal)
  (mt (listHead (filter (fn [p] (= (pairFirst p) k)) kv))
    ((some p) (some (pairSecond p)))
    ((none) (none)))

fn kvText v: c/KvVal -> String
  (mt v ((c/kvStr s) s) ((c/kvInt d) d))

fn getS kv: (List (Pair String c/KvVal)) k: String -> String
  (mt (kvGet kv k) ((some v) (kvText v)) ((none) ""))

fn getI kv: (List (Pair String c/KvVal)) k: String -> Int64
  (optionOr (stringToInt64 (getS kv k)) 0)

fn listed kv: (List (Pair String c/KvVal)) prefix: String -> (List String)
  (map (fn [i] (getS kv (str prefix (stringFromInt64 i)))) (range 0 (getI kv "n")))

fn envKey row: String -> String
  (mt (stringIndexOf row "=") ((some i) (c/sliceOf row 0 i)) ((none) row))

fn keptRow row: String -> Bool
  (let [k (envKey row)]
    (not (or (stringStartsWith? k "GIT_") (or (= k "LC_ALL") (or (= k "PATH") (stringEndsWith? k "_API_KEY"))))))

fn cleanEnv! pathDir: String -> (List String)
  (let [path (optionOr (envGet "PATH") "/usr/bin:/bin")]
    (listAppend (filter keptRow (envList))
      (list "GIT_CONFIG_GLOBAL=/dev/null" "GIT_CONFIG_NOSYSTEM=1" "LC_ALL=C"
        (str "PATH=" (if (stringEmpty? pathDir) path (str pathDir ":" path))))))

fn stubDir kind: String -> String
  (cond
    ((= kind "slow") "stubSlow")
    ((= kind "quiet") "stubQuiet")
    ((= kind "shSlow") "stubShSlow")
    ((= kind "shQuiet") "stubShQuiet")
    ((= kind "shStub") "stubSh")
    (else ""))

fn envFor! base: String kind: String -> (Option (List String))
  (if (= kind "inherit")
    (none)
    (let [d (stubDir kind)]
      (some (cleanEnv! (if (stringEmpty? d) "" (str base "/" d))))))

fn setupStep! base: String setupEnv: (List String) line: String -> Bool
  (let [kv (c/parseKv line)
        step (getS kv "step")
        path (str base "/" (getS kv "path"))]
    (cond
      ((= step "mkdir") (ok? (dirCreate path)))
      ((= step "write") (ok? (fileWrite path (getS kv "text"))))
      ((= step "run")
        (mt (g/runBounded! (listed kv "a") (some (str base "/" (getS kv "cwd"))) (some 60) (some (listAppend (cleanEnv! "") setupEnv)))
          ((ok b) (= (optionOr b.code -1) 0))
          ((err e) (do (eprintln (str "setup run failed: " e)) false))))
      (else false)))

fn withBase base: String s: String -> String
  (stringReplace s "@BASE@" base)

fn subBase base: String s: String -> String
  (stringReplace s base "@BASE@")

fn lineArgText a: g/LineArg -> String
  (mt a ((g/laNone) "none") ((g/laBad) "bad") ((g/laNum n) (stringFromInt64 n)))

fn optStr o: (Option c/KvVal) -> (Option String)
  (mt o ((some v) (some (kvText v))) ((none) (none)))

fn sliceText kv: (List (Pair String c/KvVal)) -> String
  (let [start (getI kv "start")
        end (getI kv "end")
        sl (g/gitSlice (getS kv "text") (if (= start 0) (none) (some start)) (if (< end 0) (none) (some end)) (getI kv "cap"))
        nums (pairSecond sl)]
    (str "(slice " (c/serString (pairFirst sl)) (c/joinAll (map (fn [n] (str " " (stringFromInt64 n))) nums)) ")"))

fn filesText base: String res: (Result (List String) String) -> String
  (mt res
    ((ok fs) (str "(files" (c/joinAll (map (fn [f] (str " " (c/serString (subBase base f)))) fs)) ")"))
    ((err e) (str "(error " (c/serString e) ")")))

fn pidAlive! pid: Int64 tries: Int64 -> Bool
  (cond
    ((<= pid 0) false)
    ((err? (procKill pid "SIGCONT")) false)
    ((<= tries 0) true)
    (else (do (sleepMs 20) (pidAlive! pid (- tries 1)))))

fn libcNeutral s: String -> String
  (stringReplace s "Filename too long" "File name too long")

fn runCase! base: String kv: (List (Pair String c/KvVal)) formats: (Map String String) -> (Pair String (Map String String))
  (let [fnName (getS kv "fn")
        root (withBase base (getS kv "root"))
        env (envFor! base (getS kv "env"))]
    (cond
      ((= fnName "gitOp")
        (let [ctx (g/makeGitCtx root (getS kv "mode") (getS kv "defaultBase") (getI kv "t") (getI kv "cap") env)]
          (pair (subBase base (g/serRec (g/execGitOp! (c/parseKv (withBase base (getS kv "op"))) ctx "ID"))) formats)))
      ((= fnName "isPathInRepo")
        (pair (if (g/isPathInRepo! (withBase base (getS kv "path")) root) "true" "false") formats))
      ((= fnName "lineArg")
        (pair (lineArgText (g/lineArg (kvGet (c/parseKv (getS kv "op")) "start"))) formats))
      ((= fnName "gitSlice") (pair (sliceText kv) formats))
      ((= fnName "nextForm")
        (let [op (c/parseKv (getS kv "op"))
              path (let [p (getS op "path")] (if (stringEmpty? p) (getS op "file") p))]
          (pair (g/gitNextForm (getS kv "opName") (getS op "rev") path (getS op "base") (optStr (kvGet op "limit")) (getI kv "start")) formats)))
      ((= fnName "runGates")
        (pair (subBase base (g/serRecs "gates" (g/runGates! (map (fn [x] (pair "ID" x)) (listed kv "g")) root (getI kv "t") env))) formats))
      ((= fnName "runGatesGroup")
        (let [recs (g/runGates! (map (fn [x] (pair "ID" (withBase base x))) (listed kv "g")) root (getI kv "t") env)
              pid (optionOr (stringToInt64 (stringTrim (resultOr (fileReadString (str base "/bg.pid")) ""))) 0)]
          (pair (str (subBase base (g/serRecs "gates" recs)) " (alive " (if (pidAlive! pid 100) "true" "false") ")") formats)))
      ((= fnName "preflight")
        (let [bad (g/gatePreflight! (listed kv "g") root env)]
          (pair (subBase base (g/serRecs "bad" bad)) (mapSet formats (getS kv "id") (subBase base (g/formatGatePreflight bad))))))
      ((= fnName "formatPreflight")
        (pair (optionOr (mapGet formats (getS kv "of")) "(no preflight case)") formats))
      ((= fnName "changedOwned")
        (pair (filesText base (g/changedOwnedFiles! (listed kv "o") root (envFor! base "clean"))) formats))
      (else (pair (str "(unknown fn " fnName ")") formats))))

fn firstDiff a: String b: String i: Int64 -> Int64
  (if (or (>= i (stringLength a)) (or (>= i (stringLength b)) (!= (c/sliceOf a i (+ i 1)) (c/sliceOf b i (+ i 1))))) i (firstDiff a b (+ i 1)))

fn around s: String i: Int64 -> String
  (c/sliceOf s (max 0 (- i 80)) (min (stringLength s) (+ i 160)))

fn replay! base: String lines: (List String) formats: (Map String String) acc: (List (Pair String Bool)) -> (List (Pair String Bool))
  (if (listEmpty? lines)
    (listReverse acc)
    (let [kv (c/parseKv (c/firstOf lines))
          id (getS kv "id")
          want (getS kv "want")
          res (runCase! base kv formats)
          got (libcNeutral (pairFirst res))
          same (= got want)
          at (firstDiff got want 0)]
      (do
        (if same true (do (eprintln (str "MISMATCH " id " at " (stringFromInt64 at) "\n  want " (around want at) "\n  got  " (around got at))) false))
        (replay! base (c/restOf lines) (pairSecond res) (cons (pair id same) acc)))))

fn ! runTests -> Bool
  (let [root (resultOr (realPath ".") ".")
        content (resultOr (fileReadString (str root "/asl/agentLoop/tests/gitOpsFixture.asn")) "")
        all (stringLines content)
        header (c/parseKv (optionOr (listHead all) ""))
        cases (filter (fn [l] (stringStartsWith? l "(:case ")) all)
        setups (filter (fn [l] (stringStartsWith? l "(:setup ")) all)
        setupEnv (map (fn [l] (let [kv (c/parseKv l)] (str (getS kv "k") "=" (getS kv "v"))))
                   (filter (fn [l] (stringStartsWith? l "(:env ")) all))
        tmp (str (optionOr (envGet "TMPDIR") "/tmp") "/aslGitOpsTest" (stringFromInt64 (nowNs)))
        made (dirCreate tmp)
        base (resultOr (realPath tmp) tmp)
        setupOk (listAll? (fn [l] (setupStep! base setupEnv l)) setups)
        n (listLength cases)]
    (do
      (assert (ok? made) "the temporary base directory is created")
      (assert setupOk "every setup step of the fixture recipe succeeds")
      (assert (= n (getI header "cases")) "the fixture holds the number of cases its header declares")
      (assert (>= n 150) "the fixture holds at least 150 cases")
      (let [results (replay! base cases (mapEmpty) (list))
            removed (pathRemove base)
            passed (listLength (filter (fn [r] (pairSecond r)) results))]
        (do
          (assert (ok? removed) "the temporary base directory is removed")
          (assert (= (listLength results) n) "every case of the fixture was replayed")
          (fold (fn [acc r] (do (assert (pairSecond r) (str "case " (pairFirst r) " matches the Python original")) acc)) true results)
          (= passed n)))))
