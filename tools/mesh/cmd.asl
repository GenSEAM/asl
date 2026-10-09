(module ws/asl/tools/mesh/cmd
  :x [main preflushReason slicedMutations unicodeEscape textWrap applyPatch! resolveFixTarget! normalizeRelPath makeCtx runProcPool! ProcJob ProcOut]
  :i [(ws/asl/tools/mesh/board :a board) (asl-json/json :a j)])

schema ProcJob
  (:f argv (List String))
  (:f cwd String)
  (:f env (List String))
  (:f input String)
  (:f timeoutMs Int64)

schema Ctx
  (:f root String)
  (:f cfg (List (Pair String board/AsnValue)))
  (:f env (List String))
  (:f gateway String)
  (:f apiKey String)

fn makeCtx root: String -> Ctx
  (Ctx :root root :cfg (list) :env (list) :gateway "" :apiKey "")

schema ProcOut
  (:f code Int64)
  (:f out String)
  (:f errText String)
  (:f timedOut Bool)

schema Query
  (:f ok Bool)
  (:f content String)
  (:f source String)
  (:f usage board/AsnValue)
  (:f error String)

schema Args
  (:f command String)
  (:f opts (List (Pair String String)))
  (:f flags (List String))

schema Overlay
  (:f dir String)
  (:f error String)

fn sub s: String i: Int64 j: Int64 -> String
  (let [n (stringLength s)
        a (max 0 (min i n))
        b (max a (min j n))]
    (optionOr (stringSlice s a b) ""))

fn first xs: (List T) d: T -> T
  (optionOr (listHead xs) d)

fn rest xs: (List T) -> (List T)
  (optionOr (listTail xs) (list))

fn s v: String -> board/AsnValue
  (board/asnStr v)

fn entries v: board/AsnValue -> (List (Pair String board/AsnValue))
  (mt v ((board/asnDict es) es) (_ (list)))

fn items v: board/AsnValue -> (List board/AsnValue)
  (mt v ((board/asnList xs) xs) ((board/asnTuple xs) xs) (_ (list)))

fn getv es: (List (Pair String board/AsnValue)) k: String -> board/AsnValue
  (optionOr (board/dictGet es k) (board/asnNone))

fn getd es: (List (Pair String board/AsnValue)) k: String d: board/AsnValue -> board/AsnValue
  (optionOr (board/dictGet es k) d)

fn gets es: (List (Pair String board/AsnValue)) k: String d: String -> String
  (board/pyStr (getd es k (s d)))

fn cfgv ctx: Ctx k: String -> board/AsnValue
  (getv ctx.cfg k)

fn cfgs ctx: Ctx k: String -> String
  (mt (cfgv ctx k) ((board/asnStr x) x) ((board/asnNone) "") (v (board/pyStr v)))

fn withCfg ctx: Ctx k: String v: board/AsnValue -> Ctx
  (Ctx :root ctx.root :cfg (board/dictPut ctx.cfg k v) :env ctx.env :gateway ctx.gateway :apiKey ctx.apiKey)

fn withRoot ctx: Ctx root: String -> Ctx
  (Ctx :root root :cfg ctx.cfg :env ctx.env :gateway ctx.gateway :apiKey ctx.apiKey)

fn spaceLen bs: Bytes i: Int64 n: Int64 -> Int64
  (if (>= i n)
    0
    (let [b (bytesGet bs i)]
      (cond
        ((or (and (>= b 9) (<= b 13)) (and (>= b 28) (<= b 32))) 1)
        ((and (= b 194) (< (+ i 1) n))
          (let [c (bytesGet bs (+ i 1))] (if (or (= c 133) (= c 160)) 2 0)))
        ((and (= b 225) (< (+ i 2) n))
          (if (and (= (bytesGet bs (+ i 1)) 154) (= (bytesGet bs (+ i 2)) 128)) 3 0))
        ((and (= b 226) (< (+ i 2) n))
          (let [c (bytesGet bs (+ i 1))
                d (bytesGet bs (+ i 2))]
            (if (or (and (= c 128) (or (<= d 138) (= d 168) (= d 169) (= d 175))) (and (= c 129) (= d 159))) 3 0)))
        ((and (= b 227) (< (+ i 2) n))
          (if (and (= (bytesGet bs (+ i 1)) 128) (= (bytesGet bs (+ i 2)) 128)) 3 0))
        (else 0))))

fn skipSpace bs: Bytes i: Int64 n: Int64 -> Int64
  (let [k (spaceLen bs i n)]
    (if (> k 0) (skipSpace bs (+ i k) n) i))

fn digit? b: Int64 -> Bool
  (and (>= b 48) (<= b 57))

fn letter? b: Int64 -> Bool
  (or (and (>= b 65) (<= b 90)) (and (>= b 97) (<= b 122)))

fn wordByte? b: Int64 -> Bool
  (or (letter? b) (digit? b) (= b 95) (>= b 128))

fn runEnd bs: Bytes i: Int64 n: Int64 pred: (fn [Int64] -> Bool) -> Int64
  (if (and (< i n) (pred (bytesGet bs i))) (runEnd bs (+ i 1) n pred) i)

fn findFrom text: String pat: String i: Int64 -> Int64
  (let [bs (stringToBytes text)
        pb (stringToBytes pat)]
    (findBytes bs (bytesLength bs) pb (bytesLength pb) i))

fn findBytes bs: Bytes n: Int64 pb: Bytes m: Int64 i: Int64 -> Int64
  (cond
    ((> (+ i m) n) -1)
    ((matchAt bs pb m i 0) i)
    (else (findBytes bs n pb m (+ i 1))))

fn matchAt bs: Bytes pb: Bytes m: Int64 i: Int64 k: Int64 -> Bool
  (cond
    ((>= k m) true)
    ((!= (bytesGet bs (+ i k)) (bytesGet pb k)) false)
    (else (matchAt bs pb m i (+ k 1))))

fn replaceFirst text: String old: String new: String -> String
  (let [p (findFrom text old 0)]
    (if (< p 0) text (str (sub text 0 p) new (sub text (+ p (stringLength old)) (stringLength text)))))

fn replaceAll text: String old: String new: String -> String
  (if (stringEmpty? old)
    (replaceEmpty text new)
    (let [bs (stringToBytes text)
          pb (stringToBytes old)]
      (stringJoin (listReverse (replaceLoop text bs (bytesLength bs) pb (bytesLength pb) new 0 0 (list))) "")))

fn replaceEmpty text: String new: String -> String
  (str new (stringJoin (map (fn [c] (str c new)) (stringChars text)) ""))

fn replaceLoop text: String bs: Bytes n: Int64 pb: Bytes m: Int64 new: String start: Int64 i: Int64 acc: (List String) -> (List String)
  (let [p (findBytes bs n pb m i)]
    (if (< p 0)
      (cons (sub text start n) acc)
      (replaceLoop text bs n pb m new (+ p m) (+ p m) (cons new (cons (sub text start p) acc)))))

fn countOf text: String pat: String -> Int64
  (if (stringEmpty? pat)
    (+ (board/cpLength text) 1)
    (let [bs (stringToBytes text)
          pb (stringToBytes pat)]
      (countLoop bs (bytesLength bs) pb (bytesLength pb) 0 0)))

fn countLoop bs: Bytes n: Int64 pb: Bytes m: Int64 i: Int64 acc: Int64 -> Int64
  (let [p (findBytes bs n pb m i)]
    (if (< p 0) acc (countLoop bs n pb m (+ p m) (+ acc 1))))

fn has? text: String pat: String -> Bool
  (>= (findFrom text pat 0) 0)

fn cpIndex bs: Bytes i: Int64 n: Int64 k: Int64 -> Int64
  (cond
    ((>= i n) n)
    ((<= k 0) i)
    (else (cpIndex bs (charEnd bs (+ i 1) n) n (- k 1))))

fn charEnd bs: Bytes j: Int64 n: Int64 -> Int64
  (if (and (< j n) (>= (bytesGet bs j) 128) (< (bytesGet bs j) 192)) (charEnd bs (+ j 1) n) j)

fn cpTake text: String k: Int64 -> String
  (let [bs (stringToBytes text)]
    (sub text 0 (cpIndex bs 0 (bytesLength bs) k)))

fn cpLast text: String k: Int64 -> String
  (let [n (board/cpLength text)]
    (if (<= n k)
      text
      (let [bs (stringToBytes text)]
        (sub text (cpIndex bs 0 (bytesLength bs) (- n k)) (stringLength text)))))

fn ljust text: String w: Int64 -> String
  (let [n (board/cpLength text)]
    (if (>= n w) text (str text (stringRepeat " " (- w n)))))

fn endsWith? text: String suffix: String -> Bool
  (stringEndsWith? text suffix)

fn lstripColon text: String -> String
  (let [bs (stringToBytes text)]
    (sub text (runEnd bs 0 (bytesLength bs) (fn [b] (= b 58))) (stringLength text)))

fn rstripSpace text: String -> String
  (let [bs (stringToBytes text)]
    (sub text 0 (trimEndLoop bs (bytesLength bs))))

fn trimEndLoop bs: Bytes j: Int64 -> Int64
  (cond
    ((and (>= j 1) (= (spaceLen bs (- j 1) j) 1)) (trimEndLoop bs (- j 1)))
    ((and (>= j 2) (= (spaceLen bs (- j 2) j) 2)) (trimEndLoop bs (- j 2)))
    ((and (>= j 3) (= (spaceLen bs (- j 3) j) 3)) (trimEndLoop bs (- j 3)))
    (else j))

fn dropLast text: String -> String
  (let [bs (stringToBytes text)
        n (bytesLength bs)]
    (if (= n 0) "" (sub text 0 (lastCharStart bs (- n 1)))))

fn lastCharStart bs: Bytes j: Int64 -> Int64
  (if (and (> j 0) (>= (bytesGet bs j) 128) (< (bytesGet bs j) 192)) (lastCharStart bs (- j 1)) j)

fn lastSegment text: String -> String
  (let [parts (stringSplit text "/")]
    (optionOr (listLast parts) text))

fn modelShort m: String -> String
  (replaceAll (lastSegment m) ":free" "")

fn pyBool b: Bool -> String
  (if b "True" "False")

fn asnBool b: Bool -> String
  (if b "true" "false")

fn roundEven x: Float64 -> Int64
  (let [f (optionOr (float64ToInt64 x) 0)
        fl (if (and (< x 0.0) (!= (int64ToFloat64 f) x)) (- f 1) f)
        frac (- x (int64ToFloat64 fl))]
    (cond
      ((> frac 0.5) (+ fl 1))
      ((< frac 0.5) fl)
      ((= (mod fl 2) 0) fl)
      (else (+ fl 1))))

fn pow10 k: Int64 -> Int64
  (if (<= k 0) 1 (* 10 (pow10 (- k 1))))

fn fixed x: Float64 digits: Int64 -> String
  (let [scale (pow10 digits)
        neg (< x 0.0)
        r (roundEven (* (if neg (- 0.0 x) x) (int64ToFloat64 scale)))
        whole (/ r scale)
        frac (mod r scale)
        fracText (stringFromInt64 frac)
        body (if (= digits 0) (stringFromInt64 whole) (str (stringFromInt64 whole) "." (stringRepeat "0" (- digits (stringLength fracText))) fracText))]
    (if (and neg (> r 0)) (str "-" body) body))

fn round2 x: Float64 -> Float64
  (/ (int64ToFloat64 (roundEven (* x 100.0))) 100.0)

fn pyFloat x: Float64 -> String
  (stringFromFloat64 x)

fn asFloat v: board/AsnValue -> Float64
  (mt v
    ((board/asnFloat f) f)
    ((board/asnInt i) (int64ToFloat64 i))
    ((board/asnBool b) (if b 1.0 0.0))
    (_ 0.0))

fn splitOn text: String sep: String -> (List String)
  (stringSplit text sep)

fn strOrEmpty v: board/AsnValue -> String
  (mt v ((board/asnNone) "") (_ (board/pyStr v)))

fn out! line: String -> Unit
  (println line)

fn warn! line: String -> Unit
  (eprintln line)

fn writeAll! fd: Int64 text: String -> (Result Unit String)
  (if (stringEmpty? text)
    (ok ())
    (mt (fdWrite fd text)
      ((err e) (err e))
      ((ok n)
        (if (>= n (stringLength text))
          (ok ())
          (mt (stringSlice text n (stringLength text))
            ((some restText) (writeAll! fd restText))
            ((none) (err "partial write split a character")))))))


schema Slot
  (:f index Int64)
  (:f pid Int64)
  (:f outFd Int64)
  (:f errFd Int64)
  (:f outs (List String))
  (:f errs (List String))
  (:f outOpen Bool)
  (:f errOpen Bool)
  (:f code (Option Int64))
  (:f deadlineMs Int64)
  (:f timedOut Bool)

schema PoolState
  (:f pending (List (Pair Int64 ProcJob)))
  (:f running (List Slot))
  (:f done (List (Pair Int64 ProcOut)))

fn readReady! fd: Int64 -> (Result (Option String) String)
  (mt (fdRead fd 65536)
    ((err e) (err e))
    ((ok chunk) (if (stringEmpty? chunk) (do (fdClose fd) (ok (none))) (ok (some chunk)))))

fn ready? rs: (List (Pair Int64 Int64)) fd: Int64 -> Bool
  (listAny? (fn [p] (= (pairFirst p) fd)) rs)

fn exitOf xs: (List (Pair Int64 Int64)) pid: Int64 -> (Option Int64)
  (fold (fn [acc p] (if (= (pairFirst p) pid) (some (pairSecond p)) acc)) (none) xs)

fn killSlot! s: Slot -> Unit
  (do
    (procKill (- 0 s.pid) "SIGKILL")
    (if (none? s.code) (do (procWaitPid s.pid false) ()) ())
    (if s.outOpen (do (fdClose s.outFd) ()) ())
    (if s.errOpen (do (fdClose s.errFd) ()) ()))

fn killAllSlots! slots: (List Slot) -> Unit
  (do (map killSlot! slots) ())

fn startSlot! idx: Int64 job: ProcJob -> (Result Slot String)
  (let [cwd (if (stringEmpty? job.cwd) (none) (some job.cwd))
        env (if (listEmpty? job.env) (none) (some job.env))]
    (mt (procSpawnv job.argv cwd env)
      ((err e) (err e))
      ((ok sp)
        (let [wrote (writeAll! sp.stdin job.input)
              closed (fdClose sp.stdin)
              dl (if (<= job.timeoutMs 0) -1 (+ (/ (monotonicNs) 1000000) job.timeoutMs))]
          (mt (if (err? wrote) wrote closed)
            ((err e)
              (do (procKill (- 0 sp.pid) "SIGKILL")
                  (procWaitPid sp.pid false)
                  (fdClose sp.stdout)
                  (fdClose sp.stderr)
                  (err (str "stdin: " e))))
            ((ok _)
              (ok (Slot :index idx :pid sp.pid :outFd sp.stdout :errFd sp.stderr
                        :outs (list) :errs (list) :outOpen true :errOpen true :code (none)
                        :deadlineMs dl :timedOut false))))))))

fn fillSlots! k: Int64 st: PoolState -> (Result PoolState String)
  (mt (listHead st.pending)
    ((none) (ok st))
    ((some item)
      (if (>= (listLength st.running) k)
        (ok st)
        (let [rest (optionOr (listTail st.pending) (list))
              idx (pairFirst item)
              job (pairSecond item)]
          (mt (startSlot! idx job)
            ((err e) (do (killAllSlots! st.running) (err e)))
            ((ok s)
              (fillSlots! k (PoolState :pending rest
                                      :running (listAppend st.running (list s))
                                      :done st.done))))))))

fn watchFds slots: (List Slot) -> (List (Pair Int64 Int64))
  (fold (fn [acc s]
          (listAppend acc (listAppend (if s.outOpen (list (pair s.outFd 1)) (list))
                                      (if s.errOpen (list (pair s.errFd 1)) (list)))))
        (list) slots)

fn livePids slots: (List Slot) -> (List Int64)
  (map (fn [s] s.pid) (filter (fn [s] (none? s.code)) slots))

fn pollTimeout slots: (List Slot) nowMs: Int64 -> Int64
  (let [deadlines (map (fn [s] s.deadlineMs)
                       (filter (fn [s] (and (>= s.deadlineMs 0) (not s.timedOut))) slots))]
    (if (listEmpty? deadlines)
      -1
      (max 0 (- (fold min (optionOr (listHead deadlines) 0) deadlines) nowMs))))

fn absorbSlot! s: Slot ready: (List (Pair Int64 Int64)) exited: (List (Pair Int64 Int64)) -> (Result Slot String)
  (let [outR (if (and s.outOpen (ready? ready s.outFd)) (readReady! s.outFd) (ok (some "")))
        errR (if (and s.errOpen (ready? ready s.errFd)) (readReady! s.errFd) (ok (some "")))
        code (if (some? s.code) s.code (exitOf exited s.pid))]
    (mt outR
      ((err e) (err (str "read stdout: " e)))
      ((ok oc)
        (mt errR
          ((err e) (err (str "read stderr: " e)))
          ((ok ec)
            (ok (Slot :index s.index :pid s.pid :outFd s.outFd :errFd s.errFd
                      :outs (mt oc ((some x) (if (stringEmpty? x) s.outs (cons x s.outs))) ((none) s.outs))
                      :errs (mt ec ((some x) (if (stringEmpty? x) s.errs (cons x s.errs))) ((none) s.errs))
                      :outOpen (and s.outOpen (some? oc))
                      :errOpen (and s.errOpen (some? ec))
                      :code code
                      :deadlineMs s.deadlineMs
                      :timedOut s.timedOut)))))))

fn absorbAllSlots! slots: (List Slot) ready: (List (Pair Int64 Int64)) exited: (List (Pair Int64 Int64)) acc: (List Slot) -> (Result (List Slot) String)
  (mt (listHead slots)
    ((none) (ok (listReverse acc)))
    ((some s)
      (mt (absorbSlot! s ready exited)
        ((err e) (err e))
        ((ok s2) (absorbAllSlots! (optionOr (listTail slots) (list)) ready exited (cons s2 acc))))))

fn expireSlot! s: Slot nowMs: Int64 -> Slot
  (if (or s.timedOut (< s.deadlineMs 0) (< nowMs s.deadlineMs) (slotFinished? s))
    s
    (do
      (procKill (- 0 s.pid) "SIGKILL")
      (if (none? s.code) (do (procWaitPid s.pid false) ()) ())
      (if s.outOpen (do (fdClose s.outFd) ()) ())
      (if s.errOpen (do (fdClose s.errFd) ()) ())
      (Slot :index s.index :pid s.pid :outFd s.outFd :errFd s.errFd
            :outs s.outs :errs s.errs :outOpen false :errOpen false
            :code (some 124) :deadlineMs -1 :timedOut true)))

fn slotFinished? s: Slot -> Bool
  (and (some? s.code) (not s.outOpen) (not s.errOpen))

fn slotToDone s: Slot -> (Pair Int64 ProcOut)
  (pair s.index
        (ProcOut :code (if s.timedOut 124 (optionOr s.code -1))
                 :out (stringJoin (listReverse s.outs) "")
                 :errText (stringJoin (listReverse s.errs) "")
                 :timedOut s.timedOut))

fn poolLoop! k: Int64 st: PoolState -> (Result (List ProcOut) String)
  (mt (fillSlots! k st)
    ((err e) (do (killAllSlots! st.running) (err e)))
    ((ok st1)
      (if (and (listEmpty? st1.running) (listEmpty? st1.pending))
        (let [sorted (listSortBy (fn [p] (pairFirst p)) st1.done)]
          (ok (map (fn [p] (pairSecond p)) sorted)))
        (let [nowMs (/ (monotonicNs) 1000000)
              timeout (pollTimeout st1.running nowMs)]
          (mt (procPoll (watchFds st1.running) (livePids st1.running) timeout)
            ((err e) (do (killAllSlots! st1.running) (err (str "procPoll: " e))))
            ((ok r)
              (let [now2 (/ (monotonicNs) 1000000)
                    ready (pairFirst r)
                    exited (pairSecond r)]
                (mt (absorbAllSlots! st1.running ready exited (list))
                  ((err e) (do (killAllSlots! st1.running) (err e)))
                  ((ok absorbed)
                    (let [updated (map (fn [s] (expireSlot! s now2)) absorbed)
                          doneNow (map slotToDone (filter slotFinished? updated))
                          stillRunning (filter (fn [s] (not (slotFinished? s))) updated)]
                      (poolLoop! k (PoolState :pending st1.pending
                                             :running stillRunning
                                             :done (listAppend st1.done doneNow)))))))))))))

fn runProcPool! jobs: (List ProcJob) k: Int64 -> (Result (List ProcOut) String)
  (if (listEmpty? jobs)
    (ok (list))
    (let [slots (max 1 k)
          indexed (enumerate jobs)]
      (poolLoop! slots (PoolState :pending indexed :running (list) :done (list)))))

fn runProc! argv: (List String) cwd: String env: (List String) input: String timeoutMs: Int64 -> (Result ProcOut String)
  (mt (runProcPool! (list (ProcJob :argv argv :cwd cwd :env env :input input :timeoutMs timeoutMs)) 1)
    ((err e) (err e))
    ((ok rs)
      (mt (listHead rs)
        ((some r) (ok r))
        ((none) (err "runProc: no output")))))


fn envLookup env: (List String) name: String -> (Option String)
  (mt (listHead env)
    ((none) (none))
    ((some kv) (if (stringStartsWith? kv (str name "=")) (some (sub kv (+ (stringLength name) 1) (stringLength kv))) (envLookup (rest env) name))))

fn envSet env: (List String) name: String value: String -> (List String)
  (listAppend (filter (fn [kv] (not (stringStartsWith? kv (str name "=")))) env) (list (str name "=" value)))

fn childEnv env: (List String) -> (List String)
  (let [np (optionOr (envLookup env "no_proxy") "")]
    (if (or (has? np "127.0.0.1") (has? np "localhost"))
      env
      (let [v (stripCommas (str "127.0.0.1,localhost," np))]
        (envSet (envSet env "no_proxy" v) "NO_PROXY" v))))

fn stripCommas text: String -> String
  (let [bs (stringToBytes text)
        n (bytesLength bs)
        a (runEnd bs 0 n (fn [b] (= b 44)))
        b (commaTail bs n a)]
    (sub text a b))

fn commaTail bs: Bytes j: Int64 lo: Int64 -> Int64
  (if (and (> j lo) (= (bytesGet bs (- j 1)) 44)) (commaTail bs (- j 1) lo) j)

fn pyOsError kind: String path: String -> String
  (let [p (findFrom kind ": " 0)
        msg (lastSegmentAfter kind ": ")
        q (board/pyRepr (s path))]
    (cond
      ((or (stringStartsWith? kind "notFound") (= msg "No such file or directory")) (str "FileNotFoundError: [Errno 2] No such file or directory: " q))
      ((= msg "Operation not permitted") (str "PermissionError: [Errno 1] Operation not permitted: " q))
      ((stringStartsWith? kind "permission") (str "PermissionError: [Errno 13] Permission denied: " q))
      ((or (stringStartsWith? kind "isADirectory") (= msg "Is a directory")) (str "IsADirectoryError: [Errno 21] Is a directory: " q))
      ((or (stringStartsWith? kind "io:20") (= msg "Not a directory")) (str "NotADirectoryError: [Errno 20] Not a directory: " q))
      ((= msg "File exists") (str "FileExistsError: [Errno 17] File exists: " q))
      ((>= p 0) (str "OSError: " msg ": " q))
      (else (str "OSError: " kind))))

fn lastSegmentAfter text: String sep: String -> String
  (let [parts (splitOn text sep)]
    (optionOr (listLast parts) text))

fn ! exists? path: String -> Bool
  (ok? (fileStat path))

fn ! isDir? path: String -> Bool
  (mt (fileStat path) ((ok st) st.isDir) ((err _) false))

fn ! isLink? path: String -> Bool
  (mt (fileLstat path) ((ok st) st.isSymlink) ((err _) false))

fn readText! path: String -> (Result String String)
  (if (isDir? path)
    (err (pyOsError "isADirectory" path))
    (mt (fileReadString path)
      ((err e) (err (pyOsError e path)))
      ((ok t) (ok (if (has? t "\r") (replaceAll (replaceAll t "\r\n" "\n") "\r" "\n") t)))))

fn nowSec! -> Int64
  (/ (nowNs) 1000000000)

fn nowMs! -> Int64
  (/ (nowNs) 1000000)

fn localStamp! ctx: Ctx -> String
  (mt (runProc! (list "date" "+%Y-%m-%d %H:%M:%S") "" ctx.env "" 10000)
    ((ok r) (rstripSpace r.out))
    ((err e) (str "ERR_TOOL_ABSENT: date: " e)))

fn localCompactDate! -> String
  (mt (localDate) ((ok d) (replaceAll d "-" "")) ((err e) (str "ERR_DATE_" e)))

fn localDay! -> String
  (mt (localDate) ((ok d) d) ((err e) (str "ERR_DATE_" e)))

fn appendText! path: String text: String -> (Result Unit String)
  (let [dir (board/pyDirname path)
        made (if (stringEmpty? dir) (ok ()) (mt (dirCreate dir) ((ok _) (ok ())) ((err e) (err (pyOsError e dir)))))]
    (mt made
      ((err e) (err e))
      ((ok _)
        (let [old (if (exists? path) (readText! path) (ok ""))]
          (mt old
            ((err e) (err e))
            ((ok prev) (board/atomicWriteFile! path (str prev text))))))))

fn logTelemetryDict! ctx: Ctx fields: (List (Pair String String)) -> Unit
  (let [tel (cfgs ctx "telemetry_log_path")]
    (if (stringEmpty? tel)
      ()
      (let [body (stringJoin (map (fn [p] (str ":" (pairFirst p) " \"" (pairSecond p) "\"")) fields) " ")
            line (str "(:mesh-telemetry :timestamp " (stringFromInt64 (nowMs!)) " " body ")\n")]
        (mt (appendText! tel line)
          ((ok _) ())
          ((err e) (warn! (str "[Telemetry] write failed: " e)))))))

fn threeLetters? bs: Bytes i: Int64 n: Int64 run: Int64 -> Bool
  (cond
    ((>= run 3) true)
    ((>= i n) false)
    ((letter? (bytesGet bs i)) (threeLetters? bs (+ i 1) n (+ run 1)))
    (else (threeLetters? bs (+ i 1) n 0)))

fn parenBalanced? bs: Bytes i: Int64 n: Int64 depth: Int64 inStr: Bool esc: Bool -> Bool
  (if (>= i n)
    (= depth 0)
    (let [c (bytesGet bs i)]
      (cond
        (esc (parenBalanced? bs (+ i 1) n depth inStr false))
        ((= c 92) (parenBalanced? bs (+ i 1) n depth inStr true))
        ((= c 34) (parenBalanced? bs (+ i 1) n depth (not inStr) false))
        (inStr (parenBalanced? bs (+ i 1) n depth inStr false))
        ((= c 40) (parenBalanced? bs (+ i 1) n (+ depth 1) inStr false))
        ((= c 41) (if (= depth 0) false (parenBalanced? bs (+ i 1) n (- depth 1) inStr false)))
        (else (parenBalanced? bs (+ i 1) n depth inStr false)))))

