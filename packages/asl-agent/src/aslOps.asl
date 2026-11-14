(module aslAgent/aslOps
  :x [RVal Bounded PumpEnd RunAslResult MemoEntry
      budgetLeft stepTimeout nowMono chooseTransport transportField engineSocketPath! gateTimeoutSec
      engineRequest runAslSocket
      nearestLines placeholderAssert? runBounded runAsl
      memoRunId memoSessionOk? memoRunBegin! memoRunBeginIfOn! memoRunEnd! memoRunDir! memoPrune! toolMemoIn toolMemoOn! memoKey memoGet! memoPut! execAslOp! execAslOpCustom! execAslOpMemo! readOutlineBytes readOutlineBytesIn readOutlineBytesFor! serReceipt serValue
      runExit runStdout runStderr runTimedOut runSeconds runFellBack chooseTransportFor]
  :i [(aslAgent/core :a c)
      (aslAgent/agentConfig :a ac)
      (aslAgent/jail :a jl)
      (aslAgent/diff :a diff)
      (aslAgent/txn :a t)
      (asl-json/json :a j)
      (asl-engine/transport :a etp)
      (asl-forms/main :a forms)
      (asl-forms/kernel :a k)])

enum RVal
  (rStr text: String)
  (rInt n: Int64)
  (rBool b: Bool)
  (rList xs: (List String))
  (rPair first: Int64 second: Int64)
  (rNone)

(schema Bounded (:f code (Option Int64)) (:f out String) (:f errText String) (:f timedOut Bool))

enum PumpEnd
  (pumpDone out: String errText: String)
  (pumpLate outOpen: Bool errOpen: Bool out: String errText: String)
  (pumpFailed msg: String)

(schema RunAslResult
  (:f exit Int64)
  (:f stdout String)
  (:f stderr String)
  (:f timedOut Bool)
  (:f seconds Int64)
  (:f fellBack String))

(schema MemoEntry (:f run t/AslRun) (:f rid String) (:f age Int64))

fn runExit r: RunAslResult -> Int64 r.exit
fn runStdout r: RunAslResult -> String r.stdout
fn runStderr r: RunAslResult -> String r.stderr
fn runTimedOut r: RunAslResult -> Bool r.timedOut
fn runSeconds r: RunAslResult -> Int64 r.seconds
fn runFellBack r: RunAslResult -> String r.fellBack

fn ch s: String i: Int64 -> String
  (c/sliceOf s i (+ i 1))

fn isSpace c: String -> Bool
  (or (= c " ") (or (and (>= c "\t") (<= c "\r")) (and (>= c "\u001c") (<= c "\u001f"))))

fn runEnd s: String n: Int64 i: Int64 test: (fn [String] -> Bool) -> Int64
  (if (and (< i n) (test (ch s i))) (runEnd s n (+ i 1) test) i)

fn quotedEnd s: String n: Int64 j: Int64 -> Int64
  (cond
    ((>= j n) -1)
    ((= (ch s j) "\"") j)
    ((= (ch s j) "\\") (if (and (< (+ j 1) n) (!= (ch s (+ j 1)) "\n")) (quotedEnd s n (+ j 2)) -1))
    (else (quotedEnd s n (+ j 1))))

fn universalNewlines t: String -> String
  (if (stringContains? t "\r") (stringReplace (stringReplace t "\r\n" "\n") "\r" "\n") t)

fn serValue v: RVal -> String
  (match v
    ((rStr s) (c/serString s))
    ((rInt n) (stringFromInt64 n))
    ((rBool b) (if b "true" "false"))
    ((rList xs) (str "(" (stringJoin (map c/serString xs) " ") ")"))
    ((rPair a b) (str "(" (stringFromInt64 a) " " (stringFromInt64 b) ")"))
    ((rNone) "none"))

fn serReceipt r: (List (Pair String RVal)) -> String
  (str "(receipt" (stringJoin (map (fn [p] (str " (" (pairFirst p) " " (serValue (pairSecond p)) ")")) r) "") ")")

fn gateTimeoutSec -> Int64
  300

fn ! nowMono -> Float64
  (/ (int64ToFloat64 (monotonicNs)) 1000000000.0)

fn budgetLeft deadlineAt: (Option Float64) nowMono: Float64 -> (Option Float64)
  (match deadlineAt
    ((none) (none))
    ((some at) (some (- at nowMono))))

fn stepTimeout runTimeout: Int64 deadlineAt: (Option Float64) nowMono: Float64 -> Int64
  (match (budgetLeft deadlineAt nowMono)
    ((none) runTimeout)
    ((some left) (match (float64ToInt64 left)
                   ((some n) (max 1 (min runTimeout n)))
                   ((none) (if (> left 0.0) runTimeout 1)))))

fn engineSocketPath! rootDir: String -> String
  (let [envSock (optionOr (envGet "ASL_ENGINE_SOCKET") "")]
    (if (!= envSock "") envSock (str rootDir "/.asl/engine.sock")))

; (:m :tags (transport))
fn ! engineRequest sockPath: String line: String timeoutSec: Int64 -> (Result String (Pair String String))
  (match (etp/socketExchange! sockPath line (* (max 1 timeoutSec) 1000))
    ((ok ans) (ok (stringTrim ans)))
    ((err e) (err (pair (if (= e "timed out") "ERR_TIMEOUT" "ERR_SOCKET") e))))

fn envJson! env: (Option (List String)) -> j/Json
  (j/jobj (map (fn [row]
                 (match (stringIndexOf row "=")
                   ((some i) (pair (c/sliceOf row 0 i) (j/jstr (c/sliceOf row (+ i 1) (stringLength row)))))
                   ((none) (pair row (j/jstr "")))))
               (match env ((some rows) rows) ((none) (envList)))))

fn jsonInt v: (Option j/Json) -> (Option Int64)
  (match (optionOr v (j/jnull)) ((j/jint n) (some n)) (_ none))

fn jsonStr v: (Option j/Json) -> (Option String)
  (match (optionOr v (j/jnull)) ((j/jstr s) (some s)) (_ none))

; (:m :tags (transport))
fn ! runAslSocket sockPath: String form: String rootDir: String timeoutSec: Int64 env: (Option (List String)) -> (Result RunAslResult (Pair String String))
  (let [request (j/jsonEmit (j/jobj (list (pair "forms" (j/jarr (list (j/jstr form))))
                                          (pair "root" (j/jstr (t/normPath rootDir)))
                                          (pair "env" (envJson! env)))))]
    (match (engineRequest sockPath request timeoutSec)
      ((err e)
        (if (= (pairFirst e) "ERR_TIMEOUT")
          (ok (RunAslResult :exit 1 :stdout ""
                :stderr (str "no engine answer in " (stringFromInt64 timeoutSec) " s (:timeout true :seconds " (stringFromInt64 timeoutSec) ")")
                :timedOut true :seconds timeoutSec :fellBack ""))
          (err e)))
      ((ok ans)
        (match (j/jsonParse ans)
          ((err m) (err (pair "ERR_ENGINE_ANSWER" (str "the engine answer is not JSON: " m))))
          ((ok obj)
            (let [code (jsonInt (j/jsonGet obj "exit"))
                  out (jsonStr (j/jsonGet obj "stdout"))
                  errText (jsonStr (j/jsonGet obj "stderr"))]
              (if (and (some? code) (some? out) (some? errText))
                (ok (RunAslResult :exit (optionOr code 1) :stdout (optionOr out "") :stderr (optionOr errText "") :timedOut false :seconds 0 :fellBack ""))
                (err (pair "ERR_ENGINE_ANSWER" (str "the engine answer lacks exit, stdout or stderr: " (c/sliceOf ans 0 (min 200 (stringLength ans)))))))))))))

fn ! chooseTransport envVal: String sockPath: String -> (Pair String String)
  (cond
    ((= envVal "socket") (pair "socket" "ASL_TRANSPORT=socket"))
    ((= envVal "inProcess") (pair "inProcess" "ASL_TRANSPORT=inProcess"))
    ((= envVal "subprocess") (pair "subprocess" "ASL_TRANSPORT=subprocess"))
    ((not (ok? (fileStat sockPath))) (pair "subprocess" (str "no engine socket at " sockPath)))
    (else
      (match (engineRequest sockPath "(:ping)" 2)
        ((ok ans)
          (if (stringStartsWith? ans "(:pong")
            (pair "socket" "")
            (pair "subprocess" (str "no pong at " sockPath ": " (c/sliceOf ans 0 (min 80 (stringLength ans)))))))
        ((err e) (pair "subprocess" (str "no ping answer at " sockPath ": " (pairSecond e)))))))

