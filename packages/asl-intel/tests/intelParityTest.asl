(module asl-intel/tests/intelParityTest
  :x [runTests]
  :i [(asl-intel :a intel)
      (asl-intel/host :a h)
      (asl-intel/text :a t)
      (asl-intel/fixture :a fx)
      (asl-tools/fleet/run :a fr)])

(schema Case
  (:f id String)
  (:f tree String)
  (:f git String)
  (:f path String)
  (:f cwd String)
  (:f aslRoot String)
  (:f argv (List String))
  (:f out String)
  (:f err String)
  (:f code Int64)
  (:f log String))

(schema TreeFile
  (:f path String)
  (:f exec Bool)
  (:f text String))

(schema Verdict
  (:f id String)
  (:f setup String)
  (:f out Bool)
  (:f err Bool)
  (:f code Bool)
  (:f log Bool))

fn fixturePath -> String
  "tests/parity/intel/intelParityFixtures.asn"

fn badWords -> (List String)
  (list ".git" "node_modules" "dist" "target" "build" "scratch" "test" "fixtures" "corpus" "examples" "invalid")

fn safeBase! -> (Result String String)
  (let [(cands (filter (fn [(c String)] -> Bool (not (stringEmpty? c))) (list (optionOr (envGet "TMPDIR") "") "/tmp")))
        (real (map (fn [(c String)] -> String (match (realPath c) ((ok r) r) ((err _) ""))) cands))
        (picks (filter (fn [(c String)] -> Bool (and (not (stringEmpty? c)) (not (listAny? (fn [(w String)] -> Bool (stringContains? c w)) (badWords))))) real))]
    (match (listHead picks)
      ((none) (err "no temp dir free of ignored path words"))
      ((some d) (ok (t/joinPath d (str "intelpar" (t/intStr (procSelf))))))))

fn strItems xs: (List fx/Asn) -> (List String)
  (listReverse (fold (fn [(acc (List String)) (a fx/Asn)] -> (List String) (match a ((fx/aStr s) (cons s acc)) (else acc))) (list) xs))

fn caseOf a: fx/Asn -> (Result Case String)
  (match (fx/kwStr a "id") ((err e) (err e)) ((ok id)
  (match (fx/kwStr a "tree") ((err e) (err e)) ((ok tree)
  (match (fx/kwKw a "git") ((err e) (err e)) ((ok git)
  (match (fx/kwKw a "path") ((err e) (err e)) ((ok path)
  (match (fx/kwStr a "cwd") ((err e) (err e)) ((ok cwd)
  (match (fx/kwStr a "aslRoot") ((err e) (err e)) ((ok aslRoot)
  (match (fx/kwItems a "argv") ((err e) (err e)) ((ok argv)
  (match (fx/kwStr a "out") ((err e) (err e)) ((ok out)
  (match (fx/kwStr a "err") ((err e) (err e)) ((ok er)
  (match (fx/kwInt a "exit") ((err e) (err e)) ((ok code)
  (match (fx/kwStr a "log") ((err e) (err e)) ((ok log)
    (ok (Case :id id :tree tree :git git :path path :cwd cwd :aslRoot aslRoot :argv (strItems argv)
              :out out :err er :code code :log log))))))))))))))))))))))))

fn fileOf a: fx/Asn -> (Result TreeFile String)
  (match (fx/kwStr a "path") ((err e) (err e)) ((ok p)
  (match (fx/kwStr a "text") ((err e) (err e)) ((ok x)
  (match (fx/kwArg a "exec") ((none) (err "missing :exec")) ((some ex)
    (ok (TreeFile :path p :text x :exec (match ex ((fx/aSym s) (= s "true")) (else false))))))))))

fn allOk rs: (List (Result T String)) -> (Result (List T) String)
  (fold (fn [(acc (Result (List T) String)) (r (Result T String))] -> (Result (List T) String)
          (match acc ((err e) (err e)) ((ok xs) (match r ((ok x) (ok (cons x xs))) ((err e) (err e))))))
        (ok (list)) (listReverse rs))