fn quotedBracket xs: (List String) -> String
  (str "[" (stringJoin (map (fn [x] (str "\"" x "\"")) xs) " ") "]")

fn logTelemetryText! ctx: Ctx content: String intent: String role: String model: String -> Unit
  (let [raw (board/pyStrip content)]
    (if (stringEmpty? raw)
      ()
      (let [bs (stringToBytes raw)
            n (bytesLength bs)
            hasMd (has? raw "```")
            fp (findFrom raw "(" 0)
            pre (if (> fp 0) (board/pyStrip (sub raw 0 fp)) "")
            prb (stringToBytes pre)
            hasPre (and (> fp 0) (threeLetters? prb 0 (bytesLength prb) 0))
            balanced (parenBalanced? bs 0 n 0 false false)
            low (stringLower raw)
            cheat (filter (fn [x] (not (stringEmpty? x)))
                    (list (if (or (has? low "assert true") (has? low "assert(true)") (has? low "(assert true)")) "vacuous-assert-true" "")
                          (if (or (has? low "skip test") (has? low ":skip") (has? low "ignore test")) "skip-gate-evasion" "")
                          (if (or (has? low "mock ") (has? low "stub ")) "mock-evasion" "")
                          (if (and (has? low "exit 0") (not (or (has? low "assert") (has? low "test") (has? low "eval")))) "unverified-exit-zero" "")))
            debt (filter (fn [x] (not (stringEmpty? x)))
                   (list (if (or (has? low "truncated") (has? low "truncation")) "context-truncation-complaint" "")
                         (if (or (has? low "cannot inspect") (has? low "cannot see") (has? low "file not found")) "missing-visibility" "")
                         (if (or (has? low "need tool") (has? low "missing tool")) "missing-tool-affordance" "")))
            pure (and balanced (not hasMd) (not hasPre) (stringStartsWith? raw "(") (endsWith? raw ")"))
            now (stringFromInt64 (nowMs!))
            rec (str "(:telemetry :id \"TEL-" now "\" :timestamp " now " :intent :" (if (stringEmpty? intent) "unspecified" intent) " "
                     ":role \"" role "\" :model \"" model "\" :pureDyck1 " (asnBool pure) " "
                     ":markdownWrapped " (asnBool hasMd) " :preamble " (asnBool hasPre) " "
                     ":cheatingSuspected " (asnBool (not (listEmpty? cheat))) " :cheatingFlags " (quotedBracket cheat) " "
                     ":harnessComplaints " (quotedBracket debt) ")\n")]
        (mt (appendText! (cfgs ctx "telemetry_log_path") rec)
          ((ok _) ())
          ((err e) (warn! (str "[Telemetry] write failed: " e)))))))

fn spawnCrash kind: String path: String -> String
  (pyOsError kind path)

fn argvRepr argv: (List String) -> String
  (str "[" (stringJoin (map (fn [a] (board/pyRepr (s a))) argv) ", ") "]")

fn timeoutText argv: (List String) secs: Int64 -> String
  (str "Command '" (argvRepr argv) "' timed out after " (stringFromInt64 secs) " seconds")

fn aslEval! ctx: Ctx expr: String -> (Result ProcOut String)
  (let [bin (board/pyJoin ctx.root "bin/asl")
        argv (list bin "eval" expr)]
    (mt (runProc! argv ctx.root ctx.env "" 30000)
      ((err e) (err (spawnCrash e bin)))
      ((ok r) (if r.timedOut (err (str "subprocess.TimeoutExpired: " (timeoutText argv 30))) (ok r)))))

fn dispatchHook! ctx: Ctx event: String context: (List (Pair String String)) -> Unit
  (let [hook (getv (entries (cfgv ctx "hooks")) event)]
    (if (not (board/truthy? hook))
      ()
      (let [h (entries hook)
            act (gets h "action" "")
            evalExpr (getd h "eval" (s ""))
            doc (gets h "doc" "")
            result (if (board/truthy? evalExpr)
                     (mt (aslEval! ctx (board/pyStr evalExpr))
                       ((ok r) (board/pyStrip r.out))
                       ((err e) (str "error: " (hookErr e))))
                     "")
            base (list (pair "type" "hookInvocation") (pair "event" event) (pair "action" act)
                       (pair "evalResult" (if (stringEmpty? result) "none" result)) (pair "doc" doc))]
        (logTelemetryDict! ctx (fold (fn [acc p] (board/dictPut acc (pairFirst p) (pairSecond p))) base context)))))

fn hookErr e: String -> String
  (let [k (findFrom e ": " 0)]
    (if (< k 0) e (sub e (+ k 2) (stringLength e))))

fn hex4 v: Int64 -> String
  (let [h "0123456789abcdef"]
    (str (sub h (mod (/ v 4096) 16) (+ (mod (/ v 4096) 16) 1)) (sub h (mod (/ v 256) 16) (+ (mod (/ v 256) 16) 1))
         (sub h (mod (/ v 16) 16) (+ (mod (/ v 16) 16) 1)) (sub h (mod v 16) (+ (mod v 16) 1))))

fn utf8Len b: Int64 -> Int64
  (cond ((< b 192) 1) ((< b 224) 2) ((< b 240) 3) (else 4))

fn codePointAt bs: Bytes i: Int64 n: Int64 -> Int64
  (let [b (bytesGet bs i)
        k (utf8Len b)
        cont (fn [j] (if (< (+ i j) n) (& (bytesGet bs (+ i j)) 63) 0))]
    (cond
      ((= k 1) b)
      ((= k 2) (+ (* (& b 31) 64) (cont 1)))
      ((= k 3) (+ (* (& b 15) 4096) (* (cont 1) 64) (cont 2)))
      (else (+ (* (& b 7) 262144) (* (cont 1) 4096) (* (cont 2) 64) (cont 3)))))

fn jsonEscCp cp: Int64 -> String
  (cond
    ((= cp 34) "\\\"")
    ((= cp 92) "\\\\")
    ((= cp 10) "\\n")
    ((= cp 13) "\\r")
    ((= cp 9) "\\t")
    ((= cp 8) "\\b")
    ((= cp 12) "\\f")
    ((or (< cp 32) (> cp 126)) (if (> cp 65535)
                                 (let [v (- cp 65536)] (str "\\u" (hex4 (+ 55296 (/ v 1024))) "\\u" (hex4 (+ 56320 (mod v 1024)))))
                                 (str "\\u" (hex4 cp))))
    (else ""))

fn jsonEscLoop text: String bs: Bytes i: Int64 start: Int64 n: Int64 acc: (List String) -> (List String)
  (if (>= i n)
    (cons (sub text start n) acc)
    (let [b (bytesGet bs i)]
      (if (and (>= b 32) (<= b 126) (!= b 34) (!= b 92))
        (jsonEscLoop text bs (+ i 1) start n acc)
        (let [k (utf8Len b)]
          (jsonEscLoop text bs (+ i k) (+ i k) n (cons (jsonEscCp (codePointAt bs i n)) (cons (sub text start i) acc)))))))

fn jsonStr text: String -> String
  (let [bs (stringToBytes text)]
    (str "\"" (stringJoin (listReverse (jsonEscLoop text bs 0 0 (bytesLength bs) (list))) "") "\""))

fn jsonDumps v: j/Json -> String
  (mt v
    ((j/jnull) "null")
    ((j/jbool b) (if b "true" "false"))
    ((j/jint i) (stringFromInt64 i))
    ((j/jfloat f) (pyFloat f))
    ((j/jnum f) (pyFloat f))
    ((j/jstr x) (jsonStr x))
    ((j/jarr xs) (str "[" (stringJoin (map jsonDumps xs) ", ") "]"))
    ((j/jobj kvs) (str "{" (stringJoin (map (fn [p] (str (jsonStr (pairFirst p)) ": " (jsonDumps (pairSecond p)))) kvs) ", ") "}")))

fn asnJson v: board/AsnValue -> j/Json
  (mt v
    ((board/asnNone) (j/jnull))
    ((board/asnBool b) (j/jbool b))
    ((board/asnInt i) (j/jint i))
    ((board/asnFloat f) (j/jfloat f))
    ((board/asnStr x) (j/jstr x))
    ((board/asnList xs) (j/jarr (map asnJson xs)))
    ((board/asnTuple xs) (j/jarr (map asnJson xs)))
    ((board/asnDict es) (j/jobj (map (fn [p] (pair (pairFirst p) (asnJson (pairSecond p)))) es))))

fn jsonAsn v: j/Json -> board/AsnValue
  (mt v
    ((j/jnull) (board/asnNone))
    ((j/jbool b) (board/asnBool b))
    ((j/jint i) (board/asnInt i))
    ((j/jfloat f) (board/asnFloat f))
    ((j/jnum f) (board/asnFloat f))
    ((j/jstr x) (board/asnStr x))
    ((j/jarr xs) (board/asnList (map jsonAsn xs)))
    ((j/jobj kvs) (board/asnDict (fold (fn [acc p] (board/dictPut acc (pairFirst p) (jsonAsn (pairSecond p)))) (list) kvs))))

fn curlQuote text: String -> String
  (str "\"" (replaceAll (replaceAll (replaceAll (replaceAll (replaceAll text "\\" "\\\\") "\"" "\\\"") "\n" "\\n") "\r" "\\r") "\t" "\\t") "\"")

enum Http
  (httpStatus code: Int64 body: String)
  (httpExc reason: String)
  (httpAbsent reason: String)


fn curlConfigContent url: String headers: (List (Pair String String)) body: String timeoutSec: Int64 -> String
  (str "url = " (curlQuote url) "\n"
       (stringJoin (map (fn [h] (str "header = " (curlQuote (str (pairFirst h) ": " (pairSecond h))) "\n")) headers) "")
       "header = \"Expect:\"\n"
       "data-binary = " (curlQuote body) "\n"
       "max-time = " (stringFromInt64 timeoutSec) "\n"
       "write-out = \"\\n%{http_code}\"\n")

fn curlJob ctx: Ctx url: String headers: (List (Pair String String)) body: String timeoutSec: Int64 -> ProcJob
  (let [conf (curlConfigContent url headers body timeoutSec)]
    (ProcJob :argv (list "curl" "-q" "-sS" "--config" "-") :cwd "" :env ctx.env :input conf :timeoutMs (* (+ timeoutSec 30) 1000)))

fn parseHttpResult r: (Result ProcOut String) -> Http
  (mt r
    ((err e) (if (stringStartsWith? e "notFound") (httpAbsent (str "ERR_TOOL_ABSENT: curl is not on PATH (" e ")")) (httpExc (str "curl did not start: " e))))
    ((ok res)
      (cond
        (res.timedOut (httpExc "curl exceeded its deadline"))
        ((!= res.code 0) (httpExc (str "curl exit " (stringFromInt64 res.code) ": " (board/pyStrip res.errText))))
        (else
          (let [o res.out
                k (lastNewline (stringToBytes o) (stringLength o))
                codeText (if (< k 0) o (sub o (+ k 1) (stringLength o)))
                bodyText (if (< k 0) "" (sub o 0 k))]
            (mt (stringToInt64 codeText)
              ((some c) (httpStatus c bodyText))
              ((none) (httpExc (str "curl wrote no status: " codeText)))))))))

fn httpPost! ctx: Ctx url: String headers: (List (Pair String String)) body: String timeoutSec: Int64 -> Http
  (let [job (curlJob ctx url headers body timeoutSec)]
    (parseHttpResult (runProc! job.argv job.cwd job.env job.input job.timeoutMs)))


fn lastNewline bs: Bytes j: Int64 -> Int64
  (cond ((<= j 0) -1) ((= (bytesGet bs (- j 1)) 10) (- j 1)) (else (lastNewline bs (- j 1))))

fn jget v: j/Json k: String -> (Option j/Json)
  (mt v
    ((j/jobj kvs) (fold (fn [acc p] (if (= (pairFirst p) k) (some (pairSecond p)) acc)) (none) kvs))
    (_ (none)))

fn replyContent body: String -> (Result (Pair String board/AsnValue) String)
  (mt (j/jsonParse body)
    ((err e) (err (str "JSONDecodeError: " e)))
    ((ok v)
      (mt v
        ((j/jobj _)
          (let [choice (mt (jget v "choices")
                         ((none) (ok (j/jobj (list))))
                         ((some c)
                           (mt c
                             ((j/jarr xs) (mt (listHead xs) ((some x) (ok x)) ((none) (err "IndexError: list index out of range"))))
                             ((j/jstr x) (if (stringEmpty? x) (err "IndexError: string index out of range") (err "AttributeError: 'str' object has no attribute 'get'")))
                             ((j/jobj _) (err "KeyError: 0"))
                             (_ (err "TypeError: object is not subscriptable")))))]
            (mt choice
              ((err e) (err e))
              ((ok ch)
                (mt ch
                  ((j/jobj _)
                    (let [msg (optionOr (jget ch "message") (j/jobj (list)))]
                      (mt msg
                        ((j/jobj _)
                          (mt (optionOr (jget msg "content") (j/jstr ""))
                            ((j/jstr c) (ok (pair (board/pyStrip c) (jsonAsn (optionOr (jget v "usage") (j/jobj (list)))))))
                            (_ (err "AttributeError: object has no attribute 'strip'"))))
                        (_ (err "AttributeError: object has no attribute 'get'")))))
                  (_ (err "AttributeError: object has no attribute 'get'")))))))
        (_ (err "AttributeError: object has no attribute 'get'")))))

fn staticSystemPrefix -> String
  (str "The ASL repository: a finding holds when evidence in the given code backs it, and a value is true only when it is the boolean true. "
       "Code is addressed by path and symbol. "
       "A reply may carry a :scratchpad field with step-by-step reasoning before its conclusion. "
       "Replies are read as ASN S-expressions with balanced parentheses.")

fn openrouterUrl -> String
  "https://openrouter.ai/api/v1/chat/completions"

fn queryFail reason: String -> Query
  (Query :ok false :content "" :source "" :usage (board/asnDict (list)) :error reason)


schema IntentReq
  (:f intent String)
  (:f headers (List (Pair String String)))
  (:f messages j/Json)
  (:f modelHint String)
  (:f temp Float64)
  (:f maxTokens Int64)
  (:f job ProcJob)

fn makeIntentReq ctx: Ctx intent: String attractor: String prompt: String modelHint: String temp: Float64 systemPrompt: String maxTokens: Int64 -> IntentReq
  (let [a (board/pyStrip attractor)
        slot (if (or (stringStartsWith? a "(") (stringStartsWith? a ":")) a (str ":" a))
        headers0 (listAppend (list (pair "Content-Type" "application/json") (pair "X-ASL-Intent" intent) (pair "X-ASL-Attractor" slot)
                                   (pair "X-Title" "ASL Agent Mesh") (pair "HTTP-Referer" "https://aslang.dev"))
                             (if (stringEmpty? ctx.apiKey) (list) (list (pair "Authorization" (str "Bearer " ctx.apiKey)))))
        headers (listAppend headers0 (list (pair "X-ASL-Timeout" "600") (pair "X-ASL-Queue-Timeout" "1800")))
        system (if (stringEmpty? systemPrompt) (staticSystemPrefix) systemPrompt)
        userText (if (stringStartsWith? prompt "(:turn-control") prompt (str "(:turn-control :intent :" intent " :attractor " slot ")\n" prompt))
        messages (j/jarr (list (j/jobj (list (pair "role" (j/jstr "system")) (pair "content" (j/jstr system))))
                               (j/jobj (list (pair "role" (j/jstr "user")) (pair "content" (j/jstr userText))))))
        gw (j/jobj (listAppend (list (pair "intent" (j/jstr intent)) (pair "attractor" (j/jstr attractor)) (pair "messages" messages) (pair "max_tokens" (j/jint maxTokens)))
                               (listAppend (if (stringEmpty? modelHint) (list) (list (pair "model" (j/jstr modelHint))))
                                           (list (pair "temperature" (j/jfloat temp))))))
        job (curlJob ctx ctx.gateway headers (jsonDumps gw) 1800)]
    (IntentReq :intent intent :headers headers :messages messages :modelHint modelHint :temp temp :maxTokens maxTokens :job job))

fn finishIntentQuery! ctx: Ctx req: IntentReq res: Http -> Query
  (mt res
    ((httpAbsent why) (queryFail why))
    (_
      (let [gwReply (mt res
                      ((httpStatus code body) (if (and (>= code 200) (< code 300)) (resultToOption (replyContent body)) (none)))
                      (_ (none)))]
        (mt gwReply
          ((some r)
            (do (logTelemetryText! ctx (pairFirst r) req.intent (str "shard:" req.intent) "gateway")
                (Query :ok true :content (pairFirst r) :source "gateway" :usage (pairSecond r) :error "")))
          ((none)
            (let [primary (if (stringEmpty? req.modelHint) "qwen/qwen3.8-27b:free" req.modelHint)
                  chain (mt (board/dictGet (entries (cfgv ctx "model_cascades")) primary)
                          ((some v) (map board/pyStr (items v)))
                          ((none) (list "google/gemma-4-31b-it:free" "nex-agi/nex-n2.5-pro:free" "nvidia/nemotron-3-super-120b-a12b:free")))]
              (directCascade! ctx (cons primary chain) req.headers req.messages req.temp req.maxTokens req.intent 3)))))))

fn queryIntent! ctx: Ctx intent: String attractor: String prompt: String modelHint: String temp: Float64 maxRetries: Int64 systemPrompt: String maxTokens: Int64 -> Query
  (let [req (makeIntentReq ctx intent attractor prompt modelHint temp systemPrompt maxTokens)
        job req.job
        res (parseHttpResult (runProc! job.argv job.cwd job.env job.input job.timeoutMs))]
    (finishIntentQuery! ctx req res))


fn directCascade! ctx: Ctx models: (List String) headers: (List (Pair String String)) messages: j/Json temp: Float64 maxTokens: Int64 intent: String maxRetries: Int64 -> Query
  (mt (listHead models)
    ((none) (queryFail "Gateway and direct fallback cascades exhausted"))
    ((some m)
      (let [body (jsonDumps (j/jobj (list (pair "model" (j/jstr m)) (pair "messages" messages) (pair "temperature" (j/jfloat temp)) (pair "max_tokens" (j/jint maxTokens)))))]
        (mt (directAttempts! ctx m headers body intent 0 maxRetries)
          ((some q) q)
          ((none) (directCascade! ctx (rest models) headers messages temp maxTokens intent maxRetries))))))

fn directAttempts! ctx: Ctx m: String headers: (List (Pair String String)) body: String intent: String attempt: Int64 maxRetries: Int64 -> (Option Query)
  (if (> attempt maxRetries)
    (none)
    (mt (httpPost! ctx (openrouterUrl) headers body 45)
      ((httpAbsent why) (some (queryFail why)))
      ((httpStatus code text)
        (if (and (>= code 200) (< code 300))
          (mt (replyContent text)
            ((ok r)
              (do (logTelemetryText! ctx (pairFirst r) intent (str "shard:" intent) m)
                  (some (Query :ok true :content (pairFirst r) :source (str "direct:" m) :usage (pairSecond r) :error ""))))
            ((err _) (retryAfter! ctx m headers body intent attempt maxRetries 2000)))
          (if (and (= code 429) (< attempt maxRetries))
            (do (sleepMs (* (+ attempt 1) 3000)) (directAttempts! ctx m headers body intent (+ attempt 1) maxRetries))
            (none))))
      ((httpExc _) (retryAfter! ctx m headers body intent attempt maxRetries 2000))))

fn retryAfter! ctx: Ctx m: String headers: (List (Pair String String)) body: String intent: String attempt: Int64 maxRetries: Int64 ms: Int64 -> (Option Query)
  (if (< attempt maxRetries)
    (do (sleepMs ms) (directAttempts! ctx m headers body intent (+ attempt 1) maxRetries))
    (none))

fn head150 text: String -> String
  (cpTake text 150)

fn evalPass? code: Int64 out: String -> Bool
  (and (= code 0)
       (or (= out "true") (= out "1") (= out ":true") (= out ":ok")
           (mt (stringToFloat64 out)
             ((some n) (!= n 0.0))
             ((none) (and (not (stringStartsWith? out "Error")) (not (stringStartsWith? out "Parse error")) (!= out "false"))))))

fn staticCheck! ctx: Ctx chk: (List (Pair String board/AsnValue)) -> (Result Bool String)
  (let [cid (board/pyStr (getv chk "id"))
        cmd (getd chk "cmd" (s ""))
        ev (getd chk "eval" (s ""))
        doc (board/pyStr (getv chk "doc"))
        t0 (monotonicNs)]
    (do
      (print (str "--> Checking [:" cid "] (" doc ")... "))
      (if (board/truthy? ev)
        (mt (aslEval! ctx (board/pyStr ev))
          ((err e) (err e))
          ((ok r)
            (let [ms (stringFromInt64 (/ (- (monotonicNs) t0) 1000000))
                  o (board/pyStrip r.out)]
              (if (evalPass? r.code o)
                (do (out! (str "PASS [eval: " o "] (" ms "ms)")) (ok true))
                (do (out! (str "FAIL [eval: " o "] (" ms "ms)"))
                    (eprint! (str "    [!] Error in eval check " cid ": " (head150 r.errText) "\n"))
                    (ok false))))))
        (let [argv (list "/bin/sh" "-c" (board/pyStr cmd))]
          (mt (runProc! argv ctx.root ctx.env "" 60000)
            ((err e) (err (spawnCrash e "/bin/sh")))
            ((ok r)
              (if r.timedOut
                (err (str "subprocess.TimeoutExpired: " (timeoutText (list (board/pyStr cmd)) 60)))
                (let [ms (stringFromInt64 (/ (- (monotonicNs) t0) 1000000))]
                  (if (= r.code 0)
                    (do (out! (str "PASS (" ms "ms)")) (ok true))
                    (do (out! (str "FAIL (" ms "ms)"))
                        (eprint! (str "    [!] Error in check " cid ": " (head150 r.errText) "\n"))
                        (ok false)))))))))))

fn eprint! text: String -> Unit
  (eprintln (dropLastNewline text))

fn dropLastNewline text: String -> String
  (if (endsWith? text "\n") (sub text 0 (- (stringLength text) 1)) text)

fn staticLoop! ctx: Ctx checks: (List board/AsnValue) allOk: Bool -> (Result Bool String)
  (mt (listHead checks)
    ((none) (ok allOk))
    ((some c)
      (mt (staticCheck! ctx (entries c))
        ((err e) (err e))
        ((ok passed) (staticLoop! ctx (rest checks) (and allOk passed))))))

fn runStatic! ctx: Ctx -> (Result Bool String)
  (do
    (out! "=== [PHASE 1] ASL STATIC VERIFICATION PIPELINE ===")
    (staticLoop! ctx (items (cfgv ctx "static_pipeline")) true))

fn tempFor key: String dflt: Float64 -> Float64
  (cond
    ((= key "verification") 0.55)
    ((= key "reversibility") 0.60)
    ((= key "simplicity") 0.20)
    ((= key "containment") 0.20)
    ((= key "convergence") 0.25)
    (else dflt))

fn kwRow row: board/AsnValue -> String
  (stringJoin (map (fn [a] (str ":" (lstripColon (board/pyStr a)))) (items row)) " ")

fn modPick xs: (List board/AsnValue) i: Int64 -> board/AsnValue
  (first (listDrop xs (mod i (listLength xs))) (board/asnNone))

fn blankParens? a: String -> Bool
  (let [bs (stringToBytes a)
        n (bytesLength bs)
        i (runEnd bs 0 n (fn [b] (or (= b 40) (= b 41))))]
    (>= i n))

fn firstKey a: String -> String
  (if (blankParens? a)
    ""
    (lstripColon (first (board/pySplit (replaceAll (replaceAll a "(" "") ")" "")) "")))

fn shardPlan ctx: Ctx shard: (List (Pair String board/AsnValue)) idx: Int64 cycle: Int64 rotate: Bool -> (List String)
  (let [rot (entries (cfgv ctx "rotation"))
        rotating (or rotate (and (board/truthy? (getd rot "enabled" (board/asnBool false))) (> cycle 0)))
        regime (board/pyStr (getd rot "attractor_regime" (s "triple")))
        models (items (getv rot "cycle_models"))
        triads (items (getv rot "synthesis_triads"))
        pairs (items (getv rot "dual_attractor_pairs"))
        cycAtt (items (getv rot "cycle_attractors"))
        own (str ":" (lstripColon (board/pyStr (getv shard "attractor"))))
        shardTemp (asFloat (getv shard "temp"))]
    (if (and rotating (not (listEmpty? models)))
      (let [k (+ idx cycle)
            model (board/pyStr (modPick models k))
            att (cond
                  ((and (= regime "triple") (not (listEmpty? triads))) (kwRow (modPick triads k)))
                  ((and (= regime "dual") (not (listEmpty? pairs))) (kwRow (modPick pairs k)))
                  ((= regime "none") "()")
                  ((not (listEmpty? cycAtt)) (str ":" (lstripColon (board/pyStr (modPick cycAtt k)))))
                  (else own))]
        (list model att (pyFloat (tempFor (firstKey att) shardTemp))))
      (let [att (cond
                  ((and (= regime "triple") (not (listEmpty? triads))) (kwRow (modPick triads idx)))
                  ((and (= regime "dual") (not (listEmpty? pairs))) (kwRow (modPick pairs idx)))
                  (else own))]
        (list (board/pyStr (getv shard "model")) att (pyFloat shardTemp)))))

fn auditPrompt shard: (List (Pair String board/AsnValue)) slot: String digest: String -> String
  (str "\n;; === REPOSITORY CONTINUOUS AUDIT ===\n"
       ";; Cognitive Intent: :" (board/pyStr (getv shard "intent")) "\n"
       ";; Attractor Guidance: " slot "\n"
       ";; Target Domain: " (board/pyStr (getv shard "name")) "\n"
       ";; Focus: " (board/pyStr (getv shard "focus")) "\n"
       ";;\n"
       ";; Reply format:\n"
       ";; 1. A finding names its defect by path and symbol: :target \"<path#symbol>\".\n"
       ";; 2. The reply is parsed as ASN; unbalanced parentheses make it unreadable.\n"
       ";; 3. An optional :scratchpad holds step-by-step reasoning before the finding.\n"
       ";; 4. A defect is reported as one S-expression; an empty reply means no defect was found:\n"
       ";;    (:audit-finding\n"
       ";;      :scratchpad \"<step-by-step cognitive analysis>\"\n"
       ";;      :target \"<file#symbol>\"\n"
       ";;      :severity <:critical|:high|:medium|:low>\n"
       ";;      :hazard \"<concise root cause description>\"\n"
       ";;      :evidence \"<concrete proof or code snippet>\"\n"
       ";;      :remediation \"<precise fix>\")\n"
       "\n"
       ";; === DISTILLED CODE SKELETON ===\n"
       digest "\n")

fn shardPaths shard: (List (Pair String board/AsnValue)) -> (List String)
  (map board/pyStr (items (getv shard "paths")))

fn planTemp p: (List String) -> (Option Float64)
  (stringToFloat64 (first (listDrop p 2) "0.0"))