fn safeObserveDim? dim: String -> Bool
  (listContains? (list "memory" "session" "tokenCost") dim)

fn safeInProcessForm? form: String -> Bool
  (let [(steps (k/extractSteps form))]
    (and (= (listLength steps) 1)
         (match (listHead steps)
           ((none) false)
           ((some raw)
             (let [(step (k/parseStep raw))
                   (op step.op)]
                (or (listContains? (list "read" "query" "tree" "diff" "edit" "write"
                                         "flush" "discard" "txn" "note" "tools" "help" "where") op)
                    (and (= op "intel") (= (optionOr (mapGet step.kwargs "op") "") "outline"))
                    (and (= op "observe")
                         (safeObserveDim? (optionOr (mapGet step.kwargs "dim") "")))))))))

fn ! chooseTransportFor envVal: String sockPath: String form: String -> (Pair String String)
  (cond
    ((= envVal "socket") (pair "socket" "ASL_TRANSPORT=socket"))
    ((= envVal "inProcess") (pair "inProcess" "ASL_TRANSPORT=inProcess"))
    ((= envVal "subprocess") (pair "subprocess" "ASL_TRANSPORT=subprocess"))
    ((safeInProcessForm? form) (pair "inProcess" ""))
    (else (chooseTransport "" sockPath)))

; (:m :tags (transport leon))
fn transportField mode: String why: String -> String
  (str ":transport :" mode (if (!= why "") (str " :transportWhy \"" (c/escapeAsn why) "\"") ""))

fn pyStrip s: String -> String
  (let [n (stringLength s)
        i (runEnd s n 0 isSpace)]
    (c/sliceOf s i (max i (t/stripRightAt s n))))

fn bestIndex! lines: (List String) target: String k: Int64 i: Int64 maxI: Int64 bestI: Int64 bestScore: Float64 -> Int64
  (if (> i maxI)
    bestI
    (let [cand (pyStrip (stringJoin (optionOr (listSlice lines i (+ i k)) (list)) "\n"))
          score (diff/ratio cand target)]
      (if (> score bestScore)
        (bestIndex! lines target k (+ i 1) maxI i score)
        (bestIndex! lines target k (+ i 1) maxI bestI bestScore))))

; (:m :tags (leon))
fn ! nearestLines root: String filePath: String old: String -> (Option (Pair (Pair Int64 Int64) String))
  (let [full (t/normPath (if (stringStartsWith? filePath "/") filePath (str root "/" filePath)))]
    (match (t/readText! full)
      ((fileAbsent) (none))
      ((fileFailed _) (none))
      ((fileText text)
        (let [lines (t/splitLines text)
              n (listLength lines)]
          (cond
            ((= n 0) (none))
            ((<= n 60) (some (pair (pair 1 n) (str (stringJoin lines "\n") "\n"))))
            (else
              (let [oldLines (t/splitLines old)
                    k (max 1 (listLength oldLines))
                    target (pyStrip old)
                    maxI (- n k)]
                (if (< maxI 0)
                  (none)
                  (let [best (bestIndex! lines target k 0 maxI 0 -1.0)
                        a (max 0 (- best 3))
                        b (min n (+ (+ best k) 3))
                        slice (optionOr (listSlice lines a b) (list))]
                    (some (pair (pair (+ a 1) b) (str (stringJoin slice "\n") "\n"))))))))))))

fn isWordChar c: String -> Bool
  (or (c/isDigit c) (or (and (>= c "a") (<= c "z")) (or (and (>= c "A") (<= c "Z")) (= c "_"))))

fn placeholderLoop text: String n: Int64 pos: Int64 -> Bool
  (match (stringIndexOf (c/sliceOf text pos n) "assert")
    ((none) false)
    ((some relPos)
      (let [i (+ pos relPos)]
        (if (and (> i 0) (isWordChar (c/sliceOf text (- i 1) i)))
          (placeholderLoop text n (+ i 6))
          (let [p (+ i 6)]
            (if (or (>= p n) (not (isSpace (c/sliceOf text p (+ p 1)))))
              (placeholderLoop text n (+ i 6))
              (let [j (runEnd text n p isSpace)]
                (cond
                  ((and (<= (+ j 5) n) (or (= (c/sliceOf text j (+ j 5)) "false") (= (c/sliceOf text j (+ j 5)) "False")))
                    (if (or (= (+ j 5) n) (not (isWordChar (c/sliceOf text (+ j 5) (+ j 6)))))
                      true
                      (placeholderLoop text n (+ i 6))))
                   (else (placeholderLoop text n (+ i 6)))))))))))

fn placeholderAssert? text: String -> Bool
  (placeholderLoop text (stringLength text) 0)

fn pollSet sp: SpawnedProc outOpen: Bool errOpen: Bool -> (List (Pair Int64 Int64))
  (listAppend (if outOpen (list (pair sp.stdout 1)) (list)) (if errOpen (list (pair sp.stderr 1)) (list)))

fn readyOn ready: (List (Pair Int64 Int64)) fd: Int64 -> Bool
  (listAny? (fn [p] (= (pairFirst p) fd)) ready)

fn readPipe! fd: Int64 open: Bool isReady: Bool text: String -> (Pair Bool String)
  (if (not (and open isReady))
    (pair open text)
    (match (fdRead fd 65536)
      ((ok chunk) (if (stringEmpty? chunk) (do (fdClose fd) (pair false text)) (pair true (str text chunk))))
      ((err e) (if (= e "wouldBlock") (pair true text) (do (fdClose fd) (pair false text))))))

fn closePipes! sp: SpawnedProc outOpen: Bool errOpen: Bool -> Bool
  (do
    (if outOpen (fdClose sp.stdout) (ok ()))
    (if errOpen (fdClose sp.stderr) (ok ()))
    true)

fn leftMs! deadline: (Option Int64) -> Int64
  (match deadline ((some d) (max 0 (/ (- d (monotonicNs)) 1000000))) ((none) -1))

fn pumpPipes! sp: SpawnedProc outOpen: Bool errOpen: Bool out: String errText: String deadline: (Option Int64) -> PumpEnd
  (if (not (or outOpen errOpen))
    (pumpDone out errText)
    (let [ms (leftMs! deadline)]
      (if (= ms 0)
        (pumpLate outOpen errOpen out errText)
        (match (fdPoll (pollSet sp outOpen errOpen) ms)
          ((err e) (do (closePipes! sp outOpen errOpen) (pumpFailed (str "poll failed: " e))))
          ((ok ready)
            (let [o (readPipe! sp.stdout outOpen (readyOn ready sp.stdout) out)
                  r (readPipe! sp.stderr errOpen (readyOn ready sp.stderr) errText)]
              (pumpPipes! sp (pairFirst o) (pairFirst r) (pairSecond o) (pairSecond r) deadline)))))))

fn waitExit! pid: Int64 deadline: (Option Int64) -> (Result (Option Int64) String)
  (match deadline
    ((none) (procWaitPid pid false))
    ((some d)
      (match (procWaitPid pid true)
        ((err e) (err e))
        ((ok got)
          (match got
            ((some code) (ok (some code)))
            ((none) (if (>= (monotonicNs) d) (ok (none)) (do (sleepMs 5) (waitExit! pid deadline)))))))))

fn killGroup! pid: Int64 -> Bool
  (match (procKill (- 0 pid) "SIGKILL") ((ok _) true) ((err _) false))

fn afterKill! sp: SpawnedProc outOpen: Bool errOpen: Bool out: String errText: String -> (Result Bounded String)
  (let [drained (pumpPipes! sp outOpen errOpen out errText (some (+ (monotonicNs) 5000000000)))
        texts (match drained
                ((pumpDone o e) (pair o e))
                ((pumpLate oo eo _ _) (do (closePipes! sp oo eo) (pair "" "")))
                ((pumpFailed _) (pair "" "")))]
    (match (procWaitPid sp.pid false)
      ((err e) (err e))
      ((ok _) (ok (Bounded :code (none) :out (universalNewlines (pairFirst texts)) :errText (universalNewlines (pairSecond texts)) :timedOut true)))))

fn spawnError path: String kind: String -> String
  (cond
    ((= kind "notFound") (str "[Errno 2] No such file or directory: '" path "'"))
    ((= kind "permission") (str "[Errno 13] Permission denied: '" path "'"))
    (else (str "spawn failed: " kind)))

