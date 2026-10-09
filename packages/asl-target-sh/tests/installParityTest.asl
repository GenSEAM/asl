(module asl-target-sh/tests/installParityTest
  :x [runTests]
  :i [(asl-target-sh/distrib :a dist)])

(enum Node (:c nStr [(s String)] "string atom") (:c nSym [(s String)] "symbol, keyword or number atom") (:c nList [(xs (List Node))] "parenthesised list"))

fn byteAt bs: Bytes i: Int64 -> Int64
  (if (< i (bytesLength bs)) (bytesGet bs i) -1)

fn skipWs bs: Bytes i: Int64 -> Int64
  (let [(b (byteAt bs i))]
    (if (or (= b 32) (= b 10) (= b 9) (= b 13)) (skipWs bs (+ i 1)) i))

fn atomEnd bs: Bytes i: Int64 -> Int64
  (let [(b (byteAt bs i))]
    (if (or (= b -1) (= b 32) (= b 10) (= b 9) (= b 13) (= b 40) (= b 41) (= b 34)) i (atomEnd bs (+ i 1))))

fn plainEnd bs: Bytes i: Int64 -> Int64
  (let [(b (byteAt bs i))]
    (if (or (= b -1) (= b 34) (= b 92)) i (plainEnd bs (+ i 1))))

fn escaped b: Int64 -> String
  (cond ((= b 110) "\n") ((= b 116) "\t") ((= b 114) "\r") ((= b 34) "\"") ((= b 92) "\\") (else ""))

fn codepoint hex: String -> String
  (cond ((= hex "1F4E6") "\u{1F4E6}") ((= hex "1F680") "\u{1F680}") ((= hex "1F916") "\u{1F916}") ((= hex "FE0F") "\u{FE0F}") (else (str "<U+" hex ">")))

fn readStr text: String bs: Bytes i: Int64 parts: (List String) -> (Pair String Int64)
  (let [(j (plainEnd bs i))
        (chunk (optionOr (stringSlice text i j) ""))
        (b (byteAt bs j))]
    (cond
      ((= b 34) (pair (stringJoin (listReverse (cons chunk parts)) "") (+ j 1)))
      ((and (= b 92) (= (byteAt bs (+ j 1)) 117))
        (let [(close (optionOr (stringIndexOf (optionOr (stringSlice text j (stringLength text)) "") "}") 0))
              (hex (optionOr (stringSlice text (+ j 3) (+ j close)) ""))]
          (readStr text bs (+ j close 1) (cons (codepoint hex) (cons chunk parts)))))
      ((= b 92) (readStr text bs (+ j 2) (cons (escaped (byteAt bs (+ j 1))) (cons chunk parts))))
      (else (pair (stringJoin (listReverse (cons chunk parts)) "") j))))

fn readNode text: String bs: Bytes i0: Int64 -> (Pair Node Int64)
  (let [(i (skipWs bs i0)) (b (byteAt bs i))]
    (cond
      ((= b 40) (readList text bs (+ i 1) (list)))
      ((= b 34) (let [(r (readStr text bs (+ i 1) (list)))] (pair (nStr (pairFirst r)) (pairSecond r))))
      (else (let [(j (atomEnd bs i))] (pair (nSym (optionOr (stringSlice text i j) "")) j)))))

fn readList text: String bs: Bytes i0: Int64 acc: (List Node) -> (Pair Node Int64)
  (let [(i (skipWs bs i0)) (b (byteAt bs i))]
    (if (or (= b 41) (= b -1))
      (pair (nList (listReverse acc)) (+ i 1))
      (let [(r (readNode text bs i))] (readList text bs (pairSecond r) (cons (pairFirst r) acc)))))

fn items n: Node -> (List Node)
  (mt n ((nList xs) xs) ((nStr _) (list)) ((nSym _) (list)))

fn atom n: Node -> String
  (mt n ((nStr s) s) ((nSym s) s) ((nList _) ""))

fn field n: Node key: String -> Node
  (fieldIn (items n) key)