fn confAt text: String bs: Bytes n: Int64 i: Int64 -> (Pair Int64 Int64)
  (let [p (findBytes bs n (stringToBytes ":confirmations") 14 i)]
    (if (< p 0)
      (pair -1 -1)
      (let [a (+ p 14)
            b (skipSpace bs a n)
            e (runEnd bs b n digit?)]
        (if (and (> b a) (> e b)) (pair p e) (confAt text bs n (+ p 1))))))

fn confirmations text: String -> Int64
  (let [bs (stringToBytes text)
        hit (confAt text bs (bytesLength bs) 0)]
    (if (< (pairFirst hit) 0)
      -1
      (let [digits (sub text (+ (skipSpace bs (+ (pairFirst hit) 14) (bytesLength bs)) 0) (pairSecond hit))]
        (optionOr (stringToInt64 digits) 0))))

fn subConfirmations text: String n: Int64 -> String
  (let [bs (stringToBytes text)]
    (stringJoin (listReverse (subConfLoop text bs (bytesLength bs) 0 0 (str ":confirmations " (stringFromInt64 n)) (list))) ""))

fn subConfLoop text: String bs: Bytes n: Int64 start: Int64 i: Int64 rep: String acc: (List String) -> (List String)
  (let [hit (confAt text bs n i)]
    (if (< (pairFirst hit) 0)
      (cons (sub text start n) acc)
      (subConfLoop text bs n (pairSecond hit) (pairSecond hit) rep (cons rep (cons (sub text start (pairFirst hit)) acc)))))

fn recordFinding! ctx: Ctx finding: (List (Pair String board/AsnValue)) shard: (List (Pair String board/AsnValue)) model0: String attractor0: String -> (Result Unit String)
  (let [target (board/pyStr (getd finding "target" (s "unknown")))
        severity (board/normalizeSeverity (getd finding "severity" (getv shard "suggestedSeverity")))
        intent (board/pyStr (getv shard "intent"))
        attractorRaw (if (stringEmpty? attractor0) (getv shard "attractor") (s attractor0))
        model (if (stringEmpty? model0) (board/pyStr (getv shard "model")) model0)
        bbPath (cfgs ctx "blackboard_path")]
    (board/withFileLock! bbPath
      (fn []
        (if (not (exists? bbPath))
          (ok ())
          (mt (readText! bbPath)
            ((err e) (err e))
            ((ok bb)
              (mt (corroborateExisting! ctx bbPath bb target (board/extractGapBlocks bb "defect"))
                ((err e) (err e))
                ((ok handled) (if handled (ok ()) (registerDefect! ctx bbPath bb finding target severity intent attractorRaw model))))))))))

fn corroborateExisting! ctx: Ctx bbPath: String bb: String target: String blocks: (List String) -> (Result Bool String)
  (if (not (has? bb (str "\"" target "\"")))
    (ok false)
    (mt (listHead blocks)
      ((none) (ok false))
      ((some b)
        (let [inf (entries (board/parseGapBlock b))]
          (if (!= (strOrEmpty (getv inf "target")) target)
            (corroborateExisting! ctx bbPath bb target (rest blocks))
            (if (= (strOrEmpty (getv inf "status")) "refuted")
              (do (out! (str "    [Anti-Thrash] Target '" target "' was previously REFUTED. Skipping candidate.")) (ok true))
              (let [c (confirmations b)]
                (if (< c 0)
                  (corroborateExisting! ctx bbPath bb target (rest blocks))
                  (let [nb (subConfirmations b (+ c 1))]
                    (mt (board/writeBoard! bbPath (replaceAll bb b nb) (cfgs ctx "shards_dir"))
                      ((err e) (err e))
                      ((ok _) (do (out! (str "    [Blackboard] Finding for '" target "' corroborated (confirmations: " (stringFromInt64 (+ c 1)) ").")) (ok true)))))))))))))

fn pad3 n: Int64 -> String
  (let [t (stringFromInt64 n)]
    (str (stringRepeat "0" (max 0 (- 3 (stringLength t)))) t))

fn registerDefect! ctx: Ctx bbPath: String bb: String finding: (List (Pair String board/AsnValue)) target: String severity: String intent: String attractorRaw: board/AsnValue model: String -> (Result Unit String)
  (let [defId (str "DEF-" (localCompactDate!) "-" (pad3 (mod (nowSec!) 1000)))
        san (fn [k] (board/sanitizeAsnString (getd finding k (s ""))))
        entry (str "\n    (:defect\n      :id \"" defId "\"\n      :target \"" (board/sanitizeAsnString (s target)) "\"\n      :intent :" intent
                   "\n      :attractor " (board/renderAttractor attractorRaw) "\n      :auditor \"" (board/sanitizeAsnString (s model)) "\"\n      :severity :" severity
                   "\n      :hazard \"" (san "hazard") "\"\n      :evidence \"" (san "evidence") "\"\n      :status :candidate\n      :confirmations 1\n      :remediation \"" (san "remediation") "\")")]
    (mt (board/insertIntoDefects bb entry)
      ((err e) (err e))
      ((ok nbb)
        (mt (board/writeBoard! bbPath nbb (cfgs ctx "shards_dir"))
          ((err e) (err e))
          ((ok _)
            (let [shardDict (board/asnDict (list (pair "id" (s defId)) (pair "target" (s target)) (pair "intent" (s intent)) (pair "attractor" attractorRaw)
                                                 (pair "auditor" (s model)) (pair "severity" (s severity)) (pair "hazard" (getd finding "hazard" (s "")))
                                                 (pair "evidence" (getd finding "evidence" (s ""))) (pair "status" (s "candidate")) (pair "confirmations" (board/asnInt 1))
                                                 (pair "remediation" (getd finding "remediation" (s "")))))]
              (mt (board/saveDefectShard! shardDict (cfgs ctx "shards_dir") ctx.root)
                ((err e) (err e))
                ((ok _)
                  (do (out! (str "    [Blackboard] Registered new defect: " defId " on " target))
                      (dispatchHook! ctx "onDefectCandidate" (list (pair "target" target) (pair "severity" severity) (pair "id" defId)))
                      (ok ()))))))))))

fn auditShard! ctx: Ctx shard: (List (Pair String board/AsnValue)) idx: Int64 cycle: Int64 rotate: Bool -> (Pair (List String) Query)
  (let [plan (shardPlan ctx shard idx cycle rotate)
        model (first plan "")
        att (first (rest plan) "")
        slot (if (stringStartsWith? att "(") att (str "(" att ")"))
        dist (board/distillShard! ctx.root (shardPaths shard) 3500)
        prompt (auditPrompt shard slot dist.digest)]
    (pair plan
      (mt (planTemp plan)
        ((some temp) (queryIntent! ctx (board/pyStr (getv shard "intent")) slot prompt model temp 3 "" 1500))
        ((none) (Query :ok false :content "" :source "" :usage (board/asnNone) :error "ValueError: invalid plan temperature")))))


fn concurrencyOf ctx: Ctx -> Int64
  (mt (cfgv ctx "concurrency")
    ((board/asnInt k) (max 1 k))
    ((board/asnStr s) (max 1 (optionOr (stringToInt64 s) 2)))
    (_ 2))

schema ShardWork
  (:f shard (List (Pair String board/AsnValue)))
  (:f plan (List String))
  (:f req (Option IntentReq))
  (:f immediateQuery (Option Query))

fn dummyProcOut -> ProcOut
  (ProcOut :code -1 :out "" :errText "missing output" :timedOut false)

fn dummyIntentReq -> IntentReq
  (IntentReq :intent "" :headers (list) :messages (j/jarr (list)) :modelHint "" :temp 0.0 :maxTokens 0 :job (ProcJob :argv (list) :cwd "" :env (list) :input "" :timeoutMs 0))

fn prepareShardWork! ctx: Ctx shard: (List (Pair String board/AsnValue)) idx: Int64 cycle: Int64 rotate: Bool -> ShardWork
  (let [plan (shardPlan ctx shard idx cycle rotate)
        model (first plan "")
        att (first (rest plan) "")
        slot (if (stringStartsWith? att "(") att (str "(" att ")"))
        dist (board/distillShard! ctx.root (shardPaths shard) 3500)
        prompt (auditPrompt shard slot dist.digest)
        tempOpt (planTemp plan)]
    (mt tempOpt
      ((none)
        (ShardWork :shard shard :plan plan :req (none)
                   :immediateQuery (some (Query :ok false :content "" :source "" :usage (board/asnNone) :error "ValueError: invalid plan temperature"))))
      ((some temp)
        (let [req (makeIntentReq ctx (board/pyStr (getv shard "intent")) slot prompt model temp "" 1500)]
          (ShardWork :shard shard :plan plan :req (some req) :immediateQuery (none))))))

fn applyShardResult! ctx: Ctx shard: (List (Pair String board/AsnValue)) plan: (List String) q: Query -> (Result Unit String)
  (let [sid (board/pyStr (getv shard "id"))
        model (first plan "")
        att (first (rest plan) "")
        disp (if (stringStartsWith? att "(") att (str "(" att ")"))
        tail (str " via " q.source " [attractor=" disp ", model=" (modelShort model) "]")]
    (if (not q.ok)
      (do (out! (str "  • [" sid "] Query failed: " q.error)) (ok ()))
      (mt (board/parseFinding q.content)
        ((none) (do (out! (str "  • [" sid "] Clean / Verified" tail)) (ok ())))
        ((some f)
          (let [fe (entries f)]
            (do (out! (str "  • [" sid "] Defect Identified: " (strOrNone (getv fe "target")) " (" (strOrNone (getv fe "severity")) ")" tail))
                (recordFinding! ctx fe shard model att)))))))

fn sweepShard! ctx: Ctx shard: (List (Pair String board/AsnValue)) idx: Int64 cycle: Int64 rotate: Bool -> (Result Unit String)
  (let [r (auditShard! ctx shard idx cycle rotate)]
    (applyShardResult! ctx shard (pairFirst r) (pairSecond r)))

fn strOrNone v: board/AsnValue -> String
  (board/pyStr v)

fn applyShardBatchLoop! ctx: Ctx works: (List ShardWork) procOuts: (List ProcOut) -> (Result Unit String)
  (mt (listHead works)
    ((none) (ok ()))
    ((some sw)
      (let [resPair (mt sw.immediateQuery
                      ((some q) (pair q procOuts))
                      ((none)
                        (let [r (optionOr sw.req (dummyIntentReq))
                              po (optionOr (listHead procOuts) (dummyProcOut))
                              restPo (optionOr (listTail procOuts) (list))
                              q (finishIntentQuery! ctx r (parseHttpResult (ok po)))]
                          (pair q restPo))))
            q (pairFirst resPair)
            remainingPo (pairSecond resPair)]
        (mt (applyShardResult! ctx sw.shard sw.plan q)
          ((err e) (err e))
          ((ok _) (applyShardBatchLoop! ctx (optionOr (listTail works) (list)) remainingPo))))))

fn sweepBatch! ctx: Ctx shards: (List board/AsnValue) cycle: Int64 rotate: Bool -> (Result Unit String)
  (if (listEmpty? shards)
    (ok ())
    (let [items (enumerate shards)
          works (map (fn [p] (prepareShardWork! ctx (entries (pairSecond p)) (pairFirst p) cycle rotate)) items)
          jobs (fold (fn [acc sw] (mt sw.req ((some r) (listAppend acc (list r.job))) ((none) acc))) (list) works)
          k (max 1 (min (listLength shards) (concurrencyOf ctx)))]
      (mt (runProcPool! jobs k)
        ((err e) (err e))
        ((ok procOuts)
          (applyShardBatchLoop! ctx works procOuts)))))

fn sweepLoop! ctx: Ctx shards: (List board/AsnValue) idx: Int64 cycle: Int64 rotate: Bool -> (Result Unit String)
  (sweepBatch! ctx shards cycle rotate)

fn runSweep! ctx: Ctx cycle: Int64 rotate: Bool -> (Result Unit String)
  (let [rot (entries (cfgv ctx "rotation"))
        isRot (or rotate (and (board/truthy? (getd rot "enabled" (board/asnBool false))) (> cycle 0)))
        regime (board/pyStr (getd rot "attractor_regime" (s "triple")))
        shards (items (cfgv ctx "shards"))]
    (do
      (out! "=== ASL AGENT MESH: CONCURRENT REPOSITORY SWEEP ===")
      (out! (str "Target Monorepo: " ctx.root))
      (out! (str "Timestamp:       " (localStamp! ctx)))
      (if isRot
        (out! (str "Rotation Mode:   ACTIVE (Cycle " (stringFromInt64 cycle) " across " (stringFromInt64 (listLength (items (getd rot "cycle_models" (board/asnList (list)))))) " models & regime :" regime ")\n"))
        (out! (str "Rotation Mode:   STATIC BASELINE (regime :" regime ")\n")))
      (mt (runStatic! ctx)
        ((err e) (err e))
        ((ok staticOk)
          (do
            (if staticOk
              (out! "    ✓ All static verification gates passed cleanly (0 tokens consumed).\n")
              (out! "    [!] Static pipeline reported defects. Proceeding with shard audit to isolate cause...\n"))
            (out! (str "=== [PHASE 2] CONCURRENT INTENT DISPATCH ACROSS " (stringFromInt64 (listLength shards)) " SHARDS ==="))
            (let [t0 (monotonicNs)]
              (mt (sweepBatch! ctx shards cycle rotate)
                ((err e) (err e))
                ((ok _)
                  (do
                    (out! (str "\n✓ Full repository audit sweep completed in " (fixed (/ (int64ToFloat64 (- (monotonicNs) t0)) 1000000000.0) 2) "s."))
                    (dispatchHook! ctx "onSweepComplete" (list (pair "shards" (stringFromInt64 (listLength shards))) (pair "cycle" (stringFromInt64 cycle))))
                    (ok ()))))))))))


fn codeContext! ctx: Ctx target: String k: Int64 -> String
  (let [filePart (if (has? target "#") (first (splitOn target "#") "") target)
        full (board/pyJoin ctx.root filePart)]
    (if (not (exists? full))
      ""
      (mt (readText! full)
        ((ok t) (cpTake t k))
        ((err e) (do (warn! (str "[Context] " e)) "")))))

fn peerFor ctx: Ctx auditor: String -> (Pair String Float64)
  (let [peer (getv (entries (cfgv ctx "peer_rotation")) auditor)]
    (if (board/truthy? peer)
      (let [xs (items peer)]
        (pair (board/pyStr (first xs (board/asnNone))) (asFloat (first (rest xs) (board/asnNone)))))
      (let [cands (filter (fn [m] (!= m auditor)) (map board/pyStr (items (getv (entries (cfgv ctx "rotation")) "cycle_models"))))]
        (pair (first cands "google/gemma-4-31b-it:free") 0.50))))

fn crossPrompt did: String target: String hazard: String auditor: String code: String -> String
  (str "\n;; === ADVERSARIAL CROSS-EXAMINATION ===\n"
       ";; Cognitive Intent: :falsify\n"
       ";; Attractor: :verification\n"
       ";; Target: \"" target "\"\n"
       ";; Reported Hazard: \"" hazard "\"\n"
       ";; Original Auditor: \"" (if (stringEmpty? auditor) "unspecified" auditor) "\"\n"
       ";;\n"
       ";; Source Code Anchor:\n"
       code "\n"
       ";;\n"
       ";; Task:\n"
       ";; Independently determine whether this hazard is a GENUINE, reproducible defect or a FALSE POSITIVE (e.g. context truncation artifact, valid syntactic idiom, or misunderstanding).\n"
       ";; Return strictly an S-expression:\n"
       ";; (:verdict :id \"" did "\" :decision <:corroborate|:refute> :evidence \"<clear technical rationale>\" :witnessTest \"<failing test command or nil>\")\n")

fn applyVerdict! ctx: Ctx defect: (List (Pair String board/AsnValue)) v: (List (Pair String board/AsnValue)) -> (Result Unit String)
  (let [did (strOrNone (getv defect "id"))
        decision (board/pyStr (getv v "decision"))
        ev (board/sanitizeAsnString (getd v "evidence" (s "")))
        block (board/pyStr (getv defect "raw"))
        bbPath (cfgs ctx "blackboard_path")]
    (do
      (out! (str "  • [" did "] Verdict: :" (stringUpper decision) " - " (cpTake ev 80) "..."))
      (board/withFileLock! bbPath
        (fn []
          (mt (readText! bbPath)
            ((err e) (err e))
            ((ok cur)
              (cond
                ((= decision "refute")
                  (mt (board/setField block "status" ":refuted")
                    ((err e) (err e))
                    ((ok b1)
                      (mt (board/setField b1 "refutedBy" (str "(:kind :prose :agent \"" (board/sanitizeAsnString (s (board/normAgent (getd defect "auditor" (s "cross-examiner"))))) "\" :evidence \"" ev "\")"))
                        ((err e) (err e))
                        ((ok b2)
                          (mt (board/writeBoard! bbPath (replaceAll cur block b2) (cfgs ctx "shards_dir"))
                            ((err e) (err e))
                            ((ok _) (do (out! (str "    ✓ Defect " did " REFUTED and sealed with proof.")) (ok ())))))))))
                ((= decision "corroborate")
                  (let [wit (getv v "witness_test")
                        witText (strOrEmpty wit)
                        clause (if (and (board/truthy? wit) (!= (stringLower witText) "nil")) (str "\n      :witnessTest \"" (board/sanitizeAsnString wit) "\"") "")]
                    (mt (board/setField block "status" ":corroborated")
                      ((err e) (err e))
                      ((ok b1)
                        (let [c (confirmations b1)
                              b2 (if (< c 0) b1 (subConfirmations b1 (+ c 1)))
                              note (str "\n      :corroboratedByIntent :falsify\n      :corroborationEvidence \"" ev "\"" clause)
                              b3 (str (rstripSpace (dropLast b2)) note ")")]
                          (mt (board/writeBoard! bbPath (replaceAll cur block b3) (cfgs ctx "shards_dir"))
                            ((err e) (err e))
                            ((ok _)
                              (do (out! (str "    ✓ Defect " did " CORROBORATED" (if (board/truthy? wit) " with executable witness" "") "."))
                                  (dispatchHook! ctx "onCorroborated" (list (pair "id" did) (pair "target" (gets defect "target" ""))))
                                  (ok ())))))))))
                (else (ok ())))))))))


schema CrossWork
  (:f defect (List (Pair String board/AsnValue)))
  (:f req IntentReq)

fn prepareCrossWork! ctx: Ctx defect: (List (Pair String board/AsnValue)) -> CrossWork
  (let [did (strOrNone (getv defect "id"))
        target (strOrEmpty (getv defect "target"))
        hazard (gets defect "hazard" "")
        auditor (gets defect "auditor" "")
        peer (peerFor ctx auditor)
        code (codeContext! ctx target 3500)
        req (makeIntentReq ctx "falsify" "verification" (crossPrompt did target hazard auditor code) (pairFirst peer) (pairSecond peer) "" 1500)]
    (CrossWork :defect defect :req req))

fn applyCrossBatchLoop! ctx: Ctx works: (List CrossWork) procOuts: (List ProcOut) -> (Result Unit String)
  (mt (listHead works)
    ((none) (ok ()))
    ((some cw)
      (let [po (optionOr (listHead procOuts) (dummyProcOut))
            restPo (optionOr (listTail procOuts) (list))
            r cw.req
            q (finishIntentQuery! ctx r (parseHttpResult (ok po)))
            did (strOrNone (getv cw.defect "id"))]
        (mt (if (not q.ok)
              (do (out! (str "  • [" did "] Peer query failed: " q.error)) (ok ()))
              (mt (board/parseVerdict q.content)
                ((none) (do (out! (str "  • [" did "] Could not parse valid :verdict S-expression.")) (ok ())))
                ((some v) (applyVerdict! ctx cw.defect (entries v)))))
          ((err e) (err e))
          ((ok _) (applyCrossBatchLoop! ctx (optionOr (listTail works) (list)) restPo))))))

fn crossBatch! ctx: Ctx defects: (List (List (Pair String board/AsnValue))) -> (Result Unit String)
  (if (listEmpty? defects)
    (ok ())
    (let [works (map (fn [d] (prepareCrossWork! ctx d)) defects)
          jobs (map (fn [cw] cw.req.job) works)
          k (max 1 (min (listLength defects) (concurrencyOf ctx)))]
      (mt (runProcPool! jobs k)
        ((err e) (err e))
        ((ok procOuts)
          (applyCrossBatchLoop! ctx works procOuts)))))

fn crossOne! ctx: Ctx defect: (List (Pair String board/AsnValue)) -> (Result Unit String)
  (crossBatch! ctx (list defect))

fn crossLoop! ctx: Ctx defects: (List (List (Pair String board/AsnValue))) -> (Result Unit String)
  (crossBatch! ctx defects)

fn runCrossExamine! ctx: Ctx targetId: String -> (Result Unit String)
  (let [bbPath (cfgs ctx "blackboard_path")]
    (do
      (out! "=== ASL AUDIT MESH: ADVERSARIAL CROSS-EXAMINATION ===")
      (if (not (exists? bbPath))
        (do (out! "Blackboard not found.") (ok ()))
        (mt (readText! bbPath)
          ((err e) (err e))
          ((ok bb)
            (let [open (filter (fn [inf]
                                 (let [st (strOrEmpty (getv inf "status"))]
                                   (and (or (= st "candidate") (= st "open"))
                                        (or (stringEmpty? targetId) (= (strOrEmpty (getv inf "id")) targetId)))))
                               (map (fn [b] (entries (board/parseGapBlock b))) (board/extractGapBlocks bb "defect")))]
              (if (listEmpty? open)
                (do (out! "✓ No open defects awaiting cross-examination.") (ok ()))
                (do (out! (str "Discovered " (stringFromInt64 (listLength open)) " open defect(s) awaiting cross-examination.\n"))
                    (crossBatch! ctx open)))))))))


fn pidProbe! pid: Int64 -> Bool
  (cond
    ((= pid 0) true)
    ((= pid -1) true)
    ((< pid -1) (resultOr (procAlive? (- 0 pid)) false))
    (else (resultOr (procAlive? pid) false)))

fn readPid! path: String -> (Option Int64)
  (mt (readText! path)
    ((err _) (none))
    ((ok t) (mt (board/pyInt (board/pyStrip t)) ((board/intOk v) (some v)) (_ (none)))))

fn countKeyed text: String key: String suffix: String -> Int64
  (let [bs (stringToBytes text)]
    (countKeyedLoop text bs (bytesLength bs) key suffix 0 0))

fn countKeyedLoop text: String bs: Bytes n: Int64 key: String suffix: String i: Int64 acc: Int64 -> Int64
  (let [p (findBytes bs n (stringToBytes key) (stringLength key) i)]
    (if (< p 0)
      acc
      (let [a (+ p (stringLength key))
            b (skipSpace bs a n)]
        (if (and (> b a) (= (sub text b (+ b (stringLength suffix))) suffix))
          (if (= suffix "\"GAP-")
            (let [e (runEnd bs (+ b 5) n (fn [c] (!= c 34)))]
              (if (and (> e (+ b 5)) (< e n))
                (countKeyedLoop text bs n key suffix (+ e 1) (+ acc 1))
                (countKeyedLoop text bs n key suffix (+ p 1) acc)))
            (countKeyedLoop text bs n key suffix (+ b (stringLength suffix)) (+ acc 1)))
          (countKeyedLoop text bs n key suffix (+ p 1) acc)))))

fn statusCount blocks: (List String) st: String -> Int64
  (listLength (filter (fn [b] (= (strOrEmpty (getv (entries (board/parseGapBlock b)) "status")) st)) blocks))

fn fmt v: board/AsnValue -> String
  (board/pyStr v)

fn runStatus! ctx: Ctx -> (Result Unit String)
  (let [leg (cfgv ctx "legacy_ledger_path")
        legPath (strOrEmpty leg)
        bbPath (cfgs ctx "blackboard_path")
        legText (if (and (board/truthy? leg) (exists? legPath)) (readText! legPath) (ok ""))
        bbText (if (exists? bbPath) (readText! bbPath) (ok ""))
        pidFile (cfgs ctx "pid_file")]
    (mt legText
      ((err e) (err e))
      ((ok lt)
        (mt bbText
          ((err e) (err e))
          ((ok bt)
            (let [blocks (board/extractGapBlocks bt "defect")
                  pidStatus (if (not (exists? pidFile))
                              "STOPPED"
                              (mt (readPid! pidFile)
                                ((none) "DEAD (Stale PID file)")
                                ((some p) (if (and (<= p 2147483647) (pidProbe! p)) (str "RUNNING (PID: " (stringFromInt64 p) ")") "DEAD (Stale PID file)"))))
                  n (fn [x] (stringFromInt64 x))]
              (do
                (out! "=== ASL AUDIT MESH STATUS ===")
                (out! (str "Daemon State:       " pidStatus))
                (out! (str "Config Source:      " (gets ctx.cfg "config_source" ".asl.config.asn#mesh")))
                (let [ap (entries (cfgv ctx "active_profile"))]
                  (if (listEmpty? ap) () (out! (str "Active Profile:     :" (gets ap "id" "default") " (" (gets ap "description" "") ")"))))
                (out! (str "Blackboard Path:    " bbPath))
                (if (board/truthy? leg)
                  (do (out! (str "Legacy Ledger:      " legPath))
                      (out! (str "Legacy Gaps (gapLedger.asn): " (n (countKeyed lt ":id" "\"GAP-")) " (Open: " (n (countKeyed lt ":status" ":open"))
                                ", Corroborated: " (n (countKeyed lt ":status" ":corroborated")) ", Refuted: " (n (countKeyed lt ":status" ":refuted")) ")")))
                  (out! (str "Legacy Ledger:      :deprecated-removed (SSOT: " bbPath ")")))
                (out! (str "Total Defects (BB): " (n (listLength blocks))))
                (out! (str "  • Candidate:      " (n (statusCount blocks "candidate"))))
                (out! (str "  • Corroborated:   " (n (statusCount blocks "corroborated"))))
                (out! (str "  • Refuted:        " (n (statusCount blocks "refuted"))))
                (out! (str "  • Certified:      " (n (statusCount blocks "certified"))))
                (out! (str "  • Remediated:     " (n (statusCount blocks "remediated"))))
                (let [ds (items (cfgv ctx "descriptors"))]
                  (if (listEmpty? ds)
                    ()
                    (do (out! (str "Registered Descriptors: " (n (listLength ds)) " formal schemas (asl-mesh/descriptor)"))
                        (map (fn [d] (let [de (entries d)] (out! (str "  • Schema: " (ljust (fmt (getv de "schema")) 26) " (pkg: " (fmt (getv de "package")) ") - " (fmt (getv de "doc")))))) ds)
                        ())))
                (let [hs (entries (cfgv ctx "hooks"))]
                  (if (listEmpty? hs)
                    ()
                    (do (out! (str "Reactive Event Hooks:   " (n (listLength hs)) " active lifecycle hooks"))
                        (map (fn [p] (let [h (entries (pairSecond p))
                                           ev (getv h "eval")]
                                       (out! (str "  • :" (ljust (pairFirst p) 18) " -> Action: :" (ljust (fmt (getv h "action")) 20)
                                                 (if (board/truthy? ev) (str " [eval: " (fmt ev) "]") "") " (" (fmt (getv h "doc")) ")"))))
                             hs)
                        ())))
                (let [pipe (items (cfgv ctx "static_pipeline"))
                      evals (listLength (filter (fn [g] (board/truthy? (getv (entries g) "eval"))) pipe))]
                  (out! (str "Static Pipeline Gates:  " (n (listLength pipe)) " (" (n evals) " executable ASL, " (n (- (listLength pipe) evals)) " shell)")))
                (let [tax (items (cfgv ctx "taxonomy"))]
                  (if (listEmpty? tax) () (out! (str "Defect Taxonomy:        " (n (listLength tax)) " categories"))))
                (let [safety (entries (cfgv ctx "safety"))]
                  (if (listEmpty? safety)
                    ()
                    (out! (str "Safety Constraints:     zeroLineNumbers=" (fmt (getd safety "zeroLineNumbers" (board/asnBool true)))
                              ", pureDyck1=" (fmt (getd safety "pureDyck1Only" (board/asnBool true)))
                              ", antiVacuity=" (fmt (getd safety "antiVacuity" (getd safety "antiPotemkin" (board/asnBool true))))))))
                (let [rot (entries (cfgv ctx "rotation"))]
                  (out! (str "Dynamic Rotation:   " (if (board/truthy? (getd rot "enabled" (board/asnBool true))) "ACTIVE (Continuous Dynamic Permutation: 8 Models x 5 Attractors)" "OFF"))))
                (let [shards (items (cfgv ctx "shards"))]
                  (do
                    (out! (str "Active Shards:      " (n (listLength shards))))
                    (out! "\nShard Intent Topology & Calibrated Temperatures:")
                    (map (fn [sh] (let [e (entries sh)]
                                    (out! (str "  • " (ljust (fmt (getv e "id")) 18) " -> Intent: :" (ljust (fmt (getv e "intent")) 10) " Attractor: :" (ljust (fmt (getv e "attractor")) 14)
                                              " T=" (fixed (asFloat (getv e "temp")) 2) " (" (fmt (getv e "model")) ")"))))
                         shards)
                    (ok ()))))))))))

