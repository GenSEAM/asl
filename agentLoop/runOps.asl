(module asl/agentLoop/runOps
  :x [RVal rStr rInt rBool rList Proc Procs Snap OpResult KillOut RunCtx
      makeRunCtx newProcs execRunOp! execManageOp! execDeleteOp! killSpawned! rebaseWritten! drainProcs!
      checkRunGitGuard shellWords runOutward runReadOnly hiddenVars logTail insideRoot! serRec]
  :i [(asl/agentLoop/core :a c) (asl/agentLoop/gitOps :a g)])

enum RVal
  (rStr text: String)
  (rInt value: Int64)
  (rBool flag: Bool)
  (rList items: (List String))

(schema RunCtx
  (:f root String)
  (:f owns (List String))
  (:f session String)
  (:f timeoutSec Int64)
  (:f hidden (List String))
  (:f toolRoot String))

(schema Proc
  (:f sid String)
  (:f pid Int64)
  (:f inFd Int64)
  (:f outFd Int64)
  (:f errFd Int64)
  (:f inOpen Bool)
  (:f outOpen Bool)
  (:f errOpen Bool)
  (:f log (List String))
  (:f logSize Int64)
  (:f code (Option Int64))
  (:f signalled Bool))

(schema Mark
  (:f rel String)
  (:f size Int64)
  (:f mtime Int64))

(schema Snap
  (:f marks (List Mark))
  (:f kept (List (Pair String (Option String))))
  (:f at Int64))

(schema Procs
  (:f ids (List String))
  (:f table (List Proc))
  (:f base (Option Snap)))

(schema OpResult
  (:f rec (List (Pair String RVal)))
  (:f procs Procs))

(schema KillOut
  (:f killed (List String))
  (:f restored (List String))
  (:f kept (List String))
  (:f procs Procs))

(schema Settled
  (:f restored (List String))
  (:f kept (List String))
  (:f procs Procs))

fn makeRunCtx root: String owns: (List String) session: String timeoutSec: Int64 hidden: (List String) toolRoot: String -> RunCtx
  (RunCtx :root root :owns owns :session session :timeoutSec timeoutSec :hidden hidden :toolRoot toolRoot)

fn newProcs -> Procs
  (Procs :ids (list) :table (list) :base (none))

fn itos n: Int64 -> String
  (stringFromInt64 n)

fn byteAt bs: Bytes i: Int64 -> Int64
  (bytesGet bs i)

fn oneByte s: String i: Int64 -> String
  (c/sliceOf s i (+ i 1))

fn isCont b: Int64 -> Bool
  (and (>= b 128) (< b 192))

fn cpIndex bs: Bytes n: Int64 i: Int64 k: Int64 -> Int64
  (cond
    ((>= i n) n)
    ((isCont (byteAt bs i)) (cpIndex bs n (+ i 1) k))
    ((<= k 0) i)
    (else (cpIndex bs n (+ i 1) (- k 1))))

fn cpDrop s: String k: Int64 -> String
  (let [bs (stringToBytes s)
        n (bytesLength bs)]
    (c/sliceOf s (cpIndex bs n 0 k) n))

fn cpTail s: String k: Int64 -> String
  (let [len (g/cpLength s)]
    (cond
      ((= k 0) s)
      ((< k 0) (cpDrop s (- 0 k)))
      ((<= len k) s)
      (else (cpDrop s (- len k)))))

fn rs k: String v: String -> (Pair String RVal)
  (pair k (rStr v))

fn ri k: String v: Int64 -> (Pair String RVal)
  (pair k (rInt v))

fn rb k: String v: Bool -> (Pair String RVal)
  (pair k (rBool v))

fn rl k: String v: (List String) -> (Pair String RVal)
  (pair k (rList v))

fn serVal v: RVal -> String
  (mt v
    ((rStr s) (c/serString s))
    ((rInt n) (itos n))
    ((rBool b) (if b "true" "false"))
    ((rList xs) (str "(" (stringJoin (map c/serString xs) " ") ")")))

fn serRec rec: (List (Pair String RVal)) -> String
  (str "(r" (stringJoin (map (fn [p] (str " (" (pairFirst p) " " (serVal (pairSecond p)) ")")) rec) "") ")")

fn opGet op: (List (Pair String c/KvVal)) key: String -> (Option c/KvVal)
  (mt (listHead (filter (fn [p] (= (pairFirst p) key)) op))
    ((some p) (some (pairSecond p)))
    ((none) (none)))

fn kvText v: c/KvVal -> String
  (mt v ((c/kvStr s) s) ((c/kvInt d) d))

fn kvTruthy v: c/KvVal -> Bool
  (mt v
    ((c/kvStr s) (not (stringEmpty? s)))
    ((c/kvInt d) (!= (optionOr (stringToInt64 d) 0) 0)))

fn firstTruthy op: (List (Pair String c/KvVal)) keys: (List String) -> String
  (if (listEmpty? keys)
    ""
    (mt (opGet op (c/firstOf keys))
      ((some v) (if (kvTruthy v) (kvText v) (firstTruthy op (c/restOf keys))))
      ((none) (firstTruthy op (c/restOf keys)))))

fn lstripColons s: String -> String
  (if (stringStartsWith? s ":") (lstripColons (cpDrop s 1)) s)

fn isWs b: Int64 -> Bool
  (or (= b 32) (or (= b 9) (or (= b 13) (= b 10))))

fn isPunct b: Int64 -> Bool
  (or (= b 40) (or (= b 41) (or (= b 59) (or (= b 60) (or (= b 62) (or (= b 124) (= b 38)))))))

fn isQuote b: Int64 -> Bool
  (or (= b 39) (= b 34))

fn lineEnd bs: Bytes n: Int64 i: Int64 -> Int64
  (cond
    ((>= i n) n)
    ((= (byteAt bs i) 10) (+ i 1))
    (else (lineEnd bs n (+ i 1))))

fn emitTok piece: (List String) acc: (List String) -> (List String)
  (cons (c/joinAll (listReverse piece)) acc)