fn fieldIn xs: (List Node) key: String -> Node
  (mt (listHead xs)
    ((none) (nList (list)))
    ((some h) (let [(rest (optionOr (listTail xs) (list)))]
                (if (= (atom h) key) (optionOr (listHead rest) (nList (list))) (fieldIn rest key)))))

fn nth n: Node i: Int64 -> Node
  (optionOr (listGet (items n) i) (nList (list)))

(schema Blob (:f text String) (:f bytes (Option Bytes)))

fn blobMap! blobs: Node -> (Map String Blob)
  (fold (fn [m row]
          (let [(kind (atom (nth row 1))) (val (atom (nth row 2)))]
            (mapSet m (atom (nth row 0)) (if (= kind ":base64") (Blob :text "" :bytes (resultToOption (bytesFromBase64 val))) (Blob :text val :bytes (none))))))
        (mapEmpty) (items blobs))

(schema Env (:f sandbox String) (:f root String) (:f home String) (:f host String) (:f repo String))

fn sh! cmd: (List String) -> Bool
  (mt (dist/runArgv! cmd (none) (none) 60000) ((ok r) (= r.code 0)) ((err _) false))

fn place! blobs: (Map String Blob) env: Env base: String row: Node -> Bool
  (let [(rel (atom (nth row 0)))
        (kind (atom (nth row 1)))
        (path (str base "/" rel))
        (made (dirCreate (dist/dirName path)))
        (exec (= (atom (nth row 3)) "true"))
        (blob (optionOr (mapGet blobs (atom (nth row 2))) (Blob :text "" :bytes (none))))]
    (cond
      ((= kind ":link") (sh! (list "ln" "-s" (atom (nth row 2)) path)))
      (else
        (let [(wrote (cond
                       ((= kind ":installer") (fileWrite path (dist/generateInstallSh)))
                       ((= kind ":installerDrift") (fileWrite path (str (dist/generateInstallSh) blob.text)))
                       (else (mt blob.bytes
                               ((some b) (fileWrite path b))
                               ((none) (fileWrite path (stringReplace blob.text "@HOME" env.home)))))))]
          (and (ok? wrote) (ok? (dist/chmodTo! path (if exec 493 420))))))))

fn digits? s: String -> Bool
  (and (not (stringEmpty? s)) (listAll? (fn [c] (and (>= (charCode c) 48) (<= (charCode c) 57))) (stringChars s)))

fn digitRun s: String i: Int64 -> Int64
  (let [(c (optionOr (stringSlice s i (+ i 1)) ""))]
    (if (digits? c) (digitRun s (+ i 1)) i))

fn normStamp s: String prefix: String from: Int64 -> String
  (mt (stringIndexOf (optionOr (stringSlice s from (stringLength s)) "") prefix)
    ((none) s)
    ((some rel)
      (let [(at (+ from rel (stringLength prefix)))
            (d1 (digitRun s at))
            (dash (optionOr (stringSlice s d1 (+ d1 1)) ""))
            (d2 (digitRun s (+ d1 1)))]
        (if (and (= (- d1 at) 14) (= dash "-") (> d2 (+ d1 1)))
          (normStamp (str (optionOr (stringSlice s 0 at) "") "<STAMP>" (optionOr (stringSlice s d2 (stringLength s)) "")) prefix (+ at 7))
          (normStamp s prefix at)))))

fn normalize env: Env s: String -> String
  (normStamp (normStamp (stringReplace s env.sandbox "<S>") "directives-" 0) "skills-" 0)

fn bashLine l: String -> String
  (mt (stringIndexOf l "install.sh: line ")
    ((none) l)
    ((some i)
      (let [(after (+ i 17))
            (d (digitRun l after))
            (rest (optionOr (stringSlice l (+ d 2) (stringLength l)) ""))
            (p (digitRun rest 0))
            (rest2 (if (and (> p 0) (stringStartsWith? (optionOr (stringSlice rest p (stringLength rest)) "") ": ")) (optionOr (stringSlice rest (+ p 2) (stringLength rest)) "") rest))]
        (str "install.sh: " rest2))))

fn expectedStderr s: String -> String
  (dist/joinLines (filter (fn [l] (not (stringStartsWith? l "install.sh: /dev/tty:"))) (map bashLine (dist/splitLines s))))