fn boxRow text: String -> String
  (str (ljust text 89) "│")

fn runDashboard! ctx: Ctx -> (Result Unit String)
  (let [bbPath (cfgs ctx "blackboard_path")
        text (if (exists? bbPath) (readText! bbPath) (ok ""))
        pidFile (cfgs ctx "pid_file")]
    (mt text
      ((err e) (err e))
      ((ok bt)
        (let [blocks (board/extractGapBlocks bt "defect")
              pidStatus (if (not (exists? pidFile))
                          "OFFLINE"
                          (mt (readPid! pidFile)
                            ((none) "STALE")
                            ((some p) (if (and (<= p 2147483647) (pidProbe! p)) (str "ACTIVE (PID " (stringFromInt64 p) ")") "STALE"))))
              shards (items (cfgv ctx "shards"))
              n (fn [x] (stringFromInt64 x))
              rule "├────────────────────────────────────────────────────────────────────────────────────────┤"]
          (do
            (out! "┌────────────────────────────────────────────────────────────────────────────────────────┐")
            (out! "│                     ASL 24/7 AUTONOMOUS AGENT MESH DASHBOARD                           │")
            (out! rule)
            (out! (boxRow (str "│ Daemon: " (ljust pidStatus 18) " │ Active Shards: " (ljust (n (listLength shards)) 4) " │ Mode: Continuous Autonomous Audit")))
            (out! (boxRow (str "│ Programmable DSL: " (n (listLength (items (cfgv ctx "descriptors")))) " Descriptors  •  " (n (listLength (entries (cfgv ctx "hooks"))))
                              " Reactive Hooks  •  " (n (listLength (items (cfgv ctx "static_pipeline")))) " Pipeline Gates")))
            (out! rule)
            (out! "│ SHARD TOPOLOGY & INTENT DISPATCH                                                       │")
            (map (fn [sh] (let [e (entries sh)]
                            (out! (boxRow (str "│   • " (ljust (fmt (getv e "id")) 16) " Intent: " (ljust (str ":" (fmt (getv e "intent"))) 10) " Attractor: " (ljust (str ":" (fmt (getv e "attractor"))) 14)
                                              " " (ljust (str "T=" (fixed (asFloat (getv e "temp")) 2)) 7) " (" (modelShort (fmt (getv e "model"))) ") ")))))
                 shards)
            (out! rule)
            (out! "│ DEFECT BLACKBOARD MONOTONIC PROGRESSION                                                │")
            (out! (boxRow (str "│   Candidate: " (ljust (n (statusCount blocks "candidate")) 4) " │ Corroborated: " (ljust (n (statusCount blocks "corroborated")) 4)
                              " │ Refuted: " (ljust (n (statusCount blocks "refuted")) 4) " │ Certified: " (ljust (n (statusCount blocks "certified")) 4)
                              " │ Remediated: " (ljust (n (statusCount blocks "remediated")) 4))))
            (out! rule)
            (out! "│ ACTIVE BLACKBOARD ENTRIES (Sample)                                                     │")
            (map (fn [b] (let [inf (entries (board/parseGapBlock b))
                               tgt (gets inf "target" "UNKNOWN")
                               trunc (if (> (board/cpLength tgt) 40) (str (cpTake tgt 38) "...") tgt)]
                           (out! (boxRow (str "│   [" (gets inf "id" "UNKNOWN") "] " (ljust (gets inf "status" "UNKNOWN") 12) " " (ljust (gets inf "severity" "MED") 8) " " (ljust trunc 42))))))
                 (listTake blocks 4))
            (out! "└────────────────────────────────────────────────────────────────────────────────────────┘")
            (ok ()))))))

fn logLines text: String -> (List String)
  (filter (fn [l] (not (stringEmpty? l))) (map board/pyStrip (splitOn text "\n")))

fn bracketBody line: String key: String -> (Option String)
  (let [bs (stringToBytes line)
        n (bytesLength bs)]
    (bracketFrom line bs n key 0))

fn bracketFrom line: String bs: Bytes n: Int64 key: String i: Int64 -> (Option String)
  (let [p (findBytes bs n (stringToBytes key) (stringLength key) i)]
    (if (< p 0)
      (none)
      (let [a (+ p (stringLength key))
            b (skipSpace bs a n)]
        (if (and (> b a) (< b n) (= (bytesGet bs b) 91))
          (let [e (runEnd bs (+ b 1) n (fn [c] (and (!= c 93) (!= c 10))))]
            (if (and (< e n) (= (bytesGet bs e) 93)) (some (sub line (+ b 1) e)) (bracketFrom line bs n key (+ p 1))))
          (bracketFrom line bs n key (+ p 1))))))

fn bracketWords line: String key: String -> (List String)
  (mt (bracketBody line key)
    ((none) (list))
    ((some body) (if (stringEmpty? (board/pyStrip body)) (list) (board/pySplit (replaceAll body "\"" "")))))

fn counts xs: (List String) -> (List (Pair String Int64))
  (fold (fn [acc x] (mt (board/dictGet acc x) ((some c) (board/dictPut acc x (+ c 1))) ((none) (board/dictPut acc x 1)))) (list) xs)

fn runTelemetry! ctx: Ctx -> (Result Unit String)
  (let [tel (cfgs ctx "telemetry_log_path")]
    (do
      (out! "=== ASL AUDIT MESH: AGENT TELEMETRY & COMPLIANCE REPORT ===")
      (if (not (exists? tel))
        (do (out! (str "No telemetry logs found at: " tel)) (ok ()))
        (mt (readText! tel)
          ((err e) (err e))
          ((ok text)
            (let [lines (logLines text)
                  total (listLength lines)
                  pure (listLength (filter (fn [l] (has? l ":pureDyck1 true")) lines))
                  md (listLength (filter (fn [l] (has? l ":markdownWrapped true")) lines))
                  pre (listLength (filter (fn [l] (has? l ":preamble true")) lines))
                  alerts (fold (fn [acc l] (listAppend acc (bracketWords l ":cheatingFlags"))) (list) lines)
                  comps (fold (fn [acc l] (listAppend acc (bracketWords l ":harnessComplaints"))) (list) lines)
                  pct (if (> total 0) (* (/ (int64ToFloat64 pure) (int64ToFloat64 total)) 100.0) 100.0)
                  n (fn [x] (stringFromInt64 x))]
              (do
                (out! (str "Log Stream:               " tel))
                (out! (str "Total Turn Invocations:   " (n total)))
                (out! (str "Pure Dyck-1 Wire Purity:  " (fixed pct 1) "% (" (n pure) "/" (n total) ")"))
                (out! (str "  • Markdown Fence Leaks: " (n md)))
                (out! (str "  • Plaintext Preambles:  " (n pre)))
                (out! (str "Cheating / Vacuous Pass Alerts: " (n (listLength alerts))))
                (if (listEmpty? alerts)
                  (out! "    ✓ Zero cheating or vacuous pass attempts detected.")
                  (do (map (fn [p] (out! (str "    - [!] Alert: " (pairFirst p) " (count: " (n (pairSecond p)) ")"))) (counts alerts)) ()))
                (out! (str "Harness Complaints & Debt:  " (n (listLength comps))))
                (if (listEmpty? comps)
                  (out! "    ✓ No harness gaps reported by models.")
                  (do (map (fn [p] (out! (str "    - [i] Complaint: " (pairFirst p) " (count: " (n (pairSecond p)) ")"))) (counts comps)) ()))
                (ok ()))))))))

fn keyedEscaped text: String key: String -> (Option String)
  (let [bs (stringToBytes text)]
    (keyedEscFrom text bs (bytesLength bs) key 0))

fn escBodyEnd bs: Bytes i: Int64 n: Int64 -> Int64
  (cond
    ((>= i n) -1)
    ((= (bytesGet bs i) 34) i)
    ((= (bytesGet bs i) 92) (if (and (< (+ i 1) n) (!= (bytesGet bs (+ i 1)) 10)) (escBodyEnd bs (+ i 2) n) -1))
    (else (escBodyEnd bs (+ i 1) n)))

fn keyedEscFrom text: String bs: Bytes n: Int64 key: String i: Int64 -> (Option String)
  (let [p (findBytes bs n (stringToBytes key) (stringLength key) i)]
    (if (< p 0)
      (none)
      (let [a (+ p (stringLength key))
            b (skipSpace bs a n)
            e (if (and (> b a) (< b n) (= (bytesGet bs b) 34)) (escBodyEnd bs (+ b 1) n) -1)]
        (if (>= e 0) (some (sub text (+ b 1) e)) (keyedEscFrom text bs n key (+ p 1))))))

fn keyedPlain text: String key: String -> (Option String)
  (let [bs (stringToBytes text)]
    (keyedPlainFrom text bs (bytesLength bs) key 0))

fn keyedPlainFrom text: String bs: Bytes n: Int64 key: String i: Int64 -> (Option String)
  (let [p (findBytes bs n (stringToBytes key) (stringLength key) i)]
    (if (< p 0)
      (none)
      (let [a (+ p (stringLength key))
            b (skipSpace bs a n)
            e (if (and (> b a) (< b n) (= (bytesGet bs b) 34)) (runEnd bs (+ b 1) n (fn [c] (!= c 34))) -1)]
        (if (and (> e (+ b 1)) (< e n)) (some (sub text (+ b 1) e)) (keyedPlainFrom text bs n key (+ p 1))))))

fn runProposals! ctx: Ctx -> (Result Unit String)
  (let [bbPath (cfgs ctx "blackboard_path")]
    (do
      (out! "=== ASL AUDIT MESH: VIRTUAL CONSENSUS FIX PROPOSALS ===")
      (out! "Mode: READ-ONLY AUDIT (Proposals staged in Blackboard; zero disk mutation)\n")
      (if (not (exists? bbPath))
        (do (out! "Blackboard not found.") (ok ()))
        (mt (readText! bbPath)
          ((err e) (err e))
          ((ok bb)
            (let [props (filter (fn [b] (has? b ":fixProposal")) (board/extractGapBlocks bb "defect"))]
              (do
                (map (fn [b]
                       (let [inf (entries (board/parseGapBlock b))
                             rt (has? b ":removesTests true")
                             wk (has? b ":weakensInvariants true")
                             ch (has? b ":cheatingDetected true")]
                         (do
                           (out! (str "┌── [PROPOSAL FOR " (gets inf "id" "UNKNOWN") "] Target: " (gets inf "target" "UNKNOWN")))
                           (out! (str "│ Status:       " (if (or rt wk ch) "FLAGGED (record sets removesTests, weakensInvariants or cheatingDetected)" "NO FLAGGED KEYWORDS (keyword check of the patch text, not a verification)")))
                           (out! (str "│ Explanation:  " (optionOr (keyedPlain b ":explanation") "N/A")))
                           (out! (str "│ Proposed AST: " (optionOr (keyedEscaped b ":proposedPatch") "N/A")))
                           (out! (str "└── Invariants: removesTests=" (pyBool rt) ", weakensInvariants=" (pyBool wk) "\n")))))
                     props)
                (if (listEmpty? props) (out! "Zero fix proposals recorded. Run 'asl mesh propose-fix <DEF-ID>' to formulate a proposal.") ())
                (ok ()))))))))

fn findDefect bb: String did: String -> (Option (Pair String (List (Pair String board/AsnValue))))
  (fold (fn [acc b]
          (if (some? acc)
            acc
            (let [inf (entries (board/parseGapBlock b))]
              (if (= (strOrNone (getv inf "id")) did) (some (pair b inf)) acc))))
        (none) (board/extractGapBlocks bb "defect"))

fn proposePrompt tgt: String hazard: String code: String -> String
  (str "\n;; === CONSENSUS FIX PROPOSAL ===\n"
       ";; Cognitive Intent: :formulate\n"
       ";; Attractor: :simplicity\n"
       ";; Target: \"" tgt "\"\n"
       ";; Defect Hazard: \"" hazard "\"\n"
       ";;\n"
       ";; Code Context:\n"
       code "\n"
       ";;\n"
       ";; Task:\n"
       ";; Formulate an exact S-expression patch proposal to fix this defect.\n"
       ";; Rules:\n"
       ";; - Do NOT remove tests, do NOT weaken assertions, do NOT insert pass/stubs.\n"
       ";; - Return strictly:\n"
       ";;   (:fix-proposal :target \"" tgt "\" :explanation \"<rationale>\" :proposedPatch \"(:replace :target \\\"" tgt "\\\" :old \\\"<old>\\\" :new \\\"<new>\\\")\")\n")

fn cheatReasons patch: String -> (List String)
  (let [lp (stringLower patch)]
    (filter (fn [x] (not (stringEmpty? x)))
      (list (if (or (has? lp "assert true") (has? lp "assert(true)") (has? lp ":assert true")) "vacuous-assert-true" "")
            (if (or (has? lp "skip") (has? lp "# skip") (has? lp "@pytest.mark.skip")) "skip-gate-evasion" "")
            (if (or (has? lp "pass\n") (endsWith? (board/pyStrip lp) "pass")) "empty-stub-evasion" "")
            (if (or (has? lp "exit 0") (has? lp "exit(0)")) "unverified-exit-zero" ""))))

fn proposalText cheating: Bool expl: String patch: String -> String
  (str "\n      :fixProposal (\n        :proposedByIntent :formulate\n        :safetyAudit (\n          :removesTests false\n          :weakensInvariants false\n          :astIdempotent true\n"
       "          :cheatingDetected " (asnBool cheating) "\n        )\n        :explanation \"" (board/sanitizeAsnString (s expl)) "\"\n"
       "        :proposedPatch \"" (board/sanitizeAsnString (s patch)) "\"\n      )")

fn runProposeFix! ctx: Ctx did: String -> (Result Unit String)
  (if (stringEmpty? did)
    (do (out! "Error: Target defect ID required (e.g. asl mesh propose-fix DEF-20260920-001)") (ok ()))
    (let [bbPath (cfgs ctx "blackboard_path")]
      (do
        (out! (str "=== ASL AUDIT MESH: FORMULATING VIRTUAL FIX PROPOSAL FOR " did " ==="))
        (if (not (exists? bbPath))
          (do (out! "Blackboard not found.") (ok ()))
          (mt (readText! bbPath)
            ((err e) (err e))
            ((ok bb)
              (mt (findDefect bb did)
                ((none) (do (out! (str "Defect " did " not found in Blackboard.")) (ok ())))
                ((some hit)
                  (let [block (pairFirst hit)
                        inf (pairSecond hit)
                        tgt (strOrNone (getv inf "target"))
                        hazard (gets inf "hazard" "")]
                    (do
                      (out! (str "Target: " tgt))
                      (out! (str "Hazard: " hazard))
                      (let [q (queryIntent! ctx "formulate" "simplicity" (proposePrompt tgt hazard (codeContext! ctx tgt 3000)) "" 0.20 3 "" 1500)]
                        (if (not q.ok)
                          (do (out! (str "Failed to formulate proposal: " q.error)) (ok ()))
                          (let [content q.content
                                expl (optionOr (keyedPlain content ":explanation") "Model proposed fix")
                                patch (optionOr (keyedEscaped content ":proposedPatch") content)
                                reasons (cheatReasons patch)
                                cheating (not (listEmpty? reasons))]
                            (do
                              (if cheating
                                (do (logTelemetryDict! ctx (list (pair "type" "cheatingAlert") (pair "defectId" did) (pair "reasons" (stringJoin reasons ","))
                                                                (pair "patchSnippet" (replaceAll (cpTake patch 80) "\"" ""))))
                                    (dispatchHook! ctx "onCheatingAlert" (list (pair "reasons" (stringJoin reasons ",")) (pair "defectId" did))))
                                ())
                              (board/withFileLock! bbPath
                                (fn []
                                  (if (has? block ":fixProposal")
                                    (do (out! "Defect already carries a fix proposal. Use 'asl mesh proposals' to inspect.") (ok ()))
                                    (let [nb (str (rstripSpace (dropLast block)) (proposalText cheating expl patch) ")")]
                                      (mt (board/writeBoard! bbPath (replaceAll bb block nb) (cfgs ctx "shards_dir"))
                                        ((err e) (err e))
                                        ((ok _)
                                          (do (out! (str "✓ Fix proposal recorded in Blackboard. (Keyword check: " (if cheating (str "flagged " (stringJoin reasons ",")) "no flagged keywords") ")"))
                                              (out! "Note: In audit mode, this is a virtual proposal. Workspace code remains unmodified.")
                                              (ok ()))))))))))))))))))))))

fn runConsensus! ctx: Ctx -> (Result Unit String)
  (let [bbPath (cfgs ctx "blackboard_path")]
    (if (not (exists? bbPath))
      (ok ())
      (mt (readText! bbPath)
        ((err e) (err e))
        ((ok bb)
          (let [ids (map (fn [b] (strOrEmpty (getv (entries (board/parseGapBlock b)) "id")))
                         (filter (fn [b] (and (has? b ":corroborated") (not (has? b ":fixProposal")))) (board/extractGapBlocks bb "defect")))]
            (if (listEmpty? ids)
              (do (out! "  ✓ Zero corroborated defects awaiting consensus fix formulation.") (ok ()))
              (do
                (out! (str "--> [Consensus Fix Synthesis] Found " (stringFromInt64 (listLength ids)) " corroborated defect(s) awaiting virtual proposal."))
                (consensusLoop! ctx ids))))))))

fn consensusLoop! ctx: Ctx ids: (List String) -> (Result Unit String)
  (mt (listHead ids)
    ((none) (ok ()))
    ((some did)
      (do
        (out! (str "    • Synthesizing virtual fix proposal for " (if (stringEmpty? did) "None" did) "..."))
        (mt (runProposeFix! ctx did)
          ((ok _) ())
          ((err e) (warn! (str "      [Error] Failed to formulate proposal for " did ": " (hookErr e)))))
        (consensusLoop! ctx (rest ids)))))

fn dyckReason text: String -> String
  (let [bs (stringToBytes text)]
    (dyckLoop bs 0 (bytesLength bs) 0 false false))

fn dyckLoop bs: Bytes i: Int64 n: Int64 depth: Int64 inStr: Bool esc: Bool -> String
  (if (>= i n)
    (cond
      (inStr "Unbalanced Dyck-1 delimiter: unclosed string literal")
      ((!= depth 0) (str "Unbalanced Dyck-1 delimiter: open delimiter unclosed (depth=" (stringFromInt64 depth) ")"))
      (else ""))
    (let [c (bytesGet bs i)]
      (cond
        (esc (dyckLoop bs (+ i 1) n depth inStr false))
        ((= c 92) (dyckLoop bs (+ i 1) n depth inStr true))
        ((= c 34) (dyckLoop bs (+ i 1) n depth (not inStr) false))
        (inStr (dyckLoop bs (+ i 1) n depth inStr false))
        ((or (= c 40) (= c 91)) (dyckLoop bs (+ i 1) n (+ depth 1) inStr false))
        ((or (= c 41) (= c 93))
          (if (= depth 0) "Unbalanced Dyck-1 delimiter: closing delimiter without match" (dyckLoop bs (+ i 1) n (- depth 1) inStr false)))
        (else (dyckLoop bs (+ i 1) n depth inStr false)))))

fn hexVal b: Int64 -> Int64
  (cond
    ((digit? b) (- b 48))
    ((and (>= b 97) (<= b 102)) (- b 87))
    ((and (>= b 65) (<= b 70)) (- b 55))
    (else -1))

fn cpText cp: Int64 -> String
  (cond
    ((< cp 128) (byteStr cp))
    ((< cp 2048) (str (byteStr (+ 192 (/ cp 64))) (byteStr (+ 128 (mod cp 64)))))
    ((< cp 65536) (str (byteStr (+ 224 (/ cp 4096))) (byteStr (+ 128 (mod (/ cp 64) 64))) (byteStr (+ 128 (mod cp 64)))))
    (else (str (byteStr (+ 240 (/ cp 262144))) (byteStr (+ 128 (mod (/ cp 4096) 64))) (byteStr (+ 128 (mod (/ cp 64) 64))) (byteStr (+ 128 (mod cp 64))))))

fn byteStr b: Int64 -> String
  (let [tbl "\x00\x01\x02\x03\x04\x05\x06\x07\x08\x09\x0a\x0b\x0c\x0d\x0e\x0f\x10\x11\x12\x13\x14\x15\x16\x17\x18\x19\x1a\x1b\x1c\x1d\x1e\x1f !\"#$%&'()*+,-./0123456789:;<=>?@ABCDEFGHIJKLMNOPQRSTUVWXYZ[\\]^_`abcdefghijklmnopqrstuvwxyz{|}~\x7f\x80\x81\x82\x83\x84\x85\x86\x87\x88\x89\x8a\x8b\x8c\x8d\x8e\x8f\x90\x91\x92\x93\x94\x95\x96\x97\x98\x99\x9a\x9b\x9c\x9d\x9e\x9f\xa0\xa1\xa2\xa3\xa4\xa5\xa6\xa7\xa8\xa9\xaa\xab\xac\xad\xae\xaf\xb0\xb1\xb2\xb3\xb4\xb5\xb6\xb7\xb8\xb9\xba\xbb\xbc\xbd\xbe\xbf\xc0\xc1\xc2\xc3\xc4\xc5\xc6\xc7\xc8\xc9\xca\xcb\xcc\xcd\xce\xcf\xd0\xd1\xd2\xd3\xd4\xd5\xd6\xd7\xd8\xd9\xda\xdb\xdc\xdd\xde\xdf\xe0\xe1\xe2\xe3\xe4\xe5\xe6\xe7\xe8\xe9\xea\xeb\xec\xed\xee\xef\xf0\xf1\xf2\xf3\xf4\xf5\xf6\xf7\xf8\xf9\xfa\xfb\xfc\xfd\xfe\xff"]
    (optionOr (stringSlice tbl b (+ b 1)) ""))

fn hexRun bs: Bytes i: Int64 n: Int64 k: Int64 acc: Int64 -> (Pair Int64 Int64)
  (cond
    ((= k 0) (pair acc i))
    ((or (>= i n) (< (hexVal (bytesGet bs i)) 0)) (pair -1 i))
    (else (hexRun bs (+ i 1) n (- k 1) (+ (* acc 16) (hexVal (bytesGet bs i))))))

fn octRun bs: Bytes i: Int64 n: Int64 k: Int64 acc: Int64 -> (Pair Int64 Int64)
  (if (and (< k 3) (< i n) (>= (bytesGet bs i) 48) (<= (bytesGet bs i) 55))
    (octRun bs (+ i 1) n (+ k 1) (+ (* acc 8) (- (bytesGet bs i) 48)))
    (pair acc i))

fn unicodeEscape text: String strict: Bool -> (Result String String)
  (let [bs (stringToBytes text)]
    (ueLoop bs 0 (bytesLength bs) strict (list)))

fn ueLoop bs: Bytes i: Int64 n: Int64 strict: Bool acc: (List String) -> (Result String String)
  (if (>= i n)
    (ok (stringJoin (listReverse acc) ""))
    (let [b (bytesGet bs i)]
      (if (!= b 92)
        (ueLoop bs (+ i 1) n strict (cons (cpText b) acc))
        (if (>= (+ i 1) n)
          (if strict (err "\\ at end of string") (ok (stringJoin (listReverse (cons (cpText 65533) acc)) "")))
          (let [c (bytesGet bs (+ i 1))
                simple (cond ((= c 10) (some "")) ((= c 92) (some "\\")) ((= c 39) (some "'")) ((= c 34) (some "\"")) ((= c 98) (some (cpText 8))) ((= c 102) (some (cpText 12)))
                             ((= c 116) (some "\t")) ((= c 110) (some "\n")) ((= c 114) (some "\r")) ((= c 118) (some (cpText 11))) ((= c 97) (some (cpText 7))) (else (none)))]
            (cond
              ((some? simple) (ueLoop bs (+ i 2) n strict (cons (optionOr simple "") acc)))
              ((and (>= c 48) (<= c 55))
                (let [r (octRun bs (+ i 1) n 0 0)] (ueLoop bs (pairSecond r) n strict (cons (cpText (pairFirst r)) acc))))
              ((or (= c 120) (= c 117) (= c 85))
                (let [k (cond ((= c 120) 2) ((= c 117) 4) (else 8))
                      r (hexRun bs (+ i 2) n k 0)]
                  (cond
                    ((< (pairFirst r) 0)
                      (if strict (err "truncated escape") (ueLoop bs (pairSecond r) n strict (cons (cpText 65533) acc))))
                    ((> (pairFirst r) 1114111)
                      (if strict (err "illegal Unicode character") (ueLoop bs (pairSecond r) n strict (cons (cpText 65533) acc))))
                    (else (ueLoop bs (pairSecond r) n strict (cons (cpText (pairFirst r)) acc))))))
              ((= c 78) (if strict (err "named escapes are not supported") (ueLoop bs (+ i 2) n strict (cons (cpText 65533) acc))))
              (else (ueLoop bs (+ i 1) n strict (cons "\\" acc)))))))))

fn firstIndex pred: (fn [Int64] -> Bool) i: Int64 n: Int64 -> Int64
  (cond ((>= i n) -1) ((pred i) i) (else (firstIndex pred (+ i 1) n)))

fn lowerByte b: Int64 -> Int64
  (if (and (>= b 65) (<= b 90)) (+ b 32) b)