fn ! runBounded argv: (List String) cwd: (Option String) timeoutSec: (Option Int64) env: (Option (List String)) -> (Result Bounded String)
  (match (procSpawnv argv cwd env)
    ((err kind) (err (spawnError (optionOr (listHead argv) "") kind)))
    ((ok sp)
      (let [closed (fdClose sp.stdin)
            deadline (match timeoutSec ((some t) (some (+ (monotonicNs) (* t 1000000000)))) ((none) (none)))]
        (match (pumpPipes! sp true true "" "" deadline)
          ((pumpFailed m) (do (killGroup! sp.pid) (procWaitPid sp.pid false) (err m)))
          ((pumpLate oo eo o e) (do (killGroup! sp.pid) (afterKill! sp oo eo o e)))
          ((pumpDone o e)
            (match (waitExit! sp.pid deadline)
              ((err m) (err m))
              ((ok got)
                (match got
                  ((none) (do (killGroup! sp.pid) (afterKill! sp false false o e)))
                  ((some code) (ok (Bounded :code (some code) :out (universalNewlines o) :errText (universalNewlines e) :timedOut false)))))))))))

; (:m :tags (transport))
fn envWithAslRoot! rootDir: String env: (Option (List String)) -> (List String)
  (let [base (match env ((some rows) rows) ((none) (envList)))
        filtered (filter (fn [r] (not (stringStartsWith? r "ASL_ROOT="))) base)
        homed (if (listAny? (fn [r] (stringStartsWith? r "HOME=")) filtered)
                filtered
                (match (envGet "HOME")
                  ((none) filtered)
                  ((some h) (cons (str "HOME=" h) filtered))))]
    (cons (str "ASL_ROOT=" (t/normPath rootDir)) homed))

fn envOverride key: String env: (Option (List String)) -> (Option String)
  (match (listHead (filter (fn [row] (stringStartsWith? row (str key "="))) (optionOr env (list))))
    ((none) (none))
    ((some row) (stringSlice row (+ (stringLength key) 1) (stringLength row))))

; (:m :ref FABLE-BLIND-03 :do "an asl form run as a subprocess executes the unit's own files (a test op runs any .asl file the unit wrote, a check expands its macros), so it is a unit child like a run op: the allowlisted env of jail#childEnvIn! (no provider key, no harness setting) with private caches seeded from the shared ones, plus ASL_ROOT and, of rows the caller passes explicitly, the non-secret ASL_ ones; the argv goes through jail#jailWrap!, loopback-only network. A missing root or a binary that is absent or not executable keeps the plain spawn, which cannot start anything")
fn explicitRow? row: String -> Bool
  (let [name (jl/envKey row)]
    (and (not (jl/secretName? name)) (and (stringStartsWith? name "ASL_") (not (listContains? (jl/cacheNames) name)))))

fn ! jailedAsl! aslBin: String form: String rootDir: String env: (Option (List String)) -> (Pair (List String) (List String))
  (let [absRoot (resultOr (realPath rootDir) rootDir)
        toolRoot (if (stringEndsWith? aslBin "/bin/asl") (c/sliceOf aslBin 0 (- (stringLength aslBin) 8)) absRoot)
        base (match env ((some rows) rows) ((none) (envList)))
        extra (cons (str "ASL_ROOT=" (t/normPath rootDir))
                (match env ((some rows) (filter (fn [r] (and (explicitRow? r) (not (stringStartsWith? r "ASL_ROOT=")))) rows)) ((none) (list))))
        extraKeys (map jl/envKey extra)
        rows (listAppend (filter (fn [r] (not (listContains? extraKeys (jl/envKey r)))) (jl/childEnvIn! absRoot base (list) (optionOr (envGet "HOME") "") true)) extra)
        jail (jl/jailOf! absRoot (jl/jailHome absRoot) rows (list toolRoot) (list) false)]
    (pair (jl/jailWrap! jail (list aslBin form)) rows))

fn ! isDirAt! p: String -> Bool
  (match (fileStat p) ((ok st) st.isDir) ((err _) false))

fn ! runnable! p: String -> Bool
  (match (fileStat p) ((ok st) (and st.isFile (!= (& st.mode 73) 0))) ((err _) false))

fn ! runAslOnBin aslBin: String form: String rootDir: String timeoutSec: Int64 env: (Option (List String)) -> RunAslResult
  (let [jailed (if (and (isDirAt! rootDir) (runnable! aslBin))
                 (jailedAsl! aslBin form rootDir env)
                 (pair (list aslBin form) (envWithAslRoot! rootDir env)))
        argv (pairFirst jailed)
        childEnv (some (pairSecond jailed))
        res (runBounded argv (some rootDir) (some timeoutSec) childEnv)]
    (match res
      ((err m) (RunAslResult :exit 1 :stdout "" :stderr m :timedOut false :seconds 0 :fellBack ""))
      ((ok b)
        (if b.timedOut
          (RunAslResult :exit 1 :stdout b.out
            :stderr (str "killed after " (stringFromInt64 timeoutSec) " s (:timeout true :seconds " (stringFromInt64 timeoutSec) ")\n" b.errText)
            :timedOut true :seconds timeoutSec :fellBack "")
          (RunAslResult :exit (optionOr b.code 1) :stdout b.out :stderr b.errText :timedOut false :seconds 0 :fellBack "")))))

fn ! runAsl repoRoot: String form: String rootDir: String timeoutSec: Int64 env: (Option (List String)) mode: String -> RunAslResult
  (let [toolRoot repoRoot
        automatic (= mode "")
        selected (if automatic
                  (pairFirst (chooseTransportFor (optionOr (envOverride "ASL_TRANSPORT" env) (optionOr (envGet "ASL_TRANSPORT") "")) (engineSocketPath! toolRoot) form))
                  mode)
        decided (if (and (= selected "inProcess") (some? env)
                         (or (none? (envOverride "ASL_TRANSPORT" env))
                             (or (some? (envOverride "ASL_SESSION" env))
                                 (some? (envOverride "ASL_VFS_DIR" env))))) "subprocess" selected)
        aslBin (str toolRoot "/bin/asl")]
    (if (= decided "inProcess")
      (let [started (monotonicNs)
            result (forms/runPayloadText! (forms/workspaceFor! rootDir) form)
            elapsed (- (monotonicNs) started)]
        (RunAslResult :exit (pairSecond result) :stdout (pairFirst result) :stderr "" :timedOut false
          :seconds (/ elapsed 1000000000) :fellBack ""))
      (if (= decided "socket")
      (match (runAslSocket (engineSocketPath! toolRoot) form rootDir timeoutSec env)
        ((ok r) r)
        ((err e)
          (let [r (runAslOnBin aslBin form rootDir timeoutSec env)]
            (RunAslResult :exit r.exit :stdout r.stdout :stderr r.stderr :timedOut r.timedOut :seconds r.seconds :fellBack (pairSecond e)))))
      (runAslOnBin aslBin form rootDir timeoutSec env))))

fn getKvStr kv: (List (Pair String c/KvVal)) key: String -> String
  (match (listHead (filter (fn [p] (= (pairFirst p) key)) kv))
    ((some p) (match (pairSecond p) ((c/kvStr s) s) ((c/kvInt s) s)))
    (none ""))

fn allDigits s: String -> Bool
  (and (> (stringLength s) 0) (= (runEnd s (stringLength s) 0 c/isDigit) (stringLength s)))

fn countLns s: String n: Int64 pos: Int64 acc: Int64 -> Int64
  (if (>= pos n)
    acc
    (countLns s n (+ pos 1) (if (= (c/sliceOf s pos (+ pos 1)) "\n") (+ acc 1) acc)))

fn replaceFirst s: String oldStr: String newStr: String -> String
  (match (stringIndexOf s oldStr)
    ((none) s)
    ((some idx)
      (str (c/sliceOf s 0 idx) newStr (c/sliceOf s (+ idx (stringLength oldStr)) (stringLength s)))))

fn findReadContent s: String -> String
  (match (stringIndexOf s ":content \"")
    ((none) "")
    ((some idx)
      (let [start (+ idx 10)
            end (quotedEnd s (stringLength s) start)]
        (if (>= end start) (c/asnUnescape (c/sliceOf s start end)) ""))))

fn findIntField s: String prefix: String -> (Option Int64)
  (match (stringIndexOf s prefix)
    ((none) (none))
    ((some idx)
      (let [start (+ idx (stringLength prefix))
            n (stringLength s)
            end (runEnd s n start c/isDigit)]
        (if (> end start) (stringToInt64 (c/sliceOf s start end)) (none)))))