fn treeFiles forms: (List fx/Asn) id: String -> (Result (List TreeFile) String)
  (match (listHead (filter (fn [(a fx/Asn)] -> Bool (and (= (fx/headKw a) "tree") (= (resultOr (fx/kwStr a "id") "") id))) forms))
    ((none) (err (str "no tree " id)))
    ((some tr) (match (fx/kwItems tr "files") ((err e) (err e)) ((ok fs) (allOk (map fileOf fs))))))

fn must! ctx: h/Ctx argv: (List String) cwd: String -> (Result Bool String)
  (match (h/runCapture! ctx argv (some cwd))
    ((err e) (err e))
    ((ok r) (if (= r.code 0) (ok true) (err (str (t/joinWith argv " ") " exited " (t/intStr r.code) ": " r.err)))))

fn ! caseEnv base: String c: Case -> (List String)
  (let [(stub (t/joinPath base "stub"))
        (path (if (= c.path "nogit") stub (str stub ":/usr/bin:/bin")))
        (env (listAppend (list (str "PATH=" path) (str "HOME=" (t/joinPath base "home")) "GIT_CONFIG_NOSYSTEM=1") (fr/cacheEnv!)))]
    (if (stringEmpty? c.aslRoot) env (listAppend env (list (str "ASL_ROOT=" c.aslRoot)))))

fn writeFile! setup: h/Ctx root: String f: TreeFile -> (Result Bool String)
  (let [(full (t/joinPath root f.path))]
    (match (dirCreate (t/dirName full))
      ((err e) (err e))
      ((ok _) (match (fileWrite full f.text)
                ((err e) (err e))
                ((ok _) (if f.exec (must! setup (list "chmod" "755" full) root) (ok true)))))))

fn stubDir! setup: h/Ctx base: String -> (Result Bool String)
  (let [(stub (t/joinPath base "stub"))]
    (if (fileExists? (t/joinPath stub "find")) (ok true)
      (match (dirCreate stub) ((err e) (err e)) ((ok _) (must! setup (list "ln" "-s" "/usr/bin/find" (t/joinPath stub "find")) base)))))

fn gitState! setup: h/Ctx root: String mode: String -> (Result Bool String)
  (if (= mode "none") (ok true)
    (match (must! setup (list "git" "-c" "init.defaultBranch=main" "init" "-q") root) ((err e) (err e)) ((ok _)
      (match (must! setup (list "git" "add" "-A") root) ((err e) (err e)) ((ok _)
        (if (= mode "remote") (must! setup (list "git" "remote" "add" "origin" "https://example.invalid/r.git") root) (ok true)))))))

fn ! materialise! base: String root: String c: Case files: (List TreeFile) -> (Result Bool String)
  (let [(setup (h/Ctx :home root :cwd root :aslRoot "" :env (some (listAppend (list "PATH=/usr/bin:/bin" (str "HOME=" (t/joinPath base "home")) "GIT_CONFIG_NOSYSTEM=1") (fr/cacheEnv!)))))]
    (match (allOk (map (fn [(f TreeFile)] -> (Result Bool String) (writeFile! setup root f)) files)) ((err e) (err e)) ((ok _)
      (match (dirCreate (t/joinPath base "home")) ((err e) (err e)) ((ok _)
        (match (stubDir! setup base) ((err e) (err e)) ((ok _)
          (gitState! setup root c.git))))))))

fn firstDiff want: String got: String -> String
  (let [(lw (stringSplit want "\n")) (lg (stringSplit got "\n"))]
    (match (listHead (filter (fn [(p (Pair String String))] -> Bool (!= (pairFirst p) (pairSecond p))) (zip lw lg)))
      ((some p) (str "want [" (pairFirst p) "] got [" (pairSecond p) "]"))
      ((none) (str "line counts " (t/intStr (listLength lw)) " vs " (t/intStr (listLength lg))))))