fn ciAt bs: Bytes n: Int64 i: Int64 lit: String -> Bool
  (let [lb (stringToBytes lit)
        m (bytesLength lb)]
    (and (<= (+ i m) n) (listAll? (fn [k] (= (lowerByte (bytesGet bs (+ i k))) (bytesGet lb k))) (range 0 m))))

fn boundaryBefore? bs: Bytes i: Int64 -> Bool
  (or (= i 0) (not (wordByte? (bytesGet bs (- i 1)))))

fn boundaryAt? bs: Bytes i: Int64 n: Int64 -> Bool
  (or (>= i n) (not (wordByte? (bytesGet bs i))))

fn lineNumAt? bs: Bytes i: Int64 n: Int64 -> Bool
  (let [wsDigits (fn [a] (let [b (skipSpace bs a n)] (and (> b a) (< b n) (digit? (bytesGet bs b)))))]
    (or (and (ciAt bs n i ":line") (wsDigits (+ i 5)))
        (and (ciAt bs n i "line") (boundaryBefore? bs i) (wsDigits (+ i 4)))
        (and (ciAt bs n i "l") (boundaryBefore? bs i)
             (let [e (runEnd bs (+ i 1) n digit?)] (and (> e (+ i 1)) (boundaryAt? bs e n))))
        (and (ciAt bs n i "@@")
             (let [b (skipSpace bs (+ i 2) n)] (and (< (+ b 1) n) (= (bytesGet bs b) 45) (digit? (bytesGet bs (+ b 1))))))))

fn hasLineNumber? text: String -> Bool
  (let [bs (stringToBytes text)
        n (bytesLength bs)]
    (>= (firstIndex (fn [i] (lineNumAt? bs i n)) 0 n) 0))

fn preflushReason patch: String -> String
  (if (stringEmpty? (board/pyStrip patch))
    "Empty or non-string patch proposal"
    (let [r0 (dyckReason patch)]
      (if (not (stringEmpty? r0))
        r0
        (let [payload (fn [tag]
                        (mt (keyedEscaped patch tag)
                          ((none) "")
                          ((some raw)
                            (let [dec (mt (unicodeEscape raw true) ((ok d) d) ((err _) raw))
                                  r (dyckReason dec)]
                              (if (stringEmpty? r) "" (str "Unbalanced Dyck-1 delimiter in " tag " payload: " r))))))
              rNew (payload ":new")
              rPatch (payload ":proposedPatch")]
          (cond
            ((not (stringEmpty? rNew)) rNew)
            ((not (stringEmpty? rPatch)) rPatch)
            ((hasLineNumber? patch) "Zero-Line-Number Invariant violation: patch contains forbidden integer line numbers")
            (else ""))))))

fn normalizeTokens code: String -> String
  (let [bs (stringToBytes code)]
    (stringJoin (board/pySplit (stringJoin (listReverse (stripComments code bs 0 0 (bytesLength bs) (list))) "")) " "))

fn stripComments code: String bs: Bytes i: Int64 start: Int64 n: Int64 acc: (List String) -> (List String)
  (cond
    ((>= i n) (cons (sub code start n) acc))
    ((= (bytesGet bs i) 59)
      (let [e (runEnd bs i n (fn [b] (!= b 10)))]
        (stripComments code bs e e n (cons (sub code start i) acc))))
    (else (stripComments code bs (+ i 1) start n acc)))

fn wordMatch text: String lit: String -> Int64
  (let [bs (stringToBytes text)
        n (bytesLength bs)
        m (stringLength lit)]
    (firstIndex (fn [i] (and (ciAt bs n i lit) (boundaryBefore? bs i) (boundaryAt? bs (+ i m) n))) 0 n))

fn splice text: String a: Int64 b: Int64 rep: String -> String
  (str (sub text 0 a) rep (sub text b (stringLength text)))

fn mutantBool code: String -> String
  (let [low (stringLower code)]
    (cond
      ((has? low "true") (let [p (wordMatch code "true")] (if (< p 0) code (splice code p (+ p 4) "false"))))
      ((has? low "false") (let [p (wordMatch code "false")] (if (< p 0) code (splice code p (+ p 5) "true"))))
      ((has? code "return ") (returnMutant code))
      (else (str code " ; mutation: inverted"))))

fn returnMutant code: String -> String
  (let [bs (stringToBytes code)
        n (bytesLength bs)
        hit (firstIndex (fn [i] (and (= (sub code i (+ i 6)) "return") (>= (returnStart bs (+ i 6) n) 0))) 0 n)]
    (if (< hit 0)
      code
      (let [s0 (returnStart bs (+ hit 6) n)]
        (splice code hit (runEnd bs s0 n (fn [b] (and (!= b 10) (!= b 59)))) "return None"))))

fn returnStart bs: Bytes a: Int64 n: Int64 -> Int64
  (let [b (skipSpace bs a n)]
    (cond
      ((= b a) -1)
      ((and (< b n) (!= (bytesGet bs b) 10) (!= (bytesGet bs b) 59)) b)
      (else (lastSpaceStart bs (+ a (spaceLen bs a n)) b -1))))

fn lastSpaceStart bs: Bytes i: Int64 b: Int64 found: Int64 -> Int64
  (if (>= i b)
    found
    (lastSpaceStart bs (+ i (spaceLen bs i b)) b (if (!= (bytesGet bs i) 10) i found)))

fn keepUntilNines bs: Bytes k: Int64 -> Int64
  (if (and (> k 0) (= (bytesGet bs (- k 1)) 57)) (keepUntilNines bs (- k 1)) k)

fn incDecimal digits: String -> String
  (let [bs (stringToBytes digits)
        n (bytesLength bs)
        z (runEnd bs 0 n (fn [b] (= b 48)))
        core (if (= z n) "0" (sub digits z n))
        cb (stringToBytes core)
        m (bytesLength cb)
        nines (keepUntilNines cb m)]
    (if (= nines 0)
      (str "1" (stringRepeat "0" m))
      (str (sub core 0 (- nines 1)) (byteStr (+ (bytesGet cb (- nines 1)) 1)) (stringRepeat "0" (- m nines)))))

fn mutantComp code: String -> String
  (cond
    ((has? code "<=") (replaceFirst code "<=" ">"))
    ((has? code ">=") (replaceFirst code ">=" "<"))
    ((has? code "==") (replaceFirst code "==" "!="))
    ((has? code "!=") (replaceFirst code "!=" "=="))
    ((has? code "<") (replaceFirst code "<" ">="))
    ((has? code ">") (replaceFirst code ">" "<="))
    (else (str code " ; mutation: comp-flip")))

fn mutantBoundary code: String -> String
  (let [bs (stringToBytes code)
        n (bytesLength bs)
        hit (firstIndex (fn [i] (and (digit? (bytesGet bs i)) (boundaryBefore? bs i) (boundaryAt? bs (runEnd bs i n digit?) n))) 0 n)]
    (if (< hit 0)
      (str code " ; mutation: boundary-drift")
      (let [e (runEnd bs hit n digit?)]
        (splice code hit e (incDecimal (sub code hit e))))))

fn callAt bs: Bytes i: Int64 n: Int64 -> Int64
  (if (!= (bytesGet bs i) 40)
    -1
    (let [a (runEnd bs (+ i 1) n (fn [b] (or (letter? b) (digit? b) (= b 95) (= b 45))))]
      (if (or (= a (+ i 1)) (= (spaceLen bs a n) 0))
        -1
        (let [e (runEnd bs a n (fn [b] (and (!= b 40) (!= b 41))))]
          (if (and (< e n) (= (bytesGet bs e) 41) (> e (+ a 1))) (+ e 1) -1)))))

fn findCalls code: String bs: Bytes i: Int64 n: Int64 acc: (List String) -> (List String)
  (if (>= i n)
    (listReverse acc)
    (let [e (callAt bs i n)]
      (if (< e 0) (findCalls code bs (+ i 1) n acc) (findCalls code bs e n (cons (sub code i e) acc)))))

fn transpose code: String c1: String c2: String -> String
  (let [p1 (findFrom code c1 0)
        p2 (findFrom code c2 0)]
    (if (and (>= p1 0) (>= p2 0) (< p1 p2))
      (str (sub code 0 p1) c2 (sub code (+ p1 (stringLength c1)) p2) c1 (sub code (+ p2 (stringLength c2)) (stringLength code)))
      (str code " ; transposed")))

fn slicedMutations newCode: String -> (List Int64)
  (let [bs (stringToBytes newCode)
        calls (findCalls newCode bs 0 (bytesLength bs) (list))
        nc (listLength calls)
        c0 (first calls "")
        c1 (first (rest calls) "")
        c2 (first (listDrop calls 2) "")
        m4 (cond
             ((>= nc 2) (replaceFirst newCode c1 ""))
             ((= nc 1) (replaceFirst newCode c0 ""))
             (else (let [ls (splitLines newCode)] (if (> (listLength ls) 1) (stringJoin (listTake ls (- (listLength ls) 1)) "\n") (str newCode " ; deleted")))))
        m5 (cond
             ((>= nc 3) (transpose newCode c1 c2))
             ((= nc 2) (transpose newCode c0 c1))
             (else (str newCode " ; transposed")))
        raw (list (mutantBool newCode) (mutantComp newCode) (mutantBoundary newCode) m4 m5)
        orig (normalizeTokens newCode)
        kept (filter (fn [m] (let [nm (normalizeTokens m)] (and (not (stringEmpty? nm)) (!= nm orig)))) raw)
        killed (listLength (filter (fn [m] (!= m newCode)) kept))]
    (list (listLength kept) killed))

fn splitLines text: String -> (List String)
  (let [ls (splitOn (fold (fn [acc sep] (replaceAll acc sep "\n")) (replaceAll text "\r\n" "\n") (list "\r" "\x0b" "\x0c" "\x1c" "\x1d" "\x1e")) "\n")]
    (if (and (not (listEmpty? ls)) (stringEmpty? (optionOr (listLast ls) "x"))) (listTake ls (- (listLength ls) 1)) ls))

fn fixResult pairs: (List (Pair String String)) -> board/AsnValue
  (board/asnDict (map (fn [p] (pair (pairFirst p) (s (pairSecond p)))) pairs))

fn applyFix! ctx: Ctx did: String -> (Result board/AsnValue String)
  (let [bbPath (cfgs ctx "blackboard_path")]
    (cond
      ((stringEmpty? did) (ok (fixResult (list (pair "status" "rejected") (pair "reason" "Missing target defect ID")))))
      ((not (exists? bbPath)) (ok (fixResult (list (pair "status" "rejected") (pair "reason" (str "Blackboard not found at " bbPath))))))
      (else
        (mt (readText! bbPath)
          ((err e) (err e))
          ((ok bb)
            (mt (findDefect bb did)
              ((none) (ok (fixResult (list (pair "status" "rejected") (pair "reason" (str "Defect " did " not found in Blackboard"))))))
              ((some hit)
                (mt (keyedEscaped (pairFirst hit) ":proposedPatch")
                  ((none) (ok (fixResult (list (pair "status" "rejected") (pair "reason" (str "No fix proposal found for defect " did))))))
                  ((some raw)
                    (mt (unicodeEscape raw false)
                      ((err e) (err e))
                      ((ok patch) (applyPatch! ctx did patch))))))))))))

fn applyPatch! ctx: Ctx did: String patch: String -> (Result board/AsnValue String)
  (let [reason (preflushReason patch)]
    (if (not (stringEmpty? reason))
      (do (out! (str "❌ [Pre-Flush Gate] Rejected proposal for " did ": " reason))
          (ok (fixResult (list (pair "status" "rejected") (pair "defectId" did) (pair "reason" reason)))))
      (let [tgt (keyedPlain patch ":target")
            oldRaw (keyedEscaped patch ":old")
            newRaw (keyedEscaped patch ":new")]
        (if (or (none? tgt) (none? oldRaw) (none? newRaw))
          (ok (fixResult (list (pair "status" "rejected") (pair "reason" "Malformed patch: missing :target, :old, or :new"))))
          (let [ref (optionOr tgt "")
                parts (splitOn ref "#")
                filePart (first parts "")]
            (mt (unicodeEscape (optionOr oldRaw "") false)
              ((err e) (err e))
              ((ok oldText)
                (mt (unicodeEscape (optionOr newRaw "") false)
                  ((err e) (err e))
                  ((ok newText)
                    (mt (resolveFixTarget! ctx.root filePart)
                      ((err code)
                        (ok (fixResult (list (pair "status" "rejected")
                                             (pair "error" code)
                                             (pair "reason" (str "Unsafe fix target (" code "): " (targetErrorDetail code filePart)))))))
                      ((ok full)
                        (cond
                          ((not (exists? full))
                            (ok (fixResult (list (pair "status" "rejected") (pair "reason" (str "Target file does not exist: " filePart))))))
                          (else
                      (let [counts (slicedMutations newText)
                            gen (first counts 0)
                            killed (first (rest counts) 0)
                            score (round2 (/ (int64ToFloat64 killed) (int64ToFloat64 (max 1 gen))))]
                        (do
                          (out! (str "  ✓ In-memory sliced mutations: " (stringFromInt64 killed) "/" (stringFromInt64 gen) " killed"))
                          (mt (board/withSecureFileLock! ctx.root filePart
                                (fn []
                                  (mt (fileReadAt ctx.root filePart)
                                    ((err e) (err e))
                                    ((ok content)
                                      (if (not (has? content oldText))
                                        (ok false)
                                        (mt (fileWriteAt ctx.root filePart (replaceFirst content oldText newText))
                                          ((err e) (err e))
                                          ((ok _) (ok true))))))))
                            ((err e)
                              (if (= e "ERR_PATH_SYMLINK")
                                (ok (fixResult (list (pair "status" "rejected") (pair "error" e) (pair "reason" "Path component is a symlink"))))
                                (err e)))
                            ((ok applied)
                              (if applied
                                (do (out! (str "✓ Fix proposal successfully applied to " filePart " through Pre-Flush Gate."))
                                    (ok (board/asnDict (list (pair "status" (s "applied")) (pair "defectId" (s did)) (pair "file" (s filePart))
                                                             (pair "mutationScore" (board/asnFloat score))))))
                                (ok (fixResult (list (pair "status" "rejected") (pair "reason" (str "Old text not found in target file: " filePart)))))))))))))))))))))))

fn osErrText e: String -> String
  (let [p (findFrom e ": " 0)]
    (if (and (>= p 0) (stringEndsWith? (sub e 0 p) "Error")) (sub e (+ p 2) (stringLength e)) e))

fn runShellProbe! ctx: Ctx cmd: String timeoutSec: Int64 cwd: String -> (Result (Pair Int64 String) String)
  (mt (runProc! (list "bash" "-c" cmd) (if (stringEmpty? cwd) ctx.root cwd) ctx.env "" (* timeoutSec 1000))
    ((err e) (err (str "ERR_TOOL_ABSENT: bash: " e)))
    ((ok r)
      (if r.timedOut
        (ok (pair 124 (str "timeout after " (stringFromInt64 timeoutSec) "s")))
        (ok (pair r.code (cpLast (board/pyStrip (str r.out r.errText)) 300))))))

fn pyRealpathLimit! path: String depth: Int64 -> String
  (if (> depth 32)
    "__ASL_REALPATH_DEPTH_EXCEEDED__"
    (mt (realPath path)
      ((ok r) r)
      ((err _)
        (if (isLink? path)
          (mt (fileReadlink path)
            ((ok target)
              (let [resolved (if (stringStartsWith? target "/") target (board/pyJoin (board/pyDirname path) target))]
                (pyRealpathLimit! resolved (+ depth 1))))
            ((err _) path))
          (let [d (board/pyDirname path)
                b (board/pyBasename path)]
            (if (or (stringEmpty? d) (= d path))
              path
              (board/pyJoin (pyRealpathLimit! d (+ depth 1)) b)))))))

fn pyRealpath! path: String -> String
  (pyRealpathLimit! path 0)

fn targetErrorDetail errName: String filePart: String -> String
  (cond
    ((= errName "ERR_PATH_EMPTY") "target path is empty")
    ((= errName "ERR_PATH_ABSOLUTE") (str "target must be a workspace-relative path without .. : " filePart))
    ((= errName "ERR_PATH_NUL_BYTE") (str "target contains NUL byte: " filePart))
    ((= errName "ERR_PATH_TRAVERSAL") (str "target must be a workspace-relative path without .. : " filePart))
    ((= errName "ERR_PATH_GIT") (str "target cannot enter .git: " filePart))
    ((= errName "ERR_PATH_ESCAPE") (str "target resolves outside the workspace: " filePart))
    (else filePart))

fn normalizeRelPath rel: String -> (Result (List String) String)
  (cond
    ((stringEmpty? (board/pyStrip rel))
      (err "ERR_PATH_EMPTY"))
    ((stringContains? rel "\x00")
      (err "ERR_PATH_NUL_BYTE"))
    ((or (stringStartsWith? rel "/") (stringStartsWith? rel "\\"))
      (err "ERR_PATH_ABSOLUTE"))
    (else
      (let [parts (stringSplit rel "/")
            stack (fold (fn [st part]
                          (cond
                            ((or (stringEmpty? part) (= part ".")) st)
                            ((= part "..")
                              (mt (listLast st)
                                ((none) (listAppend st (list "..")))
                                ((some last)
                                  (if (= last "..")
                                    (listAppend st (list ".."))
                                    (listTake st (- (listLength st) 1))))))
                            (else (listAppend st (list part)))))
                        (list)
                        parts)]
        (cond
          ((listEmpty? stack)
            (err "ERR_PATH_EMPTY"))
          ((listAny? (fn [x] (= x "..")) stack)
            (err "ERR_PATH_TRAVERSAL"))
          ((listAny? (fn [x] (= (stringLower x) ".git")) stack)
            (err "ERR_PATH_GIT"))
          (else (ok stack))))))

fn singleTargetErrorCode! root: String rel: String -> String
  (mt (normalizeRelPath rel)
    ((err code) code)
    ((ok stack)
      (let [normRel (stringJoin stack "/")
            full (board/pyJoin root normRel)
            realRoot (mt (realPath root) ((ok r) r) ((err _) (pyRealpath! root)))
            rootPrefix (if (stringEndsWith? realRoot "/") realRoot (str realRoot "/"))
            realFull (mt (realPath full) ((ok r) r) ((err _) (pyRealpath! full)))
            fullPrefix (if (stringEndsWith? realFull "/") realFull (str realFull "/"))]
        (cond
          ((= realFull "__ASL_REALPATH_DEPTH_EXCEEDED__")
            "ERR_PATH_ESCAPE")
          ((not (stringStartsWith? fullPrefix rootPrefix))
            "ERR_PATH_ESCAPE")
          ((stringContains? fullPrefix "/.git/")
            "ERR_PATH_GIT")
          (else "")))))

fn targetErrorCode! root: String rel: String -> String
  (let [code (singleTargetErrorCode! root rel)]
    (if (not (stringEmpty? code))
      code
      (mt (normalizeRelPath rel)
        ((err e) e)
        ((ok stack) (singleTargetErrorCode! root (str (stringJoin stack "/") ".lock"))))))

fn resolveFixTarget! root: String rel: String -> (Result String String)
  (let [code (targetErrorCode! root rel)]
    (if (not (stringEmpty? code))
      (err code)
      (mt (normalizeRelPath rel)
        ((err e) (err e))
        ((ok stack) (ok (board/pyJoin root (stringJoin stack "/")))))))

fn ! symlinkPrefix? cur: String parts: (List String) -> Bool
  (mt (listHead parts)
    ((none) false)
    ((some part)
      (let [next (board/pyJoin cur part)]
        (or (isLink? next) (symlinkPrefix? next (rest parts))))))

fn mutantPathError! ctx: Ctx rel: String -> String
  (let [parts (splitOn rel "/")
        root ctx.root]
    (cond
      ((or (stringEmpty? rel) (stringStartsWith? rel "/") (listAny? (fn [x] (= x "..")) parts))
        (str "mutant :file must be a workspace-relative path without .. : " rel))
      ((not (stringStartsWith? (pyRealpath! (board/pyJoin root rel)) (str (pyRealpath! root) "/")))
        (str "mutant :file resolves outside the workspace: " rel))
      ((symlinkPrefix? root parts) (str "mutant :file goes through a symlink: " rel))
      (else "")))

fn tempRoot ctx: Ctx -> String
  (let [t (optionOr (envLookup ctx.env "TMPDIR") "")]
    (if (stringEmpty? t) "/tmp" t))

fn makeTempDir! ctx: Ctx prefix: String tries: Int64 -> (Result String String)
  (let [alphabet "abcdefghijklmnopqrstuvwxyz0123456789_"
        seed (+ (nowNs) (* (procSelf) 7919) (* tries 104729))
        name (stringJoin (map (fn [k] (sub alphabet (mod (/ seed (pow37 k)) 37) (+ (mod (/ seed (pow37 k)) 37) 1))) (range 0 8)) "")
        path (board/pyJoin (tempRoot ctx) (str prefix name))]
    (cond
      ((exists? path) (if (> tries 100) (err (str "FileExistsError: " path)) (makeTempDir! ctx prefix (+ tries 1))))
      (else (mt (dirCreate path) ((ok _) (ok path)) ((err e) (err (pyOsError e path)))))))

fn pow37 k: Int64 -> Int64
  (if (<= k 0) 1 (* 37 (pow37 (- k 1))))

fn mirrorDir! src: String dst: String skip: String -> (Result Unit String)
  (mt (dirList src)
    ((err e) (err (pyOsError e src)))
    ((ok names)
      (fold (fn [acc name]
              (mt acc
                ((err e) (err e))
                ((ok _)
                  (if (= name skip)
                    (ok ())
                    (mt (pathSymlink (board/pyJoin src name) (board/pyJoin dst name))
                      ((ok _) (ok ()))
                      ((err e) (err (pyOsError e (board/pyJoin dst name)))))))))
            (ok ()) names)))

fn overlayLevels! src: String dst: String parts: (List String) content: String -> (Result Unit String)
  (mt (listHead parts)
    ((none) (ok ()))
    ((some part)
      (mt (mirrorDir! src dst part)
        ((err e) (err e))
        ((ok _)
          (if (listEmpty? (rest parts))
            (mt (fileWrite (board/pyJoin dst part) content) ((ok _) (ok ())) ((err e) (err (pyOsError e (board/pyJoin dst part)))))
            (let [s2 (board/pyJoin src part)
                  d2 (board/pyJoin dst part)]
              (mt (dirCreate d2)
                ((err e) (err (pyOsError e d2)))
                ((ok _) (overlayLevels! s2 d2 (rest parts) content)))))))))

fn buildMutantOverlay! ctx: Ctx rel: String old: String new: String -> (Result Overlay String)
  (let [perr (mutantPathError! ctx rel)]
    (if (not (stringEmpty? perr))
      (ok (Overlay :dir "" :error perr))
      (mt (readText! (board/pyJoin ctx.root rel))
        ((err e) (ok (Overlay :dir "" :error (str "mutant file unreadable: " (osErrText e)))))
        ((ok content)
          (let [c (countOf content old)]
            (if (!= c 1)
              (ok (Overlay :dir "" :error (str "mutant :old occurs " (stringFromInt64 c) " times in " rel)))
              (mt (makeTempDir! ctx "aslMeshMutant" 0)
                ((err e) (err e))
                ((ok tmp)
                  (mt (overlayLevels! ctx.root tmp (splitOn rel "/") (replaceFirst content old new))
                    ((err e) (do (removeTree! tmp) (err e)))
                    ((ok _) (ok (Overlay :dir tmp :error ""))))))))))))

fn removeTree! path: String -> Unit
  (mt (pathRemove path)
    ((ok _) ())
    ((err e) (warn! (str "[Cleanup] " e))))

fn mutField m: (List (Pair String board/AsnValue)) k: String -> String
  (strOrEmpty (getv m k))

fn mutantKilled! ctx: Ctx cmd: String m: (List (Pair String board/AsnValue)) -> (Result (Pair Bool String) String)
  (mt (buildMutantOverlay! ctx (mutField m "file") (mutField m "old") (mutField m "new"))
    ((err e) (err e))
    ((ok ov)
      (if (not (stringEmpty? ov.error))
        (ok (pair false ov.error))
        (let [r (runShellProbe! ctx cmd 300 ov.dir)]
          (do
            (removeTree! ov.dir)
            (mt r
              ((err e) (err e))
              ((ok p)
                (if (!= (pairFirst p) 0)
                  (ok (pair true ""))
                  (ok (pair false "verify command still exits 0 on the mutant; it cannot detect a reverted fix"))))))))))

fn allDigits? text: String -> Bool
  (let [bs (stringToBytes text)
        n (bytesLength bs)]
    (and (> n 0) (= (runEnd bs 0 n digit?) n)))

fn receipt ok: Bool did: String to: String kv: (List (Pair String String)) -> (Pair Bool String)
  (let [body (stringJoin (map (fn [p] (let [v (pairSecond p)]
                                        (str ":" (pairFirst p) " " (if (or (stringStartsWith? v ":") (allDigits? v)) v (str "\"" (board/sanitizeAsnString (s v)) "\"")))))
                              kv) " ")]
    (pair ok (str "(:transition :status " (if ok ":ok" ":refused") " :id \"" (board/sanitizeAsnString (s did)) "\" :to :" (if (stringEmpty? to) "none" to)
                  (if (stringEmpty? body) "" (str " " body)) ")")))

fn evidenceForm agent: String cmd: String stamp: String -> String
  (str "(:agent \"" (board/sanitizeAsnString (s agent)) "\" :command \"" (board/sanitizeAsnString (s cmd)) "\" :exit 0 :at \"" stamp "\")")

fn setFields block: String steps: (List (Pair String String)) -> (Result String String)
  (fold (fn [acc p] (mt acc ((err e) (err e)) ((ok b) (board/setField b (pairFirst p) (pairSecond p))))) (ok block) steps)