fn lex s: String bs: Bytes n: Int64 i: Int64 state: Int64 escState: Int64 piece: (List String) quoted: Bool acc: (List String) -> (Result (List String) String)
  (let [b (if (< i n) (byteAt bs i) -1)
        has (or (not (listEmpty? piece)) quoted)]
    (cond
      ((= state 0)
        (cond
          ((< b 0) (ok (listReverse acc)))
          ((isWs b) (lex s bs n (+ i 1) 0 escState piece quoted acc))
          ((= b 35) (lex s bs n (lineEnd bs n (+ i 1)) 0 escState piece quoted acc))
          ((= b 92) (lex s bs n (+ i 1) 5 1 piece quoted acc))
          ((isPunct b) (lex s bs n (+ i 1) 2 escState (list (oneByte s i)) quoted acc))
          ((= b 39) (lex s bs n (+ i 1) 3 escState piece quoted acc))
          ((= b 34) (lex s bs n (+ i 1) 4 escState piece quoted acc))
          (else (lex s bs n (+ i 1) 1 escState (list (oneByte s i)) quoted acc))))
      ((or (= state 1) (= state 2))
        (cond
          ((< b 0) (ok (listReverse (if has (emitTok piece acc) acc))))
          ((isWs b)
            (if has
              (lex s bs n (+ i 1) 0 escState (list) false (emitTok piece acc))
              (lex s bs n (+ i 1) 0 escState piece quoted acc)))
          ((= b 35)
            (let [j (lineEnd bs n (+ i 1))]
              (if has
                (lex s bs n j 0 escState (list) false (emitTok piece acc))
                (lex s bs n j 0 escState piece quoted acc))))
          ((= state 2)
            (if (isPunct b)
              (lex s bs n (+ i 1) 2 escState (cons (oneByte s i) piece) quoted acc)
              (lex s bs n i 0 escState (list) false (emitTok piece acc))))
          ((isQuote b) (lex s bs n (+ i 1) (if (= b 39) 3 4) escState piece quoted acc))
          ((= b 92) (lex s bs n (+ i 1) 5 1 piece quoted acc))
          ((not (isPunct b)) (lex s bs n (+ i 1) 1 escState (cons (oneByte s i) piece) quoted acc))
          (has (lex s bs n i 0 escState (list) false (emitTok piece acc)))
          (else (lex s bs n i 0 escState piece quoted acc))))
      ((or (= state 3) (= state 4))
        (let [q (if (= state 3) 39 34)]
          (cond
            ((< b 0) (err "No closing quotation"))
            ((= b q) (lex s bs n (+ i 1) 1 escState piece true acc))
            ((and (= b 92) (= state 4)) (lex s bs n (+ i 1) 5 4 piece true acc))
            (else (lex s bs n (+ i 1) state escState (cons (oneByte s i) piece) true acc)))))
      (else
        (cond
          ((< b 0) (err "No escaped character"))
          (else
            (let [keepSlash (and (or (= escState 3) (= escState 4)) (and (!= b 92) (!= b (if (= escState 3) 39 34))))
                  withSlash (if keepSlash (cons "\\" piece) piece)]
              (lex s bs n (+ i 1) escState escState (cons (oneByte s i) withSlash) quoted acc)))))))

fn shellWords cmd: String -> (Result (List String) String)
  (let [bs (stringToBytes cmd)]
    (lex cmd bs (bytesLength bs) 0 0 1 (list) false (list)))

fn isReWs b: Int64 -> Bool
  (or (= b 32) (or (and (>= b 9) (<= b 13)) (and (>= b 28) (<= b 31))))

fn wsSplit s: String bs: Bytes n: Int64 i: Int64 start: Int64 acc: (List String) -> (List String)
  (cond
    ((>= i n) (listReverse (cons (c/sliceOf s start n) acc)))
    ((isReWs (byteAt bs i))
      (let [j (wsRunEnd bs n i)]
        (wsSplit s bs n j j (cons (c/sliceOf s start i) acc))))
    (else (wsSplit s bs n (+ i 1) start acc)))

fn wsRunEnd bs: Bytes n: Int64 i: Int64 -> Int64
  (if (and (< i n) (isReWs (byteAt bs i))) (wsRunEnd bs n (+ i 1)) i)

fn reSplitWs s: String -> (List String)
  (let [bs (stringToBytes s)]
    (wsSplit s bs (bytesLength bs) 0 0 (list)))

fn isFlag a: String -> Bool
  (stringStartsWith? a "-")

fn memberOf x: String xs: (List String) -> Bool
  (listAny? (fn [y] (= x y)) xs)

fn gitArgs toks: (List String) acc: (List String) -> (List String)
  (if (or (listEmpty? toks) (memberOf (c/firstOf toks) (list ";" "&&" "||" "|" "&")))
    (listReverse acc)
    (gitArgs (c/restOf toks) (cons (c/firstOf toks) acc)))

fn filesHint -> String
  "edit or write ops for files"

fn commitHint -> String
  "(:done :commit msg) for commits"

fn refuse name: String hint: String -> (Option (Pair String String))
  (some (pair name hint))

fn gitVerdict args: (List String) -> (Option (Pair String String))
  (let [plain (filter (fn [a] (not (isFlag a))) args)
        sub (cond ((not (listEmpty? plain)) (c/firstOf plain)) ((not (listEmpty? args)) (c/firstOf args)) (else ""))
        rest (if (listEmpty? args) (list) (c/restOf args))]
    (cond
      ((= sub "checkout")
        (if (and (not (listEmpty? rest)) (memberOf (c/firstOf rest) (list "-b" "-B")))
          (none)
          (if (or (memberOf "--" rest) (or (memberOf "-f" rest) (or (memberOf "--force" rest) (listAny? (fn [a] (not (isFlag a))) rest))))
            (refuse "git checkout" (filesHint))
            (none))))
      ((= sub "restore") (refuse "git restore" (filesHint)))
      ((= sub "reset") (refuse "git reset" (filesHint)))
      ((= sub "clean") (refuse "git clean" (filesHint)))
      ((= sub "stash")
        (let [subsub (if (and (not (listEmpty? rest)) (not (isFlag (c/firstOf rest)))) (c/firstOf rest) "")]
          (if (memberOf subsub (list "list" "show")) (none) (refuse "git stash" (filesHint)))))
      ((= sub "apply")
        (if (listAny? (fn [a] (memberOf a (list "--check" "--stat" "--summary" "--numstat"))) rest)
          (none)
          (refuse "git apply" (filesHint))))
      ((= sub "commit") (refuse "git commit" (commitHint)))
      ((= sub "merge") (refuse "git merge" (commitHint)))
      ((= sub "rebase") (refuse "git rebase" (commitHint)))
      ((= sub "cherry-pick") (refuse "git cherry-pick" (commitHint)))
      ((= sub "revert") (refuse "git revert" (commitHint)))
      ((= sub "tag") (refuse "git tag" (commitHint)))
      ((= sub "branch")
        (if (listAny? (fn [a] (memberOf a (list "-d" "-D" "--delete"))) args) (refuse "git branch -d/-D" (commitHint)) (none)))
      ((= sub "update-ref") (refuse "git update-ref" (commitHint)))
      ((= sub "am") (refuse "git am" (commitHint)))
      (else (none))))

fn skipShFlags toks: (List String) -> (List String)
  (if (and (not (listEmpty? toks)) (and (isFlag (c/firstOf toks)) (!= (c/firstOf toks) "-c")))
    (skipShFlags (c/restOf toks))
    toks)

fn shVerdict rest: (List String) -> (Option (Pair String String))
  (let [after (skipShFlags rest)]
    (if (and (not (listEmpty? after)) (and (= (c/firstOf after) "-c") (not (listEmpty? (c/restOf after)))))
      (checkRunGitGuard (c/firstOf (c/restOf after)))
      (none)))

fn scanTokens toks: (List String) -> (Option (Pair String String))
  (if (listEmpty? toks)
    (none)
    (let [tok (c/firstOf toks)
          rest (c/restOf toks)
          shHit (if (and (memberOf tok (list "sh" "bash" "zsh" "dash")) (not (listEmpty? rest))) (shVerdict rest) (none))]
      (cond
        ((some? shHit) shHit)
        ((and (= tok "git") (not (listEmpty? rest)))
          (let [v (gitVerdict (gitArgs rest (list)))]
            (if (some? v) v (scanTokens rest))))
        (else (scanTokens rest)))))

fn checkRunGitGuard cmd: String -> (Option (Pair String String))
  (scanTokens (mt (shellWords cmd) ((ok ws) ws) ((err _) (reSplitWs cmd))))

