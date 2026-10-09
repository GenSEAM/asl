(module ws/asl/tools/mesh/tests/cmdTest
  :x [runTests]
  :i [(ws/asl/tools/mesh/cmd :a cmd)])

fn fixturePath -> String
  "tests/parity/mesh/cmdFixture.asn"

fn sub s: String i: Int64 j: Int64 -> String
  (let [n (stringLength s)
        a (max 0 (min i n))
        b (max a (min j n))]
    (optionOr (stringSlice s a b) ""))

fn first xs: (List T) d: T -> T
  (optionOr (listHead xs) d)

fn rest xs: (List T) -> (List T)
  (optionOr (listTail xs) (list))

fn at xs: (List String) k: Int64 -> String
  (optionOr (listGet xs k) "")

fn ctlChar b: Int64 -> String
  (let [tbl "\x00\x01\x02\x03\x04\x05\x06\x07\x08\x09\x0a\x0b\x0c\x0d\x0e\x0f\x10\x11\x12\x13\x14\x15\x16\x17\x18\x19\x1a\x1b\x1c\x1d\x1e\x1f"]
    (if (= b 127) "\x7f" (sub tbl b (+ b 1))))

fn hexVal b: Int64 -> Int64
  (cond ((and (>= b 48) (<= b 57)) (- b 48)) ((and (>= b 97) (<= b 102)) (- b 87)) ((and (>= b 65) (<= b 70)) (- b 55)) (else 0))

fn plainEnd bs: Bytes i: Int64 n: Int64 -> Int64
  (if (or (>= i n) (= (bytesGet bs i) 34) (= (bytesGet bs i) 92)) i (plainEnd bs (+ i 1) n))

fn unescapeLoop s: String bs: Bytes i: Int64 n: Int64 acc: (List String) -> String
  (if (or (>= i n) (= (bytesGet bs i) 34))
    (stringJoin (listReverse acc) "")
    (if (= (bytesGet bs i) 92)
      (let [c (bytesGet bs (+ i 1))]
        (cond
          ((= c 110) (unescapeLoop s bs (+ i 2) n (cons "\n" acc)))
          ((= c 116) (unescapeLoop s bs (+ i 2) n (cons "\t" acc)))
          ((= c 114) (unescapeLoop s bs (+ i 2) n (cons "\r" acc)))
          ((= c 120) (unescapeLoop s bs (+ i 4) n (cons (ctlChar (+ (* 16 (hexVal (bytesGet bs (+ i 2)))) (hexVal (bytesGet bs (+ i 3))))) acc)))
          (else (unescapeLoop s bs (+ i 2) n (cons (sub s (+ i 1) (+ i 2)) acc)))))
      (let [j (plainEnd bs i n)]
        (unescapeLoop s bs j n (cons (sub s i j) acc)))))

fn netstrings s: String -> (List String)
  (let [bs (stringToBytes s)]
    (nsLoop s bs 0 (bytesLength bs) (list)))

fn nsLoop s: String bs: Bytes i: Int64 n: Int64 acc: (List String) -> (List String)
  (if (>= i n)
    (listReverse acc)
    (let [c (colonFrom bs i n)
          len (optionOr (stringToInt64 (sub s i c)) 0)
          e (+ (+ c 1) len)]
      (nsLoop s bs e n (cons (sub s (+ c 1) e) acc))))

fn colonFrom bs: Bytes i: Int64 n: Int64 -> Int64
  (if (or (>= i n) (= (bytesGet bs i) 58)) i (colonFrom bs (+ i 1) n))

fn caseLines text: String -> (List String)
  (filter (fn [l] (stringStartsWith? l "(:case \"")) (stringSplit text "\n"))

fn caseFields line: String -> (List String)
  (let [bs (stringToBytes line)]
    (netstrings (unescapeLoop line bs 8 (bytesLength bs) (list))))

fn declaredCases text: String -> Int64
  (let [p (optionOr (stringIndexOf text ":cases ") -1)
        tail (sub text (+ p 7) (+ p 20))
        digits (first (stringSplit tail ")") "")]
    (optionOr (stringToInt64 digits) -1))

fn replaceAll text: String old: String new: String -> String
  (if (stringEmpty? old) text (stringJoin (stringSplit text old) new))

fn subst text: String root: String pid: String -> String
  (replaceAll (replaceAll text "@ROOT@" root) "@PID@" pid)