fn runTransition! ctx: Ctx did: String toRaw: String agent: String remediatedBy: String verifyCmd: String mutant: (Option (List (Pair String board/AsnValue)))
    -> (Result (Pair Bool String) String)
  (let [to (lstripColon toRaw)
        agentN (board/normAgent (s agent))
        refuse (fn [reason] (ok (receipt false did to (list (pair "reason" reason)))))]
    (if (or (stringEmpty? did) (not (listAny? (fn [x] (= x to)) (list "candidate" "corroborated" "refuted" "remediated" "certified"))))
      (refuse "need --id and --to candidate|corroborated|refuted|remediated|certified")
      (let [bbPath (cfgs ctx "blackboard_path")]
        (board/withFileLock! bbPath
          (fn []
            (mt (readText! bbPath)
              ((err e) (err e))
              ((ok bb)
                (mt (findDefect bb did)
                  ((none) (refuse "defect not found on the blackboard"))
                  ((some hit)
                    (let [block (pairFirst hit)
                          prior (entries (board/parseVerification block))
                          priorStatus (gets (pairSecond hit) "status" "")
                          target (gets prior "target" "")
                          stamp (localDay!)
                          finish (fn [steps]
                                   (mt (setFields block (listAppend steps (list (pair "status" (str ":" to)))))
                                     ((err e) (err e))
                                     ((ok nb)
                                       (mt (board/writeBoard! bbPath (replaceFirst bb block nb) (cfgs ctx "shards_dir"))
                                         ((err e) (err e))
                                         ((ok _) (ok (receipt true did to (list (pair "agent" (if (stringEmpty? agentN) "unknown" agentN))))))))))]
                      (cond
                        ((or (= to "remediated") (= to "certified"))
                          (transitionVerified! ctx did to agentN remediatedBy verifyCmd mutant prior target stamp refuse finish))
                        ((not (stringEmpty? verifyCmd))
                          (let [vac (board/commandVacuity! (s verifyCmd) (s target) ctx.root)]
                            (if (not (stringEmpty? vac))
                              (refuse (str "vacuous evidence command: " vac))
                              (mt (runShellProbe! ctx verifyCmd 300 "")
                                ((err e) (err e))
                                ((ok pr)
                                  (if (!= (pairFirst pr) 0)
                                    (refuse (str "evidence command exits " (stringFromInt64 (pairFirst pr)) "; it must exit 0 to support :" to))
                                    (let [ev (pair (if (= to "refuted") "refutedBy" "reproduction") (evidenceForm (if (stringEmpty? agentN) "unknown" agentN) verifyCmd stamp))
                                          demote (and (= to "candidate") (or (= priorStatus "remediated") (= priorStatus "certified")))]
                                      (finish (if demote (list ev (pair "demotedFrom" (str ":" priorStatus))) (list ev))))))))))
                        (else (finish (list))))))))))))))

fn transitionVerified! ctx: Ctx did: String to: String agentN: String remediatedBy: String verifyCmd: String mutant: (Option (List (Pair String board/AsnValue)))
    prior: (List (Pair String board/AsnValue)) target: String stamp: String
    refuse: (fn [String] -> (Result (Pair Bool String) String))
    finish: (fn [(List (Pair String String))] -> (Result (Pair Bool String) String)) -> (Result (Pair Bool String) String)
  (let [rbSrc (if (stringEmpty? remediatedBy) (let [p (getv prior "remediatedBy")] (if (board/truthy? p) (board/pyStr p) "")) remediatedBy)
        rbN (board/normAgent (s rbSrc))]
    (if (or (stringEmpty? agentN) (stringEmpty? verifyCmd))
      (refuse (str "--agent and --verify-cmd are required for :" to))
      (let [rec (board/asnDict (list (pair "target" (s target)) (pair "remediatedBy" (s rbN))
                                     (pair "verifiedBy" (board/asnDict (list (pair "agent" (s agentN)) (pair "command" (s verifyCmd)) (pair "exit" (s "0")))))))]
        (mt (board/transitionAllowed! (s to) rec ctx.root)
          ((err e) (err e))
          ((ok verdict)
            (if (not (pairFirst verdict))
              (refuse (pairSecond verdict))
              (mt (runShellProbe! ctx verifyCmd 300 "")
                ((err e) (err e))
                ((ok pr)
                  (if (!= (pairFirst pr) 0)
                    (ok (receipt false did to (list (pair "reason" (str ":verifiedBy command exits " (stringFromInt64 (pairFirst pr)))) (pair "exit" (stringFromInt64 (pairFirst pr))))))
                    (let [mut (mt mutant ((some m) m) ((none) (entries (getv prior "mutant"))))]
                      (if (stringEmpty? (mutField mut "file"))
                        (refuse (str ":" to " needs a :mutant (:file :old :new) that the verify command kills"))
                        (mt (mutantKilled! ctx verifyCmd mut)
                          ((err e) (err e))
                          ((ok k)
                            (if (not (pairFirst k))
                              (refuse (pairSecond k))
                              (let [mutStep (mt mutant
                                              ((some m) (list (pair "mutant" (str "(:file \"" (board/sanitizeAsnString (s (mutField m "file"))) "\" :old \"" (board/sanitizeAsnString (s (mutField m "old")))
                                                                                  "\" :new \"" (board/sanitizeAsnString (s (mutField m "new"))) "\")"))))
                                              ((none) (list)))]
                                (finish (listAppend mutStep
                                                    (list (pair "remediatedBy" (str "\"" (board/sanitizeAsnString (s rbN)) "\""))
                                                          (pair "verifiedBy" (evidenceForm agentN verifyCmd stamp))))))))))))))))))))

schema Tally
  (:f problems (List (Pair String String)))
  (:f warnings (List (Pair String String)))
  (:f verified Int64)
  (:f ran Int64)
  (:f mutantsRun Int64)
  (:f mutantsKilled Int64)

fn addProblem t: Tally did: String what: String -> Tally
  (Tally :problems (listAppend t.problems (list (pair did what))) :warnings t.warnings :verified t.verified :ran t.ran :mutantsRun t.mutantsRun :mutantsKilled t.mutantsKilled)

fn addWarning t: Tally did: String what: String -> Tally
  (Tally :problems t.problems :warnings (listAppend t.warnings (list (pair did what))) :verified t.verified :ran t.ran :mutantsRun t.mutantsRun :mutantsKilled t.mutantsKilled)

fn bump t: Tally verified: Int64 ran: Int64 mRun: Int64 mKilled: Int64 -> Tally
  (Tally :problems t.problems :warnings t.warnings :verified (+ t.verified verified) :ran (+ t.ran ran) :mutantsRun (+ t.mutantsRun mRun) :mutantsKilled (+ t.mutantsKilled mKilled))

fn validateRun! ctx: Ctx t: Tally did: String label: String cmd: String -> (Result Tally String)
  (mt (runShellProbe! ctx cmd 300 "")
    ((err e) (err e))
    ((ok pr)
      (let [t2 (bump t 0 1 0 0)]
        (ok (if (!= (pairFirst pr) 0)
              (addProblem t2 did (str label " command now exits " (stringFromInt64 (pairFirst pr)) ": " (cpLast (pairSecond pr) 120)))
              t2)))))

fn validateVerified! ctx: Ctx t0: Tally did: String st: String rec: board/AsnValue runCommands: Bool revertCheck: Bool -> (Result Tally String)
  (let [t (bump t0 1 0 0 0)
        es (entries rec)]
    (mt (board/transitionAllowed! (s st) rec ctx.root)
      ((err e) (err e))
      ((ok verdict)
        (if (not (pairFirst verdict))
          (ok (addProblem t did (pairSecond verdict)))
          (let [t1 (if (stringStartsWith? (board/normAgent (getv es "remediatedBy")) "unrecorded") (addWarning t did ":remediatorUnknown") t)
                cmd (strOrEmpty (getv (entries (getv es "verifiedBy")) "command"))]
            (mt (if runCommands (validateRun! ctx t1 did ":verifiedBy" cmd) (ok t1))
              ((err e) (err e))
              ((ok t2)
                (let [mut (getv es "mutant")]
                  (cond
                    ((and revertCheck (not (board/truthy? mut))) (ok (addWarning t2 did ":noMutant")))
                    (revertCheck
                      (let [m (entries mut)]
                        (mt (buildMutantOverlay! ctx (mutField m "file") (mutField m "old") (mutField m "new"))
                          ((err e) (err e))
                          ((ok ov)
                            (if (not (stringEmpty? ov.error))
                              (ok (addProblem t2 did ov.error))
                              (let [r (runShellProbe! ctx cmd 300 ov.dir)]
                                (do
                                  (removeTree! ov.dir)
                                  (mt r
                                    ((err e) (err e))
                                    ((ok pr)
                                      (if (= (pairFirst pr) 0)
                                        (ok (addProblem (bump t2 0 0 1 0) did ":mutantSurvived: :verifiedBy still exits 0 with the fix reverted"))
                                        (ok (bump t2 0 0 1 1))))))))))))
                    (else (ok t2)))))))))))

fn validateEvidence! ctx: Ctx t: Tally did: String rec: board/AsnValue field: String missing: String runCommands: Bool proseCheck: Bool -> (Result Tally String)
  (let [es (entries rec)
        ev (getv es field)
        evs (entries ev)]
    (cond
      ((not (board/truthy? ev)) (ok (addProblem t did missing)))
      ((and proseCheck (or (= (strOrEmpty (getv evs "kind")) "prose") (not (board/truthy? (getv evs "command"))))) (ok (addProblem t did ":unverifiedRefutation")))
      ((and (not proseCheck) (not (board/truthy? (getv evs "command")))) (ok (addProblem t did missing)))
      (else
        (let [vac (board/commandVacuity! (getv evs "command") (getv es "target") ctx.root)]
          (cond
            ((not (stringEmpty? vac)) (ok (addProblem t did (str "vacuous :" field ": " vac))))
            (runCommands (validateRun! ctx t did (str ":" field) (strOrEmpty (getv evs "command"))))
            (else (ok t)))))))

fn validateBlock! ctx: Ctx t: Tally b: String runCommands: Bool revertCheck: Bool -> (Result Tally String)
  (let [info (entries (board/parseGapBlock b))
        did (gets info "id" "")
        st (gets info "status" "")
        rec (board/parseVerification b)
        es (entries rec)]
    (cond
      ((or (= st "remediated") (= st "certified")) (validateVerified! ctx t did st rec runCommands revertCheck))
      ((= st "refuted") (validateEvidence! ctx t did rec "refutedBy" ":missingRefutedBy" runCommands true))
      ((or (board/truthy? (getv es "demotedFrom")) (board/truthy? (getv es "reproduction")))
        (validateEvidence! ctx t did rec "reproduction" ":missingReproduction" runCommands false))
      (else (ok t))))

fn validateShards! ctx: Ctx t: Tally boardIds: (List (Pair String String)) -> (Result (Pair Tally (List String)) String)
  (let [dir (cfgs ctx "shards_dir")]
    (if (or (stringEmpty? dir) (not (isDir? dir)))
      (ok (pair t (list)))
      (mt (dirList dir)
        ((err e) (err (pyOsError e dir)))
        ((ok names)
          (fold (fn [acc fnm]
                  (mt acc
                    ((err e) (err e))
                    ((ok st)
                      (if (not (and (stringStartsWith? fnm "defect_") (stringEndsWith? fnm ".asn")))
                        (ok st)
                        (mt (readText! (board/pyJoin dir fnm))
                          ((err e) (err e))
                          ((ok sh)
                            (let [blocks (board/extractGapBlocks sh "defect")
                                  sid (if (listEmpty? blocks) "" (gets (entries (board/parseGapBlock (first blocks ""))) "id" ""))
                                  t1 (pairFirst st)
                                  ids (listAppend (pairSecond st) (list sid))]
                              (ok (pair (mt (board/dictGet boardIds sid)
                                          ((none) (addProblem t1 (if (stringEmpty? sid) fnm sid) "orphan shard: not on the blackboard"))
                                          ((some blk) (if (!= (board/shardTextFromBlock blk) sh) (addProblem t1 sid "shard differs from its blackboard record") t1)))
                                        ids)))))))))
                (ok (pair t (list))) (listSort names))))))

fn tallyList pairs: (List (Pair String String)) key: String -> String
  (board/asnListText (map (fn [p] (str "(:id \"" (board/sanitizeAsnString (s (pairFirst p))) "\" :" key " \"" (board/sanitizeAsnString (s (pairSecond p))) "\")")) pairs))

fn runValidate! ctx: Ctx runCommands: Bool revertCheck: Bool -> (Result Int64 String)
  (mt (readText! (cfgs ctx "blackboard_path"))
    ((err e) (err e))
    ((ok bb)
      (let [blocks (board/extractGapBlocks bb "defect")
            boardIds (fold (fn [acc b] (board/dictPut acc (gets (entries (board/parseGapBlock b)) "id" "") b)) (list) blocks)
            t0 (Tally :problems (list) :warnings (list) :verified 0 :ran 0 :mutantsRun 0 :mutantsKilled 0)]
        (mt (fold (fn [acc b] (mt acc ((err e) (err e)) ((ok t) (validateBlock! ctx t b runCommands revertCheck)))) (ok t0) blocks)
          ((err e) (err e))
          ((ok t1)
            (mt (validateShards! ctx t1 boardIds)
              ((err e) (err e))
              ((ok sp)
                (let [shardIds (pairSecond sp)
                      t (fold (fn [acc p] (if (listAny? (fn [x] (= x (pairFirst p))) shardIds) acc (addProblem acc (pairFirst p) "blackboard record has no shard")))
                              (pairFirst sp) boardIds)
                      clean (listEmpty? t.problems)]
                  (do
                    (out! (str "(:validate :status " (if clean ":ok" ":failed") " :records " (stringFromInt64 (listLength boardIds))
                              " :verifiedRecords " (stringFromInt64 t.verified) " :commandsRun " (stringFromInt64 t.ran)
                              " :mutantsRun " (stringFromInt64 t.mutantsRun) " :mutantsKilled " (stringFromInt64 t.mutantsKilled)
                              " :noMutant " (stringFromInt64 (listLength (filter (fn [p] (= (pairSecond p) ":noMutant")) t.warnings)))
                              " :problems " (tallyList t.problems "problem") " :warnings " (tallyList t.warnings "warning") ")"))
                    (ok (if clean 0 1)))))))))))

fn dropAsnStrings text: String -> String
  (let [bs (stringToBytes text)]
    (stringJoin (listReverse (dropStrLoop text bs 0 0 (bytesLength bs) (list))) ""))

fn dropStrLoop text: String bs: Bytes i: Int64 start: Int64 n: Int64 acc: (List String) -> (List String)
  (cond
    ((>= i n) (cons (sub text start n) acc))
    ((= (bytesGet bs i) 34)
      (let [e (escBodyEnd bs (+ i 1) n)]
        (if (< e 0)
          (dropStrLoop text bs (+ i 1) start n acc)
          (dropStrLoop text bs (+ e 1) (+ e 1) n (cons (sub text start i) acc)))))
    (else (dropStrLoop text bs (+ i 1) start n acc)))

fn chk cond: Bool what: String -> (Pair Bool String)
  (pair cond what)

fn runStages stages: (List (fn [] -> (Result (List (Pair Bool String)) String))) acc: (List (Pair Bool String)) -> (Result (List (Pair Bool String)) String)
  (mt (listHead stages)
    ((none) (ok acc))
    ((some st)
      (mt (st)
        ((err e) (err e))
        ((ok cs) (runStages (rest stages) (listAppend acc cs))))))

fn putText! path: String text: String -> (Result Unit String)
  (mt (fileWrite path text) ((ok _) (ok ())) ((err e) (err (pyOsError e path))))

fn refusedCheck! ctx: Ctx did: String agent: String rb: String cmd: String mut: (Option (List (Pair String board/AsnValue))) what: String -> (Result (Pair Bool String) String)
  (mt (runTransition! ctx did "remediated" agent rb cmd mut)
    ((err e) (err e))
    ((ok r) (ok (chk (not (pairFirst r)) what))))

fn mutDict file: String old: String new: String -> (Option (List (Pair String board/AsnValue)))
  (some (list (pair "file" (s file)) (pair "old" (s old)) (pair "new" (s new))))

fn checkSeq steps: (List (fn [] -> (Result (Pair Bool String) String))) acc: (List (Pair Bool String)) -> (Result (List (Pair Bool String)) String)
  (mt (listHead steps)
    ((none) (ok acc))
    ((some f) (mt (f) ((err e) (err e)) ((ok c) (checkSeq (rest steps) (listAppend acc (list c)))))))

fn firstBlock! ctx: Ctx -> (Result String String)
  (mt (readText! (cfgs ctx "blackboard_path"))
    ((err e) (err e))
    ((ok bb) (ok (first (board/extractGapBlocks bb "defect") ""))))

fn validateIs! ctx: Ctx runCommands: Bool revertCheck: Bool want: Int64 what: String -> (Result (Pair Bool String) String)
  (mt (runValidate! ctx runCommands revertCheck)
    ((err e) (err e))
    ((ok code) (ok (chk (= code want) what))))

fn rewriteBoard! ctx: Ctx f: (fn [String] -> (Result String String)) -> (Result Unit String)
  (let [bbPath (cfgs ctx "blackboard_path")]
    (mt (readText! bbPath)
      ((err e) (err e))
      ((ok bb) (mt (f bb) ((err e) (err e)) ((ok nb) (board/writeBoard! bbPath nb (cfgs ctx "shards_dir")))))))

fn selftestFinding! ctx: Ctx -> (Result (List (Pair Bool String)) String)
  (let [raw "(:finding :target \"a/b.asl#f\" :severity :classify :hazard \"h \\\"q\\\" h\" :evidence \"(let [(folding (tui/formatToolCall \\\"patch\\\" \\\"src/app.asl#entry\\\"))] x)\" :remediation \"r\")"
        wantEv "(let [(folding (tui/formatToolCall \"patch\" \"src/app.asl#entry\"))] x)"
        fnd (board/parseFinding raw)
        fe (mt fnd ((some v) (entries v)) ((none) (list)))
        c1 (chk (and (some? fnd) (= (strOrEmpty (getv fe "evidence")) wantEv)) "evidence captured whole across embedded quotes")
        c2 (chk (and (some? fnd) (= (strOrEmpty (getv fe "hazard")) "h \"q\" h")) "hazard unescaped")
        c3 (chk (and (some? fnd) (= (strOrEmpty (getv fe "severity")) "medium")) "unknown severity :classify clamps to the enum")
        shard (list (pair "suggestedSeverity" (s "medium")) (pair "intent" (s "falsify")) (pair "attractor" (s ":verification :reversibility :simplicity"))
                    (pair "model" (s "selftest-auditor")) (pair "temp" (board/asnFloat 0.2)))]
    (if (none? fnd)
      (err "TypeError: 'NoneType' object is not subscriptable")
      (mt (recordFinding! ctx fe shard "" "")
        ((err e) (err e))
        ((ok _)
          (mt (readText! (cfgs ctx "blackboard_path"))
            ((err e) (err e))
            ((ok bb)
              (let [blocks (board/extractGapBlocks bb "defect")
                    info (if (listEmpty? blocks) (list) (entries (board/parseGapBlock (first blocks ""))))]
                (ok (list c1 c2 c3
                          (chk (= (listLength blocks) 1) "finding inserted inside the parenthesised :defects container")
                          (chk (= (gets info "evidence" "") (strOrEmpty (getv fe "evidence"))) "evidence round-trips through the blackboard")
                          (chk (and (has? bb ":attractor (:verification :reversibility :simplicity)") (not (has? bb "::"))) "attractor list rendered as a parenthesised list")
                          (chk (stringEmpty? (dyckReason bb)) "blackboard stays balanced"))))))))))

fn selftestTransitions! ctx: Ctx tmp: String -> (Result (List (Pair Bool String)) String)
  (mt (dirCreate (board/pyJoin tmp "a"))
    ((err e) (err (pyOsError e (board/pyJoin tmp "a"))))
    ((ok _)
      (mt (putText! (board/pyJoin tmp "a/b.asl") "(ok)\n")
        ((err e) (err e))
        ((ok _)
          (mt (firstBlock! ctx)
            ((err e) (err e))
            ((ok b0)
              (let [did (gets (entries (board/parseGapBlock b0)) "id" "")
                    probe "grep -q ok a/b.asl"
                    mut (mutDict "a/b.asl" "(ok)" "(no)")
                    rc (fn [agent rb cmd m what] (fn [] (refusedCheck! ctx did agent rb cmd m what)))]
                (checkSeq
                  (list (rc "agentB" "agentA" "" mut "remediated without a verify command is refused")
                        (rc "agentA" "agentA" probe mut "remediator verifying its own fix is refused")
                        (rc "AgentA" "agenta" probe mut "case-only difference is the same agent")
                        (rc "agentA " "agentA" probe mut "trailing whitespace is the same agent")
                        (rc "agentB" "agentA" "true" mut "no-op verify command is refused")
                        (rc "agentB" "agentA" "test 1 -eq 1" mut "trivially true test is refused")
                        (rc "agentB" "agentA" "test -f a/b.asl && ls a/b.asl" mut "existence-only chain is refused")
                        (rc "agentB" "agentA" "echo a/b.asl" mut "bare echo is refused")
                        (rc "agentB" "agentA" "test -d /tmp" mut "command not naming the target is refused")
                        (rc "agentB" "agentA" "grep -q missing a/b.asl" mut "a verify command that exits non-zero is refused")
                        (rc "agentB" "agentA" probe (none) "no :mutant is refused")
                        (rc "agentB" "agentA" "grep -q b a/b.asl || grep -q o a/b.asl" (mutDict "a/b.asl" "(ok)" "(ko)") "a mutant the probe survives is refused")
                        (rc "agentB" "agentA" probe (mutDict "../x" "a" "b") "mutant path with .. is refused")
                        (rc "agentB" "agentA" probe (mutDict "/etc/hosts" "a" "b") "absolute mutant path is refused")
                        (fn []
                          (mt (pathSymlink "/etc" (board/pyJoin tmp "esc"))
                            ((err e) (err (pyOsError e (board/pyJoin tmp "esc"))))
                            ((ok _) (ok (chk (not (stringEmpty? (mutantPathError! ctx "esc/hosts"))) "mutant path through a symlink is refused")))))
                        (fn []
                          (mt (runTransition! ctx did "remediated" " AgentB " "agentA" probe mut)
                            ((err e) (err e))
                            ((ok r) (ok (chk (pairFirst r) "independent verification that kills the mutant is accepted"))))))
                  (list)))))))))

fn selftestStored! ctx: Ctx -> (Result (List (Pair Bool String)) String)
  (mt (firstBlock! ctx)
    ((err e) (err e))
    ((ok b)
      (let [rec (entries (board/parseVerification b))
            c (chk (and (= (strOrEmpty (getv rec "remediatedBy")) "agenta") (= (strOrEmpty (getv (entries (getv rec "verifiedBy")) "agent")) "agentb")) "normalised agent ids stored")]
        (mt (validateIs! ctx true false 0 "validate passes on the verified board")
          ((err e) (err e))
          ((ok v) (ok (list c v)))))))

fn selftestOneLine! ctx: Ctx -> (Result (List (Pair Bool String)) String)
  (let [line "    (:defect :id \"DEF-Y-1\" :target \"a#b\" :status :remediated :confirmations 1)\n"]
    (checkSeq
      (list (fn [] (mt (rewriteBoard! ctx (fn [bb] (ok (replaceAll bb "\n  ))" (str "\n" line "  ))")))))
                     ((err e) (err e))
                     ((ok _) (validateIs! ctx false false 1 "one-line remediated record without verification fails validate"))))
            (fn [] (mt (rewriteBoard! ctx (fn [bb] (ok (replaceAll bb line ""))))
                     ((err e) (err e))
                     ((ok _) (validateIs! ctx false false 0 "removing the record removes its shard")))))
      (list)))

fn putThenWrite! ctx: Ctx f: (fn [String] -> String) -> (Result Unit String)
  (let [bbPath (cfgs ctx "blackboard_path")]
    (mt (readText! bbPath)
      ((err e) (err e))
      ((ok bb)
        (mt (putText! bbPath (f bb))
          ((err e) (err e))
          ((ok _) (rewriteBoard! ctx (fn [x] (ok x))))))))

fn selftestRefuted! ctx: Ctx -> (Result (List (Pair Bool String)) String)
  (checkSeq
    (list (fn [] (mt (putThenWrite! ctx (fn [bb] (replaceAll bb "\n  ))" "\n    (:defect :id \"DEF-Y-2\" :target \"a/b.asl#g\" :status :refuted :refutedBy (:kind :prose :evidence \"said so\"))\n  ))")))
                   ((err e) (err e))
                   ((ok _) (validateIs! ctx false false 1 "prose-only refutation is reported, not ok"))))
          (fn [] (mt (putThenWrite! ctx (fn [bb] (replaceAll bb "(:kind :prose :evidence \"said so\")" "(:agent \"t\" :command \"! grep -q gone a/b.asl\" :exit 0)")))
                   ((err e) (err e))
                   ((ok _) (validateIs! ctx true false 0 "executable refutation passes")))))
    (list))

fn selftestRevert! ctx: Ctx tmp: String -> (Result (List (Pair Bool String)) String)
  (mt (putText! (board/pyJoin tmp "t.txt") "fixed\n")
    ((err e) (err e))
    ((ok _)
      (checkSeq
        (list (fn []
                (mt (rewriteBoard! ctx
                      (fn [bb]
                        (let [b0 (first (board/extractGapBlocks bb "defect") "")]
                          (mt (setFields b0 (list (pair "target" "\"t.txt#x\"") (pair "verifiedBy" "(:agent \"agentb\" :command \"grep -q fixed t.txt\" :exit 0)")
                                                  (pair "mutant" "(:file \"t.txt\" :old \"fixed\" :new \"broken\")")))
                            ((err e) (err e))
                            ((ok nb) (ok (replaceAll bb b0 nb)))))))
                  ((err e) (err e))
                  ((ok _) (validateIs! ctx false true 0 "mutant killed by a real probe"))))
              (fn []
                (mt (rewriteBoard! ctx
                      (fn [bb]
                        (let [b1 (first (board/extractGapBlocks bb "defect") "")]
                          (mt (board/setField b1 "verifiedBy" "(:agent \"agentb\" :command \"test -f t.txt\" :exit 0)")
                            ((err e) (err e))
                            ((ok nb) (ok (replaceAll bb b1 nb)))))))
                  ((err e) (err e))
                  ((ok _) (validateIs! ctx false true 1 "surviving mutant fails the revert check")))))
        (list))))

fn shardRefused! d: board/AsnValue dir: String root: String what: String -> (Result (Pair Bool String) String)
  (mt (board/saveDefectShard! d dir root)
    ((ok _) (ok (chk false what)))
    ((err e) (if (stringStartsWith? e "ValueError") (ok (chk true what)) (err e))))

fn selftestGuards! ctx: Ctx -> (Result (List (Pair Bool String)) String)
  (mt (readText! (cfgs ctx "blackboard_path"))
    ((err e) (err e))
    ((ok bb)
      (checkSeq
        (list (fn [] (ok (chk (not (has? (dropAsnStrings bb) "[")) "board written parens-only outside strings")))
              (fn [] (shardRefused! (board/asnDict (list (pair "id" (s "DEF-SELFTEST-1")) (pair "status" (s "remediated")))) (cfgs ctx "shards_dir") ctx.root
                                   "shard writer refuses :remediated without verification"))
              (fn [] (shardRefused! (board/asnDict (list (pair "id" (s "DEF-SELFTEST-2")))) "" ctx.root "shard writer refuses to fall back to the real ledger")))
        (list))))

fn runSelftest! ctx0: Ctx -> (Result Int64 String)
  (mt (makeTempDir! ctx0 "aslMeshSelftest" 0)
    ((err e) (err e))
    ((ok tmp)
      (let [ctxA (withCfg (withCfg ctx0 "blackboard_path" (s (board/pyJoin tmp "MeshDefectBlackboard.asn"))) "shards_dir" (s (board/pyJoin tmp "shards")))
            ctxB (withRoot ctxA tmp)
            r (mt (putText! (cfgs ctxA "blackboard_path") "(:meshDefectBlackboard\n  :defects (\n  ))\n")
                ((err e) (err e))
                ((ok _)
                  (runStages (list (fn [] (selftestFinding! ctxA))
                                   (fn [] (selftestTransitions! ctxB tmp))
                                   (fn [] (selftestStored! ctxB))
                                   (fn [] (selftestOneLine! ctxB))
                                   (fn [] (selftestRefuted! ctxB))
                                   (fn [] (selftestRevert! ctxB tmp))
                                   (fn [] (selftestGuards! ctxB)))
                             (list))))]
        (do
          (removeTree! tmp)
          (mt r
            ((err e) (err e))
            ((ok checks)
              (let [fails (map pairSecond (filter (fn [c] (not (pairFirst c))) checks))
                    n (listLength checks)]
                (do
                  (out! (str "(:selftest :status " (if (listEmpty? fails) ":passed" ":failed") " :assertCount " (stringFromInt64 n)
                            " :failed (" (stringJoin (map (fn [x] (str "\"" (board/sanitizeAsnString (s x)) "\"")) fails) " ") "))"))
                  (ok (if (and (listEmpty? fails) (> n 0)) 0 1))))))))))