fn rootOrDot root: String -> String
  (if (stringEmpty? root) "." root)

fn runOutward cmd: String owns: (List String) root: String -> (Result String String)
  (mt (shellWords cmd)
    ((err e) (err e))
    ((ok ws) (ok (c/runOutward ws owns (rootOrDot root)))))

fn runReadOnly cmd: String -> Bool
  (mt (shellWords cmd)
    ((err _) false)
    ((ok ws) (and (not (listEmpty? ws)) (c/runReadOnly ws))))

fn isNameStart b: Int64 -> Bool
  (or (= b 95) (or (and (>= b 65) (<= b 90)) (and (>= b 97) (<= b 122))))

fn isNameByte b: Int64 -> Bool
  (or (isNameStart b) (or (and (>= b 48) (<= b 57)) (>= b 128)))

fn isVarName s: String -> Bool
  (let [bs (stringToBytes s)
        n (bytesLength bs)]
    (and (> n 0) (and (isNameStart (byteAt bs 0)) (listAll? (fn [i] (isNameByte (byteAt bs i))) (range 1 n)))))

fn hiddenVars text: String -> (List String)
  (filter isVarName (filter (fn [w] (not (stringEmpty? w))) (reSplitWs text)))

fn universalNewlines s: String -> String
  (stringReplace (stringReplace s "\r\n" "\n") "\r" "\n")

fn tailLines text: String n: Int64 -> (List String)
  (let [u (universalNewlines text)
        parts (stringSplit u "\n")
        lines (if (and (not (listEmpty? parts)) (stringEmpty? (optionOr (listLast parts) "x"))) (listTake parts (- (listLength parts) 1)) parts)
        total (listLength lines)]
    (cond
      ((> n 0) (listDrop lines (max 0 (- total n))))
      ((= n 0) lines)
      (else (listDrop lines (- 0 n)))))

fn logTail text: String n: Int64 cap: Int64 -> String
  (cpTail (stringJoin (tailLines text n) "\n") cap)

fn escapeStr s: String -> String
  (stringReplace (stringReplace (stringReplace s "\\" "\\\\") "\"" "\\\"") "\n" "\\n")

fn byLengthDesc xs: (List String) -> (List String)
  (listReverse (listSortBy (fn [x] (stringLength x)) xs))

fn dedup xs: (List String) acc: (List String) -> (List String)
  (if (listEmpty? xs)
    (listReverse acc)
    (dedup (c/restOf xs) (if (memberOf (c/firstOf xs) acc) acc (cons (c/firstOf xs) acc))))

fn wireRoots! ctx: RunCtx -> (List String)
  (let [tool ctx.toolRoot
        cands (listAppend (if (stringEmpty? tool) (list) (list tool (g/pyRealpath! tool)))
                (list (g/pyRealpath! (pyAbspath! (rootOrDot ctx.root)))))]
    (byLengthDesc (filter (fn [r] (and (not (stringEmpty? r)) (!= r "/"))) (dedup cands (list)))))

fn relativize body: String roots: (List String) -> String
  (let [start (if (memberOf body roots) "." body)]
    (fold (fn [acc r] (stringReplace acc (str r "/") "")) start roots))

fn wireLine line: String roots: (List String) -> String
  (c/asnUnescape (relativize (stringReplace (escapeStr line) "\r" "") roots))

fn opTail! p: Proc ctx: RunCtx -> String
  (let [roots (wireRoots! ctx)]
    (cpTail (stringJoin (map (fn [l] (wireLine l roots)) (tailLines (logText p) 20)) "\n") 2000))

fn wireStrVal s: String roots: (List String) -> String
  (str "\"" (relativize (escapeStr s) roots) "\"")

fn engineReject receipt: String -> String
  (cpTail (str "(:manage :status :rejected :error ERR_ENGINE_REJECTED :receipt " receipt " :see \"(:help :op manage)\")") 300)

fn engineError! sid: String message: String ctx: RunCtx -> String
  (let [roots (wireRoots! ctx)]
    (engineReject (str "(:receipt :status :error :id " (wireStrVal sid roots) " :message " (wireStrVal message roots) ")")))

fn badSessionBody -> String
  "(:error :code ERR_BAD_SESSION :message \"ASL_SESSION must match [A-Za-z0-9._-]+ without ..\")"

fn isIdByte b: Int64 -> Bool
  (or (and (>= b 65) (<= b 90)) (or (and (>= b 97) (<= b 122)) (or (and (>= b 48) (<= b 57)) (or (= b 46) (or (= b 95) (= b 45))))))

fn idChars s: String -> Bool
  (let [bs (stringToBytes s)]
    (listAll? (fn [i] (isIdByte (byteAt bs i))) (range 0 (bytesLength bs))))

fn sessionBad session: String -> Bool
  (and (not (stringEmpty? session))
    (or (not (idChars session)) (or (stringContains? session "..") (= session "."))))

fn sidValid sid: String -> Bool
  (and (> (stringLength sid) 0) (and (<= (stringLength sid) 128) (and (idChars sid) (not (stringContains? sid "..")))))

fn invalidIdBody! sid: String ctx: RunCtx -> String
  (engineReject (str "(:receipt :status :error :errorCode \":ERR_INVALID_ID\" :id " (wireStrVal sid (wireRoots! ctx))
                  " :message \"Session id must match [A-Za-z0-9._-]{1,128} and must not contain ..\")"))

fn sidPrefix ctx: RunCtx -> String
  (if (stringEmpty? ctx.session) "leon" ctx.session)

fn getCwd! -> String
  (resultOr (realPath ".") ".")

fn pyAbspath! p: String -> String
  (g/pyNormpath (if (stringStartsWith? p "/") p (str (getCwd!) "/" p)))

fn joinPath a: String b: String -> String
  (cond
    ((stringStartsWith? b "/") b)
    ((or (stringEmpty? a) (stringEndsWith? a "/")) (str a b))
    (else (str a "/" b)))

fn parentDir p: String -> String
  (mt (listLast (listIndexesOf p "/"))
    ((some i) (c/sliceOf p 0 i))
    ((none) ""))

fn listIndexesOf s: String sub: String -> (List Int64)
  (let [bs (stringToBytes s)
        n (bytesLength bs)
        b (charCode sub)]
    (filter (fn [i] (= (byteAt bs i) b)) (range 0 n)))

fn isFile! p: String -> Bool
  (mt (fileStat p) ((ok st) st.isFile) ((err _) false))

fn isDir! p: String -> Bool
  (mt (fileStat p) ((ok st) st.isDir) ((err _) false))

fn insideRoot! path: String rootDir: String -> Bool
  (let [root (rootOrDot rootDir)
        rel (g/pyNormpath (g/pyRelpath! (joinPath root path) root))
        first (optionOr (listHead (stringSplit rel "/")) "")]
    (and (g/isPathInRepo! path rootDir) (!= first ".git")))

fn isBytecode rel: String -> Bool
  (or (stringEndsWith? rel ".pyc") (or (stringEndsWith? rel ".pyo") (memberOf "__pycache__" (stringSplit rel "/"))))

fn logText p: Proc -> String
  (c/joinAll (listReverse p.log))

fn logCap -> Int64
  1048576