fn findMoreRange s: String -> (Option (Pair Int64 Int64))
  (match (stringIndexOf s ":truncated true")
    ((none) (none))
    ((some _)
      (match (stringIndexOf s ":more (:start ")
        ((none) (none))
        ((some mIdx)
          (let [sStart (+ mIdx 14)
                n (stringLength s)
                sEnd (runEnd s n sStart c/isDigit)]
            (match (stringIndexOf (c/sliceOf s sEnd n) " :end ")
              ((none) (none))
              ((some eRel)
                (let [eStart (+ (+ sEnd eRel) 6)
                      eEnd (runEnd s n eStart c/isDigit)]
                  (match (stringToInt64 (c/sliceOf s sStart sEnd))
                    ((none) (none))
                    ((some a)
                      (match (stringToInt64 (c/sliceOf s eStart eEnd))
                        ((none) (none))
                        ((some b) (some (pair a b))))))))))))))

fn byteAt s: String n: Int64 i: Int64 -> String
  (if (< i n) (ch s i) "")

fn afterKeySpace s: String n: Int64 j: Int64 -> Int64
  (let [k (runEnd s n j isSpace)]
    (if (= k j) -1 k))

fn errorCodeAt s: String n: Int64 i: Int64 -> (Option String)
  (let [j0 (+ i 6)
        j1 (if (and (<= (+ j0 5) n) (= (c/sliceOf s j0 (+ j0 5)) "-code")) (+ j0 5) j0)
        j2 (afterKeySpace s n j1)]
    (if (< j2 0)
      (none)
      (let [j3 (if (= (byteAt s n j2) "\"") (+ j2 1) j2)
            j4 (if (= (byteAt s n j3) ":") (+ j3 1) j3)
            j5 (runEnd s n j4 isWordChar)]
        (if (= j5 j4) (none) (some (c/sliceOf s j4 j5))))))

fn errorCodeFrom s: String n: Int64 pos: Int64 -> (Option String)
  (match (stringIndexOf (c/sliceOf s pos n) ":error")
    ((none) (none))
    ((some rel)
      (let [i (+ pos rel)]
        (match (errorCodeAt s n i)
          ((some code) (some code))
          ((none) (errorCodeFrom s n (+ i 1)))))))

fn findReadError s: String defaultErr: String -> String
  (optionOr (errorCodeFrom s (stringLength s) 0) defaultErr)

fn messageFrom s: String n: Int64 pos: Int64 -> (Option String)
  (match (stringIndexOf (c/sliceOf s pos n) ":message")
    ((none) (none))
    ((some rel)
      (let [i (+ pos rel)
            j (afterKeySpace s n (+ i 8))
            end (if (and (>= j 0) (= (byteAt s n j) "\"")) (quotedEnd s n (+ j 1)) -1)]
        (if (< end 0) (messageFrom s n (+ i 1)) (some (c/sliceOf s (+ j 1) end))))))

fn findReadMsg s: String errText: String -> String
  (match (messageFrom s (stringLength s) 0)
    ((some m) m)
    ((none)
      (let [stripped (pyStrip s)]
        (if (!= stripped "") (c/sliceOf stripped 0 (min 300 (stringLength stripped))) errText))))

fn ! countFileLines path: String -> (Option Int64)
  (match (fileStat path)
    ((err _) (none))
    ((ok st)
      (if st.isDir
        (none)
        (match (fileReadString path)
          ((err _) (none))
          ((ok t) (some (listLength (t/splitLines t))))))))

fn ! findAnchorLine path: String anchor: String -> Int64
  (match (fileReadString path)
    ((err _) 1)
    ((ok t)
      (match (stringIndexOf t anchor)
        ((none) 1)
        ((some idx) (+ (countLns t idx 0 0) 1)))))

fn formatReadBody content: String cap: Int64 totalLines: (Option Int64) mStart: (Option Int64) mMore: (Option (Pair Int64 Int64)) -> (Pair String String)
  (let [cLen (stringLength content)]
    (cond
      ((and (> cLen 0) (and (some? mMore) (<= cLen cap)))
        (let [mr (optionOr mMore (pair 0 0))
              s (stringFromInt64 (pairFirst mr))
              e (stringFromInt64 (pairSecond mr))
              tailMsg (str "\n... [lines " s "-" e " not shown; read :start " s " :end n, or :symbol name]")
              fullCont (str content tailMsg)
              body (c/sliceOf fullCont 0 (min (+ cap 200) (stringLength fullCont)))]
          (pair fullCont body)))
      ((> cLen cap)
        (let [shown (c/sliceOf content 0 cap)
              shownLns (countLns shown (stringLength shown) 0 0)
              startN (optionOr mStart 1)
              shownEnd (- (+ startN shownLns) 1)
              totStr (match totalLines ((some tl) (stringFromInt64 tl)) ((none) "None"))
              tailMsg (str "\n... [cut at line " (stringFromInt64 shownEnd) " of " totStr "; read :start " (stringFromInt64 (+ shownEnd 1)) " :end n, or :symbol name]")
              fullCont (str shown tailMsg)]
          (pair fullCont shown)))
      (else (pair content content))))

fn parseOutlineItems stdout: String -> String
  (let [items (t/outlineItems stdout (stringLength stdout) 0 (list))]
    (stringJoin
      (map (fn [w] (match w ((t/widenItem a b nm kd) (str (stringFromInt64 a) "-" (stringFromInt64 b) " " kd " " nm))))
        items)
      "\n"))

fn intelSubops -> (List String)
  (list "outline" "impact" "coupling" "graph" "deadcode" "complexity" "stubs" "query")

fn validIntelSubop? sub: String -> Bool
  (listContains? (intelSubops) sub)

; (:m :tags (owns) :do "no :owns on the session means the session may write anywhere inside :root; an empty owns list sends the unrestricted \"**\" scope instead of an empty one")
fn repairNote fixed: (Option (Pair String String)) -> String
  (match fixed ((some f) (pairSecond f)) ((none) ""))

fn buildWriteForm filePath: String content: String force: Bool owns: (List String) -> String
  (let [ownsAsn (stringJoin (map (fn [o] (str "\"" (pyStrip o) "\"")) (if (listEmpty? owns) (list "**") owns)) " ")
        forceAsn (if force " :force true" "")]
    (str "(:txn :owns (" ownsAsn ") (:write :file \"" filePath "\" :content \"" (c/escapeAsn content) "\"" forceAsn "))"))

fn buildEditForm filePath: String old: String new: String owns: (List String) -> String
  (let [ownsAsn (stringJoin (map (fn [o] (str "\"" (pyStrip o) "\"")) (if (listEmpty? owns) (list "**") owns)) " ")]
    (str "(:txn :owns (" ownsAsn ") (:edit :file \"" filePath "\" :old \"" (c/escapeAsn old) "\" :new \"" (c/escapeAsn new) "\"))"))

fn buildReadForm filePath: String symbol: String anchor: String start: String end: String cap: Int64 -> String
  (let [f0 (str "(:read :file \"" (c/escapeAsn filePath) "\"")
        f1 (if (!= symbol "") (str f0 " :symbol \"" (c/escapeAsn symbol) "\"") f0)
        f2 (if (!= anchor "") (str f1 " :anchor \"" (c/escapeAsn anchor) "\"") f1)
        f3 (if (allDigits start) (str f2 " :start " (stringFromInt64 (optionOr (stringToInt64 start) 0))) f2)
        f4 (if (allDigits end) (str f3 " :end " (stringFromInt64 (optionOr (stringToInt64 end) 0))) f3)
        f5 (if (> cap 8000) (str f4 " :limit " (stringFromInt64 (/ cap 20)) " :maxBytes " (stringFromInt64 cap)) f4)]
    (str f5 ")"))

fn buildQueryForm qText: String inMode: String limitStr: String -> String
  (let [f0 (str "(:query :text \"" (c/escapeAsn qText) "\"")
        cleanIn (if (stringStartsWith? inMode ":") (c/sliceOf inMode 1 (stringLength inMode)) inMode)
        f1 (if (listContains? (list "code" "text" "all") cleanIn) (str f0 " :in " cleanIn) f0)
        f2 (if (allDigits limitStr) (str f1 " :limit " limitStr) f1)]
    (str f2 ")"))

fn buildIntelForm sub: String op: (List (Pair String c/KvVal)) -> String
  (let [f0 (str "(:intel :op " sub)
        keys (list "file" "symbol" "target" "filter")
        args (fold (fn [acc k]
                     (let [v (getKvStr op k)]
                       (if (!= v "") (str acc " :" k " \"" (c/escapeAsn v) "\"") acc)))
               f0 keys)]
    (str args ")"))

fn ! outlineText filePath: String root: String run: (fn [String String] -> t/AslRun) -> String
  (let [form (buildIntelForm "outline" (list (pair "file" (c/kvStr filePath))))
        res (run form root)]
    (parseOutlineItems (aslRunOut res)))