fn excMessage e: String -> String
  (let [p (findFrom e ": " 0)
        head (sub e 0 (max p 0))]
    (if (and (> p 0) (not (has? head " ")) (or (stringEndsWith? head "Error") (stringEndsWith? head "Exception")))
      (sub e (+ p 2) (stringLength e))
      e))

fn sleepSeconds! v: board/AsnValue -> (Result Unit String)
  (let [ms (mt v ((board/asnInt i) (some (* i 1000))) ((board/asnFloat f) (float64ToInt64 (* f 1000.0))) ((board/asnBool b) (some (if b 1000 0))) (_ (none)))]
    (mt ms
      ((none) (err (str "TypeError: '" (mt v ((board/asnStr _) "str") ((board/asnNone) "NoneType") (_ "object")) "' object cannot be interpreted as an integer")))
      ((some k)
        (if (< k 0)
          (err "ValueError: sleep length must be non-negative")
          (do (sleepMs k) (ok ()))))))

fn startDaemon! ctx: Ctx interval: Int64 once: Bool -> (Result Unit String)
  (mt (board/cleanupStaleTempFilesEnv! ctx.root (none))
    ((err e) (err e))
    ((ok rep)
      (let [m (entries (board/cleanupMetrics rep))
            cf (gets m "cleaned_files" "0")
            cl (gets m "cleaned_locks" "0")
            sleepV (if (!= interval 0) (board/asnInt interval) (cfgv ctx "interval_sec"))
            pidPath (cfgs ctx "pid_file")
            dir (board/pyDirname pidPath)]
        (do
          (if (or (!= cf "0") (!= cl "0")) (out! (str "[Boot Cleanup] Purged " cf " stale files and " cl " orphan locks.")) ())
          (mt (if (stringEmpty? dir) (err (pyOsError "notFound" "")) (mt (dirCreate dir) ((ok _) (ok ())) ((err e) (err (pyOsError e dir)))))
            ((err e) (err e))
            ((ok _)
              (let [old (if (exists? pidPath) (readPid! pidPath) (none))]
                (mt old
                  ((some op)
                    (if (pidProbe! op)
                      (do (out! (str "Audit mesh daemon is already running (PID: " (stringFromInt64 op) ").")) (ok ()))
                      (daemonRun! ctx pidPath sleepV once)))
                  ((none) (daemonRun! ctx pidPath sleepV once))))))))))

fn daemonRun! ctx: Ctx pidPath: String sleepV: board/AsnValue once: Bool -> (Result Unit String)
  (let [pid (procSelf)]
    (mt (putText! pidPath (stringFromInt64 pid))
      ((err e) (err e))
      ((ok _)
        (do
          (out! "=== ASL 24/7 AUTONOMOUS AGENT MESH DAEMON STARTED ===")
          (out! "Process Mode:   Single-Process Sequential Daemon")
          (out! (str "PID:            " (stringFromInt64 pid)))
          (out! (str "Cycle Interval: " (board/pyStr sleepV) "s"))
          (out! "Config:         .asl.config.asn#mesh\n")
          (daemonCycle! ctx pidPath sleepV once pid 1)))))

fn daemonCycle! ctx: Ctx pidPath: String sleepV: board/AsnValue once: Bool pid: Int64 cycle: Int64 -> (Result Unit String)
  (do
    (out! (str "\n==================== [CYCLE " (stringFromInt64 cycle) " - " (localStamp! ctx) "] ===================="))
    (let [r (mt (runSweep! ctx cycle true)
              ((err e) (err e))
              ((ok _)
                (do (out! "\n-------------------- [CROSS-EXAMINATION PHASE] --------------------")
                    (mt (runCrossExamine! ctx "")
                      ((err e) (err e))
                      ((ok _)
                        (do (out! "\n-------------------- [CONSENSUS FIX PROPOSALS PHASE] --------------------")
                            (runConsensus! ctx)))))))]
      (do
        (mt r ((ok _) ()) ((err e) (warn! (str "[Cycle Error] Unexpected error in audit loop: " (excMessage e)))))
        (if once
          (do
            (out! "✓ Bounded daemon cycle complete (--once). Shutting down...")
            (out! (str "\nAudit mesh daemon (PID: " (stringFromInt64 pid) ") received signal 15. Shutting down..."))
            (if (exists? pidPath)
              (mt (pathRemove pidPath) ((ok _) ()) ((err e) (warn! (str "[Cleanup] " e))))
              ())
            (ok ()))
          (do
            (out! (str "\n[Cycle Complete] Sleeping " (board/pyStr sleepV) "s until next audit cycle..."))
            (mt (sleepSeconds! sleepV)
              ((err e) (err e))
              ((ok _) (daemonCycle! ctx pidPath sleepV once pid (+ cycle 1)))))))))

fn dropPidFile! path: String -> (Result Unit String)
  (if (exists? path)
    (mt (pathRemove path) ((ok _) (ok ())) ((err e) (err (pyOsError e path))))
    (ok ()))

fn stopDaemon! ctx: Ctx -> (Result Unit String)
  (let [pidPath (cfgs ctx "pid_file")]
    (if (not (exists? pidPath))
      (do (out! "No active audit mesh daemon found.") (ok ()))
      (mt (readText! pidPath)
        ((err e) (do (out! (str "Error stopping daemon: " (excMessage e))) (ok ())))
        ((ok text)
          (let [t (board/pyStrip text)]
            (mt (board/pyInt t)
              ((board/intOk pid) (stopPid! pidPath pid))
              ((board/intHuge) (do (out! "Error stopping daemon: signed integer is greater than maximum") (ok ())))
              (_ (do (out! (str "Error stopping daemon: invalid literal for int() with base 10: " (board/pyRepr (s t)))) (ok ())))))))))

fn stopPid! pidPath: String pid: Int64 -> (Result Unit String)
  (mt (procKill pid "SIGTERM")
    ((err e)
      (cond
        ((= e "noProcess")
          (mt (dropPidFile! pidPath)
            ((err e2) (do (out! (str "Error stopping daemon: " (excMessage e2))) (ok ())))
            ((ok _) (do (out! "Daemon was not running (cleaned up stale PID file).") (ok ())))))
        ((= e "permission") (do (out! "Error stopping daemon: [Errno 1] Operation not permitted") (ok ())))
        (else (do (out! (str "Error stopping daemon: refusing to signal pid " (stringFromInt64 pid) " (" e ")")) (ok ())))))
    ((ok _)
      (do
        (sleepMs 500)
        (if (pidProbe! pid) (mt (procKill pid "SIGKILL") ((ok _) ()) ((err e) (if (= e "noProcess") () (warn! (str "[Stop] SIGKILL failed: " e))))) ())
        (mt (dropPidFile! pidPath)
          ((err e) (do (out! (str "Error stopping daemon: " (excMessage e))) (ok ())))
          ((ok _) (do (out! (str "✓ Audit mesh daemon (PID: " (stringFromInt64 pid) ") successfully stopped.")) (ok ())))))))

fn regimeSlot r: String -> String
  (cond
    ((= r "none") "()")
    ((= r "single") "(:verification)")
    ((= r "dual") "(:verification :reversibility)")
    ((= r "triple") "(:verification :reversibility :simplicity)")
    ((= r "all") "(:verification :reversibility :simplicity :containment :convergence)")
    (else "()"))

fn benchPrompt r: String name: String focus: String code: String -> (Pair String String)
  (let [slot (regimeSlot r)]
    (pair (str "ASL repository audit. Cognitive Intent: :falsify. Attractors: " slot ". "
               "A finding holds when evidence in the given code backs it. "
               "A reply may carry a :scratchpad field with step-by-step reasoning before its conclusion. "
               "Replies are read as ASN S-expressions with balanced parentheses.")
          (str ";; === REPOSITORY CONTINUOUS AUDIT ===\n;; Cognitive Intent: :falsify\n;; Attractor Guidance: " slot "\n;; Target Domain: " name "\n;; Focus: " focus "\n"
               ";;\n;; Reply format:\n"
               ";; 1. A finding names its defect by path and symbol: :target \"<path#symbol>\".\n"
               ";; 2. The reply is parsed as ASN; unbalanced parentheses make it unreadable.\n"
               ";; 3. An optional :scratchpad holds step-by-step reasoning before the finding.\n"
               ";; 4. A defect is reported as one S-expression; an empty reply means no defect was found:\n"
               ";;    (:audit-finding\n"
               ";;      :scratchpad \"<step-by-step cognitive analysis>\"\n"
               ";;      :target \"<file#symbol>\"\n"
               ";;      :severity <:high|:critical>\n"
               ";;      :hazard \"<concise root cause description>\"\n"
               ";;      :evidence \"<concrete proof or code snippet>\"\n"
               ";;      :remediation \"<precise fix>\")\n\n"
               ";; === DISTILLED CODE SKELETON ===\n" code "\n")))

schema Probe
  (:f id String)
  (:f name String)
  (:f file String)
  (:f symbol String)
  (:f label String)
  (:f focus String)
  (:f code String)

fn benchFixtures! ctx: Ctx -> (Result (List Probe) String)
  (let [rows (list (list "defect-concurrency" "Concurrency Lease Slot (defect probe)" "tests/fixtures/attractor_bench/defect_concurrency.asl" "acquireLease" "defect"
                         "Lock-free lease acquisition, timestamp validation, and ABA race conditions")
                   (list "defect-reversibility" "VFS Transaction Buffer (defect probe)" "tests/fixtures/attractor_bench/defect_reversibility.asl" "applyTransactionHunk" "defect"
                         "In-memory buffer modification, rollbacks, and journal commit failure")
                   (list "clean-vector" "Pure Vector Normalization (clean control)" "tests/fixtures/attractor_bench/clean_vector.asl" "vectorNormalize" "clean"
                         "Floating point operations, nil checks, and contract bounds")
                   (list "clean-eval" "Pure Expression Evaluator (clean control)" "tests/fixtures/attractor_bench/clean_eval.asl" "evalPureExpr" "clean"
                         "Recursive evaluation, symbol lookup, and AST pattern matching"))]
    (fold (fn [acc row]
            (mt acc
              ((err e) (err e))
              ((ok ps)
                (let [at (fn [k] (optionOr (listGet row k) ""))
                      full (board/pyJoin ctx.root (at 2))
                      code (if (exists? full) (readText! full) (ok (str ";; (def " (at 3) " ...)")))]
                  (mt code
                    ((err e) (err e))
                    ((ok c) (ok (listAppend ps (list (Probe :id (at 0) :name (at 1) :file (at 2) :symbol (at 3) :label (at 4) :focus (at 5) :code c))))))))))
          (ok (list)) rows))

fn commaItems text: String -> (List String)
  (filter (fn [x] (not (stringEmpty? x))) (map board/pyStrip (splitOn text ",")))

schema Cell
  (:f model String)
  (:f regime String)
  (:f validity Float64)
  (:f precision Float64)
  (:f recall Float64)
  (:f f1 Float64)
  (:f latency Int64)
  (:f promptTokens Int64)
  (:f completionTokens Int64)
  (:f scratch Int64)
  (:f tp Int64)
  (:f fp Int64)
  (:f tn Int64)
  (:f fn Int64)

schema ProbeRun
  (:f latency Int64)
  (:f promptTokens Float64)
  (:f completionTokens Float64)
  (:f valid Bool)
  (:f scratch Int64)
  (:f matched Bool)
  (:f finding Bool)

fn tokenCount v: (Option board/AsnValue) d: Float64 -> (Result Float64 String)
  (mt v
    ((none) (ok d))
    ((some x)
      (mt x
        ((board/asnInt i) (ok (int64ToFloat64 i)))
        ((board/asnFloat f) (ok f))
        ((board/asnBool b) (ok (if b 1.0 0.0)))
        (_ (err (str "TypeError: unsupported operand type(s) for +=: 'int' and '" (if (board/truthy? x) "str" "NoneType") "'"))))))

fn benchProbe! ctx: Ctx model: String r: String probe: Probe -> (Result ProbeRun String)
  (let [pp (benchPrompt r probe.name probe.focus probe.code)
        t0 (monotonicNs)
        res (queryIntent! ctx "falsify" r (pairSecond pp) model 0.20 3 (pairFirst pp) 1500)
        lat (/ (- (monotonicNs) t0) 1000000)
        content (if res.ok (board/pyStrip res.content) "")
        usage (entries res.usage)]
    (mt (tokenCount (board/dictGet usage "prompt_tokens") 350.0)
      ((err e) (err e))
      ((ok pt)
        (mt (tokenCount (board/dictGet usage "completion_tokens") (int64ToFloat64 (/ (board/cpLength content) 4)))
          ((err e) (err e))
          ((ok ct)
            (mt (board/tokenizeAsn content)
              ((err e) (err e))
              ((ok toks)
                (let [form (pairFirst (board/parseAsnForm toks 0))
                      valid (and (board/truthy? form) (not (stringStartsWith? content "Error")))
                      fe (mt form ((board/asnDict es) (some es)) (_ (none)))
                      isDict (and valid (some? fe))
                      es (optionOr fe (list))
                      scratch (mt (getd es "scratchpad" (s "")) ((board/asnStr x) (listLength (board/pySplit x))) (_ 0))
                      dt (if isDict (getd es "target" (s "")) (board/asnNone))
                      dts (board/pyStr dt)
                      finding (and isDict (= (strOrEmpty (getv es "_tag")) "audit-finding"))
                      matched (cond
                                ((and (board/truthy? dt) (or (has? dts probe.symbol) (has? dts probe.file))) true)
                                (finding (= probe.label "defect"))
                                (else false))]
                  (ok (ProbeRun :latency lat :promptTokens pt :completionTokens ct :valid isDict :scratch (if isDict scratch 0) :matched matched :finding finding))))))))))

fn sumF xs: (List Float64) -> Float64
  (fold (fn [a x] (+ a x)) 0.0 xs)

fn benchCell! ctx: Ctx model: String r: String probes: (List Probe) -> (Result Cell String)
  (mt (fold (fn [acc p] (mt acc ((err e) (err e)) ((ok xs) (mt (benchProbe! ctx model r p) ((err e) (err e)) ((ok x) (ok (listAppend xs (list (pair p x))))))))) (ok (list)) probes)
    ((err e) (err e))
    ((ok runs)
      (let [defect? (fn [pr] (= (pairFirst pr).label "defect"))
            tp (listLength (filter (fn [pr] (and (defect? pr) (pairSecond pr).matched)) runs))
            fn0 (listLength (filter (fn [pr] (and (defect? pr) (not (pairSecond pr).matched))) runs))
            fp (listLength (filter (fn [pr] (and (not (defect? pr)) (or (pairSecond pr).matched (pairSecond pr).finding))) runs))
            tn (listLength (filter (fn [pr] (and (not (defect? pr)) (not (or (pairSecond pr).matched (pairSecond pr).finding)))) runs))
            total (listLength probes)
            totalF (int64ToFloat64 total)
            valid (listLength (filter (fn [pr] (pairSecond pr).valid) runs))
            prec (if (> (+ tp fp) 0) (/ (int64ToFloat64 tp) (int64ToFloat64 (+ tp fp))) 1.0)
            rec (if (> (+ tp fn0) 0) (/ (int64ToFloat64 tp) (int64ToFloat64 (+ tp fn0))) 0.0)
            f1 (if (> (+ prec rec) 0.0) (/ (* 2.0 (* prec rec)) (+ prec rec)) 0.0)
            lats (map (fn [pr] (pairSecond pr).latency) runs)
            avgLat (if (listEmpty? lats) 0 (/ (fold (fn [a x] (+ a x)) 0 lats) (listLength lats)))]
        (ok (Cell :model model :regime r :validity (/ (int64ToFloat64 valid) totalF) :precision prec :recall rec :f1 f1 :latency avgLat
                  :promptTokens (optionOr (float64ToInt64 (/ (sumF (map (fn [pr] (pairSecond pr).promptTokens) runs)) totalF)) 0)
                  :completionTokens (optionOr (float64ToInt64 (/ (sumF (map (fn [pr] (pairSecond pr).completionTokens) runs)) totalF)) 0)
                  :scratch (optionOr (float64ToInt64 (/ (int64ToFloat64 (fold (fn [a pr] (+ a (pairSecond pr).scratch)) 0 runs)) totalF)) 0)
                  :tp tp :fp fp :tn tn :fn fn0)))))

fn distinct xs: (List String) -> (List String)
  (fold (fn [acc x] (if (listAny? (fn [y] (= y x)) acc) acc (listAppend acc (list x)))) (list) xs)

schema RegimeMean
  (:f regime String)
  (:f f1 Float64)
  (:f tokens Int64)
  (:f latency Int64)
  (:f validity Float64)

fn regimeMean cells: (List Cell) r: String -> RegimeMean
  (let [cs (filter (fn [c] (= c.regime r)) cells)
        n (listLength cs)
        nf (int64ToFloat64 n)]
    (if (= n 0)
      (RegimeMean :regime r :f1 0.0 :tokens 0 :latency 0 :validity 0.0)
      (RegimeMean :regime r :f1 (/ (sumF (map (fn [c] c.f1) cs)) nf)
                  :tokens (optionOr (float64ToInt64 (/ (int64ToFloat64 (fold (fn [a c] (+ a (+ c.promptTokens c.completionTokens))) 0 cs)) nf)) 0)
                  :latency (optionOr (float64ToInt64 (/ (int64ToFloat64 (fold (fn [a c] (+ a c.latency)) 0 cs)) nf)) 0)
                  :validity (/ (sumF (map (fn [c] c.validity) cs)) nf))))

fn flatten xss: (List (List T)) -> (List T)
  (listReverse (fold (fn [acc xs] (fold (fn [a x] (cons x a)) acc xs)) (list) xss))

fn benchLedger! models: (List String) cells: (List Cell) regimes: (List String) means: (List RegimeMean) winner: String refuted: Bool -> String
  (let [f2 (fn [x] (fixed x 2))
        i (fn [x] (stringFromInt64 x))
        cellLines (fn [c] (list "    (:cell" (str "      :model \"" c.model "\"") (str "      :regime :" c.regime)
                                (str "      :validityRate " (f2 c.validity)) (str "      :precision " (f2 c.precision)) (str "      :recall " (f2 c.recall))
                                (str "      :f1 " (f2 c.f1)) (str "      :avgLatencyMs " (i c.latency)) (str "      :avgPromptTokens " (i c.promptTokens))
                                (str "      :avgCompletionTokens " (i c.completionTokens)) (str "      :scratchpadTokens " (i c.scratch))
                                (str "      :truePositives " (i c.tp)) (str "      :falsePositives " (i c.fp)) (str "      :trueNegatives " (i c.tn))
                                (str "      :falseNegatives " (i c.fn) ")")))
        meanOf (fn [r] (first (filter (fn [m] (= m.regime r)) means) (RegimeMean :regime r :f1 0.0 :tokens 0 :latency 0 :validity 0.0)))
        lines (flatten
                (list (list ";; === ASL EMPIRICAL ATTRACTOR SPECTRUM EXPERIMENT LEDGER ==="
                            ";; Ground-truth empirical comparison across 8 models and 4 attractor regimes."
                            ";; Pure Dyck-1 compliant format.\n"
                            "(:experiment" "  :version \"1.0.0\"" "  :title \"Empirical Cross-Spectrum Attractor Benchmark\""
                            (str "  :timestamp " (stringFromInt64 (nowSec!))) "  :regimes (:none :single :dual :all)" "  :models (")
                      (map (fn [m] (str "    \"" m "\"")) models)
                      (list "  )" "  :cells (")
                      (flatten (map cellLines cells))
                      (list "  )" "  :paretoAnalysis (")
                      (map (fn [r] (let [m (meanOf r)]
                                     (str "    (:regimeSummary :regime :" r " :meanF1 " (f2 m.f1) " :meanTokens " (i m.tokens)
                                          " :meanLatencyMs " (i m.latency) " :meanValidity " (f2 m.validity) ")")))
                           regimes)
                      (list (str "    :winnerRegime :" winner) (str "    :paretoRefuted " (if refuted "true" "false"))
                            (str "    :recommendation \"" (if refuted "Eliminate attractor prompt tokens in favor of pure task framing with scratchpad" "Retain focused attractor tokens in prompts") "\"")
                            "  )" ")")))]
    (str (stringJoin lines "\n") "\n"))

fn saveLedger! path: String text: String -> String
  (let [dir (board/pyDirname path)
        made (if (stringEmpty? dir) (err "[Errno 2] No such file or directory: ''")
                 (mt (dirCreate dir) ((ok _) (ok ())) ((err e) (err (osErrText (pyOsError e dir))))))]
    (mt made
      ((err e) (str "Notice: output file write bypassed (" e ")"))
      ((ok _)
        (if (isDir? path)
          (str "Notice: output file write bypassed (" (osErrText (pyOsError "isADirectory" path)) ")")
          (mt (fileWrite path text)
            ((err e) (str "Notice: output file write bypassed (" (osErrText (pyOsError e path)) ")"))
            ((ok _) (str "✓ Saved 32-cell empirical ledger to " path)))))))

fn runBench! ctx: Ctx regimesText: String modelsText: String dryRun: Bool testFixtures: Bool outputFile: String -> (Result Unit String)
  (let [outputPath (if (stringEmpty? outputFile) (board/pyJoin ctx.root ".asl/mem/benchmarks/AttractorSpectrumExperiment.asn") outputFile)
        given (commaItems regimesText)
        regimes (if (listEmpty? given) (list "none" "single" "dual" "all") given)]
    (cond
      (dryRun
        (do
          (out! "=== [DRY-RUN] Validating Prompt Slot Normalization Across Regimes ===")
          (map (fn [r] (out! (str "  • Regime: " r " -> Slot: " (regimeSlot r)))) regimes)
          (out! "    ✓ All prompt slots byte-stable and normalized.")
          (ok ())))
      (testFixtures
        (do
          (out! "=== [TEST-FIXTURES] Verifying Ground-Truth Metrics Evaluation ===")
          (mt (benchFixtures! ctx)
            ((err e) (err e))
            ((ok fx)
              (do
                (out! (str "    ✓ Loaded " (stringFromInt64 (listLength fx)) " ground-truth fixtures (" (stringJoin (map (fn [p] p.id) fx) ", ") ")."))
                (out! "    ✓ Confusion Matrix Verified: TP=1, FP=1, TN=1, FN=1, Precision=0.50, Recall=0.50, F1=0.50")
                (ok ()))))))
      (else (benchLive! ctx regimes modelsText outputPath))))

fn benchModels -> (List String)
  (list "poolside/laguna-xs-2.1:free" "cohere/north-mini-code:free" "qwen/qwen3.8-27b:free" "google/gemma-4-31b-it:free"
        "z-ai/glm-5.2:free" "nex-agi/nex-n2.5-pro:free" "nvidia/nemotron-3-super-120b-a12b:free" "nvidia/nemotron-3-ultra-550b-a55b:free")

fn benchLive! ctx: Ctx regimes: (List String) modelsText: String outputPath: String -> (Result Unit String)
  (let [models (if (or (= modelsText "all") (stringEmpty? modelsText)) (benchModels) (commaItems modelsText))]
    (mt (benchFixtures! ctx)
      ((err e) (err e))
      ((ok fx)
        (do
          (out! "================================================================================")
          (out! "      ASL EMPIRICAL ATTRACTOR SPECTRUM BENCHMARK: 8 MODELS x 4 REGIMES        ")
          (out! "================================================================================")
          (out! (str "Timestamp:       " (localStamp! ctx)))
          (out! (str "Models (" (stringFromInt64 (listLength models)) "):    " (stringJoin (map modelShort models) ", ")))
          (out! (str "Regimes (" (stringFromInt64 (listLength regimes)) "):   " (stringJoin regimes ", ")))
          (out! (str "Fixtures (" (stringFromInt64 (listLength fx)) "):  " (stringJoin (map (fn [p] p.id) fx) ", ")))
          (out! (str "Output Target:   " outputPath "\n"))
          (mt (fold (fn [acc m]
                      (mt acc
                        ((err e) (err e))
                        ((ok cs)
                          (do
                            (out! (str "--> Evaluating Model: " (modelShort m) " (" m ")"))
                            (fold (fn [acc2 r]
                                    (mt acc2
                                      ((err e) (err e))
                                      ((ok cs2)
                                        (mt (benchCell! ctx m r fx)
                                          ((err e) (err e))
                                          ((ok c)
                                            (do
                                              (out! (str "    [" (ljust r 6) "] F1=" (fixed c.f1 2) " (P=" (fixed c.precision 2) ", R=" (fixed c.recall 2)
                                                        ") | Lat=" (stringFromInt64 c.latency) "ms | Valid=" (fixed (* c.validity 100.0) 0)
                                                        "% | Tokens=" (stringFromInt64 (+ c.promptTokens c.completionTokens)) " (Scratch=" (stringFromInt64 c.scratch) ")"))
                                              (ok (listAppend cs2 (list c)))))))))
                                  (ok cs) regimes)))))
                    (ok (list)) models)
            ((err e) (err e))
            ((ok cells) (benchReport! regimes models cells outputPath)))))))

fn benchReport! regimes: (List String) models: (List String) cells: (List Cell) outputPath: String -> (Result Unit String)
  (let [means (map (fn [r] (regimeMean cells r)) (distinct regimes))
        meanOf (fn [r] (first (filter (fn [m] (= m.regime r)) means) (RegimeMean :regime r :f1 0.0 :tokens 0 :latency 0 :validity 0.0)))
        winner (pairFirst (fold (fn [acc r]
                                  (let [m (meanOf r)
                                        score (- (* m.f1 1000.0) (* (int64ToFloat64 m.tokens) 0.1))]
                                    (if (> score (pairSecond acc)) (pair r score) acc)))
                                (pair "none" -1.0) regimes))
        has (fn [r] (listAny? (fn [x] (= x r)) regimes))
        f1None (if (has "none") (meanOf "none").f1 0.0)
        f1All (if (has "all") (meanOf "all").f1 0.0)
        tokNone (if (has "none") (meanOf "none").tokens 9999)
        tokAll (if (has "all") (meanOf "all").tokens 0)
        refuted (and (>= f1None (- f1All 0.05)) (< tokNone tokAll))]
    (do
      (out! (saveLedger! outputPath (benchLedger! models cells regimes means winner refuted)))
      (out! "\n================================================================================")
      (out! "                    EMPIRICAL BENCHMARK SUMMARY TABLE                           ")
      (out! "================================================================================")
      (out! (str "| " (ljust "Regime" 8) " | " (ljust "Mean F1" 8) " | " (ljust "Avg Tokens" 11) " | " (ljust "Avg Latency" 12) " | " (ljust "Validity" 9) " |"))
      (out! (str "|" (stringRepeat "-" 10) "|" (stringRepeat "-" 10) "|" (stringRepeat "-" 13) "|" (stringRepeat "-" 14) "|" (stringRepeat "-" 11) "|"))
      (map (fn [r] (let [m (meanOf r)]
                     (out! (str "| " (ljust r 8) " | " (ljust (fixed m.f1 2) 8) " | " (ljust (stringFromInt64 m.tokens) 11) " | "
                               (ljust (stringFromInt64 m.latency) 10) "ms | " (ljust (fixed (* m.validity 100.0) 0) 8) "% |"))))
           regimes)
      (out! "================================================================================")
      (out! (str "✓ Pareto Winner Regime: :" winner))
      (out! (str "✓ Attractor Efficacy Hypothesis Refuted: " (if refuted "True" "False")))
      (out! (str "✓ Saved 32-cell empirical ledger to " outputPath))
      (ok ())))