fn withChunk p: Proc chunk: String outOpen: Bool errOpen: Bool -> Proc
  (let [size (+ p.logSize (stringLength chunk))
        chunks (if (stringEmpty? chunk) p.log (cons chunk p.log))
        text (if (> size (logCap)) (c/joinAll (listReverse chunks)) "")
        kept (if (> size (logCap)) (list (c/sliceOf text (- size (logCap)) size)) chunks)]
    (with p :outOpen outOpen :errOpen errOpen :log kept :logSize (min size (logCap))))

fn withState p: Proc inOpen: Bool code: (Option Int64) signalled: Bool -> Proc
  (with p :inOpen inOpen :code code :signalled signalled)

fn pollSet p: Proc -> (List (Pair Int64 Int64))
  (listAppend (if p.outOpen (list (pair p.outFd 1)) (list)) (if p.errOpen (list (pair p.errFd 1)) (list)))

fn readyOn ready: (List (Pair Int64 Int64)) fd: Int64 -> Bool
  (listAny? (fn [q] (= (pairFirst q) fd)) ready)

fn readOne! fd: Int64 -> (Pair Bool String)
  (mt (fdRead fd 65536)
    ((ok chunk) (if (stringEmpty? chunk) (do (fdClose fd) (pair false "")) (pair true chunk)))
    ((err e) (if (= e "wouldBlock") (pair true "") (do (fdClose fd) (pair false "")))))

fn pumpOnce! p: Proc ms: Int64 -> (Pair Bool Proc)
  (let [fds (pollSet p)]
    (if (listEmpty? fds)
      (do (if (> ms 0) (sleepMs ms) ()) (pair false p))
      (mt (fdPoll fds ms)
        ((err _) (pair false p))
        ((ok ready)
          (if (listEmpty? ready)
            (pair false p)
            (let [o (if (and p.outOpen (readyOn ready p.outFd)) (readOne! p.outFd) (pair p.outOpen ""))
                  p1 (withChunk p (pairSecond o) (pairFirst o) p.errOpen)
                  e (if (and p1.errOpen (readyOn ready p1.errFd)) (readOne! p1.errFd) (pair p1.errOpen ""))]
              (pair true (withChunk p1 (pairSecond e) (pairFirst o) (pairFirst e)))))))))

fn drain! p: Proc left: Int64 -> Proc
  (if (<= left 0)
    p
    (let [r (pumpOnce! p 0)]
      (if (pairFirst r) (drain! (pairSecond r) (- left 1)) (pairSecond r))))

fn closeIn! p: Proc -> Proc
  (if p.inOpen (do (fdClose p.inFd) (withState p false p.code p.signalled)) p)

fn reap! p: Proc -> Proc
  (if (some? p.code)
    p
    (mt (procWaitPid p.pid true)
      ((ok got) (mt got ((some c) (closeIn! (withState p p.inOpen (some c) p.signalled))) ((none) p)))
      ((err _) (closeIn! (withState p p.inOpen (some 255) p.signalled)))))

fn refresh! p: Proc -> Proc
  (drain! (reap! p) 128)

fn running p: Proc -> Bool
  (none? p.code)

fn exitOf p: Proc -> (Option Int64)
  p.code

fn stateOf p: Proc -> String
  (mt p.code
    ((none) "running")
    ((some c) (if (= c 0) "completed" "failed")))

fn waitGone! p: Proc left: Int64 -> Proc
  (let [q (reap! p)]
    (if (or (not (running q)) (<= left 0)) q (do (sleepMs 10) (waitGone! q (- left 10)))))

fn signalGroup! pid: Int64 sig: String -> Bool
  (mt (procKill (- 0 pid) sig)
    ((ok _) true)
    ((err e) (if (= e "noProcess") true (ok? (procKill pid "SIGKILL")))))

fn reapKilled! p: Proc killed: Bool -> Proc
  (cond
    ((not (running p)) (withState p p.inOpen p.code true))
    ((not killed) (withState p p.inOpen p.code true))
    (else
      (mt (procWaitPid p.pid false)
        ((ok got) (closeIn! (withState p p.inOpen (some (optionOr got -9)) true)))
        ((err _) (closeIn! (withState p p.inOpen (some -9) true))))))

fn killProc! p: Proc -> Proc
  (let [q (reap! p)]
    (if (not (running q))
      (refresh! q)
      (do
        (signalGroup! q.pid "SIGTERM")
        (let [waited (waitGone! q 100)]
          (drain! (reapKilled! waited (signalGroup! waited.pid "SIGKILL")) 128)))))

fn tableGet table: (List Proc) sid: String -> (Option Proc)
  (listHead (filter (fn [p] (= p.sid sid)) table))

fn tablePut table: (List Proc) p: Proc -> (List Proc)
  (cons p (filter (fn [q] (!= q.sid p.sid)) table))

fn withTable procs: Procs table: (List Proc) -> Procs
  (with procs :table table)

fn withIds procs: Procs ids: (List String) -> Procs
  (with procs :ids ids)

fn withBase procs: Procs base: (Option Snap) -> Procs
  (with procs :base base)

fn removeFirst xs: (List String) x: String -> (List String)
  (if (listEmpty? xs)
    xs
    (if (= (c/firstOf xs) x) (c/restOf xs) (cons (c/firstOf xs) (removeFirst (c/restOf xs) x))))

fn updateProc procs: Procs sid: String f: (fn [Proc] -> Proc) -> Procs
  (mt (tableGet procs.table sid)
    ((some p) (withTable procs (tablePut procs.table (f p))))
    ((none) procs))

fn drainProcs! procs: Procs -> Procs
  (withTable procs (map (fn [p] (if (or p.outOpen p.errOpen) (refresh! p) (reap! p))) procs.table))

fn envKey row: String -> String
  (mt (stringIndexOf row "=") ((some i) (c/sliceOf row 0 i)) ((none) row))

fn spawnEnv! ctx: RunCtx absRoot: String -> (List String)
  (let [base (listAppend (filter (fn [r] (!= (envKey r) "PWD")) (envList)) (list (str "PWD=" absRoot)))
        shown (filter (fn [r] (not (memberOf (envKey r) ctx.hidden))) base)]
    (listAppend (filter (fn [r] (!= (envKey r) "PYTHONDONTWRITEBYTECODE")) shown) (list "PYTHONDONTWRITEBYTECODE=1")))

fn spawnProc! sid: String cmd: String ctx: RunCtx stdin: Bool -> (Result Proc String)
  (let [absRoot (pyAbspath! (rootOrDot ctx.root))]
    (if (not (isDir! absRoot))
      (err (str "no directory " absRoot))
      (mt (procSpawnv (list "/bin/sh" "-c" cmd) (some absRoot) (some (spawnEnv! ctx absRoot)))
        ((err kind) (err kind))
        ((ok sp)
          (let [inOpen (if stdin (ok? (fdNonBlocking sp.stdin true)) (do (fdClose sp.stdin) false))]
            (ok (Proc :sid sid :pid sp.pid :inFd sp.stdin :outFd sp.stdout :errFd sp.stderr
                  :inOpen inOpen :outOpen true :errOpen true :log (list) :logSize 0 :code (none) :signalled false)))))))

fn sortMarks ms: (List Mark) -> (List Mark)
  (listSortBy (fn [m] m.rel) ms)

fn gitListing! argv: (List String) root: String -> (Result g/Bounded String)
  (g/runBounded! argv (some root) (none) (none))

fn nulSplit s: String -> (List String)
  (filter (fn [x] (not (stringEmpty? x))) (stringSplit s "\x00"))