fn digit? b: Int64 -> Bool
  (and (>= b 48) (<= b 57))

fn digitsEnd bs: Bytes i: Int64 n: Int64 -> Int64
  (if (and (< i n) (digit? (bytesGet bs i))) (digitsEnd bs (+ i 1) n) i)

fn digitsK bs: Bytes i: Int64 n: Int64 k: Int64 -> Bool
  (and (<= (+ i k) n) (= (digitsEnd bs i (+ i k)) (+ i k)))

fn litAt bs: Bytes i: Int64 n: Int64 lit: String -> Bool
  (let [lb (stringToBytes lit)
        m (bytesLength lb)]
    (and (<= (+ i m) n) (listAll? (fn [k] (= (bytesGet bs (+ i k)) (bytesGet lb k))) (range 0 m))))

fn dateEnd bs: Bytes i: Int64 n: Int64 -> Int64
  (if (and (digitsK bs i n 4) (litAt bs (+ i 4) n "-") (digitsK bs (+ i 5) n 2) (litAt bs (+ i 7) n "-") (digitsK bs (+ i 8) n 2)) (+ i 10) -1)

fn ruleAt rule: Int64 s: String bs: Bytes i: Int64 n: Int64 -> (Pair Int64 String)
  (let [none (pair -1 "")]
    (cond
      ((= rule 0) (if (and (litAt bs i n "DEF-") (digitsK bs (+ i 4) n 8) (litAt bs (+ i 12) n "-") (digitsK bs (+ i 13) n 3)) (pair (+ i 16) "DEF-<D>-<N>") none))
      ((= rule 1) (let [e (digitsEnd bs (+ i 1) n)] (if (and (litAt bs i n "(") (> e (+ i 1)) (litAt bs e n "ms)")) (pair (+ e 3) "(<ms>ms)") none)))
      ((= rule 2) (let [d (dateEnd bs i n)]
                    (if (and (>= d 0) (litAt bs d n " ") (digitsK bs (+ d 1) n 2) (litAt bs (+ d 3) n ":") (digitsK bs (+ d 4) n 2) (litAt bs (+ d 6) n ":") (digitsK bs (+ d 7) n 2))
                      (pair (+ d 9) "<datetime>") none)))
      ((= rule 3) (let [a (+ i 13)
                        e (digitsEnd bs a n)]
                    (if (and (litAt bs i n "completed in ") (> e a) (litAt bs e n ".") (digitsK bs (+ e 1) n 2) (litAt bs (+ e 3) n "s")) (pair (+ e 4) "completed in <s>s") none)))
      ((= rule 4) (let [e (digitsEnd bs (+ i 11) n)] (if (and (litAt bs i n ":timestamp ") (> e (+ i 11))) (pair e ":timestamp <t>") none)))
      ((= rule 5) (let [e (digitsEnd bs (+ i 4) n)] (if (and (litAt bs i n "TEL-") (> e (+ i 4))) (pair e "TEL-<t>") none)))
      ((= rule 6) (let [d (dateEnd bs (+ i 5) n)] (if (and (litAt bs i n ":at \"") (>= d 0) (litAt bs d n "\"")) (pair (+ d 1) ":at \"<date>\"") none)))
      ((= rule 7)
        (if (litAt bs i n "PID")
          (let [c (if (litAt bs (+ i 3) n ":") (+ i 4) (+ i 3))
                sp (spacesEnd bs c n)
                m (if (litAt bs sp n "-") (+ sp 1) sp)
                e (digitsEnd bs m n)]
            (if (and (> sp c) (> e m)) (pair e (str "PID" (sub s (+ i 3) c) (sub s c sp) "<pid>")) none))
          none))
      ((= rule 8) (let [a (+ i 11)
                        e (spacesEnd bs a n)]
                    (if (and (litAt bs i n "(PID <pid>)") (> e a) (litAt bs e n "│")) (pair (+ e 3) "(PID <pid>) │") none)))
      ((= rule 9) (let [e (digitsEnd bs (+ i 4) n)] (if (and (litAt bs i n "Lat=") (> e (+ i 4)) (litAt bs e n "ms")) (pair (+ e 2) "Lat=<ms>ms") none)))
      ((= rule 10) (let [k (cond ((litAt bs i n ":avgLatencyMs ") ":avgLatencyMs") ((litAt bs i n ":meanLatencyMs ") ":meanLatencyMs") (else ""))
                        a (+ (+ i (stringLength k)) 1)
                        e (digitsEnd bs a n)]
                    (if (and (not (stringEmpty? k)) (> e a)) (pair e (str k " <ms>")) none)))
      (else (let [e (digitsEnd bs (+ i 2) n)
                  sp (spacesEnd bs e n)]
              (if (and (litAt bs i n "| ") (> e (+ i 2)) (litAt bs sp n "ms |")) (pair (+ sp 4) "| <lat>ms |") none)))))