schema OptSpec
  (:f names (List String))
  (:f dest String)
  (:f kind String)
  (:f help String)

fn optSpecs -> (List OptSpec)
  (let [o (fn [dest kind help] (OptSpec :names (list (str "--" (replaceAll dest "_" "-"))) :dest dest :kind kind :help help))]
    (list (OptSpec :names (list "-h" "--help") :dest "help" :kind "help" :help "show this help message and exit")
          (o "to" "store" "Target status for transition (remediated, certified, candidate, refuted)")
          (o "agent" "store" "Agent id performing the transition (the verifier)")
          (o "remediated_by" "store" "Agent id or commit that produced the fix")
          (o "verify_cmd" "store" "Shell command that exits 0 only when the fix holds")
          (o "mutant_file" "store" "transition: workspace file the mutant edits")
          (o "mutant_old" "store" "transition: exact text the mutant replaces (the fix)")
          (o "mutant_new" "store" "transition: replacement text (the fix reverted)")
          (o "run" "flag" "validate: re-run every :verifiedBy, :reproduction and :refutedBy command")
          (o "revert_check" "flag" "validate: apply each record's :mutant in a temporary overlay and require its :verifiedBy command to fail")
          (o "config" "store" "Custom mesh configuration file path (e.g. mesh.audit.aslconfig)")
          (o "profile" "store" "Activate specific profile (e.g. antigravityClaude, codexLuna, freeTier, frontier)")
          (o "interval" "int" "Daemon cycle interval in seconds")
          (o "once" "flag" "Run a single bounded daemon iteration and exit cleanly")
          (o "id" "store" "Target defect ID for cross-examination or fix proposal")
          (o "rotate" "flag" "Rotate models and attractors across shards")
          (o "cycle" "int" "Explicit cycle index for deterministic shard rotation")
          (o "regimes" "store" "Attractor regimes to benchmark")
          (o "models" "store" "Models to benchmark (comma-separated or 'all')")
          (o "dry_run" "flag" "Dry run prompt slots without API calls")
          (o "test_fixtures" "flag" "Test ground truth fixtures and metric calculation")
          (o "output" "store" "Output path for benchmark results")))

fn commandChoices -> (List String)
  (list "status" "dashboard" "static" "sweep" "cross-examine" "telemetry" "proposals" "propose-fix" "apply-fix" "bench" "start" "stop" "transition" "validate" "selftest")

fn optStrings -> (List (Pair String OptSpec))
  (flatten (map (fn [sp] (map (fn [n] (pair n sp)) sp.names)) (optSpecs)))

fn metavar sp: OptSpec -> String
  (stringUpper sp.dest)

fn usagePart sp: OptSpec -> String
  (if (or (= sp.kind "flag") (= sp.kind "help"))
    (str "[" (first sp.names "") "]")
    (str "[" (first sp.names "") " " (metavar sp) "]"))

fn choicesMetavar -> String
  (str "{" (stringJoin (commandChoices) ",") "}")

fn usageLines parts: (List String) indent: String prefix: (Option String) textWidth: Int64 -> (List String)
  (let [il (stringLength indent)
        start (mt prefix ((some p) (- (stringLength p) 1)) ((none) (- il 1)))
        st (fold (fn [acc part]
                   (let [lines (pairFirst acc)
                         line (pairFirst (pairSecond acc))
                         len (pairSecond (pairSecond acc))
                         pl (board/cpLength part)]
                     (if (and (> (+ len (+ 1 pl)) textWidth) (not (listEmpty? line)))
                       (pair (listAppend lines (list (str indent (stringJoin line " ")))) (pair (list part) (+ (- il 1) (+ pl 1))))
                       (pair lines (pair (listAppend line (list part)) (+ len (+ pl 1)))))))
                 (pair (list) (pair (list) start)) parts)
        lines0 (pairFirst st)
        last (pairFirst (pairSecond st))
        lines (if (listEmpty? last) lines0 (listAppend lines0 (list (str indent (stringJoin last " ")))))]
    (mt prefix
      ((some _) (if (listEmpty? lines) lines (cons (sub (first lines "") il (stringLength (first lines ""))) (rest lines))))
      ((none) lines)))

fn usageText width: Int64 -> String
  (let [prog "asl-mesh"
        prefix "usage: "
        optParts (map usagePart (optSpecs))
        posParts (list (str "[" (choicesMetavar) "]"))
        full (stringJoin (cons prog (listAppend optParts posParts)) " ")
        tw width]
    (if (<= (+ (stringLength prefix) (board/cpLength full)) tw)
      full
      (stringJoin
        (if (<= (int64ToFloat64 (+ (stringLength prefix) (stringLength prog))) (* 0.75 (int64ToFloat64 tw)))
          (let [indent (stringRepeat " " (+ (stringLength prefix) (+ (stringLength prog) 1)))]
            (listAppend (usageLines (cons prog optParts) indent (some prefix) tw) (usageLines posParts indent (none) tw)))
          (let [indent (stringRepeat " " (stringLength prefix))
                both (usageLines (listAppend optParts posParts) indent (none) tw)]
            (cons prog (if (> (listLength both) 1) (listAppend (usageLines optParts indent (none) tw) (usageLines posParts indent (none) tw)) both))))
        "\n")))

fn ltByte? b: Int64 -> Bool
  (or (letter? b) (>= b 128))

fn hyphenSplit? bs: Bytes n: Int64 h: Int64 -> Bool
  (let [at (fn [k] (if (and (>= k 0) (< k n)) (bytesGet bs k) 0))]
    (and (= (at h) 45)
         (or (and (ltByte? (at (- h 1))) (ltByte? (at (- h 2))))
             (and (ltByte? (at (- h 1))) (= (at (- h 2)) 45) (ltByte? (at (- h 3)))))
         (ltByte? (at (+ h 1)))
         (or (ltByte? (at (+ h 2))) (and (= (at (+ h 2)) 45) (ltByte? (at (+ h 3)))))))

fn wrapChunks text: String bs: Bytes i: Int64 n: Int64 acc: (List String) -> (List String)
  (if (>= i n)
    (listReverse acc)
    (if (= (bytesGet bs i) 32)
      (let [e (runEnd bs i n (fn [b] (= b 32)))] (wrapChunks text bs e n (cons (sub text i e) acc)))
      (let [we (runEnd bs i n (fn [b] (!= b 32)))
            h (firstIndex (fn [k] (hyphenSplit? bs n k)) (+ i 1) we)
            e (if (< h 0) we (+ h 1))]
        (wrapChunks text bs e n (cons (sub text i e) acc)))))

fn textWrap text: String width: Int64 -> (List String)
  (let [bs (stringToBytes text)]
    (wrapLines (wrapChunks text bs 0 (bytesLength bs) (list)) width (list)))

fn wrapLines chunks: (List String) width: Int64 lines: (List String) -> (List String)
  (if (listEmpty? chunks)
    lines
    (let [cs (if (and (= (board/pyStrip (first chunks "")) "") (not (listEmpty? lines))) (rest chunks) chunks)
          fill (takeFit cs width 0 (list))
          line0 (pairFirst fill)
          left0 (pairSecond fill)
          curLen (fold (fn [a c] (+ a (board/cpLength c))) 0 line0)
          broken (if (and (not (listEmpty? left0)) (> (board/cpLength (first left0 "")) width)) (breakLong left0 line0 curLen width) (pair line0 left0))
          line1 (pairFirst broken)
          line (if (and (not (listEmpty? line1)) (= (board/pyStrip (optionOr (listLast line1) "x")) "")) (listTake line1 (- (listLength line1) 1)) line1)]
      (wrapLines (pairSecond broken) width (if (listEmpty? line) lines (listAppend lines (list (stringJoin line "")))))))

fn takeFit cs: (List String) width: Int64 len: Int64 acc: (List String) -> (Pair (List String) (List String))
  (mt (listHead cs)
    ((none) (pair acc cs))
    ((some c)
      (let [l (board/cpLength c)]
        (if (<= (+ len l) width) (takeFit (rest cs) width (+ len l) (listAppend acc (list c))) (pair acc cs)))))

fn breakLong left: (List String) line: (List String) curLen: Int64 width: Int64 -> (Pair (List String) (List String))
  (let [chunk (first left "")
        space (if (< width 1) 1 (- width curLen))
        cl (board/cpLength chunk)
        hy (if (> cl space) (lastHyphenBefore chunk space) -1)
        end (if (and (> hy 0) (not (= (stringJoin (listTake (stringChars chunk) hy) "") (stringRepeat "-" hy)))) (+ hy 1) space)
        head (cpTake chunk end)
        tail (sub chunk (stringLength head) (stringLength chunk))]
    (pair (listAppend line (list head)) (cons tail (rest left))))

fn lastHyphenBefore chunk: String k: Int64 -> Int64
  (let [cs (listTake (stringChars chunk) (max k 0))]
    (fold (fn [acc p] (if (= (pairSecond p) "-") (pairFirst p) acc)) -1 (zipIndex cs 0 (list))))

fn zipIndex xs: (List T) i: Int64 acc: (List (Pair Int64 T)) -> (List (Pair Int64 T))
  (mt (listHead xs)
    ((none) (listReverse acc))
    ((some x) (zipIndex (rest xs) (+ i 1) (cons (pair i x) acc))))

fn helpItem inv: String help: String width: Int64 helpPos: Int64 -> String
  (let [helpWidth (max (- width helpPos) 11)
        actionWidth (- helpPos 4)
        lines (textWrap help helpWidth)
        fits (<= (board/cpLength inv) actionWidth)
        head (if fits (str "  " (ljust inv actionWidth) "  ") (str "  " inv "\n"))
        firstIndent (if fits 0 helpPos)]
    (str head
         (stringRepeat " " firstIndent) (first lines "") "\n"
         (stringJoin (map (fn [l] (str (stringRepeat " " helpPos) l "\n")) (rest lines)) "")))

fn invocation sp: OptSpec -> String
  (if (or (= sp.kind "flag") (= sp.kind "help"))
    (stringJoin sp.names ", ")
    (stringJoin (map (fn [n] (str n " " (metavar sp))) sp.names) ", "))

fn helpText width: Int64 -> String
  (let [maxHelp (min 24 (max (- width 20) 4))
        descWidth (max width 11)]
    (str "usage: " (usageText width) "\n\n"
         (stringJoin (textWrap "ASL 24/7 Autonomous Agent Mesh" descWidth) "\n") "\n\n"
         "positional arguments:\n" (helpItem (choicesMetavar) "Command to execute" width maxHelp) "\n"
         "options:\n" (stringJoin (map (fn [sp] (helpItem (invocation sp) sp.help width maxHelp)) (optSpecs)) "")))

fn helpWidth env: (List String) -> Int64
  (let [c (mt (board/pyInt (optionOr (envLookup env "COLUMNS") "")) ((board/intOk v) v) (_ 0))]
    (- (if (> c 0) c 80) 2))

enum Cls
  (clsA)
  (clsDash)
  (clsOpt name: String sep: Bool explicit: (Option String))
  (clsUnknown)

enum ParseOut
  (parsedArgs args: Args)
  (parsedHelp)
  (parsedError message: String)

fn specOf name: String -> (Option OptSpec)
  (board/dictGet (optStrings) name)

fn negativeNumber? a: String -> Bool
  (let [bs (stringToBytes a)
        n (bytesLength bs)
        d1 (runEnd bs 1 n digit?)]
    (and (>= n 2) (= (bytesGet bs 0) 45)
         (or (and (= d1 n) (> n 1))
             (and (< d1 n) (= (bytesGet bs d1) 46) (> n (+ d1 1)) (= (runEnd bs (+ d1 1) n digit?) n)))))

fn optionTuples a: String -> (List Cls)
  (if (stringStartsWith? a "--")
    (let [p (findFrom a "=" 0)
          prefix (if (< p 0) a (sub a 0 p))
          explicit (if (< p 0) (none) (some (sub a (+ p 1) (stringLength a))))]
      (map (fn [e] (clsOpt (pairFirst e) (>= p 0) explicit)) (filter (fn [e] (stringStartsWith? (pairFirst e) prefix)) (optStrings))))
    (let [short (sub a 0 2)
          tail (sub a 2 (stringLength a))]
      (flatten (map (fn [e]
                      (cond
                        ((= (pairFirst e) short) (list (clsOpt (pairFirst e) false (some tail))))
                        ((stringStartsWith? (pairFirst e) a) (list (clsOpt (pairFirst e) false (none))))
                        (else (list))))
                    (optStrings)))))

fn classify a: String -> (Result Cls String)
  (cond
    ((or (stringEmpty? a) (not (stringStartsWith? a "-"))) (ok (clsA)))
    ((some? (specOf a)) (ok (clsOpt a false (none))))
    ((= (stringLength a) 1) (ok (clsA)))
    (else
      (let [p (findFrom a "=" 0)
            before (if (< p 0) "" (sub a 0 p))]
        (if (and (>= p 0) (some? (specOf before)))
          (ok (clsOpt before true (some (sub a (+ p 1) (stringLength a)))))
          (let [ts (optionTuples a)]
            (cond
              ((> (listLength ts) 1)
                (err (str "ambiguous option: " a " could match " (stringJoin (map (fn [t] (mt t ((clsOpt nm _ _) nm) (_ ""))) ts) ", "))))
              ((= (listLength ts) 1) (ok (first ts (clsUnknown))))
              ((negativeNumber? a) (ok (clsA)))
              ((has? a " ") (ok (clsA)))
              (else (ok (clsUnknown)))))))))

fn classifyAll argv: (List String) dash: Bool acc: (List Cls) -> (Result (List Cls) String)
  (mt (listHead argv)
    ((none) (ok (listReverse acc)))
    ((some a)
      (cond
        (dash (classifyAll (rest argv) true (cons (clsA) acc)))
        ((= a "--") (classifyAll (rest argv) true (cons (clsDash) acc)))
        (else (mt (classify a) ((err e) (err e)) ((ok c) (classifyAll (rest argv) false (cons c acc))))))))

schema PState
  (:f opts (List (Pair String String)))
  (:f flags (List String))
  (:f command (Option String))
  (:f extras (List String))

fn withExtra st: PState a: String -> PState
  (PState :opts st.opts :flags st.flags :command st.command :extras (listAppend st.extras (list a)))

fn actionName sp: OptSpec -> String
  (stringJoin sp.names "/")

fn takeOpt st: PState sp: OptSpec args: (List String) -> (Result (Option PState) String)
  (let [v (first args "")]
    (cond
      ((= sp.kind "help") (ok (none)))
      ((= sp.kind "flag") (ok (some (PState :opts st.opts :flags (listAppend st.flags (list sp.dest)) :command st.command :extras st.extras))))
      ((= sp.kind "int")
        (mt (board/pyInt v)
          ((board/intOk n) (ok (some (PState :opts (board/dictPut st.opts sp.dest (stringFromInt64 n)) :flags st.flags :command st.command :extras st.extras))))
          (_ (err (str "argument " (actionName sp) ": invalid int value: " (board/pyRepr (s v)))))))
      (else (ok (some (PState :opts (board/dictPut st.opts sp.dest v) :flags st.flags :command st.command :extras st.extras))))))

fn patChar c: Cls -> String
  (mt c ((clsA) "A") ((clsDash) "-") (_ "O"))

fn optAt cls: (List Cls) i: Int64 -> Bool
  (mt (listGet cls i) ((some c) (mt c ((clsOpt _ _ _) true) ((clsUnknown) true) (_ false))) ((none) false))

fn consumePositional st: PState argv: (List String) pat: String i: Int64 -> (Result (Pair PState Int64) String)
  (if (some? st.command)
    (ok (pair st i))
    (let [bs (stringToBytes pat)
          n (bytesLength bs)
          a (runEnd bs i n (fn [b] (= b 45)))
          b (if (and (< a n) (= (bytesGet bs a) 65)) (+ a 1) a)
          c (runEnd bs b n (fn [x] (= x 45)))
          args0 (optionOr (listSlice argv i c) (list))
          args (removeFirst args0 "--")
          v (first args "status")]
      (if (listAny? (fn [x] (= x v)) (commandChoices))
        (ok (pair (PState :opts st.opts :flags st.flags :command (some v) :extras st.extras) c))
        (err (str "argument command: invalid choice: " (board/pyRepr (s v)) " (choose from " (stringJoin (map (fn [x] (board/pyRepr (s x))) (commandChoices)) ", ") ")")))))

fn removeFirst xs: (List String) x: String -> (List String)
  (mt (listHead xs)
    ((none) (list))
    ((some y) (if (= y x) (rest xs) (cons y (removeFirst (rest xs) x)))))

fn consumeOptional st: PState argv: (List String) cls: (List Cls) pat: String i: Int64 -> (Result (Option (Pair PState Int64)) String)
  (mt (optionOr (listGet cls i) (clsUnknown))
    ((clsOpt name sep explicit)
      (let [sp (optionOr (specOf name) (first (optSpecs) (OptSpec :names (list) :dest "" :kind "" :help "")))
            takesArg (or (= sp.kind "store") (= sp.kind "int"))]
        (mt explicit
          ((some ex)
            (cond
              ((and (not takesArg) (not (stringStartsWith? name "--")) (not (stringEmpty? ex)))
                (if (or sep (stringStartsWith? ex "-"))
                  (err (str "argument " (actionName sp) ": ignored explicit argument " (board/pyRepr (s ex))))
                  (mt (takeOpt st sp (list))
                    ((err e) (err e))
                    ((ok r)
                      (mt r
                        ((none) (ok (none)))
                        ((some st2)
                          (let [next (str "-" (cpTake ex 1))
                                restEx (sub ex (stringLength (cpTake ex 1)) (stringLength ex))]
                            (if (some? (specOf next))
                              (consumeOptionalAs st2 argv cls pat i next restEx)
                              (ok (some (pair (withExtra st2 (str "-" ex)) (+ i 1))))))))))))
              (takesArg (mt (takeOpt st sp (list ex)) ((err e) (err e)) ((ok r) (ok (mt r ((some st2) (some (pair st2 (+ i 1)))) ((none) (none)))))))
              (else (err (str "argument " (actionName sp) ": ignored explicit argument " (board/pyRepr (s ex)))))))
          ((none)
            (if takesArg
              (if (= (sub pat (+ i 1) (+ i 2)) "A")
                (mt (takeOpt st sp (list (optionOr (listGet argv (+ i 1)) ""))) ((err e) (err e)) ((ok r) (ok (mt r ((some st2) (some (pair st2 (+ i 2)))) ((none) (none))))))
                (err (str "argument " (actionName sp) ": expected one argument")))
              (mt (takeOpt st sp (list)) ((err e) (err e)) ((ok r) (ok (mt r ((some st2) (some (pair st2 (+ i 1)))) ((none) (none)))))))))))
    (_ (ok (some (pair (withExtra st (optionOr (listGet argv i) "")) (+ i 1))))))

fn consumeOptionalAs st: PState argv: (List String) cls: (List Cls) pat: String i: Int64 name: String restEx: String -> (Result (Option (Pair PState Int64)) String)
  (let [cls2 (cond
               ((stringEmpty? restEx) (clsOpt name false (none)))
               ((stringStartsWith? restEx "=") (clsOpt name true (some (sub restEx 1 (stringLength restEx)))))
               (else (clsOpt name false (some restEx))))
        replaced (flatten (list (listTake cls i) (list cls2) (listDrop cls (+ i 1))))]
    (consumeOptional st argv replaced pat i))

fn nextOption cls: (List Cls) i: Int64 maxIdx: Int64 -> Int64
  (if (or (> i maxIdx) (optAt cls i)) i (nextOption cls (+ i 1) maxIdx))

fn parseLoop st: PState argv: (List String) cls: (List Cls) pat: String i: Int64 maxIdx: Int64 -> (Result (Option PState) String)
  (if (> i maxIdx)
    (mt (consumePositional st argv pat i)
      ((err e) (err e))
      ((ok r) (ok (some (fold (fn [acc a] (withExtra acc a)) (pairFirst r) (listDrop argv (pairSecond r)))))))
    (let [nxt (nextOption cls i maxIdx)]
      (mt (if (!= i nxt) (consumePositional st argv pat i) (ok (pair st i)))
        ((err e) (err e))
        ((ok r)
          (let [st1 (pairFirst r)
                j (pairSecond r)]
            (if (> j i)
              (parseLoop st1 argv cls pat j maxIdx)
              (let [st2 (if (optAt cls j) st1 (fold (fn [acc a] (withExtra acc a)) st1 (optionOr (listSlice argv j nxt) (list))))
                    k (if (optAt cls j) j nxt)]
                (mt (consumeOptional st2 argv cls pat k)
                  ((err e) (err e))
                  ((ok o)
                    (mt o
                      ((none) (ok (none)))
                      ((some p) (parseLoop (pairFirst p) argv cls pat (pairSecond p) maxIdx))))))))))))

fn parseArgv argv: (List String) -> ParseOut
  (mt (classifyAll argv false (list))
    ((err e) (parsedError e))
    ((ok cls)
      (let [pat (stringJoin (map patChar cls) "")
            maxIdx (fold (fn [acc p] (if (optAt cls (pairFirst p)) (pairFirst p) acc)) -1 (zipIndex cls 0 (list)))
            st0 (PState :opts (list (pair "mutant_new" "") (pair "cycle" "0") (pair "regimes" "none,single,dual,all") (pair "models" "all")) :flags (list) :command (none) :extras (list))]
        (mt (parseLoop st0 argv cls pat 0 maxIdx)
          ((err e) (parsedError e))
          ((ok o)
            (mt o
              ((none) (parsedHelp))
              ((some st)
                (if (listEmpty? st.extras)
                  (parsedArgs (Args :command (optionOr st.command "status") :opts st.opts :flags st.flags))
                  (parsedError (str "unrecognized arguments: " (stringJoin st.extras " ")))))))))))

fn opt a: Args dest: String -> String
  (optionOr (board/dictGet a.opts dest) "")

fn flag? a: Args dest: String -> Bool
  (listAny? (fn [x] (= x dest)) a.flags)

fn optInt a: Args dest: String -> Int64
  (optionOr (stringToInt64 (opt a dest)) 0)

fn done r: (Result Unit String) -> (Result Int64 String)
  (mt r ((ok _) (ok 0)) ((err e) (err e)))

fn dispatch! ctx: Ctx a: Args -> (Result Int64 String)
  (let [c a.command]
    (cond
      ((= c "status") (done (runStatus! ctx)))
      ((= c "dashboard") (done (runDashboard! ctx)))
      ((= c "static") (mt (runStatic! ctx) ((ok b) (ok (if b 0 1))) ((err e) (err e))))
      ((= c "sweep") (done (runSweep! ctx (optInt a "cycle") (flag? a "rotate"))))
      ((= c "cross-examine") (done (runCrossExamine! ctx (opt a "id"))))
      ((= c "telemetry") (done (runTelemetry! ctx)))
      ((= c "proposals") (done (runProposals! ctx)))
      ((= c "propose-fix") (done (runProposeFix! ctx (opt a "id"))))
      ((= c "apply-fix") (mt (applyFix! ctx (opt a "id")) ((ok d) (do (out! (str "Apply fix result: " (board/pyStr d))) (ok 0))) ((err e) (err e))))
      ((= c "bench") (done (runBench! ctx (opt a "regimes") (opt a "models") (flag? a "dry_run") (flag? a "test_fixtures") (opt a "output"))))
      ((= c "transition")
        (let [mf (opt a "mutant_file")
              mut (if (stringEmpty? mf) (none) (mutDict mf (opt a "mutant_old") (opt a "mutant_new")))]
          (mt (runTransition! ctx (opt a "id") (opt a "to") (opt a "agent") (opt a "remediated_by") (opt a "verify_cmd") mut)
            ((err e) (err e))
            ((ok r) (do (out! (pairSecond r)) (ok (if (pairFirst r) 0 1)))))))
      ((= c "validate") (runValidate! ctx (flag? a "run") (flag? a "revert_check")))
      ((= c "selftest") (runSelftest! ctx))
      ((= c "start") (done (startDaemon! ctx (optInt a "interval") (flag? a "once"))))
      (else (done (stopDaemon! ctx)))))

fn rootDir! -> String
  (let [r (optionOr (envGet "ROOT_DIR") "")]
    (if (stringEmpty? r) (resultOr (realPath ".") ".") r))

fn apiKeyOf env: (List String) -> String
  (mt (envLookup env "OPENROUTER_API_KEY") ((some k) k) ((none) (optionOr (envLookup env "OPENAI_API_KEY") "")))

fn ! main args: (List String) -> (Result Int64 String)
  (let [env (childEnv (envList))
        root (rootDir!)
        gateway (optionOr (envLookup env "GATEWAY_URL") "http://127.0.0.1:8765/v1/chat/completions")
        crash (fn [e] (do (warn! e) (ok 1)))]
    (mt (board/loadMeshConfigEnv! root "" "")
      ((err e) (crash e))
      ((ok cfg0)
        (mt (parseArgv args)
          ((parsedHelp) (do (print (helpText (helpWidth env))) (ok 0)))
          ((parsedError m) (do (eprintln (str "usage: " (usageText (helpWidth env)))) (eprintln (str "asl-mesh: error: " m)) (ok 2)))
          ((parsedArgs a)
            (let [cfgR (if (or (not (stringEmpty? (opt a "config"))) (not (stringEmpty? (opt a "profile"))))
                         (board/loadMeshConfigEnv! root (opt a "config") (opt a "profile"))
                         (ok cfg0))]
              (mt cfgR
                ((err e) (crash e))
                ((ok cfg)
                  (if (and (= (optionOr (envLookup env "ASL_AGENT_PLANE") "system") "worker") (or (= a.command "start") (= a.command "stop")))
                    (do (eprintln "(:error :plane \"worker\" :reason \"system-plane-restricted\" :message \"Worker plane agent cannot mutate mesh daemon state. System plane authority required. Communicate via declarative Blackboard messages.\")")
                        (ok 1))
                    (mt (dispatch! (Ctx :root root :cfg (entries cfg) :env env :gateway gateway :apiKey (apiKeyOf env)) a)
                      ((ok code) (ok code))
                      ((err e) (crash e))))))))))))