fn gitCalls s: String -> (List String)
  (filter (fn [l] (stringStartsWith? l "git ")) (dist/splitLines s))

fn otherCalls s: String -> (List String)
  (sortUniq (map maskTemp (filter (fn [l] (not (stringStartsWith? l "git "))) (dist/splitLines s))))

fn maskTemp l: String -> String
  (mt (stringIndexOf l " -o ")
    ((none) l)
    ((some i) (let [(path (optionOr (stringSlice l (+ i 4) (stringLength l)) ""))
                    (cut (lastSlashAt path (- (stringLength path) 1)))]
                (str (optionOr (stringSlice l 0 (+ i 4)) "") "<TMP>" (optionOr (stringSlice path (max 0 cut) (stringLength path)) "")))))

fn lastSlashAt s: String i: Int64 -> Int64
  (cond ((< i 0) -1) ((= (optionOr (stringSlice s i (+ i 1)) "") "/") i) (else (lastSlashAt s (- i 1))))

fn sortUniq xs: (List String) -> (List String)
  (listReverse (fold (fn [acc x] (mt (listHead acc) ((some h) (if (= h x) acc (cons x acc))) ((none) (cons x acc)))) (list) (listSort xs)))

(schema Row (:f rel String) (:f kind String) (:f value String))

fn rowText r: Row -> String
  (str r.rel " " r.kind " " r.value)

fn walk! env: Env dir: String rel: String skip: (List String) acc: (List String) -> (List String)
  (mt (dirList dir)
    ((err _) acc)
    ((ok names)
      (fold (fn [a n]
              (let [(p (str dir "/" n))
                    (r (if (stringEmpty? rel) n (str rel "/" n)))
                    (shown (normalize env r))]
                (cond
                  ((listContains? skip r) a)
                  ((dist/symlink? dir n) (cons (str shown " :link " (mt (realPath p) ((ok t) (normalize env t)) ((err _) "<dangling>"))) a))
                  ((dist/isDir! p) (walk! env p r skip a))
                  (else (cons (str shown " :file " (mt (fileReadString p) ((ok t) (bytesSha256 (stringToBytes (stringReplace t env.sandbox "<S>")))) ((err _) "<unreadable>"))) a)))))
            acc names)))

fn treeRows n: Node -> (List String)
  (listSort (map (fn [row] (str (atom (nth row 0)) " " (atom (nth row 1)) " " (atom (nth row 2)))) (items n)))

fn subst env: Env a: String -> String
  (stringReplace (stringReplace a "@ROOT" env.root) "@HOME" env.home)

fn childEnv! env: Env -> (List String)
  (listAppend
    (filter (fn [r] (not (or (stringStartsWith? r "PATH=") (stringStartsWith? r "HOME=") (stringStartsWith? r "TMPDIR=") (stringStartsWith? r "LC_ALL=")
                             (stringStartsWith? r "STUB_") (stringStartsWith? r "ASL_ROOT=") (stringStartsWith? r "ASL_HOST=")
                             (stringContains? (optionOr (listHead (stringSplit r "=")) "") "_API_KEY"))))
      (envList))
    (list (str "PATH=" env.sandbox "/stub/bin:/usr/bin:/bin:/usr/sbin:/sbin") (str "HOME=" env.home) (str "TMPDIR=" env.sandbox "/tmp")
          "LC_ALL=C" (str "STUB_LOG=" env.sandbox "/stub/log") (str "STUB_STATE=" env.sandbox "/stub/state")))

fn stripSkillLines s: String -> String
  (dist/joinLines (filter (fn [l] (not (stringContains? l " install-skill"))) (dist/splitLines s)))

fn stripEmitLines s: String -> String
  (dist/joinLines (filter (fn [l] (not (stringContains? l " installer-emit"))) (dist/splitLines s)))

fn emitStatus s: String -> String
  (let [(hits (filter (fn [l] (stringContains? l " installer-emit")) (dist/splitLines s)))]
    (if (= (listLength hits) 1) (optionOr (listHead (filter (fn [w] (not (stringEmpty? w))) (stringSplit (optionOr (listHead hits) "") " "))) "") (str "count:" (stringFromInt64 (listLength hits)))))