fn markOf! root: String rel: String -> (Result (Option Mark) String)
  (mt (fileStat (joinPath root rel))
    ((ok st) (ok (some (Mark :rel rel :size st.size :mtime st.mtime))))
    ((err e) (if (stringStartsWith? e "notFound") (ok (none)) (err e))))

fn collectMarks! root: String rels: (List String) acc: (List Mark) -> (Result (List Mark) String)
  (if (listEmpty? rels)
    (ok (sortMarks acc))
    (mt (markOf! root (c/firstOf rels))
      ((err e) (err e))
      ((ok m) (collectMarks! root (c/restOf rels) (mt m ((some x) (cons x acc)) ((none) acc))))))

fn worktreeMarks! root: String -> (Result (List Mark) String)
  (mt (gitListing! (list "git" "ls-files" "-z" "-c" "-o" "--exclude-standard") root)
    ((err e) (err e))
    ((ok b)
      (if (!= (optionOr b.code 1) 0)
        (err (str "git ls-files: " (g/pyStrip b.errText)))
        (collectMarks! root (nulSplit b.out) (list)))))

fn errnoMessage e: String path: String -> String
  (cond
    ((stringStartsWith? e "notFound") (str "[Errno 2] No such file or directory: " (g/pyRepr path)))
    ((stringStartsWith? e "permission") (str "[Errno 13] Permission denied: " (g/pyRepr path)))
    (else e))

fn readKept! root: String rels: (List String) acc: (List (Pair String (Option String))) -> (Result (List (Pair String (Option String))) String)
  (if (listEmpty? rels)
    (ok acc)
    (let [rel (c/firstOf rels)
          full (joinPath root rel)]
      (if (isFile! full)
        (mt (fileReadString full)
          ((ok bytes) (readKept! root (c/restOf rels) (cons (pair rel (some bytes)) acc)))
          ((err e) (err (errnoMessage e full))))
        (readKept! root (c/restOf rels) acc))))

fn nowSec! -> Int64
  (/ (nowNs) 1000000000)

fn treeSnapshot! root: String -> (Result Snap String)
  (let [at (nowSec!)]
    (mt (worktreeMarks! root)
      ((err e) (err e))
      ((ok marks)
        (mt (gitListing! (list "git" "status" "--porcelain" "-z" "-uall") root)
          ((err e) (err e))
          ((ok b)
            (let [code (optionOr b.code 1)]
              (if (!= code 0)
                (err (str "Command '['git', 'status', '--porcelain', '-z', '-uall']' returned non-zero exit status " (itos code) "."))
                (mt (readKept! root (map (fn [e] (cpDrop e 3)) (nulSplit b.out)) (list))
                  ((err e) (err e))
                  ((ok kept) (ok (Snap :marks marks :kept kept :at at)))))))))))

fn rawPump! outFd: Int64 errFd: Int64 outOpen: Bool errOpen: Bool acc: (List String) -> (List String)
  (if (not (or outOpen errOpen))
    acc
    (mt (fdPoll (listAppend (if outOpen (list (pair outFd 1)) (list)) (if errOpen (list (pair errFd 1)) (list))) -1)
      ((err _) (do (if outOpen (fdClose outFd) (ok ())) (if errOpen (fdClose errFd) (ok ())) acc))
      ((ok ready)
        (let [o (if (and outOpen (readyOn ready outFd)) (readOne! outFd) (pair outOpen ""))
              e (if (and errOpen (readyOn ready errFd)) (readOne! errFd) (pair errOpen ""))]
          (rawPump! outFd errFd (pairFirst o) (pairFirst e) (if (stringEmpty? (pairSecond o)) acc (cons (pairSecond o) acc)))))))

fn preBytes! root: String rel: String -> (Result (Option String) String)
  (mt (procSpawnv (list "git" "show" (str "HEAD:" rel)) (some root) (none))
    ((err kind) (err (errnoMessage kind "git")))
    ((ok sp)
      (let [closed (fdClose sp.stdin)
            out (c/joinAll (listReverse (rawPump! sp.stdout sp.stderr true true (list))))]
        (mt (procWaitPid sp.pid false)
          ((err e) (err e))
          ((ok got) (ok (if (= (optionOr got 1) 0) (some out) (none))))))))

fn keptGet kept: (List (Pair String (Option String))) rel: String -> (Option (Option String))
  (mt (listHead (filter (fn [p] (= (pairFirst p) rel)) kept))
    ((some p) (some (pairSecond p)))
    ((none) (none)))

fn unionWalk bs: (List Mark) xs: (List Mark) acc: (List (Pair String (Pair (Option Mark) (Option Mark)))) -> (List (Pair String (Pair (Option Mark) (Option Mark))))
  (cond
    ((and (listEmpty? bs) (listEmpty? xs)) (listReverse acc))
    ((listEmpty? xs) (unionWalk (c/restOf bs) xs (cons (pair (c/firstOf bs).rel (pair (some (c/firstOf bs)) (none))) acc)))
    ((listEmpty? bs) (unionWalk bs (c/restOf xs) (cons (pair (c/firstOf xs).rel (pair (none) (some (c/firstOf xs)))) acc)))
    (else
      (let [b (c/firstOf bs)
            a (c/firstOf xs)]
        (cond
          ((= b.rel a.rel) (unionWalk (c/restOf bs) (c/restOf xs) (cons (pair a.rel (pair (some b) (some a))) acc)))
          ((< b.rel a.rel) (unionWalk (c/restOf bs) xs (cons (pair b.rel (pair (some b) (none))) acc)))
          (else (unionWalk bs (c/restOf xs) (cons (pair a.rel (pair (none) (some a))) acc)))))))

fn sameMark bm: (Option Mark) am: (Option Mark) at: Int64 -> Bool
  (mt bm
    ((none) (none? am))
    ((some b)
      (mt am
        ((none) false)
        ((some a) (and (= a.size b.size) (and (= a.mtime b.mtime) (< a.mtime at)))))))

fn readNow! full: String -> (Result (Option String) String)
  (if (isFile! full)
    (mt (fileReadString full) ((ok b) (ok (some b))) ((err e) (err (errnoMessage e full))))
    (ok (none)))

fn changes! root: String snap: Snap entries: (List (Pair String (Pair (Option Mark) (Option Mark)))) acc: (List (Pair String (Pair (Option String) (Option String)))) -> (Result (List (Pair String (Pair (Option String) (Option String)))) String)
  (if (listEmpty? entries)
    (ok (listReverse acc))
    (let [e (c/firstOf entries)
          rel (pairFirst e)
          bm (pairFirst (pairSecond e))
          am (pairSecond (pairSecond e))]
      (if (sameMark bm am snap.at)
        (changes! root snap (c/restOf entries) acc)
        (let [pre (mt (keptGet snap.kept rel)
                    ((some v) (ok v))
                    ((none) (if (some? bm) (preBytes! root rel) (ok (none)))))]
          (mt pre
            ((err m) (err m))
            ((ok preV)
              (mt (readNow! (joinPath root rel))
                ((err m) (err m))
                ((ok nowV) (changes! root snap (c/restOf entries) (if (= preV nowV) acc (cons (pair rel (pair preV nowV)) acc)))))))))))

fn modeOf! full: String -> Int64
  (mt (fileStat full) ((ok st) (mod st.mode 4096)) ((err _) 420))