fn spacesEnd bs: Bytes i: Int64 n: Int64 -> Int64
  (if (and (< i n) (= (bytesGet bs i) 32)) (spacesEnd bs (+ i 1) n) i)

fn applyRule rule: Int64 s: String -> String
  (let [bs (stringToBytes s)]
    (stringJoin (listReverse (ruleLoop rule s bs 0 0 (bytesLength bs) (list))) ""))

fn ruleLoop rule: Int64 s: String bs: Bytes i: Int64 start: Int64 n: Int64 acc: (List String) -> (List String)
  (if (>= i n)
    (cons (sub s start n) acc)
    (let [m (ruleAt rule s bs i n)]
      (if (< (pairFirst m) 0)
        (ruleLoop rule s bs (+ i 1) start n acc)
        (ruleLoop rule s bs (pairFirst m) (pairFirst m) n (cons (pairSecond m) (cons (sub s start i) acc))))))

fn normalize text: String root: String tmp: String -> String
  (fold (fn [acc r] (applyRule r acc)) (replaceAll (replaceAll text root "<ROOT>") tmp "<TMP>") (range 0 12))

fn dirOf p: String -> String
  (let [parts (stringSplit p "/")]
    (stringJoin (optionOr (listSlice parts 0 (- (listLength parts) 1)) (list)) "/"))

fn writeEntry! root: String pid: String rel: String content: String -> (Result Unit String)
  (let [path (str root "/" rel)]
    (if (stringEndsWith? rel "/")
      (mt (dirCreate path) ((ok _) (ok ())) ((err e) (err e)))
      (mt (dirCreate (dirOf path))
        ((err e) (err e))
        ((ok _)
          (if (stringStartsWith? content "@link:")
            (pathSymlink (subst (sub content 6 (stringLength content)) root pid) path)
            (mt (fileWrite path (subst content root pid))
              ((err e) (err e))
              ((ok _) (if (stringStartsWith? content "#!") (fileChmod path 493) (ok ())))))))))

fn pairsOf flat: (List String) -> (List (Pair String String))
  (if (< (listLength flat) 2)
    (list)
    (cons (pair (at flat 0) (at flat 1)) (pairsOf (listDrop flat 2))))

fn curlStub -> String
  (str "#!/bin/sh\n"
       "d=\"$MESH_STUB_DIR\"\n"
       "n=$(cat \"$d/count\" 2>/dev/null || echo 0)\n"
       "n=$((n+1))\n"
       "echo \"$n\" > \"$d/count\"\n"
       "cat > \"$d/req_$n\"\n"
       "if [ -f \"$d/resp_$n.drop\" ]; then echo 'curl: (52) Empty reply from server' >&2; exit 52; fi\n"
       "if [ -f \"$d/resp_$n.code\" ]; then cat \"$d/resp_$n.body\"; printf '\\n%s' \"$(cat \"$d/resp_$n.code\")\"; exit 0; fi\n"
       "printf 'no scripted response\\n500'\n")

fn writeResponses! stub: String http: (List String) k: Int64 -> (Result Unit String)
  (mt (listHead http)
    ((none) (ok ()))
    ((some item)
      (let [f (netstrings item)
            base (str stub "/resp_" (stringFromInt64 k))
            w (if (= (at f 0) "drop")
                (fileWrite (str base ".drop") "")
                (mt (fileWrite (str base ".code") (at f 0)) ((err e) (err e)) ((ok _) (fileWrite (str base ".body") (at f 1)))))]
        (mt w ((err e) (err e)) ((ok _) (writeResponses! stub (rest http) (+ k 1)))))))

fn curlUnquote v: String -> String
  (let [bs (stringToBytes v)
        n (bytesLength bs)]
    (if (and (>= n 2) (= (bytesGet bs 0) 34)) (unescapeLoop v bs 1 n (list)) v))