fn check! label: String ok: Bool detail: String -> Bool
  (do (if ok true (dist/writeErr! (str "FAIL " label ": " detail "\n")))
      (assert ok label)
      ok)

fn diffText want: String got: String -> String
  (str "\n--- want\n" want "\n--- got\n" got)

fn replay! fx: Node blobs: (Map String Blob) repo: String host: String c: Node -> Bool
  (let [(id (atom (field c ":id")))
        (entry (atom (field c ":entry")))
        (made (resultOr (dirCreate (str (optionOr (envGet "TMPDIR") "/tmp") "/instReplay." (stringFromInt64 (procSelf)) "." id)) ()))
        (sandbox (resultOr (realPath (str (optionOr (envGet "TMPDIR") "/tmp") "/instReplay." (stringFromInt64 (procSelf)) "." id)) ""))
        (env (Env :sandbox sandbox :root (str sandbox "/root") :home (str sandbox "/home") :host host :repo repo))
        (dirs (map (fn [d] (dirCreate (str sandbox d))) (list "/root" "/home" "/stub/bin" "/stub/state" "/tmp" "/work")))
        (placed (listAll? (fn [x] x)
                  (listAppend (map (fn [r] (place! blobs env env.root r)) (items (field c ":root")))
                    (listAppend (map (fn [r] (place! blobs env env.home r)) (items (field c ":home")))
                      (listAppend (map (fn [r] (place! blobs env (str sandbox "/stub/state") r)) (items (field c ":state")))
                        (map (fn [s] (place! blobs env (str sandbox "/stub/bin") (nList (list (nStr (atom (nth s 0))) (nSym ":file") (nStr (atom (nth s 1))) (nSym "true"))))) (items (field fx ":stubs"))))))))
        (args (map (fn [a] (subst env (atom a))) (items (field c ":args"))))
        (pipe (= (atom (field c ":from")) ":pipe"))
        (boot (if (= entry ":bootstrap") (bootstrapTree! env repo) true))
        (argv (cond
                ((= entry ":rules") (listAppend (list host "run" (str repo "/asl/packages/asl-target-sh/src/rules.asl") env.root) args))
                ((= entry ":bootstrap") (listAppend (list "perl" "-MPOSIX" "-e" "my $p = fork; if ($p) { waitpid($p, 0); exit($? >> 8) } POSIX::setsid(); exec @ARGV or exit 127" "dash" (str env.root "/scripts/install.sh")) args))
                (else (listAppend (list host "run" (str repo "/asl/packages/asl-target-sh/src/distrib.asl") env.root (if pipe "pipe" "file")
                                  (optionOr (stringSlice (atom (field fx ":tty")) 1 (stringLength (atom (field fx ":tty")))) "") (atom (field fx ":os")) (atom (field fx ":arch")))
                            args))))
        (ran (dist/runArgv! argv (some (if pipe (str sandbox "/work") env.root)) (some (childEnv! env)) 300000))
        (res (resultOr ran (dist/RunResult :code -1 :out "" :errText "spawn failed")))
        (calls (resultOr (fileReadString (str sandbox "/stub/log")) ""))
        (outGot (normalize env res.out))
        (errGot (normalize env res.errText))
        (outWant (atom (field c ":stdout")))
        (rootSkip (if (= entry ":rules") (list "scripts/install.sh" "asl/dist/install.sh" "asl/web/dist/install.sh" "asl/web/public/install.sh" ".asl/tmp") (list "scripts/install.sh" ".asl/tmp" "asl/packages" "asl/host" ".asl.config.asn")))
        (rootGot (listSort (walk! env env.root "" rootSkip (list))))
        (homeGot (listSort (walk! env env.home "" (list) (list))))
        (mode (optionOr (listHead args) ""))
        (emitWant (cond ((not (stringContains? outWant " install-skill")) "none") ((= mode "--check-rules") "ok") ((or (= mode "--render-rules") (= mode "--render-home")) "rendered") (else "none")))
        (results (list
                   (check! (str id " sandbox") (and placed boot) "fixture rows not placed")
                   (check! (str id " exit") (= res.code (optionOr (stringToInt64 (atom (field c ":exit"))) -99)) (str "want " (atom (field c ":exit")) " got " (stringFromInt64 res.code) (diffText outWant outGot) (diffText "" errGot)))
                   (check! (str id " stdout") (= (stripEmitLines outGot) (stripSkillLines outWant)) (diffText (stripSkillLines outWant) (stripEmitLines outGot)))
                   (check! (str id " installer-emit") (if (= emitWant "none") (= (emitStatus outGot) "count:0") (and (= (emitStatus outGot) emitWant) (not (stringContains? outGot "DRIFT installer-emit")))) (str "want " emitWant " got " (emitStatus outGot)))
                   (check! (str id " stderr") (= errGot (expectedStderr (atom (field c ":stderr")))) (diffText (expectedStderr (atom (field c ":stderr"))) errGot))
                   (check! (str id " git calls") (= (gitCalls (normalize env calls)) (gitCalls (atom (field c ":calls")))) (diffText (stringJoin (gitCalls (atom (field c ":calls"))) "\n") (stringJoin (gitCalls (normalize env calls)) "\n")))
                   (check! (str id " other calls") (= (otherCalls (normalize env calls)) (otherCalls (atom (field c ":calls")))) (diffText (stringJoin (otherCalls (atom (field c ":calls"))) "\n") (stringJoin (otherCalls (normalize env calls)) "\n")))
                   (check! (str id " root tree") (= rootGot (treeRows (field c ":rootTree"))) (diffText (stringJoin (treeRows (field c ":rootTree")) "\n") (stringJoin rootGot "\n")))
                   (check! (str id " home tree") (= homeGot (treeRows (field c ":homeTree"))) (diffText (stringJoin (treeRows (field c ":homeTree")) "\n") (stringJoin homeGot "\n")))))
        (cleaned (pathRemove sandbox))]
    (listAll? (fn [x] x) results))