fn applyPlan! root: String items: (List (Pair (Pair String (Pair (Option String) (Option String))) String)) onKeep: (fn [String (Option String) Int64] -> Bool) restored: (List String) kept: (List String) -> (Result (Pair (List String) (List String)) String)
  (if (listEmpty? items)
    (ok (pair (listReverse restored) (listReverse kept)))
    (let [it (c/firstOf items)
          rel (pairFirst (pairFirst it))
          preV (pairFirst (pairSecond (pairFirst it)))
          nowV (pairSecond (pairSecond (pairFirst it)))
          what (pairSecond it)
          full (joinPath root rel)
          rest (c/restOf items)]
      (cond
        ((and (= what "keep") (isBytecode rel)) (applyPlan! root rest onKeep restored kept))
        ((= what "keep")
          (if (onKeep rel preV (if (some? nowV) (modeOf! full) 420))
            (applyPlan! root rest onKeep restored (cons rel kept))
            (err (str "the journal did not take " rel " before it was kept"))))
        (else
          (mt preV
            ((none)
              (mt (pathRemove full)
                ((ok _) (applyPlan! root rest onKeep (cons rel restored) kept))
                ((err e) (err e))))
            ((some bytes)
              (let [parent (parentDir full)
                    made (if (or (stringEmpty? parent) (isDir! parent)) (ok ()) (dirCreate parent))]
                (mt made
                  ((err e) (err e))
                  ((ok _)
                    (mt (fileWrite full bytes)
                      ((ok _) (applyPlan! root rest onKeep (cons rel restored) kept))
                      ((err e) (err e))))))))))))

fn settle! ctx: RunCtx procs: Procs onKeep: (fn [String (Option String) Int64] -> Bool) -> (Result Settled String)
  (mt procs.base
    ((none) (ok (Settled :restored (list) :kept (list) :procs procs)))
    ((some snap)
      (let [root ctx.root]
        (mt (worktreeMarks! root)
          ((err e) (err e))
          ((ok after)
            (mt (changes! root snap (unionWalk snap.marks after (list)) (list))
              ((err e) (err e))
              ((ok changed)
                (let [plan (if (listEmpty? changed) (list) (c/changePlan (map pairFirst changed) ctx.owns (rootOrDot root)))]
                  (mt (applyPlan! root (zip changed plan) onKeep (list) (list))
                    ((err e) (err e))
                    ((ok done)
                      (mt (treeSnapshot! root)
                        ((err e) (err e))
                        ((ok fresh) (ok (Settled :restored (pairFirst done) :kept (pairSecond done) :procs (withBase procs (some fresh))))))))))))))))

fn putMark marks: (List Mark) m: (Option Mark) rel: String -> (List Mark)
  (let [others (filter (fn [x] (!= x.rel rel)) marks)]
    (mt m ((some x) (sortMarks (cons x others))) ((none) others)))

fn rebaseWritten! root: String paths: (List String) procs: Procs -> (Result Procs String)
  (mt procs.base
    ((none) (ok procs))
    ((some snap)
      (if (listEmpty? paths)
        (ok procs)
        (let [p (c/firstOf paths)
              full (joinPath root p)
              rel (g/pyRelpath! (g/pyNormpath full) root)
              next (if (isFile! full)
                     (mt (fileStat full)
                       ((err e) (err e))
                       ((ok st)
                         (mt (fileReadString full)
                           ((err e) (err (errnoMessage e full)))
                           ((ok bytes) (ok (Snap :marks (putMark snap.marks (some (Mark :rel rel :size st.size :mtime st.mtime)) rel)
                                             :kept (cons (pair rel (some bytes)) snap.kept) :at snap.at))))))
                     (ok (Snap :marks (putMark snap.marks (none) rel) :kept (cons (pair rel (none)) snap.kept) :at snap.at)))]
          (mt next
            ((err e) (err e))
            ((ok s) (rebaseWritten! root (c/restOf paths) (withBase procs (some s)))))))))

enum Spawned
  (spawnedOk procs: Procs proc: Proc)
  (spawnSnapFailed message: String)
  (spawnEngineFailed procs: Procs body: String)

fn spawnSession! sid: String cmd: String ctx: RunCtx stdin: Bool procs: Procs -> Spawned
  (let [snap (if (or (none? procs.base) (listEmpty? procs.ids))
               (mt (treeSnapshot! ctx.root) ((ok s) (ok (withBase procs (some s)))) ((err e) (err e)))
               (ok procs))]
    (mt snap
      ((err e) (spawnSnapFailed e))
      ((ok ps)
        (cond
          ((sessionBad ctx.session) (spawnEngineFailed ps (badSessionBody)))
          ((not (sidValid sid)) (spawnEngineFailed ps (invalidIdBody! sid ctx)))
          (else
            (let [old (mt (tableGet ps.table sid) ((some p) (some (killProc! p))) ((none) (none)))
                  ps1 (mt old ((some p) (withTable ps (tablePut ps.table p))) ((none) ps))]
              (mt (spawnProc! sid cmd ctx stdin)
                ((err m) (spawnEngineFailed ps1 (engineError! sid m ctx)))
                ((ok p) (spawnedOk (Procs :ids (listAppend ps1.ids (list sid)) :table (tablePut ps1.table p) :base ps1.base) p)))))))))

fn needsConfirm rid: String opName: String message: String cmd: String -> (List (Pair String RVal))
  (list (rs "id" rid) (rs "op" opName) (rs "status" "needsConfirm") (rb "needsConfirm" true) (rs "message" message) (rs "cmd" cmd))

fn runReject rid: String err: String cmd: String message: String -> (List (Pair String RVal))
  (list (rs "id" rid) (rs "op" "run") (rs "status" "rejected") (rs "error" err) (rs "cmd" cmd) (rs "message" message))

fn waitRun! p: Proc deadline: Int64 -> Proc
  (let [q (reap! p)]
    (cond
      ((not (running q)) (drain! q 128))
      ((>= (monotonicNs) deadline) q)
      (else (waitRun! (pairSecond (pumpOnce! q (max 1 (min 50 (/ (- deadline (monotonicNs)) 1000000))))) deadline))))

fn execRunOp! op: (List (Pair String c/KvVal)) ctx: RunCtx procs: Procs rid: String onKeep: (fn [String (Option String) Int64] -> Bool) -> OpResult
  (let [cmd (firstTruthy op (list "argv" "cmd"))]
    (if (stringEmpty? (g/pyStrip cmd))
      (OpResult :rec (list (rs "id" rid) (rs "op" "run") (rs "status" "rejected") (rs "error" "ERR_MISSING_ARG") (rs "message" "run needs :argv")) :procs procs)
      (mt (checkRunGitGuard cmd)
        ((some g)
          (OpResult :rec (runReject rid "ERR_RUN_GIT" cmd
                           (str "not run: '" (pairFirst g) "' would discard working-tree changes or alter git history; use " (pairSecond g) " instead"))
            :procs procs))
        ((none)
          (mt (runOutward cmd ctx.owns ctx.root)
            ((err e)
              (OpResult :rec (runReject rid "ERR_RUN_QUOTING" cmd
                               (str "not run: the shell quoting does not parse (" e "); close every quote, or write a script file and run it"))
                :procs procs))
            ((ok why)
              (if (not (stringEmpty? why))
                (OpResult :rec (needsConfirm rid "run" (str "not run: " why "; the run goes on") cmd) :procs procs)
                (runSpawned! cmd ctx procs rid onKeep))))))))