fn explicitHeader? name: String -> Bool
  (listAny? (fn [h] (= h name)) (list "content-type" "x-asl-intent" "x-asl-attractor" "x-title" "http-referer" "authorization" "x-asl-timeout" "x-asl-queue-timeout"))

fn parseRequest conf: String root: String tmp: String -> (List String)
  (let [lines (stringSplit conf "\n")
        val (fn [key] (map (fn [l] (curlUnquote (sub l (+ (stringLength key) 3) (stringLength l)))) (filter (fn [l] (stringStartsWith? l (str key " = "))) lines)))
        url (first (val "url") "")
        hdrs (listSort (filter (fn [h] (explicitHeader? (first (stringSplit h ": ") "")))
                               (map (fn [h] (let [p (optionOr (stringIndexOf h ": ") -1)]
                                              (if (< p 0) (stringLower h) (str (stringLower (sub h 0 p)) (sub h p (stringLength h))))))
                                    (val "header"))))
        body (first (val "data-binary") "")]
    (list url (stringJoin hdrs "\n") (normalize body root tmp)))

fn readRequests! stub: String root: String tmp: String -> (List (List String))
  (let [count (optionOr (stringToInt64 (stringTrim (resultOr (fileReadString (str stub "/count")) "0"))) 0)]
    (map (fn [k] (parseRequest (resultOr (fileReadString (str stub "/req_" (stringFromInt64 k))) "") root tmp)) (range 1 (+ count 1))))

fn expectedRequests field: String -> (List (List String))
  (map (fn [r] (let [f (netstrings r)] (list (at f 0) (stringJoin (netstrings (at f 1)) "\n") (at f 2)))) (netstrings field))

fn walkTree! root: String tmp: String pid: String rel: String -> (List (Pair String String))
  (let [dir (if (stringEmpty? rel) root (str root "/" rel))
        names (listSort (resultOr (dirList dir) (list)))]
    (fold (fn [acc name]
            (let [p (if (stringEmpty? rel) name (str rel "/" name))
                  full (str dir "/" name)
                  isLink (mt (fileLstat full) ((ok st) st.isSymlink) ((err _) false))
                  isDir (mt (fileStat full) ((ok st) st.isDir) ((err _) false))]
              (cond
                ((= p "bin/asl-mesh") acc)
                (isLink (listAppend acc (list (pair p (str "@link:" (normalize (resultOr (fileReadlink full) "") root tmp))))))
                (isDir (listAppend (listAppend acc (list (pair (str p "/") ""))) (walkTree! root tmp pid p)))
                (else (listAppend acc (list (pair (normalize p root tmp) (normalize (pidMarked (resultOr (fileReadString full) "") pid) root tmp))))))))
          (list) names))

fn pidMarked text: String pid: String -> String
  (if (and (not (stringEmpty? pid)) (= (stringTrim text) pid)) (replaceAll text pid "@PID@") text)

fn treeFlat pairs: (List (Pair String String)) -> (List String)
  (fold (fn [acc p] (listAppend acc (list (pairFirst p) (pairSecond p)))) (list) (listSortBy pairFirst pairs))

schema Run
  (:f out String)
  (:f err String)
  (:f code Int64)

fn readReady! fd: Int64 -> (Option String)
  (mt (fdRead fd 65536)
    ((ok chunk) (if (stringEmpty? chunk) (do (fdClose fd) (none)) (some chunk)))
    ((err _) (do (fdClose fd) (none))))

fn ready? rs: (List (Pair Int64 Int64)) fd: Int64 -> Bool
  (listAny? (fn [p] (= (pairFirst p) fd)) rs)