; (:m :ref LEON-CAPS :do "a whole-file read above this many bytes answers with the file's outline and a hint to read by symbol instead of the body; project-tunable as :agentLoop (:readOutlineBytes N) in .asl.config.asn, same key-scan style as the other agentLoop limits")
fn readOutlineBytes -> Int64
  16384

fn readOutlineBytesIn text: String -> (Option Int64)
  (match (ac/agentLoopValue text ":readOutlineBytes")
    ((none) none)
    ((some v) (ac/positiveInt v)))

; (:m :ref LEON-CAPS :do "a configured value that is not a positive integer is an error the read op reports, never a silent fallback to the default")
fn ! readOutlineBytesFor! root: String -> (Result Int64 String)
  (let [text (ac/configText! root)]
    (match (ac/agentLoopValue text ":readOutlineBytes")
      ((none) (ok (readOutlineBytes)))
      ((some v)
        (match (ac/positiveInt v)
          ((some n) (ok n))
          ((none) (err (str ":agentLoop :readOutlineBytes must be a positive integer, got \"" v "\"")))))))

fn oversizeBytesHint size: Int64 limit: Int64 -> String
  (str "read of " (stringFromInt64 size) " bytes exceeds the " (stringFromInt64 limit) "-byte whole-file limit; this is the file's outline instead -- read a section by :symbol name, or :start n :end m")

fn oversizeWholeHint -> String
  "read exceeded the payload cap; this is the file's outline instead -- read a section by :symbol name, or :start n :end m"

fn buildSearchForm qText: String limitStr: String engine: String -> String
  (let [f0 (str "(:search :query \"" (c/escapeAsn qText) "\"")
        f1 (if (allDigits limitStr) (str f0 " :limit " limitStr) f0)
        f2 (if (!= engine "") (str f1 " :engine \"" (c/escapeAsn engine) "\"") f1)]
    (str f2 ")"))

fn buildResearchForm topic: String depth: String -> String
  (let [f0 (str "(:research :topic \"" (c/escapeAsn topic) "\"")
        cleanDepth (if (stringStartsWith? depth ":") (c/sliceOf depth 1 (stringLength depth)) depth)
        f1 (cond
             ((= depth "") f0)
             ((allDigits depth) (str f0 " :depth " depth))
             (else (str f0 " :depth :" cleanDepth)))]
    (str f1 ")"))

fn buildCrawlForm url: String distill: String limitStr: String -> String
  (let [f0 (str "(:crawl :url \"" (c/escapeAsn url) "\"")
        cleanDistill (if (stringStartsWith? distill ":") (c/sliceOf distill 1 (stringLength distill)) distill)
        f1 (if (!= distill "") (str f0 " :distill :" cleanDistill) f0)
        f2 (if (allDigits limitStr) (str f1 " :limit " limitStr) f1)]
    (str f2 ")"))

fn buildElseForm opName: String op: (List (Pair String c/KvVal)) -> String
  (let [argKeys (cond
                  ((= opName "tree") (list "path"))
                  ((= opName "test") (list "file"))
                  ((= opName "help") (list "name" "topic"))
                  ((= opName "tools") (list "scope"))
                  ((= opName "fix") (list "file"))
                  ((= opName "observe") (list "dim" "symbol" "path" "module" "spec" "id" "scope" "limit"))
                  (else (list)))
        f0 (str "(:" opName)
        args (fold (fn [acc k]
                     (let [v (getKvStr op k)]
                       (if (= v "")
                         acc
                         (cond
                           ((= opName "observe")
                             (cond
                               ((and (= k "dim") (= (runEnd v (stringLength v) 0 (fn [ch] (or (and (>= ch "a") (<= ch "z")) (and (>= ch "A") (<= ch "Z"))))) (stringLength v)))
                                 (str acc " :dim " v))
                               ((and (= k "limit") (allDigits v)) (str acc " :limit " v))
                               (else (str acc " :" k " \"" (c/escapeAsn v) "\""))))
                           ((and (= opName "help") (= k "name")) (str acc " :op " v))
                           ((or (= k "scope") (= k "topic"))
                             (let [cv (if (stringStartsWith? v ":") (c/sliceOf v 1 (stringLength v)) v)]
                               (str acc " :" k " :" cv)))
                           (else (str acc " :" k " \"" (c/escapeAsn v) "\""))))))
               f0 argKeys)]
    (str args ")"))

fn aslRunCode r: t/AslRun -> Int64
  (match r ((t/aslRun code _ _) code))

fn aslRunOut r: t/AslRun -> String
  (match r ((t/aslRun _ out _) out))

fn aslRunErr r: t/AslRun -> String
  (match r ((t/aslRun _ _ errText) errText))

; (:m :ref LEON-PREFIX-CACHE-20261026 :do "a read-only read result is memoised on disk under .asl/run/agentLoop/memo, keyed by the sha256 of the read form, the resolved path and the file's current bytes: an identical read returns the stored result without running the form, and any write to the file changes its bytes and so misses. Only successful reads are stored; commands, writes and every other op never go through it")
fn memoDir root: String -> String
  (str root "/.asl/run/agentLoop/memo")

; (:m :do "the memo is scoped to one run: memoRunBegin! creates memo/<pid>-<sessionId>, memoRunEnd! removes only that dir, and the read path addresses it by the same session id, so concurrent runs in one root keep each other's entries. With no such dir nothing is read or stored. Pruning removes only dirs whose pid is dead and never leaves memoDir")
fn memoRunId session: String -> String
  (str (stringFromInt64 (procSelf)) "-" session)

fn memoSessionOk? session: String -> Bool
  (and (not (stringEmpty? session)) (and (not (stringContains? session "/")) (not (stringContains? session ".."))))

fn ! memoRunDir! root: String session: String -> (Option String)
  (if (memoSessionOk? session)
    (let [dir (str (memoDir root) "/" (memoRunId session))]
      (if (fileExists? dir) (some dir) none))
    none)

fn memoDirPid name: String -> (Option Int64)
  (let [parts (stringSplit name "-")]
    (if (< (listLength parts) 2) none (match (listGet parts 0) ((some p) (stringToInt64 p)) ((none) none))))

fn ! memoPrune! root: String -> Bool
  (let [base (memoDir root)
        names (resultOr (dirList base) (list))]
    (fold (fn [acc name]
            (match (memoDirPid name)
              ((some pid) (if (and (> pid 1) (not (resultOr (procAlive? pid) false)))
                            (and (ok? (pathRemove (str base "/" name))) acc)
                            acc))
              ((none) acc)))
          true names))

fn ! memoRunBegin! root: String session: String -> (Result String String)
  (if (memoSessionOk? session)
    (let [id (memoRunId session)
          _pruned (memoPrune! root)]
      (match (dirCreate (str (memoDir root) "/" id))
        ((err e) (err e))
        ((ok _) (ok id))))
    (err "memo session id unusable"))

fn ! memoRunBeginIfOn! root: String session: String -> Bool
  (if (toolMemoOn! root) (ok? (memoRunBegin! root session)) true)

fn ! memoRunEnd! root: String session: String -> Bool
  (if (memoSessionOk? session) (ok? (pathRemove (str (memoDir root) "/" (memoRunId session)))) true)

fn memoFile dir: String key: String -> String
  (str dir "/" key ".memo")

; (:m :do "the memo is opt-in per workspace with :toolMemo true in .asl.config.asn: callers that inject a fake run, and tests that compare receipts across transports, must see every read reach the run")
fn toolMemoIn text: String -> Bool
  (= (ac/agentLoopValue text ":toolMemo") (some "true"))

fn ! toolMemoOn! root: String -> Bool
  (match (fileReadString (str root "/.asl.config.asn"))
    ((ok text) (toolMemoIn text))
    ((err _) false))

fn ! memoKey root: String form: String fullPath: String -> (Option String)
  (match (fileReadString fullPath)
    ((err _) none)
    ((ok text) (some (bytesSha256 (stringToBytes (str form "\n" fullPath "\n" text))))))

