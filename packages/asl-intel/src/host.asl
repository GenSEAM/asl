(module asl-intel/host
  :x [Ctx RunOut Tree Outcome outcome runCapture! gitLsFiles! findTree! walkFiles! globFiles! readText! isDir? isFile? isLink? listSorted!]
  :i [(asl-intel/text :a t)
      (asl-intel/tab :a tb)])

(schema Ctx
  (:f home String)
  (:f cwd String)
  (:f aslRoot String)
  (:f env (Option (List String))))

(schema Outcome
  (:f out String)
  (:f err String)
  (:f code Int64))

fn outcome out: String err: String code: Int64 -> Outcome
  (Outcome :out out :err err :code code)

(schema RunOut
  (:f code Int64)
  (:f out String)
  (:f err String))

(schema Tree
  (:f dirs (List String))
  (:f files (List String)))

fn drain! outFd: Int64 errFd: Int64 outOpen: Bool errOpen: Bool outAcc: (List String) errAcc: (List String) -> (Result (Pair (List String) (List String)) String)
  (if (and (not outOpen) (not errOpen))
    (ok (pair (listReverse outAcc) (listReverse errAcc)))
    (let [(watch (if outOpen (if errOpen (list (pair outFd 1) (pair errFd 1)) (list (pair outFd 1))) (list (pair errFd 1))))]
      (mt (fdPoll watch -1)
        ((err e) (err (str "poll failed: " e)))
        ((ok ready)
          (let [(outReady (and outOpen (listAny? (fn [(p (Pair Int64 Int64))] -> Bool (= (pairFirst p) outFd)) ready)))
                (errReady (and errOpen (listAny? (fn [(p (Pair Int64 Int64))] -> Bool (= (pairFirst p) errFd)) ready)))
                (o (if outReady (fdRead outFd 65536) (ok "-")))
                (e2 (if errReady (fdRead errFd 65536) (ok "-")))]
            (mt o
              ((err x) (err (str "read failed: " x)))
              ((ok oc)
                (mt e2
                  ((err x) (err (str "read failed: " x)))
                  ((ok ec)
                    (let [(outEof (and outReady (stringEmpty? oc)))
                          (errEof (and errReady (stringEmpty? ec)))]
                      (drain! outFd errFd (and outOpen (not outEof)) (and errOpen (not errEof))
                        (if (and outReady (not outEof)) (cons oc outAcc) outAcc)
                        (if (and errReady (not errEof)) (cons ec errAcc) errAcc))))))))))))

fn runCapture! ctx: Ctx argv: (List String) cwd: (Option String) -> (Result RunOut String)
  (mt (procSpawnv argv cwd ctx.env)
    ((err e) (err (str "ERR_TOOL_ABSENT naming " (optionOr (listHead argv) "?") ": " e)))
    ((ok sp)
      (let [(ci (fdClose sp.stdin))
            (bufs (drain! sp.stdout sp.stderr true true (list) (list)))
            (co (fdClose sp.stdout))
            (ce (fdClose sp.stderr))
            (waited (procWaitPid sp.pid false))]
        (mt bufs
          ((err e) (err e))
          ((ok parts)
            (mt waited
              ((err e) (err (str "wait failed: " e)))
              ((ok code)
                (ok (RunOut :code (optionOr code -1)
                            :out (t/concatAll (pairFirst parts))
                            :err (t/concatAll (pairSecond parts)))))))))))

fn outLines s: String -> (List String)
  (let [(u (universalNewlines s)) (b (stringToBytes u))]
    (map (fn [(p (Pair Int64 Int64))] -> String (t/sliceStr u (pairFirst p) (pairSecond p)))
         (t/splitLinesPy b (bytesLength b))))

fn gitLsFiles! ctx: Ctx root: String -> (Result (List String) String)
  (mt (runCapture! ctx (list "git" "ls-files") (some root))
    ((err e) (err e))
    ((ok r)
      (if (!= r.code 0)
        (err (str "git ls-files exited " (t/intStr r.code)))
        (ok (outLines r.out)))))

fn pruneArgs -> (List String)
  (list "(" "-type" "d" "(" "-path" "*.git*" "-o" "-path" "*node_modules*" "-o" "-path" "*dist*"
        "-o" "-path" "*target*" "-o" "-path" "*build*" "-o" "-path" "*scratch*" ")" ")" "-prune" "-o")

fn nameArgs names: (List String) -> (List String)
  (listAppend (list "(")
    (listAppend (listReverse (fold (fn [(acc (List String)) (n String)] -> (List String)
                                     (cons n (cons "-name" (if (listEmpty? acc) acc (cons "-o" acc)))))
                                   (list) names))
                (list ")")))