fn collect! pid: Int64 outFd: Int64 errFd: Int64 outs: (List String) errs: (List String) outOpen: Bool errOpen: Bool code: (Option Int64) -> Run
  (if (and (not outOpen) (not errOpen) (some? code))
    (Run :out (stringJoin (listReverse outs) "") :err (stringJoin (listReverse errs) "") :code (optionOr code -1))
    (let [fds (listAppend (if outOpen (list (pair outFd 1)) (list)) (if errOpen (list (pair errFd 1)) (list)))
          polled (resultOr (procPoll fds (if (some? code) (list) (list pid)) 1000) (pair (list) (list)))
          rs (pairFirst polled)
          code2 (if (some? code) code (fold (fn [acc p] (if (= (pairFirst p) pid) (some (pairSecond p)) acc)) (none) (pairSecond polled)))
          oc (if (and outOpen (ready? rs outFd)) (readReady! outFd) (some ""))
          ec (if (and errOpen (ready? rs errFd)) (readReady! errFd) (some ""))]
      (collect! pid outFd errFd
               (mt oc ((some x) (if (stringEmpty? x) outs (cons x outs))) ((none) outs))
               (mt ec ((some x) (if (stringEmpty? x) errs (cons x errs))) ((none) errs))
               (and outOpen (some? oc)) (and errOpen (some? ec)) code2)))

fn runChild! argv: (List String) cwd: String env: (List String) -> (Result Run String)
  (mt (procSpawnv argv (some cwd) (some env))
    ((err e) (err e))
    ((ok sp)
      (do
        (fdClose sp.stdin)
        (ok (collect! sp.pid sp.stdout sp.stderr (list) (list) true true (none))))))

fn casePid! kind: String -> (Pair String Int64)
  (cond
    ((= kind "alive") (mt (procSpawnv (list "sleep" "60") (none) (none)) ((ok sp) (pair (stringFromInt64 sp.pid) sp.pid)) ((err _) (pair "" -1))))
    ((= kind "dead") (mt (procSpawnv (list "true") (none) (none)) ((ok sp) (do (procWaitPid sp.pid false) (pair (stringFromInt64 sp.pid) -1))) ((err _) (pair "" -1))))
    (else (pair "" -1)))

fn stopSleeper! pid: Int64 -> Unit
  (if (> pid 1) (do (procKill pid "SIGKILL") (procWaitPid pid false) ()) ())

fn lastLine text: String -> String
  (let [ls (filter (fn [l] (not (stringEmpty? l))) (stringSplit text "\n"))]
    (optionOr (listLast ls) ""))

fn same! cid: String what: String want: String got: String -> Bool
  (if (= want got)
    true
    (do (println (str "  MISMATCH " cid " " what "\n    want: " (sub want 0 60000) "\n    got:  " (sub got 0 60000))) false))

fn absPath! rel: String -> String
  (resultOr (realPath rel) rel)

fn checkCase! base: String k: Int64 line: String host: String cmdPath: String -> Bool
  (let [f (caseFields line)
        cid (at f 0)
        d (str base "/c" (stringFromInt64 k))
        root (str d "/r")
        tmp (str d "/t")
        stub (str d "/s")
        pp (casePid! (at f 5))
        pidText (pairFirst pp)
        made (fold (fn [acc p] (mt acc ((err e) (err e)) ((ok _) (dirCreate p)))) (ok ()) (list (str root "/bin") (str root "/home") tmp stub))
        tree (fold (fn [acc p] (mt acc ((err e) (err e)) ((ok _) (writeEntry! root pidText (pairFirst p) (pairSecond p))))) (ok ()) (pairsOf (netstrings (at f 3))))
        stubs (mt (fileWrite (str stub "/curl") (curlStub)) ((err e) (err e)) ((ok _) (mt (fileChmod (str stub "/curl") 493) ((err e) (err e)) ((ok _) (writeResponses! stub (netstrings (at f 4)) 1)))))
        env (listAppend (list (str "PATH=" stub ":/usr/bin:/bin") (str "HOME=" root "/home") (str "TMPDIR=" tmp) (str "ROOT_DIR=" root)
                              "GATEWAY_URL=http://127.0.0.1:1/gw" (str "MESH_STUB_DIR=" stub))
                        (map (fn [p] (str (pairFirst p) "=" (subst (pairSecond p) root pidText))) (pairsOf (netstrings (at f 2)))))
        argv (map (fn [a] (subst a root pidText)) (netstrings (at f 1)))
        run (if (and (ok? made) (ok? tree) (ok? stubs)) (runChild! (listAppend (list host "run" cmdPath) argv) root env) (err "setup failed"))]
    (do
      (stopSleeper! (pairSecond pp))
      (mt run
        ((err e) (do (println (str "  SETUP " cid ": " e " " (resultOr (mt made ((err x) (ok x)) ((ok _) (ok ""))) "") " " (resultOr (mt tree ((err x) (ok x)) ((ok _) (ok ""))) ""))) false))
        ((ok r)
          (let [wantErr (at f 7)
                gotErr (normalize r.err root tmp)
                errOk (if (stringStartsWith? wantErr "@traceback:")
                        (same! cid "stderr" (stringTrim (sub wantErr 11 (stringLength wantErr))) (lastLine gotErr))
                        (same! cid "stderr" wantErr gotErr))
                outOk (same! cid "stdout" (at f 6) (normalize r.out root tmp))
                codeOk (same! cid "exit" (at f 8) (stringFromInt64 r.code))
                treeOk (same! cid "tree" (stringJoin (netstrings (at f 9)) "\n--\n") (stringJoin (treeFlat (walkTree! root tmp pidText "")) "\n--\n"))
                reqOk (same! cid "requests" (stringJoin (map (fn [x] (stringJoin x "\n~\n")) (expectedRequests (at f 10))) "\n==\n")
                            (stringJoin (map (fn [x] (stringJoin x "\n~\n")) (readRequests! stub root tmp)) "\n==\n"))
                leftOk (same! cid "tmpLeft" (at f 11) (stringFromInt64 (listLength (resultOr (dirList tmp) (list)))))]
            (and outOk errOk codeOk treeOk reqOk leftOk))))))