fn runSpawned! cmd: String ctx: RunCtx procs: Procs rid: String onKeep: (fn [String (Option String) Int64] -> Bool) -> OpResult
  (let [sid (str (sidPrefix ctx) "-run" rid)]
    (mt (spawnSession! sid cmd ctx false procs)
      ((spawnSnapFailed m)
        (OpResult :rec (runReject rid "ERR_RUN_SNAPSHOT" cmd (str "the workspace must be a git repo to undo what a run changes: " m)) :procs procs))
      ((spawnEngineFailed ps body) (OpResult :rec (runReject rid "ERR_ENGINE" cmd body) :procs ps))
      ((spawnedOk ps p0)
        (let [t ctx.timeoutSec
              waited (waitRun! p0 (+ (monotonicNs) (* t 1000000000)))
              timedOut (running waited)
              final (if timedOut (killProc! waited) waited)
              tail (opTail! final ctx)
              ps1 (withIds (withTable ps (tablePut ps.table final)) (removeFirst ps.ids sid))
              exitCode (if (or timedOut (none? final.code)) 1 (optionOr (exitOf final) 1))]
          (mt (settle! ctx ps1 onKeep)
            ((err e) (OpResult :rec (runReject rid "ERR_RUN_SETTLE" cmd e) :procs ps1))
            ((ok s)
              (OpResult
                :rec (listAppend
                       (list (rs "id" rid) (rs "op" "run") (rs "status" (if (= exitCode 0) "ok" "failed")) (rs "cmd" cmd) (ri "exit" exitCode)
                         (rs "stdout" tail) (rl "restored" s.restored) (rl "flushed" s.kept) (rb "persisted" (not (listEmpty? s.kept))))
                       (if timedOut (list (rb "timeout" true) (rs "message" (str "killed after " (itos t) " s"))) (list)))
                :procs s.procs)))))))

fn manageActions -> (List String)
  (list "spawn" "poll" "tail" "kill" "list" "send")

fn isAlpha b: Int64 -> Bool
  (or (and (>= b 65) (<= b 90)) (and (>= b 97) (<= b 122)))

fn alphaEnd bs: Bytes n: Int64 i: Int64 -> Int64
  (if (and (< i n) (isAlpha (byteAt bs i))) (alphaEnd bs n (+ i 1)) i)

fn actionAt s: String bs: Bytes n: Int64 i: Int64 -> String
  (mt (stringIndexOf (c/sliceOf s i n) ":action")
    ((none) "")
    ((some k)
      (let [at (+ i k)
            w (wsRunEnd bs n (+ at 7))
            c1 (if (and (< w n) (= (byteAt bs w) 58)) (+ w 1) w)
            q1 (if (and (< c1 n) (= (byteAt bs c1) 34)) (+ c1 1) c1)
            e (alphaEnd bs n q1)]
        (if (and (> w (+ at 7)) (> e q1)) (c/sliceOf s q1 e) (actionAt s bs n (+ at 1))))))

fn formAction form: String -> String
  (let [bs (stringToBytes form)]
    (actionAt form bs (bytesLength bs) 0))

fn validName name: String -> Bool
  (and (>= (stringLength name) 1) (and (<= (stringLength name) 64) (idChars name)))

fn manageRec rid: String action: String -> (List (Pair String RVal))
  (list (rs "id" rid) (rs "op" "manage") (rs "action" action))

fn mo rec: (List (Pair String RVal)) procs: Procs -> OpResult
  (OpResult :rec rec :procs procs)

fn listLine sid: String procs: Procs -> String
  (let [name (mt (stringIndexOf sid "-") ((some i) (c/sliceOf sid (+ i 1) (stringLength sid))) ((none) sid))]
    (str name " " (mt (tableGet procs.table sid) ((some p) (stateOf p)) ((none) "None"))))

fn settleFields s: Settled -> (List (Pair String RVal))
  (list (rl "restored" s.restored) (rl "flushed" s.kept) (rb "persisted" (not (listEmpty? s.kept))))

fn settleFailed rec: (List (Pair String RVal)) e: String procs: Procs -> OpResult
  (mo (listAppend (filter (fn [p] (!= (pairFirst p) "status")) rec) (list (rs "status" "rejected") (rs "error" "ERR_RUN_SETTLE") (rs "message" e))) procs)

fn execManageOp! op: (List (Pair String c/KvVal)) ctx: RunCtx procs: Procs rid: String onKeep: (fn [String (Option String) Int64] -> Bool) -> OpResult
  (let [given (firstTruthy op (list "action"))
        action (lstripColons (if (stringEmpty? given) (formAction (firstTruthy op (list "form"))) given))
        res (manageRec rid action)]
    (cond
      ((not (memberOf action (manageActions)))
        (mo (listAppend res (list (rs "status" "rejected") (rs "error" "ERR_BAD_ARG") (rs "message" ":action is one of spawn, poll, tail, kill, list, send"))) procs))
      ((= action "list")
        (let [ps (drainProcs! procs)]
          (mo (listAppend res (list (rs "status" "ok") (rs "stdout" (stringJoin (map (fn [sid] (listLine sid ps)) ps.ids) "\n")))) ps)))
      (else
        (let [name (firstTruthy op (list "id" "name"))]
          (if (not (validName name))
            (mo (listAppend res (list (rs "status" "rejected") (rs "error" "ERR_BAD_ARG") (rs "message" ":id is 1-64 of A-Z a-z 0-9 . _ -"))) procs)
            (manageNamed! op ctx procs rid onKeep action name (listAppend res (list (rs "path" name)))))))))

fn manageNamed! op: (List (Pair String c/KvVal)) ctx: RunCtx procs: Procs rid: String onKeep: (fn [String (Option String) Int64] -> Bool) action: String name: String res: (List (Pair String RVal)) -> OpResult
  (let [sid (str (sidPrefix ctx) "-" name)
        spawned (memberOf sid procs.ids)]
    (cond
      ((= action "spawn") (manageSpawn! op ctx procs rid sid res))
      ((and (not spawned) (and (!= action "tail") (!= action "poll")))
        (mo (listAppend res (list (rs "status" "rejected") (rs "error" "ERR_NOT_SPAWNED") (rs "message" (str name " is not a process this run spawned")))) procs))
      ((= action "send") (manageSend! op ctx procs sid res))
      ((= action "tail")
        (mt (tableGet procs.table sid)
          ((some p)
            (let [q (refresh! p)]
              (mo (listAppend res (list (rs "status" "ok") (rs "stdout" (opTail! q ctx)))) (withTable procs (tablePut procs.table q)))))
          ((none) (mo (listAppend res (list (rs "status" "rejected") (rs "stdout" ""))) procs))))
      ((= action "kill")
        (let [ps (withIds (updateProc procs sid killProc!) (removeFirst procs.ids sid))
              rec (listAppend res (list (rs "status" "ok") (rs "message" "killed")))]
          (mt (settle! ctx ps onKeep)
            ((err e) (settleFailed rec e ps))
            ((ok s) (mo (listAppend rec (settleFields s)) s.procs)))))
      (else (managePoll! ctx procs sid res spawned onKeep))))