fn ! memoGet! dir: String key: String -> (Option MemoEntry)
  (match (fileReadString (memoFile dir key))
    ((err _) none)
    ((ok text)
      (match (stringIndexOf text "\n")
        ((none) none)
        ((some nl)
          (let [parts (stringSplit (c/sliceOf text 0 nl) " ")
                code (stringToInt64 (c/firstOf parts))
                outLen (stringToInt64 (c/firstOf (c/restOf parts)))
                rid (optionOr (listGet parts 2) "")
                ts (match (listGet parts 3) ((some s) (stringToInt64 s)) ((none) none))
                age (match ts ((some t0) (- (nowNs) t0)) ((none) 600000000001))
                body (c/sliceOf text (+ nl 1) (stringLength text))]
            (match code
              ((none) none)
              ((some cd)
                (match outLen
                  ((none) none)
                  ((some ol)
                    (if (> ol (stringLength body)) none
                      (some (MemoEntry :run (t/aslRun cd (c/sliceOf body 0 ol) (c/sliceOf body ol (stringLength body))) :rid rid :age age))))))))))))

; (:m :do "a memo entry is written to a temp name and renamed into place so a reader never sees a partial file; any error means the entry is skipped, and the receipt says memo skipped")
fn ! memoPut! dir: String key: String rid: String res: t/AslRun -> Bool
  (let [out (aslRunOut res)
        path (memoFile dir key)
        tmp (str path ".tmp" (stringFromInt64 (procSelf)))
        body (str (stringFromInt64 (aslRunCode res)) " " (stringFromInt64 (stringLength out)) " " rid " " (stringFromInt64 (nowNs)) "\n" out (aslRunErr res))]
    (match (fileWrite tmp body)
      ((err _) false)
      ((ok _) (ok? (pathRename tmp path)))))