fn enumerate xs: (List String) -> (List (Pair Int64 String))
  (map (fn [k] (pair (+ k 1) (at xs k))) (range 0 (listLength xs)))

fn scratchBase! -> String
  (let [t (optionOr (envGet "TMPDIR") "/tmp")]
    (str (if (stringEndsWith? t "/") (sub t 0 (- (stringLength t) 1)) t) "/cmdTest-" (stringFromInt64 (procSelf))))

fn selected! cid: String -> Bool
  (let [only (optionOr (envGet "CMD_TEST_ONLY") "")]
    (or (stringEmpty? only) (listAny? (fn [x] (= x cid)) (stringSplit only ","))))

fn largePatch n: Int64 -> String
  (str "(:replace :target \"src/a.asl#f\" :old \"(x)\" :new \""
       (stringJoin (map (fn [k] (str "(f \\\"" (stringFromInt64 k) "\\\")\\n")) (range 0 n)) "")
       "\")")

fn curlAbsent! base: String host: String cmdPath: String -> String
  (let [root (str base "/absent/r")
        empty (str base "/absent/emptybin")
        board "(:meshDefectBlackboard\n  :defects (\n    (:defect\n      :id \"DEF-Z-1\"\n      :target \"src/a.asl#f\"\n      :hazard \"h\"\n      :status :corroborated\n      :confirmations 1)\n  ))\n"
        made (dirCreate (str root "/.asl/mem/gaps"))
        made2 (dirCreate empty)
        w (fileWrite (str root "/.asl/mem/gaps/MeshDefectBlackboard.asn") board)
        env (list (str "PATH=" empty) (str "HOME=" root) (str "ROOT_DIR=" root) "GATEWAY_URL=http://127.0.0.1:1/gw")
        r (runChild! (list host "run" cmdPath "propose-fix" "--id" "DEF-Z-1") root env)]
    (mt r ((ok x) (str x.out x.err)) ((err e) e)))

fn escapeAttempt! base: String host: String cmdPath: String k: String target: String outside: String link: Bool -> (Pair String String)
  (let [d (str base "/escape" k)
        root (str d "/r")
        empty (str d "/emptybin")
        patch (str "(:replace :target \\\"" target "#f\\\" :old \\\"(+ x 1)\\\" :new \\\"(+ x 2)\\\")")
        board (str "(:meshDefectBlackboard\n  :defects (\n    (:defect\n      :id \"DEF-E-1\"\n      :target \"src/a.asl#f\"\n      :status :corroborated\n      :confirmations 1\n      :fixProposal (\n        :proposedPatch \"" patch "\"))\n  ))\n")
        made (fold (fn [acc p] (mt acc ((err e) (err e)) ((ok _) (dirCreate p)))) (ok ()) (list (str root "/.asl/mem/gaps") (str root "/src") empty (dirOf outside)))
        w1 (fileWrite (str root "/.asl/mem/gaps/MeshDefectBlackboard.asn") board)
        w2 (fileWrite (str root "/src/a.asl") "(+ x 1)\n")
        w3 (fileWrite outside "(+ x 1)\n")
        w4 (if link (pathSymlink (dirOf outside) (str root "/lnk")) (ok ()))
        env (list (str "PATH=" empty) (str "HOME=" root) (str "ROOT_DIR=" root) "GATEWAY_URL=http://127.0.0.1:1/gw")
        r (if (and (ok? made) (ok? w1) (ok? w2) (ok? w3) (ok? w4)) (runChild! (list host "run" cmdPath "apply-fix" "--id" "DEF-E-1") root env) (err "setup failed"))]
    (pair (mt r ((ok x) (str x.out x.err)) ((err e) e)) (resultOr (fileReadString outside) "")))