fn managePoll! ctx: RunCtx procs: Procs sid: String res: (List (Pair String RVal)) spawned: Bool onKeep: (fn [String (Option String) Int64] -> Bool) -> OpResult
  (mt (tableGet procs.table sid)
    ((none) (mo (listAppend res (list (rs "status" "rejected") (rs "message" "state None"))) procs))
    ((some p)
      (let [q (refresh! p)
            ps (withTable procs (tablePut procs.table q))
            rec (listAppend res (list (rs "status" "ok") (rs "message" (str "state " (stateOf q)))))]
        (mt (exitOf q)
          ((none) (mo rec ps))
          ((some code)
            (let [withExit (listAppend rec (list (ri "exit" code)))]
              (if (not spawned)
                (mo withExit ps)
                (let [ps1 (withIds ps (removeFirst ps.ids sid))]
                  (mt (settle! ctx ps1 onKeep)
                    ((err e) (settleFailed withExit e ps1))
                    ((ok s) (mo (listAppend withExit (settleFields s)) s.procs)))))))))))

fn manageSpawn! op: (List (Pair String c/KvVal)) ctx: RunCtx procs: Procs rid: String sid: String res: (List (Pair String RVal)) -> OpResult
  (let [cmd (firstTruthy op (list "cmd"))
        why (if (stringEmpty? (g/pyStrip cmd)) (ok "it names no :cmd") (runOutward cmd ctx.owns ctx.root))]
    (mt why
      ((err e) (mo (listAppend res (list (rs "status" "rejected") (rs "error" "ERR_RUN_QUOTING") (rs "message" (str "not spawned: the shell quoting does not parse (" e ")")))) procs))
      ((ok w)
        (if (not (stringEmpty? w))
          (mo (needsConfirm rid "manage" (str "not spawned: " w "; the run goes on") cmd) procs)
          (mt (spawnSession! sid cmd ctx true procs)
            ((spawnSnapFailed m) (mo (listAppend res (list (rs "status" "rejected") (rs "error" "ERR_RUN_SNAPSHOT") (rs "message" m))) procs))
            ((spawnEngineFailed ps body) (mo (listAppend res (list (rs "status" "rejected") (rs "error" "ERR_ENGINE") (rs "message" body))) ps))
            ((spawnedOk ps _) (mo (listAppend res (list (rs "status" "ok"))) ps)))))))

fn writeAll! fd: Int64 data: String deadline: Int64 -> (Result Unit String)
  (if (stringEmpty? data)
    (ok ())
    (mt (fdWrite fd data)
      ((ok k) (writeAll! fd (c/sliceOf data k (stringLength data)) deadline))
      ((err e)
        (cond
          ((!= e "wouldBlock") (err e))
          ((>= (monotonicNs) deadline) (err "timeout"))
          (else (do (fdPoll (list (pair fd 2)) 50) (writeAll! fd data deadline)))))))

fn sendMessage e: String t: Int64 -> String
  (cond
    ((= e "io:32") "[Errno 32] Broken pipe")
    ((= e "timeout") (str "the process read nothing for " (itos t) " s"))
    (else e))

fn manageSend! op: (List (Pair String c/KvVal)) ctx: RunCtx procs: Procs sid: String res: (List (Pair String RVal)) -> OpResult
  (mt (tableGet procs.table sid)
    ((none) (mo (listAppend res (list (rs "status" "rejected") (rs "error" "ERR_ENGINE") (rs "message" (engineReject (str "(:receipt :status :notFound :id " (wireStrVal sid (wireRoots! ctx)) ")"))))) procs))
    ((some p)
      (let [q (reap! p)
            text (firstTruthy op (list "text"))
            data (if (stringEndsWith? text "\n") text (str text "\n"))
            close (= (lstripColons (firstTruthy op (list "close"))) "true")]
        (if (or (not q.inOpen) (not (running q)))
          (mo (listAppend res (list (rs "status" "rejected") (rs "error" "ERR_ENGINE")
                                (rs "message" (engineError! sid "no open stdin: spawn with :stdin true, and the process must still run" ctx))))
            (withTable procs (tablePut procs.table q)))
          (let [t ctx.timeoutSec
                wrote (writeAll! q.inFd data (+ (monotonicNs) (* t 1000000000)))
                q1 (if (and close (ok? wrote)) (closeIn! q) q)
                ps (withTable procs (tablePut procs.table q1))]
            (mt wrote
              ((ok _) (mo (listAppend res (list (rs "status" "ok"))) ps))
              ((err e) (mo (listAppend res (list (rs "status" "rejected") (rs "error" "ERR_ENGINE") (rs "message" (engineError! sid (sendMessage e t) ctx)))) ps))))))))

fn killSpawned! ctx: RunCtx procs: Procs onKeep: (fn [String (Option String) Int64] -> Bool) -> (Result KillOut String)
  (let [killed procs.ids
        ps (withIds (fold (fn [acc sid] (updateProc acc sid killProc!)) procs killed) (list))]
    (if (listEmpty? killed)
      (ok (KillOut :killed (list) :restored (list) :kept (list) :procs (withBase ps (none))))
      (mt (settle! ctx ps onKeep)
        ((err e) (err e))
        ((ok s) (ok (KillOut :killed killed :restored s.restored :kept s.kept :procs (withBase s.procs (none))))))))

fn deleteReject rid: String err: String file: String message: String -> (List (Pair String RVal))
  (list (rs "id" rid) (rs "op" "delete") (rs "status" "rejected") (rs "error" err) (rs "file" file) (rs "message" message))

fn execDeleteOp! op: (List (Pair String c/KvVal)) ctx: RunCtx rid: String snap: (fn [String] -> Bool) -> (List (Pair String RVal))
  (let [rel (firstTruthy op (list "file" "path"))
        root ctx.root]
    (cond
      ((stringEmpty? rel)
        (list (rs "id" rid) (rs "op" "delete") (rs "status" "rejected") (rs "error" "ERR_MISSING_ARG") (rs "message" "delete needs :file")))
      ((not (insideRoot! rel root))
        (deleteReject rid "ERR_ROOT" rel (str "'" rel "' is outside :root; nothing in this step was written; the run goes on")))
      ((or (!= (c/changePlan (list rel) ctx.owns (rootOrDot root)) (list "keep")) (not (g/isPathInRepo! rel root)))
        (list (rs "id" rid) (rs "op" "delete") (rs "status" "rejected") (rs "error" "ERR_OWNS") (rs "file" rel) (rl "owns" ctx.owns)
          (rs "message" (str "'" rel "' is outside :owns; nothing in this step was written; the run goes on"))))
      (else
        (let [full (joinPath root rel)]
          (cond
            ((not (isFile! full)) (list (rs "id" rid) (rs "op" "delete") (rs "status" "rejected") (rs "error" "ERR_NOT_FOUND") (rs "file" rel) (rs "message" (str "no file " rel))))
            ((not (snap rel)) (deleteReject rid "ERR_SNAPSHOT" rel (str "'" rel "' could not be journaled before the delete; nothing was deleted")))
            (else
              (mt (pathRemove full)
                ((err e) (deleteReject rid "ERR_DELETE_FAILED" rel e))
                ((ok _) (list (rs "id" rid) (rs "op" "delete") (rs "status" "ok") (rs "file" rel) (ri "exit" 0) (rl "flushed" (list rel)) (rb "persisted" true))))))))))
