(module asl/agentLoop/aslOps
  :x [RVal Bounded PumpEnd RunAslResult
      budgetLeft stepTimeout nowMono chooseTransport transportField engineSocketPath! gateTimeoutSec
      engineRequest runAslSocket
      nearestLines placeholderAssert? runBounded runAsl
      execAslOp! execAslOpCustom! serReceipt serValue
      runExit runStdout runStderr runTimedOut runSeconds runFellBack chooseTransportFor]
  :i [(asl/agentLoop/core :a c)
      (asl/agentLoop/diff :a diff)
      (asl/agentLoop/txn :a t)
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
  (mt v
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
  (mt deadlineAt
    ((none) (none))
    ((some at) (some (- at nowMono))))

fn stepTimeout runTimeout: Int64 deadlineAt: (Option Float64) nowMono: Float64 -> Int64
  (mt (budgetLeft deadlineAt nowMono)
    ((none) runTimeout)
    ((some left) (mt (float64ToInt64 left)
                   ((some n) (max 1 (min runTimeout n)))
                   ((none) (if (> left 0.0) runTimeout 1)))))

fn engineSocketPath! rootDir: String -> String
  (let [envSock (optionOr (envGet "ASL_ENGINE_SOCKET") "")]
    (if (!= envSock "") envSock (str rootDir "/.asl/engine.sock")))

; (:m :tags (transport))
fn ! engineRequest sockPath: String line: String timeoutSec: Int64 -> (Result String (Pair String String))
  (mt (etp/socketExchange! sockPath line (* (max 1 timeoutSec) 1000))
    ((ok ans) (ok (stringTrim ans)))
    ((err e) (err (pair (if (= e "timed out") "ERR_TIMEOUT" "ERR_SOCKET") e))))

fn envJson! env: (Option (List String)) -> j/Json
  (j/jobj (map (fn [row]
                 (mt (stringIndexOf row "=")
                   ((some i) (pair (c/sliceOf row 0 i) (j/jstr (c/sliceOf row (+ i 1) (stringLength row)))))
                   ((none) (pair row (j/jstr "")))))
               (mt env ((some rows) rows) ((none) (envList)))))

fn jsonInt v: (Option j/Json) -> (Option Int64)
  (mt (optionOr v (j/jnull)) ((j/jint n) (some n)) (_ none))

fn jsonStr v: (Option j/Json) -> (Option String)
  (mt (optionOr v (j/jnull)) ((j/jstr s) (some s)) (_ none))

; (:m :tags (transport))
fn ! runAslSocket sockPath: String form: String rootDir: String timeoutSec: Int64 env: (Option (List String)) -> (Result RunAslResult (Pair String String))
  (let [request (j/jsonEmit (j/jobj (list (pair "forms" (j/jarr (list (j/jstr form))))
                                          (pair "root" (j/jstr (t/normPath rootDir)))
                                          (pair "env" (envJson! env)))))]
    (mt (engineRequest sockPath request timeoutSec)
      ((err e)
        (if (= (pairFirst e) "ERR_TIMEOUT")
          (ok (RunAslResult :exit 1 :stdout ""
                :stderr (str "no engine answer in " (stringFromInt64 timeoutSec) " s (:timeout true :seconds " (stringFromInt64 timeoutSec) ")")
                :timedOut true :seconds timeoutSec :fellBack ""))
          (err e)))
      ((ok ans)
        (mt (j/jsonParse ans)
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
      (mt (engineRequest sockPath "(:ping)" 2)
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
         (mt (listHead steps)
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
    (mt (t/readText! full)
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
  (mt (stringIndexOf (c/sliceOf text pos n) "assert")
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
    (mt (fdRead fd 65536)
      ((ok chunk) (if (stringEmpty? chunk) (do (fdClose fd) (pair false text)) (pair true (str text chunk))))
      ((err e) (if (= e "wouldBlock") (pair true text) (do (fdClose fd) (pair false text))))))

fn closePipes! sp: SpawnedProc outOpen: Bool errOpen: Bool -> Bool
  (do
    (if outOpen (fdClose sp.stdout) (ok ()))
    (if errOpen (fdClose sp.stderr) (ok ()))
    true)

fn leftMs! deadline: (Option Int64) -> Int64
  (mt deadline ((some d) (max 0 (/ (- d (monotonicNs)) 1000000))) ((none) -1))

fn pumpPipes! sp: SpawnedProc outOpen: Bool errOpen: Bool out: String errText: String deadline: (Option Int64) -> PumpEnd
  (if (not (or outOpen errOpen))
    (pumpDone out errText)
    (let [ms (leftMs! deadline)]
      (if (= ms 0)
        (pumpLate outOpen errOpen out errText)
        (mt (fdPoll (pollSet sp outOpen errOpen) ms)
          ((err e) (do (closePipes! sp outOpen errOpen) (pumpFailed (str "poll failed: " e))))
          ((ok ready)
            (let [o (readPipe! sp.stdout outOpen (readyOn ready sp.stdout) out)
                  r (readPipe! sp.stderr errOpen (readyOn ready sp.stderr) errText)]
              (pumpPipes! sp (pairFirst o) (pairFirst r) (pairSecond o) (pairSecond r) deadline)))))))

fn waitExit! pid: Int64 deadline: (Option Int64) -> (Result (Option Int64) String)
  (mt deadline
    ((none) (procWaitPid pid false))
    ((some d)
      (mt (procWaitPid pid true)
        ((err e) (err e))
        ((ok got)
          (mt got
            ((some code) (ok (some code)))
            ((none) (if (>= (monotonicNs) d) (ok (none)) (do (sleepMs 5) (waitExit! pid deadline)))))))))

fn killGroup! pid: Int64 -> Bool
  (mt (procKill (- 0 pid) "SIGKILL") ((ok _) true) ((err _) false))

fn afterKill! sp: SpawnedProc outOpen: Bool errOpen: Bool out: String errText: String -> (Result Bounded String)
  (let [drained (pumpPipes! sp outOpen errOpen out errText (some (+ (monotonicNs) 5000000000)))
        texts (mt drained
                ((pumpDone o e) (pair o e))
                ((pumpLate oo eo _ _) (do (closePipes! sp oo eo) (pair "" "")))
                ((pumpFailed _) (pair "" "")))]
    (mt (procWaitPid sp.pid false)
      ((err e) (err e))
      ((ok _) (ok (Bounded :code (none) :out (universalNewlines (pairFirst texts)) :errText (universalNewlines (pairSecond texts)) :timedOut true)))))

fn spawnError path: String kind: String -> String
  (cond
    ((= kind "notFound") (str "[Errno 2] No such file or directory: '" path "'"))
    ((= kind "permission") (str "[Errno 13] Permission denied: '" path "'"))
    (else (str "spawn failed: " kind)))

fn ! runBounded argv: (List String) cwd: (Option String) timeoutSec: (Option Int64) env: (Option (List String)) -> (Result Bounded String)
  (mt (procSpawnv argv cwd env)
    ((err kind) (err (spawnError (optionOr (listHead argv) "") kind)))
    ((ok sp)
      (let [closed (fdClose sp.stdin)
            deadline (mt timeoutSec ((some t) (some (+ (monotonicNs) (* t 1000000000)))) ((none) (none)))]
        (mt (pumpPipes! sp true true "" "" deadline)
          ((pumpFailed m) (do (killGroup! sp.pid) (procWaitPid sp.pid false) (err m)))
          ((pumpLate oo eo o e) (do (killGroup! sp.pid) (afterKill! sp oo eo o e)))
          ((pumpDone o e)
            (mt (waitExit! sp.pid deadline)
              ((err m) (err m))
              ((ok got)
                (mt got
                  ((none) (do (killGroup! sp.pid) (afterKill! sp false false o e)))
                  ((some code) (ok (Bounded :code (some code) :out (universalNewlines o) :errText (universalNewlines e) :timedOut false)))))))))))

fn envWithAslRoot! rootDir: String env: (Option (List String)) -> (List String)
  (let [base (mt env ((some rows) rows) ((none) (envList)))
        filtered (filter (fn [r] (not (stringStartsWith? r "ASL_ROOT="))) base)]
    (cons (str "ASL_ROOT=" (t/normPath rootDir)) filtered))

fn envOverride key: String env: (Option (List String)) -> (Option String)
  (mt (listHead (filter (fn [row] (stringStartsWith? row (str key "="))) (optionOr env (list))))
    ((none) (none))
    ((some row) (stringSlice row (+ (stringLength key) 1) (stringLength row))))

fn ! runAslOnBin aslBin: String form: String rootDir: String timeoutSec: Int64 env: (Option (List String)) -> RunAslResult
  (let [argv (list aslBin form)
        childEnv (some (envWithAslRoot! rootDir env))
        res (runBounded argv (some rootDir) (some timeoutSec) childEnv)]
    (mt res
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
      (mt (runAslSocket (engineSocketPath! toolRoot) form rootDir timeoutSec env)
        ((ok r) r)
        ((err e)
          (let [r (runAslOnBin aslBin form rootDir timeoutSec env)]
            (RunAslResult :exit r.exit :stdout r.stdout :stderr r.stderr :timedOut r.timedOut :seconds r.seconds :fellBack (pairSecond e)))))
      (runAslOnBin aslBin form rootDir timeoutSec env))))

fn getKvStr kv: (List (Pair String c/KvVal)) key: String -> String
  (mt (listHead (filter (fn [p] (= (pairFirst p) key)) kv))
    ((some p) (mt (pairSecond p) ((c/kvStr s) s) ((c/kvInt s) s)))
    (none ""))

fn allDigits s: String -> Bool
  (and (> (stringLength s) 0) (= (runEnd s (stringLength s) 0 c/isDigit) (stringLength s)))

fn countLns s: String n: Int64 pos: Int64 acc: Int64 -> Int64
  (if (>= pos n)
    acc
    (countLns s n (+ pos 1) (if (= (c/sliceOf s pos (+ pos 1)) "\n") (+ acc 1) acc)))

fn replaceFirst s: String oldStr: String newStr: String -> String
  (mt (stringIndexOf s oldStr)
    ((none) s)
    ((some idx)
      (str (c/sliceOf s 0 idx) newStr (c/sliceOf s (+ idx (stringLength oldStr)) (stringLength s)))))

fn findReadContent s: String -> String
  (mt (stringIndexOf s ":content \"")
    ((none) "")
    ((some idx)
      (let [start (+ idx 10)
            end (quotedEnd s (stringLength s) start)]
        (if (>= end start) (c/asnUnescape (c/sliceOf s start end)) ""))))

fn findIntField s: String prefix: String -> (Option Int64)
  (mt (stringIndexOf s prefix)
    ((none) (none))
    ((some idx)
      (let [start (+ idx (stringLength prefix))
            n (stringLength s)
            end (runEnd s n start c/isDigit)]
        (if (> end start) (stringToInt64 (c/sliceOf s start end)) (none)))))

fn findMoreRange s: String -> (Option (Pair Int64 Int64))
  (mt (stringIndexOf s ":truncated true")
    ((none) (none))
    ((some _)
      (mt (stringIndexOf s ":more (:start ")
        ((none) (none))
        ((some mIdx)
          (let [sStart (+ mIdx 14)
                n (stringLength s)
                sEnd (runEnd s n sStart c/isDigit)]
            (mt (stringIndexOf (c/sliceOf s sEnd n) " :end ")
              ((none) (none))
              ((some eRel)
                (let [eStart (+ (+ sEnd eRel) 6)
                      eEnd (runEnd s n eStart c/isDigit)]
                  (mt (stringToInt64 (c/sliceOf s sStart sEnd))
                    ((none) (none))
                    ((some a)
                      (mt (stringToInt64 (c/sliceOf s eStart eEnd))
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
  (mt (stringIndexOf (c/sliceOf s pos n) ":error")
    ((none) (none))
    ((some rel)
      (let [i (+ pos rel)]
        (mt (errorCodeAt s n i)
          ((some code) (some code))
          ((none) (errorCodeFrom s n (+ i 1)))))))

fn findReadError s: String defaultErr: String -> String
  (optionOr (errorCodeFrom s (stringLength s) 0) defaultErr)

fn messageFrom s: String n: Int64 pos: Int64 -> (Option String)
  (mt (stringIndexOf (c/sliceOf s pos n) ":message")
    ((none) (none))
    ((some rel)
      (let [i (+ pos rel)
            j (afterKeySpace s n (+ i 8))
            end (if (and (>= j 0) (= (byteAt s n j) "\"")) (quotedEnd s n (+ j 1)) -1)]
        (if (< end 0) (messageFrom s n (+ i 1)) (some (c/sliceOf s (+ j 1) end))))))

fn findReadMsg s: String errText: String -> String
  (mt (messageFrom s (stringLength s) 0)
    ((some m) m)
    ((none)
      (let [stripped (pyStrip s)]
        (if (!= stripped "") (c/sliceOf stripped 0 (min 300 (stringLength stripped))) errText))))

fn ! countFileLines path: String -> (Option Int64)
  (mt (fileStat path)
    ((err _) (none))
    ((ok st)
      (if st.isDir
        (none)
        (mt (fileReadString path)
          ((err _) (none))
          ((ok t) (some (listLength (t/splitLines t))))))))

fn ! findAnchorLine path: String anchor: String -> Int64
  (mt (fileReadString path)
    ((err _) 1)
    ((ok t)
      (mt (stringIndexOf t anchor)
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
              totStr (mt totalLines ((some tl) (stringFromInt64 tl)) ((none) "None"))
              tailMsg (str "\n... [cut at line " (stringFromInt64 shownEnd) " of " totStr "; read :start " (stringFromInt64 (+ shownEnd 1)) " :end n, or :symbol name]")
              fullCont (str shown tailMsg)]
          (pair fullCont shown)))
      (else (pair content content))))

fn parseOutlineItems stdout: String -> String
  (let [items (t/outlineItems stdout (stringLength stdout) 0 (list))]
    (stringJoin
      (map (fn [w] (mt w ((t/widenItem a b nm kd) (str (stringFromInt64 a) "-" (stringFromInt64 b) " " kd " " nm))))
        items)
      "\n"))

fn intelSubops -> (List String)
  (list "outline" "impact" "coupling" "graph" "deadcode" "complexity" "stubs" "query")

fn validIntelSubop? sub: String -> Bool
  (listContains? (intelSubops) sub)

fn buildWriteForm filePath: String content: String force: Bool owns: (List String) -> String
  (let [ownsAsn (stringJoin (map (fn [o] (str "\"" (pyStrip o) "\"")) owns) " ")
        forceAsn (if force " :force true" "")]
    (str "(:txn :owns (" ownsAsn ") (:write :file \"" filePath "\" :content \"" (c/escapeAsn content) "\"" forceAsn "))"))

fn buildEditForm filePath: String old: String new: String owns: (List String) -> String
  (let [ownsAsn (stringJoin (map (fn [o] (str "\"" (pyStrip o) "\"")) owns) " ")]
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
  (let [f0 (str "(:query :query \"" (c/escapeAsn qText) "\"")
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
  (mt r ((t/aslRun code _ _) code))

fn aslRunOut r: t/AslRun -> String
  (mt r ((t/aslRun _ out _) out))

fn aslRunErr r: t/AslRun -> String
  (mt r ((t/aslRun _ _ errText) errText))

fn ! execAslOpCustom! op: (List (Pair String c/KvVal)) owns: (List String) root: String newId: (fn [] -> String) snap: (fn [String] -> Bool) run: (fn [String String] -> t/AslRun) cap: Int64 budgetLeft: (Option Float64) -> (List (Pair String RVal))
  (let [opHead (getKvStr op "_head")
        rawOpName (let [o (getKvStr op "op")] (if (!= o "") o opHead))
        opName (if (= rawOpName "") "step" rawOpName)
        rid (newId)]
    (cond
      ((= opName "write")
        (let [filePath (getKvStr op "file")
              content (getKvStr op "content")
              force (c/truthy (c/dictGet op "force"))
              form (buildWriteForm filePath content force owns)
              _ (snap filePath)
              res (run form root)
              code (aslRunCode res)
              out (aslRunOut res)
              errText (aslRunErr res)
              st (if (= code 0) "ok" "rejected")
              ref (if (!= code 0) (t/txnRefusal out errText "ERR_WRITE_FAILED" (some content)) (pair "" ""))
              refErr (pairFirst ref)
              refMsg (pairSecond ref)
              err0 (cond
                     ((stringContains? out "ERR_OWNS") "ERR_OWNS")
                     ((or (stringContains? out "ERR_TXN_FLUSH_FAILED") (stringContains? refMsg "refused: the delimiters")) "ERR_TXN_FLUSH_FAILED")
                     ((stringContains? out "ERR_TXN_ABORTED") "ERR_TXN_ABORTED")
                     (else refErr))
              extra (if (or (= err0 "ERR_TXN_FLUSH_FAILED") (stringContains? refMsg "the delimiters ( ) [ ] { } and quotes do not balance")) "write a large file in parts: the first part with write, the rest with edit ops anchored on its last line" "")
              fullMsg (str refMsg " " out " " errText)
              aid (if (!= code 0) (t/abortAid! root filePath (list (t/txnStep "write" filePath (list (pair "content" (c/kvStr content))))) fullMsg extra) (none))
              balance (if (and (!= code 0) (or (= err0 "ERR_TXN_FLUSH_FAILED") (stringContains? refMsg "refused: the delimiters"))) (t/balanceAid content) (none))
              rawTmpl (str "(:step :op \"write\" :file \"" filePath "\" :content :raw)")
              hint0 (mt aid ((some x) (mt x ((t/abortAidOf _ _ h) (some h)))) ((none) (none)))
              hint (if (!= code 0)
                     (if (or (= err0 "ERR_TXN_FLUSH_FAILED") (= err0 "ERR_TXN_ABORTED"))
                       (mt hint0 ((some h) (some (str h "; " rawTmpl))) ((none) (some rawTmpl)))
                       hint0)
                     (none))]
          (listAppend
            (list (pair "id" (rStr rid)) (pair "op" (rStr "write")) (pair "file" (rStr filePath)) (pair "status" (rStr st))
              (pair "error" (if (= code 0) (rNone) (rStr err0)))
              (pair "message" (if (= code 0) (rNone) (rStr refMsg)))
              (pair "cmd" (rStr (str "asl txn write " filePath))))
            (listAppend
              (mt balance ((some b) (list (pair "balance" (rStr b)))) ((none) (list)))
              (listAppend
                (list (pair "exit" (rInt code)) (pair "stdout" (rStr out)) (pair "persisted" (rBool (= code 0))))
                (listAppend
                  (mt aid ((some x) (mt x ((t/abortAidOf k a _) (list (pair "line" (rInt k)) (pair "arrived" (rStr a)))))) ((none) (list)))
                  (listAppend
                    (mt hint ((some h) (list (pair "hint" (rStr h)))) ((none) (list)))
                    (if (and (= code 0) (placeholderAssert? content))
                      (list (pair "warning" (rStr "placeholder assert: red-first needs a real assertion on the missing behaviour")))
                      (list)))))))))
      ((= opName "edit")
        (let [filePath (getKvStr op "file")
              old (getKvStr op "old")
              new (getKvStr op "new")
              form (buildEditForm filePath old new owns)
              _ (snap filePath)
              res (run form root)
              code (aslRunCode res)
              out (aslRunOut res)
              errText (aslRunErr res)
              st (if (= code 0) "ok" "rejected")
              fullTarget (t/normPath (if (stringStartsWith? filePath "/") filePath (str root "/" filePath)))
              afterEdit (mt (t/readText! fullTarget)
                          ((fileText curF) (if (stringContains? curF old) (some (replaceFirst curF old new)) (none)))
                          (_ (none)))
              ref (if (!= code 0) (t/txnRefusal out errText "ERR_EDIT_FAILED" afterEdit) (pair "" ""))
              refErr (pairFirst ref)
              refMsg (pairSecond ref)
              err0 (cond
                     ((stringContains? out "ERR_OWNS") "ERR_OWNS")
                     ((or (stringContains? out "ERR_TXN_FLUSH_FAILED") (stringContains? refMsg "refused: the delimiters")) "ERR_TXN_FLUSH_FAILED")
                     ((stringContains? out "ERR_TXN_ABORTED") "ERR_TXN_ABORTED")
                     (else refErr))
              extra (if (or (= err0 "ERR_TXN_FLUSH_FAILED") (stringContains? refMsg "the delimiters ( ) [ ] { } and quotes do not balance")) "write a large file in parts: the first part with write, the rest with edit ops anchored on its last line" "")
              fullMsg (str refMsg " " out " " errText)
              aid (if (!= code 0) (t/abortAid! root filePath (list (t/txnStep "edit" filePath (list (pair "old" (c/kvStr old)) (pair "new" (c/kvStr new))))) fullMsg extra) (none))
              balance (if (and (!= code 0) (or (= err0 "ERR_TXN_FLUSH_FAILED") (stringContains? refMsg "refused: the delimiters"))) (t/balanceAid (optionOr afterEdit "")) (none))
              rawTmpl (str "(:step :op \"write\" :file \"" filePath "\" :content :raw)")
              hint0 (mt aid ((some x) (mt x ((t/abortAidOf _ _ h) (some h)))) ((none) (none)))
              hint (if (!= code 0)
                     (if (or (= err0 "ERR_TXN_FLUSH_FAILED") (= err0 "ERR_TXN_ABORTED"))
                       (mt hint0 ((some h) (some (str h "; " rawTmpl))) ((none) (some rawTmpl)))
                       hint0)
                     (none))
              noMatch (or (stringContains? out "ERR_NO_MATCH") (stringContains? refMsg "Old target string not found"))
              near (if (and (!= st "ok") noMatch) (nearestLines root filePath old) (none))
              finalMsg (mt near ((some _) (str refMsg "; the file's lines nearest the :old follow")) ((none) refMsg))]
          (listAppend
            (mt near ((some p) (list (pair "span" (rPair (pairFirst (pairFirst p)) (pairSecond (pairFirst p)))) (pair "content" (rStr (pairSecond p))))) ((none) (list)))
            (listAppend
              (list (pair "id" (rStr rid)) (pair "op" (rStr "edit")) (pair "file" (rStr filePath)) (pair "status" (rStr st))
                (pair "error" (if (= code 0) (rNone) (rStr err0)))
                (pair "message" (if (= code 0) (rNone) (rStr finalMsg)))
                (pair "cmd" (rStr (str "asl txn edit " filePath))))
              (listAppend
                (mt balance ((some b) (list (pair "balance" (rStr b)))) ((none) (list)))
                (listAppend
                  (list (pair "exit" (rInt code)) (pair "stdout" (rStr out)) (pair "persisted" (rBool (= code 0))))
                  (listAppend
                    (mt aid ((some x) (mt x ((t/abortAidOf k a _) (list (pair "line" (rInt k)) (pair "arrived" (rStr a)))))) ((none) (list)))
                    (listAppend
                      (mt hint ((some h) (list (pair "hint" (rStr h)))) ((none) (list)))
                      (if (and (= code 0) (placeholderAssert? new))
                        (list (pair "warning" (rStr "placeholder assert: red-first needs a real assertion on the missing behaviour")))
                        (list))))))))))
      ((= opName "read")
        (let [filePath (getKvStr op "file")
              symbolVal (getKvStr op "symbol")
              anchorVal (getKvStr op "anchor")
              startVal (getKvStr op "start")
              endVal (getKvStr op "end")
              widened (if (!= symbolVal "") (none) (t/widenToSymbol! filePath startVal endVal root cap budgetLeft run))
              effStart (mt widened ((some w) (mt w ((t/widenItem a _ _ _) (stringFromInt64 a)))) ((none) startVal))
              effEnd (mt widened ((some w) (mt w ((t/widenItem _ b _ _) (stringFromInt64 b)))) ((none) endVal))
              form (buildReadForm filePath symbolVal anchorVal effStart effEnd cap)
              res (run form root)
              code (aslRunCode res)
              out (aslRunOut res)
              errText (aslRunErr res)
              st (if (= code 0) "ok" "rejected")
              contentRaw (if (= code 0) (findReadContent out) "")
              fullPath (t/normPath (if (stringStartsWith? filePath "/") filePath (str root "/" filePath)))
              totalLines (countFileLines fullPath)
              mStart (findIntField out ":start ")
              mMore (findMoreRange out)
              preOut (c/firstOf (stringSplit (c/firstOf (stringSplit out ":content ")) ":more "))
              mFirst (findIntField preOut ":start ")
              firstLine (cond
                          ((some? mFirst) (optionOr mFirst 1))
                          ((and (!= anchorVal "") (some? totalLines)) (findAnchorLine fullPath anchorVal))
                          (else 1))
              bodyPair (formatReadBody contentRaw cap totalLines mStart mMore)
              fullCont (pairFirst bodyPair)
              body (pairSecond bodyPair)
              partial (or (!= body fullCont) (stringEndsWith? body "\n"))
              last0 (- (+ firstLine (countLns body (stringLength body) 0 0)) (if partial 1 0))
              lastLine (mt mMore ((some mr) (min last0 (- (pairFirst mr) 1))) ((none) last0))
              span (if (and (!= body "") (= code 0)) (some (pair firstLine lastLine)) (none))
              errVal (if (!= code 0) (some (findReadError out "ERR_READ_FAILED")) (none))
              msgVal (cond
                       ((!= code 0) (some (findReadMsg out errText)))
                       ((some? widened)
                         (mt (optionOr widened (t/widenItem 0 0 "" ""))
                           ((t/widenItem a b nm kd) (some (str "widened to the enclosing " kd " " nm ", lines " (stringFromInt64 a) "-" (stringFromInt64 b))))))
                       (else (none)))]
          (list (pair "id" (rStr rid)) (pair "op" (rStr "read")) (pair "file" (rStr filePath))
            (pair "span" (mt span ((some sp) (rPair (pairFirst sp) (pairSecond sp))) ((none) (rNone))))
            (pair "content" (if (= code 0) (rStr fullCont) (rNone)))
            (pair "status" (rStr st))
            (pair "error" (mt errVal ((some e) (rStr e)) ((none) (rNone))))
            (pair "message" (mt msgVal ((some m) (rStr m)) ((none) (rNone))))
            (pair "cmd" (rStr (str "asl read " filePath)))
            (pair "exit" (rInt code))
            (pair "stdout" (rStr out)))))
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

fn ! execAslOp! op: (List (Pair String c/KvVal)) owns: (List String) root: String repoRoot: String mode: String env: (Option (List String)) newId: (fn [] -> String) snap: (fn [String] -> Bool) cap: Int64 runTimeout: Int64 deadlineAt: (Option Float64) -> (List (Pair String RVal))
  (let [run (fn [f r]
              (let [res (runAsl repoRoot f r (stepTimeout runTimeout deadlineAt (nowMono)) env mode)]
                (t/aslRun res.exit res.stdout res.stderr)))]
    (execAslOpCustom! op owns root newId snap run cap (budgetLeft deadlineAt (nowMono))))