fn findLines! ctx: Ctx args: (List String) -> (Result (List String) String)
  (mt (runCapture! ctx (cons "find" args) (none))
    ((err e) (err e))
    ((ok r) (ok (filter (fn [(s String)] -> Bool (not (stringEmpty? s))) (stringSplitFast r.out 10)))))

fn stringSplitFast s: String sep: Int64 -> (List String)
  (let [(b (stringToBytes s)) (n (bytesLength b))]
    (listReverse (splitFastLoop s b n sep 0 0 (list))))

fn splitFastLoop s: String b: Bytes n: Int64 sep: Int64 start: Int64 i: Int64 acc: (List String) -> (List String)
  (cond
    ((>= i n) (cons (t/sliceStr s start n) acc))
    ((= (bytesGet b i) sep) (splitFastLoop s b n sep (+ i 1) (+ i 1) (cons (t/sliceStr s start i) acc)))
    (else (splitFastLoop s b n sep start (+ i 1) acc)))

fn findTree! ctx: Ctx root: String prune: Bool names: (List String) -> (Result Tree String)
  (let [(pre (if prune (pruneArgs) (list)))]
    (mt (findLines! ctx (cons root (listAppend pre (list "-type" "d" "-print"))))
      ((err e) (err e))
      ((ok dirs)
        (mt (findLines! ctx (cons root (listAppend pre (listAppend (list "!" "-type" "d") (listAppend (nameArgs names) (list "-print"))))))
          ((err e) (err e))
          ((ok files)
            (ok (Tree :dirs dirs :files (filter (fn [(f String)] -> Bool (not (isDir? f))) files))))))))

fn walkFiles! tree: Tree -> (List String)
  (let [(idx (fold (fn [(tab tb/Strtab) (d String)] -> tb/Strtab (pairFirst (tb/internStr! tab d)))
                   (tb/strtabNew 64) tree.dirs))
        (keyed (map (fn [(f String)] -> (Pair Int64 String) (pair (tb/lookupStr idx (t/dirName f)) f)) tree.files))
        (sorted (tb/sortPairsByInt keyed))]
    (map (fn [(p (Pair Int64 String))] -> String (pairSecond p)) sorted))

fn hiddenBelow? base: String p: String -> Bool
  (let [(rel (if (= p base) "" (t/sliceStr p (+ (stringLength base) 1) (stringLength p))))]
    (or (stringStartsWith? rel ".") (stringContains? rel "/.")))

fn globFiles! tree: Tree base: String -> (List String)
  (let [(prefix (str base "/"))
        (dirs (filter (fn [(d String)] -> Bool (and (or (= d base) (stringStartsWith? d prefix)) (not (hiddenBelow? base d)))) tree.dirs))
        (files (filter (fn [(f String)] -> Bool (and (stringStartsWith? f prefix) (not (hiddenBelow? base f)))) tree.files))]
    (walkFiles! (Tree :dirs dirs :files files)))

fn universalNewlines s: String -> String
  (if (not (stringContains? s "\r")) s
    (let [(b (stringToBytes s)) (n (bytesLength b))]
      (t/concatAll (listReverse (crLoop s b n 0 0 (list))))))

fn crLoop s: String b: Bytes n: Int64 start: Int64 i: Int64 acc: (List String) -> (List String)
  (cond
    ((>= i n) (cons (t/sliceStr s start n) acc))
    ((= (bytesGet b i) 13)
      (let [(skip (if (and (< (+ i 1) n) (= (bytesGet b (+ i 1)) 10)) 2 1))]
        (crLoop s b n (+ i skip) (+ i skip) (cons "\n" (cons (t/sliceStr s start i) acc)))))
    (else (crLoop s b n start (+ i 1) acc)))

fn readText! path: String -> (Result String String)
  (mt (fileReadString path)
    ((err e) (err e))
    ((ok s) (ok (universalNewlines s))))

fn ! isDir? p: String -> Bool
  (mt (fileStat p) ((ok st) st.isDir) ((err _) false))

fn ! isFile? p: String -> Bool
  (mt (fileStat p) ((ok st) st.isFile) ((err _) false))

fn ! isLink? parentReal: String name: String -> Bool
  (mt (realPath (t/joinPath parentReal name))
    ((ok r) (!= r (t/joinPath parentReal name)))
    ((err _) false))

fn listSorted! p: String -> (List String)
  (mt (dirList p) ((ok xs) xs) ((err _) (list)))