fn ! replay! base: String forms: (List fx/Asn) c: Case -> Verdict
  (let [(root (t/joinPath (t/joinPath base c.id) "t"))
        (built (match (treeFiles forms c.tree) ((err e) (err e)) ((ok files) (materialise! base root c files))))]
    (match built
      ((err e) (Verdict :id c.id :setup e :out false :err false :code false :log false))
      ((ok _)
        (let [(cwd (match (realPath (t/joinPath root c.cwd)) ((ok p) p) ((err _) root)))
              (ctx (h/Ctx :home root :cwd cwd :aslRoot c.aslRoot :env (some (caseEnv base c))))
              (o (intel/runIntel! ctx c.argv))
              (out (stringReplace o.out root "@ROOT@"))
              (er (stringReplace o.err root "@ROOT@"))
              (log (resultOr (fileReadString (t/joinPath root "bin/asl.log")) ""))
              (v (Verdict :id c.id :setup "" :out (= out c.out) :err (= er c.err) :code (= o.code c.code) :log (= log c.log)))]
          (do
            (if v.out () (eprintln "case" c.id "stdout" (firstDiff c.out out)))
            (if v.err () (eprintln "case" c.id "stderr" (firstDiff c.err er)))
            (if v.code () (eprintln "case" c.id "exit want" c.code "got" o.code))
            (if v.log () (eprintln "case" c.id "stub log" (firstDiff c.log log)))
            v)))))

fn matched? v: Verdict -> Bool
  (and (and v.out v.err) (and v.code v.log))

fn assertCase v: Verdict -> Bool
  (do
    (assert (stringEmpty? v.setup) (str v.id ": setup " v.setup))
    (assert v.out (str v.id ": stdout"))
    (assert v.err (str v.id ": stderr"))
    (assert v.code (str v.id ": exit status"))
    (assert v.log (str v.id ": bin/asl log"))
    (matched? v))

fn loadCases! -> (Result (Pair (List fx/Asn) (Pair Int64 (List Case))) String)
  (match (fileReadString (fixturePath)) ((err e) (err (str "cannot read fixture: " e))) ((ok text)
    (match (fx/readAsn text) ((err e) (err (str "fixture parse: " e))) ((ok forms)
      (let [(header (listHead (filter (fn [(a fx/Asn)] -> Bool (= (fx/headKw a) "fixture")) forms)))
            (declared (match header ((some hd) (resultOr (fx/kwInt hd "cases") -1)) ((none) -1)))]
        (match (allOk (map caseOf (filter (fn [(a fx/Asn)] -> Bool (= (fx/headKw a) "case")) forms)))
          ((err e) (err (str "fixture case: " e)))
          ((ok cs) (ok (pair forms (pair declared cs))))))))))

fn ! runTests -> Bool
  (match (loadCases!)
    ((err e) (do (eprintln e) (assert (stringEmpty? e) "fixture loads") false))
    ((ok loaded)
      (let [(forms (pairFirst loaded)) (declared (pairFirst (pairSecond loaded))) (cs (pairSecond (pairSecond loaded)))]
        (match (safeBase!)
          ((err e) (do (eprintln e) (assert (stringEmpty? e) "temp base") false))
          ((ok base)
            (let [(verdicts (map (fn [(c Case)] -> Verdict (replay! base forms c)) cs))
                  (cleaned (pathRemove base))
                  (good (listLength (filter (fn [(v Verdict)] -> Bool (matched? v)) verdicts)))]
              (do
                (println "intelParity:" good "of" (listLength cs) "cases match")
                (assert (= (listLength cs) declared) "case count equals the fixture header")
                (assert (> (listLength cs) 0) "fixture holds cases")
                (assert (match cleaned ((ok _) true) ((err _) false)) "temp tree removed")
                (listAll? (fn [(r Bool)] -> Bool r) (map (fn [(v Verdict)] -> Bool (assertCase v)) verdicts)))))))))