fn ! execAslOpMemo! op: (List (Pair String c/KvVal)) owns: (List String) root: String session: String newId: (fn [] -> String) snap: (fn [String] -> Bool) run: (fn [String String] -> t/AslRun) cap: Int64 budgetLeft: (Option Float64) -> (List (Pair String RVal))
  (let [opHead (getKvStr op "_head")
        rawOpName (let [o (getKvStr op "op")] (if (!= o "") o opHead))
        opName (if (= rawOpName "") "step" rawOpName)
        rid (newId)]
    (cond
      ((= opName "write")
        (let [filePath (getKvStr op "file")
              content0 (getKvStr op "content")
              force (c/truthy (c/dictGet op "force"))
              form (buildWriteForm filePath content0 force owns)
              _ (snap filePath)
              res0 (run form root)
              ref0 (if (!= (aslRunCode res0) 0) (t/txnRefusal (aslRunOut res0) (aslRunErr res0) "ERR_WRITE_FAILED" (some content0)) (pair "" ""))
              delim0 (and (!= (aslRunCode res0) 0) (or (stringContains? (aslRunOut res0) "ERR_TXN_FLUSH_FAILED") (stringContains? (pairSecond ref0) "refused: the delimiters")))
              fixed (if delim0 (t/balanceRepair content0) (none))
              res1 (match fixed ((some f) (run (buildWriteForm filePath (pairFirst f) force owns) root)) ((none) res0))
              usable (and (some? fixed) (= (aslRunCode res1) 0))
              content (match fixed ((some f) (if usable (pairFirst f) content0)) ((none) content0))
              res (if usable res1 res0)
              code (aslRunCode res)
              out (aslRunOut res)
              errText (aslRunErr res)
              st (if (= code 0) "ok" "rejected")
              ref (if (!= code 0) (t/txnRefusal out errText "ERR_WRITE_FAILED" (some content)) (pair "" ""))
              refErr (pairFirst ref)
              refMsg (pairSecond ref)
              err0 (cond
                     ((stringContains? out "ERR_OWNS") "ERR_OWNS")
                     ((= refErr "ERR_TXN_ABORTED") "ERR_TXN_ABORTED")
                     ((or (stringContains? out "ERR_TXN_FLUSH_FAILED") (stringContains? refMsg "refused: the delimiters")) "ERR_TXN_FLUSH_FAILED")
                     ((stringContains? out "ERR_TXN_ABORTED") "ERR_TXN_ABORTED")
                     (else refErr))
              extra (if (or (= err0 "ERR_TXN_FLUSH_FAILED") (stringContains? refMsg "the delimiters ( ) [ ] { } and quotes do not balance")) "change an existing file with one edit per fn you touch, never resend the whole file" "")
              fullMsg (str refMsg " " out " " errText)
              aid (if (!= code 0) (t/abortAid! root filePath (list (t/txnStep "write" filePath (list (pair "content" (c/kvStr content))))) fullMsg extra) (none))
              balance (if (and (!= code 0) (or (= err0 "ERR_TXN_FLUSH_FAILED") (stringContains? refMsg "refused: the delimiters"))) (t/balanceAid content) (none))
              rawTmpl (t/retryTemplate filePath (match (fileReadString (str root "/" filePath)) ((ok s) (stringLength s)) ((err _) 0)))
              hint0 (match aid ((some x) (match x ((t/abortAidOf _ _ h) (some h)))) ((none) (none)))
              fix (if (some? balance) (t/balanceFix content) (none))
              hint (if (!= code 0)
                     (if (some? fix)
                       (some (str (optionOr fix "") "; " rawTmpl))
                       (if (or (= err0 "ERR_TXN_FLUSH_FAILED") (= err0 "ERR_TXN_ABORTED"))
                         (match hint0 ((some h) (some (str h "; " rawTmpl))) ((none) (some rawTmpl)))
                         hint0))
                     (none))]
          (listAppend
            (listAppend
              (list (pair "id" (rStr rid)) (pair "op" (rStr "write")) (pair "file" (rStr filePath)) (pair "status" (rStr st))
                (pair "error" (if (= code 0) (rNone) (rStr err0)))
                (pair "message" (if (= code 0) (rNone) (rStr refMsg)))
                (pair "cmd" (rStr (str "asl txn write " filePath))))
              (if usable (list (pair "repaired" (rStr (repairNote fixed)))) (list)))
            (listAppend
              (match balance ((some b) (list (pair "balance" (rStr b)))) ((none) (list)))
              (listAppend
                (list (pair "exit" (rInt code)) (pair "stdout" (rStr out)) (pair "persisted" (rBool (= code 0))))
                (listAppend
                  (match aid ((some x) (match x ((t/abortAidOf k a _) (list (pair "line" (rInt k)) (pair "arrived" (rStr a)))))) ((none) (list)))
                  (listAppend
                    (match hint ((some h) (list (pair "hint" (rStr h)))) ((none) (list)))
                    (if (and (= code 0) (placeholderAssert? content))
                      (list (pair "warning" (rStr "placeholder assert: red-first needs a real assertion on the missing behaviour")))
                      (list)))))))))
      ((= opName "edit")
        (let [filePath (getKvStr op "file")
              old (getKvStr op "old")
              new (getKvStr op "new")
              form (buildEditForm filePath old new owns)
              _ (snap filePath)
              res0 (run form root)
              fullTarget (t/normPath (if (stringStartsWith? filePath "/") filePath (str root "/" filePath)))
              afterEdit (match (t/readText! fullTarget)
                          ((fileText curF) (if (stringContains? curF old) (some (replaceFirst curF old new)) (none)))
                          (_ (none)))
              ref0 (if (!= (aslRunCode res0) 0) (t/txnRefusal (aslRunOut res0) (aslRunErr res0) "ERR_EDIT_FAILED" afterEdit) (pair "" ""))
              delim0 (and (!= (aslRunCode res0) 0) (or (stringContains? (aslRunOut res0) "ERR_TXN_FLUSH_FAILED") (stringContains? (pairSecond ref0) "refused: the delimiters")))
              fixed (if delim0 (t/balanceRepair (optionOr afterEdit "")) (none))
              res1 (match fixed ((some f) (run (buildWriteForm filePath (pairFirst f) false owns) root)) ((none) res0))
              usable (and (some? fixed) (= (aslRunCode res1) 0))
              res (if usable res1 res0)
              code (aslRunCode res)
              out (aslRunOut res)
              errText (aslRunErr res)
              st (if (= code 0) "ok" "rejected")
              ref (if (!= code 0) (t/txnRefusal out errText "ERR_EDIT_FAILED" afterEdit) (pair "" ""))
              refErr (pairFirst ref)
              refMsg (pairSecond ref)
              err0 (cond
                     ((stringContains? out "ERR_OWNS") "ERR_OWNS")
                     ((= refErr "ERR_TXN_ABORTED") "ERR_TXN_ABORTED")
                     ((or (stringContains? out "ERR_TXN_FLUSH_FAILED") (stringContains? refMsg "refused: the delimiters")) "ERR_TXN_FLUSH_FAILED")
                     ((stringContains? out "ERR_TXN_ABORTED") "ERR_TXN_ABORTED")
                     (else refErr))
              extra (if (or (= err0 "ERR_TXN_FLUSH_FAILED") (stringContains? refMsg "the delimiters ( ) [ ] { } and quotes do not balance")) "change an existing file with one edit per fn you touch, never resend the whole file" "")
              fullMsg (str refMsg " " out " " errText)
              aid (if (!= code 0) (t/abortAid! root filePath (list (t/txnStep "edit" filePath (list (pair "old" (c/kvStr old)) (pair "new" (c/kvStr new))))) fullMsg extra) (none))
              balance (if (and (!= code 0) (or (= err0 "ERR_TXN_FLUSH_FAILED") (stringContains? refMsg "refused: the delimiters"))) (t/balanceAid (optionOr afterEdit "")) (none))
              rawTmpl (t/retryTemplate filePath (match (fileReadString (str root "/" filePath)) ((ok s) (stringLength s)) ((err _) 0)))
              hint0 (match aid ((some x) (match x ((t/abortAidOf _ _ h) (some h)))) ((none) (none)))
              fix (if (some? balance) (t/balanceFix (optionOr afterEdit "")) (none))
              hint (if (!= code 0)
                     (if (some? fix)
                       (some (str (optionOr fix "") "; " rawTmpl))
                       (if (or (= err0 "ERR_TXN_FLUSH_FAILED") (= err0 "ERR_TXN_ABORTED"))
                         (match hint0 ((some h) (some (str h "; " rawTmpl))) ((none) (some rawTmpl)))
                         hint0))
                     (none))
              noMatch (or (stringContains? out "ERR_NO_MATCH") (stringContains? refMsg "Old target string not found"))
              near (if (and (!= st "ok") noMatch) (nearestLines root filePath old) (none))
              finalMsg (match near ((some _) (str refMsg "; the file's lines nearest the :old follow")) ((none) refMsg))]
          (listAppend
            (match near ((some p) (list (pair "span" (rPair (pairFirst (pairFirst p)) (pairSecond (pairFirst p)))) (pair "content" (rStr (pairSecond p))))) ((none) (list)))
            (listAppend
              (listAppend
                (list (pair "id" (rStr rid)) (pair "op" (rStr "edit")) (pair "file" (rStr filePath)) (pair "status" (rStr st))
                  (pair "error" (if (= code 0) (rNone) (rStr err0)))
                  (pair "message" (if (= code 0) (rNone) (rStr finalMsg)))
                  (pair "cmd" (rStr (str "asl txn edit " filePath))))
                (if usable (list (pair "repaired" (rStr (repairNote fixed)))) (list)))
              (listAppend
                (match balance ((some b) (list (pair "balance" (rStr b)))) ((none) (list)))
                (listAppend
                  (list (pair "exit" (rInt code)) (pair "stdout" (rStr out)) (pair "persisted" (rBool (= code 0))))
                  (listAppend
                    (match aid ((some x) (match x ((t/abortAidOf k a _) (list (pair "line" (rInt k)) (pair "arrived" (rStr a)))))) ((none) (list)))
                    (listAppend
                      (match hint ((some h) (list (pair "hint" (rStr h)))) ((none) (list)))
                      (if (and (= code 0) (placeholderAssert? new))
                        (list (pair "warning" (rStr "placeholder assert: red-first needs a real assertion on the missing behaviour")))
                        (list))))))))))
      ((= opName "read")
        (match (readOutlineBytesFor! root)
          ((err cfgMsg)
            (list (pair "id" (rStr rid)) (pair "op" (rStr "read")) (pair "file" (rStr (getKvStr op "file")))
              (pair "span" (rNone)) (pair "content" (rNone)) (pair "status" (rStr "rejected"))
              (pair "error" (rStr "ERR_CONFIG")) (pair "message" (rStr cfgMsg))
              (pair "cmd" (rStr (str "asl read " (getKvStr op "file")))) (pair "exit" (rInt 2)) (pair "stdout" (rStr ""))))
          ((ok outlineLimit)
        (let [filePath (getKvStr op "file")
              symbolVal (getKvStr op "symbol")
              anchorVal (getKvStr op "anchor")
              startVal (getKvStr op "start")
              endVal (getKvStr op "end")
              wholeFile (and (= symbolVal "") (and (= anchorVal "") (and (= startVal "") (= endVal ""))))
              widened (if (!= symbolVal "") (none) (t/widenToSymbol! filePath startVal endVal root cap budgetLeft run))
              effStart (match widened ((some w) (match w ((t/widenItem a _ _ _) (stringFromInt64 a)))) ((none) startVal))
              effEnd (match widened ((some w) (match w ((t/widenItem _ b _ _) (stringFromInt64 b)))) ((none) endVal))
              form (buildReadForm filePath symbolVal anchorVal effStart effEnd cap)
              memoPath (t/normPath (if (stringStartsWith? filePath "/") filePath (str root "/" filePath)))
              memoRun (if (toolMemoOn! root) (memoRunDir! root session) none)
              mkey (match memoRun ((some _) (memoKey root form memoPath)) ((none) none))
              memoDirNow (optionOr memoRun "")
              memoHit (match mkey ((some k) (memoGet! memoDirNow k)) ((none) none))
              res (match memoHit ((some e) e.run) ((none) (run form root)))
              putOk (match memoHit
                      ((some _) true)
                      ((none) (match mkey ((some k) (if (= (aslRunCode res) 0) (memoPut! memoDirNow k rid res) true)) ((none) true))))
              memoFresh (match memoHit ((some e) (and (!= e.rid "") (and (!= e.rid rid) (< e.age 600000000000)))) ((none) false))
              sameText (match memoHit ((some e) (str "(:same :id \"" e.rid "\" :note \"identical to that earlier result; read a narrower range for new text\")")) ((none) ""))
              code (aslRunCode res)
              out (aslRunOut res)
              errText (aslRunErr res)
              st (if (= code 0) "ok" "rejected")
              contentRaw (if (= code 0) (findReadContent out) "")
              fullPath (t/normPath (if (stringStartsWith? filePath "/") filePath (str root "/" filePath)))
              fileBytes (resultOr (fileSize fullPath) 0)
              overBytes (and wholeFile (and (= code 0) (> fileBytes outlineLimit)))
              oversizeWhole (and wholeFile (and (= code 0) (or overBytes (> (stringLength contentRaw) cap))))
              totalLines (countFileLines fullPath)
              mStart (findIntField out ":start ")
              mMore (findMoreRange out)
              preOut (c/firstOf (stringSplit (c/firstOf (stringSplit out ":content ")) ":more "))
              mFirst (findIntField preOut ":start ")
              firstLine (cond
                          ((some? mFirst) (optionOr mFirst 1))
                          ((and (!= anchorVal "") (some? totalLines)) (findAnchorLine fullPath anchorVal))
                          (else 1))
              outline (if oversizeWhole (outlineText filePath root run) "")
              useOutline (and oversizeWhole (not (stringEmpty? outline)))
              bodyPair (if useOutline (pair outline outline) (formatReadBody contentRaw cap totalLines mStart mMore))
              fullCont (pairFirst bodyPair)
              body (pairSecond bodyPair)
              partial (or (!= body fullCont) (stringEndsWith? body "\n"))
              last0 (- (+ firstLine (countLns body (stringLength body) 0 0)) (if partial 1 0))
              lastLine (match mMore ((some mr) (min last0 (- (pairFirst mr) 1))) ((none) last0))
              span (if (and (!= body "") (and (= code 0) (not useOutline))) (some (pair firstLine lastLine)) (none))
              errVal (if (!= code 0) (some (findReadError out "ERR_READ_FAILED")) (none))
              ownedMissing (and (!= code 0) (and (< (resultOr (fileSize fullPath) -1) 0) (c/checkOwns filePath owns root)))
              msgVal (cond
                       (ownedMissing (some "owned file missing: create it with one write"))
                       ((!= code 0) (some (findReadMsg out errText)))
                       (useOutline (some (if overBytes (oversizeBytesHint fileBytes outlineLimit) (oversizeWholeHint))))
                       ((some? widened)
                         (match (optionOr widened (t/widenItem 0 0 "" ""))
                           ((t/widenItem a b nm kd) (some (str "widened to the enclosing " kd " " nm ", lines " (stringFromInt64 a) "-" (stringFromInt64 b))))))
                       (else (none)))]
          (listAppend (list (pair "id" (rStr rid)) (pair "op" (rStr "read")) (pair "file" (rStr filePath))
            (pair "span" (match span ((some sp) (rPair (pairFirst sp) (pairSecond sp))) ((none) (rNone))))
            (pair "content" (if (= code 0) (rStr (if memoFresh sameText fullCont)) (rNone)))
            (pair "status" (rStr st))
            (pair "error" (match errVal ((some e) (rStr e)) ((none) (rNone))))
            (pair "message" (match msgVal ((some m) (rStr m)) ((none) (rNone))))
            (pair "cmd" (rStr (str "asl read " filePath)))
            (pair "exit" (rInt code))
            (pair "stdout" (rStr (if ownedMissing "" out))))
          (if (some? memoHit) (list (pair "memo" (rStr "hit"))) (if putOk (list) (list (pair "memo" (rStr "skipped"))))))))))
      ((or (= opName "query") (= opName "q"))
        (let [queryText (let [q (getKvStr op "query")] (if (!= q "") q (getKvStr op "text")))
              inMode (getKvStr op "in")
              limitStr (getKvStr op "limit")
              form (buildQueryForm queryText inMode limitStr)
              res (run form root)
              code (aslRunCode res)
              out (aslRunOut res)
              st (if (= code 0) "ok" "rejected")
              forms (filter (fn [f] (stringStartsWith? (pyStrip f) "(:query")) (c/parseForms out))
              rawHits (if (not (listEmpty? forms)) (c/firstOf forms) (pyStrip out))
              hits (if (> (stringLength rawHits) 2000) (str (c/sliceOf rawHits 0 2000) " ... [truncated]") rawHits)]
          (list (pair "id" (rStr rid)) (pair "op" (rStr "query")) (pair "query" (rStr queryText))
            (pair "hits" (rStr hits)) (pair "status" (rStr st))
            (pair "cmd" (rStr (str "asl query " queryText)))
            (pair "exit" (rInt code)) (pair "stdout" (rStr out)))))
      ((or (= opName "outline") (= opName "intel"))
        (let [sub (if (= opName "outline") "outline" (t/intelSubop (getKvStr op "sub") (getKvStr op "form")))]
          (if (not (validIntelSubop? sub))
            (list (pair "id" (rStr rid)) (pair "op" (rStr opName)) (pair "status" (rStr "rejected"))
              (pair "error" (rStr "ERR_INVALID_ARG"))
              (pair "message" (rStr (str "intel :op " (if (!= sub "") sub "(none)") " is not offered; one of " (stringJoin (intelSubops) " ")))))
            (let [form (buildIntelForm sub op)
                  res (run form root)
                  code (aslRunCode res)
                  out (aslRunOut res)
                  st (if (= code 0) "ok" "rejected")
                  contentStr (if (= sub "outline") (parseOutlineItems out) (pyStrip out))
                  fileVal (getKvStr op "file")]
              (listAppend
                (list (pair "id" (rStr rid)) (pair "op" (rStr opName)))
                (listAppend
                  (if (!= fileVal "") (list (pair "file" (rStr fileVal))) (list))
                  (list (pair "content" (if (= code 0) (rStr contentStr) (rNone)))
                    (pair "status" (rStr st))
                    (pair "cmd" (rStr (str "asl intel " sub)))
                    (pair "exit" (rInt code))
                    (pair "stdout" (rStr out)))))))))
      ((= opName "diff")
        (let [form "(:diff)"
              res (run form root)
              code (aslRunCode res)
              out (aslRunOut res)
              st (if (= code 0) "ok" "rejected")
              rawDiff (pyStrip out)
              diffText (if (> (stringLength rawDiff) 2000) (str (c/sliceOf rawDiff 0 2000) "\n... [truncated]") rawDiff)]
          (list (pair "id" (rStr rid)) (pair "op" (rStr "diff")) (pair "diff" (rStr diffText))
            (pair "status" (rStr st)) (pair "cmd" (rStr "asl diff"))
            (pair "exit" (rInt code)) (pair "stdout" (rStr out)))))
      ((= opName "check")
        (let [filePath (getKvStr op "file")
              form (str "(:check :file \"" filePath "\")")
              res (run form root)
              code (aslRunCode res)
              out (aslRunOut res)
              st (if (= code 0) "ok" "rejected")]
          (list (pair "id" (rStr rid)) (pair "op" (rStr "check")) (pair "file" (rStr filePath))
            (pair "status" (rStr st)) (pair "cmd" (rStr (str "asl check " filePath)))
            (pair "exit" (rInt code)) (pair "stdout" (rStr out)))))
      ((= opName "flush")
        (let [filePath (getKvStr op "file")
              form (if (!= filePath "") (str "(:flush :file \"" filePath "\")") "(:flush)")
              _ (snap filePath)
              res (run form root)
              code (aslRunCode res)
              out (aslRunOut res)
              st (if (= code 0) "ok" "rejected")
              cmdStr (if (!= filePath "") (str "asl flush " filePath) "asl flush")]
          (list (pair "id" (rStr rid)) (pair "op" (rStr "flush"))
            (pair "status" (rStr st)) (pair "cmd" (rStr cmdStr))
            (pair "exit" (rInt code)) (pair "stdout" (rStr out)))))
      ((= opName "search")
        (let [queryText (let [q (getKvStr op "query")] (if (!= q "") q (getKvStr op "text")))
              limitStr (getKvStr op "limit")
              engine (getKvStr op "engine")
              form (buildSearchForm queryText limitStr engine)
              res (run form root)
              code (aslRunCode res)
              out (aslRunOut res)
              st (if (= code 0) "ok" "rejected")]
          (list (pair "id" (rStr rid)) (pair "op" (rStr "search")) (pair "query" (rStr queryText))
            (pair "status" (rStr st)) (pair "cmd" (rStr (str "asl search " queryText)))
            (pair "exit" (rInt code)) (pair "stdout" (rStr out))
            (pair "out" (rStr (pyStrip out))))))
      ((= opName "research")
        (let [topicText (let [t0 (getKvStr op "topic")] (if (!= t0 "") t0 (let [q (getKvStr op "query")] (if (!= q "") q (getKvStr op "text")))))
              depth (getKvStr op "depth")
              form (buildResearchForm topicText depth)
              res (run form root)
              code (aslRunCode res)
              out (aslRunOut res)
              st (if (= code 0) "ok" "rejected")]
          (list (pair "id" (rStr rid)) (pair "op" (rStr "research")) (pair "topic" (rStr topicText))
            (pair "status" (rStr st)) (pair "cmd" (rStr (str "asl research " topicText)))
            (pair "exit" (rInt code)) (pair "stdout" (rStr out))
            (pair "out" (rStr (pyStrip out))))))
      ((= opName "crawl")
        (let [url (getKvStr op "url")
              distill (getKvStr op "distill")
              limitStr (getKvStr op "limit")
              form (buildCrawlForm url distill limitStr)
              res (run form root)
              code (aslRunCode res)
              out (aslRunOut res)
              st (if (= code 0) "ok" "rejected")]
          (list (pair "id" (rStr rid)) (pair "op" (rStr "crawl")) (pair "url" (rStr url))
            (pair "status" (rStr st)) (pair "cmd" (rStr (str "asl crawl " url)))
            (pair "exit" (rInt code)) (pair "stdout" (rStr out))
            (pair "out" (rStr (pyStrip out))))))
      (else
        (let [form (buildElseForm opName op)
              res (run form root)
              code (aslRunCode res)
              out (aslRunOut res)
              st (if (= code 0) "ok" "rejected")]
          (list (pair "id" (rStr rid)) (pair "op" (rStr opName))
            (pair "status" (rStr st)) (pair "cmd" (rStr (str "asl " opName)))
            (pair "exit" (rInt code)) (pair "stdout" (rStr out)))))))

; (:m :do "execAslOpCustom! is the memo-less entry: with no session id no run scope is addressed, so nothing is read or stored")
fn ! execAslOpCustom! op: (List (Pair String c/KvVal)) owns: (List String) root: String newId: (fn [] -> String) snap: (fn [String] -> Bool) run: (fn [String String] -> t/AslRun) cap: Int64 budgetLeft: (Option Float64) -> (List (Pair String RVal))
  (execAslOpMemo! op owns root "" newId snap run cap budgetLeft)

fn ! execAslOp! op: (List (Pair String c/KvVal)) owns: (List String) root: String repoRoot: String mode: String env: (Option (List String)) newId: (fn [] -> String) snap: (fn [String] -> Bool) cap: Int64 runTimeout: Int64 deadlineAt: (Option Float64) -> (List (Pair String RVal))
  (let [run (fn [f r]
              (let [res (runAsl repoRoot f r (stepTimeout runTimeout deadlineAt (nowMono)) env mode)]
                (t/aslRun res.exit res.stdout res.stderr)))]
    (execAslOpCustom! op owns root newId snap run cap (budgetLeft deadlineAt (nowMono))))