fn bootstrapTree! env: Env repo: String -> Bool
  (let [(root env.root)]
    (and (ok? (dist/copyTree! (str repo "/asl/packages/asl-target-sh") (str root "/asl/packages/asl-target-sh")))
         (ok? (dist/copyTree! (str repo "/.asl.config.asn") (str root "/.asl.config.asn")))
         (sh! (list "ln" "-s" (str repo "/asl/host") (str root "/asl/host")))
         (dist/isExecutable! "/bin/dash")))

fn repoRoot! -> String
  (resultOr (realPath ".") ".")

fn hostPath! repo: String -> String
  (let [(envHost (optionOr (envGet "ASL_HOST") ""))]
    (if (and (not (stringEmpty? envHost)) (dist/isExecutable! envHost)) envHost (str repo "/asl/host/out/asl-host")))

fn ! runTests -> Bool
  (let [(repo (repoRoot!))
        (text (resultOr (fileReadString (str repo "/tests/parity/install/fixture.asn")) ""))
        (fx (pairFirst (readNode text (stringToBytes text) 0)))
        (cases (items (field fx ":list")))
        (only (optionOr (envGet "INSTALL_PARITY_CASE") ""))
        (chosen (filter (fn [c] (or (stringEmpty? only) (= (atom (field c ":id")) only))) cases))
        (blobs (blobMap! (field fx ":blobs")))
        (host (hostPath! repo))]
    (do (assert (= (atom (field fx ":base")) "75a7d7ba") "fixture pinned to base 75a7d7ba")
        (assert (= (listLength cases) (optionOr (stringToInt64 (atom (field fx ":cases"))) -1)) "fixture declares its case count")
        (assert (> (listLength chosen) 0) "at least one case replayed")
        (assert (= (dist/generateInstallSh) (resultOr (fileReadString (str repo "/scripts/install.sh")) "")) "scripts/install.sh equals the bootstrap distrib.asl emits")
        (let [(passed (filter (fn [c] (replay! fx blobs repo host c)) chosen))]
          (do (dist/writeOut! (str "installParity: " (stringFromInt64 (listLength passed)) "/" (stringFromInt64 (listLength chosen)) " cases equal\n"))
              (= (listLength passed) (listLength chosen))))))