fn ! runTests -> Bool
  (let [text (resultOr (fileReadString (fixturePath)) "")
        lines (caseLines text)
        base (scratchBase!)
        made (dirCreate base)
        host (absPath! "asl/host/out/asl-host")
        cmdPath (absPath! "asl/tools/mesh/cmd.asl")
        selectedCount (fold (fn [n p] (+ n (if (selected! (at (caseFields (pairSecond p)) 0)) 1 0))) 0 (enumerate lines))
        results (map (fn [p] (let [cid (at (caseFields (pairSecond p)) 0)]
                               (pair cid (if (selected! cid) (checkCase! base (pairFirst p) (pairSecond p) host cmdPath) true))))
                     (enumerate lines))
        patch (largePatch 8000)
        t0 (monotonicNs)
        reason (cmd/preflushReason patch)
        muts (cmd/slicedMutations (stringJoin (map (fn [k] (str "(g a" (stringFromInt64 k) " 1)")) (range 0 4000)) "\n"))
        dec (cmd/unicodeEscape patch false)
        wrapped (cmd/textWrap (stringJoin (map (fn [k] "cross-examination") (range 0 4000)) " ") 54)
        ms (/ (- (monotonicNs) t0) 1000000)
        absent (curlAbsent! base host cmdPath)
        escDots (escapeAttempt! base host cmdPath "1" "../outside.txt" (str base "/escape1/outside.txt") false)
        escAbs (escapeAttempt! base host cmdPath "2" (str base "/escape2/abs/abs.txt") (str base "/escape2/abs/abs.txt") false)
        escLink (escapeAttempt! base host cmdPath "3" "lnk/b.asl" (str base "/escape3/out/b.asl") true)
        escNul (escapeAttempt! base host cmdPath "4" "src/a\x00.asl" (str base "/escape4/out.txt") false)
        escGit (escapeAttempt! base host cmdPath "5" ".git/HEAD" (str base "/escape5/r/.git/HEAD") false)
        cleaned (pathRemove base)]
    (do
      (println (str "cmdTest: " (stringFromInt64 (listLength lines)) " fixture cases, large inputs in " (stringFromInt64 ms) " ms"))
      (assert (= (listLength lines) (declaredCases text)) "fixture case lines equal the recorder's :cases count")
      (assert (> selectedCount 0) "CMD_TEST_ONLY selects at least one fixture")
      (map (fn [r] (assert (pairSecond r) (str "parity " (pairFirst r)))) results)
      (assert (= reason "") "8000-escape patch passes the pre-flush gate")
      (assert (= muts (list 3 3)) "4000-line slice keeps three non-equivalent mutants, all killed")
      (assert (stringContains? (resultOr dec "") "(f \"7999\")\n") "8000 escapes decode")
      (assert (= (listLength wrapped) 1334) "4000 hyphenated words wrap to 1334 lines")
      (assert (< ms 20000) "large inputs under 20 s")
      (assert (stringContains? absent "ERR_TOOL_ABSENT: curl") "missing curl is reported as ERR_TOOL_ABSENT")
      (map (fn [c] (do (println (str "  escape " (pairFirst c) ": " (pairFirst (pairSecond c))))
                       (assert (stringContains? (pairFirst (pairSecond c)) "Unsafe fix target") (str "apply-fix rejects a " (pairFirst c) " target"))
                       (assert (= (pairSecond (pairSecond c)) "(+ x 1)\n") (str "apply-fix leaves the " (pairFirst c) " file unwritten"))))
           (list (pair "../" escDots) (pair "absolute" escAbs) (pair "symlinked" escLink) (pair "nul" escNul) (pair "git" escGit)))
      (assert (ok? cleaned) "scratch base removed")
      true))
