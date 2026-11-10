(module aslAgent/gitOps
  :x [RVal rStr rInt rBool rNull rPair LineArg laNone laBad laNum Bounded GitCtx
      makeGitCtx runBounded! isPathInRepo! lineArg gitSlice gitNextForm execGitOp!
      runGates! runGatesIn! runGatesWatched! scratchTree! scratchDrop! gitText! gatePreflight! formatGatePreflight changedOwnedFiles!
      serRec serRecs recGet pyStrip pySplitLines pyNormpath pyRelpath! pyRealpath! pyRepr cpLength]
  :i [(aslAgent/core :a c) (aslAgent/agentConfig :a ac) (asl-tools/fleet/run :a fr) (asl-tools/vcs/git :a vg) (aslAgent/gates :a gd)])

enum RVal
  (rStr text: String)
  (rInt value: Int64)
  (rBool flag: Bool)
  (rNull)
  (rPair first: Int64 second: Int64)

enum LineArg
  (laNone)
  (laBad)
  (laNum n: Int64)

enum PumpEnd
  (pumpDone out: String errText: String)
  (pumpLate outOpen: Bool errOpen: Bool out: String errText: String)
  (pumpFailed message: String)

(schema Bounded
  (:f code (Option Int64))
  (:f out String)
  (:f errText String)
  (:f timedOut Bool)
  (:f guard String :default ""))

(schema GitCtx
  (:f root String)
  (:f mode String)
  (:f defaultBase String)
  (:f timeoutSec Int64)
  (:f readCap Int64)
  (:f env (Option (List String))))

fn makeGitCtx root: String mode: String defaultBase: String timeoutSec: Int64 readCap: Int64 env: (Option (List String)) -> GitCtx
  (GitCtx :root root :mode mode :defaultBase defaultBase :timeoutSec timeoutSec :readCap readCap :env env)

fn itos n: Int64 -> String
  (stringFromInt64 n)

fn byteAt bs: Bytes i: Int64 -> Int64
  (bytesGet bs i)

fn cpCount bs: Bytes n: Int64 i: Int64 acc: Int64 -> Int64
  (if (>= i n)
    acc
    (let [b (byteAt bs i)]
      (cpCount bs n (+ i 1) (if (and (>= b 128) (< b 192)) acc (+ acc 1)))))

fn cpLength s: String -> Int64
  (let [bs (stringToBytes s)]
    (cpCount bs (bytesLength bs) 0 0))

fn cpIndex bs: Bytes n: Int64 i: Int64 k: Int64 -> Int64
  (cond
    ((>= i n) n)
    ((let [b (byteAt bs i)] (and (>= b 128) (< b 192))) (cpIndex bs n (+ i 1) k))
    ((<= k 0) i)
    (else (cpIndex bs n (+ i 1) (- k 1))))

fn cpTake s: String k: Int64 -> String
  (let [bs (stringToBytes s)]
    (c/sliceOf s 0 (cpIndex bs (bytesLength bs) 0 k)))

fn cpDrop s: String k: Int64 -> String
  (let [bs (stringToBytes s)
        n (bytesLength bs)]
    (c/sliceOf s (cpIndex bs n 0 k) n))

fn isPyWhite b: Int64 -> Bool
  (or (= b 32) (or (and (>= b 9) (<= b 13)) (and (>= b 28) (<= b 31))))

fn stripStart bs: Bytes n: Int64 i: Int64 -> Int64
  (if (and (< i n) (isPyWhite (byteAt bs i))) (stripStart bs n (+ i 1)) i)

fn stripEnd bs: Bytes j: Int64 lo: Int64 -> Int64
  (if (and (> j lo) (isPyWhite (byteAt bs (- j 1)))) (stripEnd bs (- j 1) lo) j)

fn pyStrip s: String -> String
  (let [bs (stringToBytes s)
        n (bytesLength bs)
        i (stripStart bs n 0)]
    (c/sliceOf s i (stripEnd bs n i)))

fn lineBreakLen bs: Bytes n: Int64 i: Int64 -> Int64
  (let [b (byteAt bs i)]
    (cond
      ((= b 13) (if (and (< (+ i 1) n) (= (byteAt bs (+ i 1)) 10)) 2 1))
      ((or (= b 10) (or (= b 11) (or (= b 12) (and (>= b 28) (<= b 30))))) 1)
      ((and (= b 194) (and (< (+ i 1) n) (= (byteAt bs (+ i 1)) 133))) 2)
      ((and (= b 226) (and (< (+ i 2) n) (and (= (byteAt bs (+ i 1)) 128) (or (= (byteAt bs (+ i 2)) 168) (= (byteAt bs (+ i 2)) 169))))) 3)
      (else 0)))

fn splitScan s: String bs: Bytes n: Int64 i: Int64 start: Int64 keep: Bool acc: (List String) -> (List String)
  (if (>= i n)
    (listReverse (if (< start n) (cons (c/sliceOf s start n) acc) acc))
    (let [k (lineBreakLen bs n i)]
      (if (= k 0)
        (splitScan s bs n (+ i 1) start keep acc)
        (splitScan s bs n (+ i k) (+ i k) keep (cons (c/sliceOf s start (if keep (+ i k) i)) acc)))))

fn pySplitLines s: String keep: Bool -> (List String)
  (let [bs (stringToBytes s)]
    (splitScan s bs (bytesLength bs) 0 0 keep (list)))

fn universalNewlines s: String -> String
  (stringReplace (stringReplace s "\r\n" "\n") "\r" "\n")

fn hexDigit d: Int64 -> String
  (c/sliceOf "0123456789abcdef" d (+ d 1))

fn reprByte q: String c: String -> String
  (let [b (charCode c)]
    (cond
      ((= c "\\") "\\\\")
      ((= c q) (str "\\" q))
      ((= c "\n") "\\n")
      ((= c "\r") "\\r")
      ((= c "\t") "\\t")
      ((or (< b 32) (= b 127)) (str "\\x" (hexDigit (/ b 16)) (hexDigit (mod b 16))))
      (else c)))

fn pyRepr s: String -> String
  (let [q (if (and (stringContains? s "'") (not (stringContains? s "\""))) "\"" "'")]
    (str q (stringJoin (map (fn [c] (reprByte q c)) (stringChars s)) "") q))

fn pathComps p: String -> (List String)
  (filter (fn [x] (not (stringEmpty? x))) (stringSplit p "/"))

fn normStep acc: (List String) comp: String rooted: Bool -> (List String)
  (cond
    ((= comp ".") acc)
    ((!= comp "..") (cons comp acc))
    ((listEmpty? acc) (if rooted acc (cons ".." acc)))
    ((= (c/firstOf acc) "..") (cons ".." acc))
    (else (c/restOf acc)))

fn pyNormpath p: String -> String
  (if (stringEmpty? p)
    "."
    (let [slashes (cond
                    ((not (stringStartsWith? p "/")) "")
                    ((and (stringStartsWith? p "//") (not (stringStartsWith? p "///"))) "//")
                    (else "/"))
          rooted (not (stringEmpty? slashes))
          comps (listReverse (fold (fn [acc x] (normStep acc x rooted)) (list) (pathComps p)))
          body (str slashes (stringJoin comps "/"))]
      (if (stringEmpty? body) "." body)))

fn getCwd! -> String
  (resultOr (realPath ".") ".")

fn pyAbspath! p: String -> String
  (pyNormpath (if (stringStartsWith? p "/") p (str (getCwd!) "/" p)))

fn joinPath a: String b: String -> String
  (cond
    ((stringStartsWith? b "/") b)
    ((or (stringEmpty? a) (stringEndsWith? a "/")) (str a b))
    (else (str a "/" b)))

fn parentOf p: String -> String
  (let [comps (pathComps p)
        n (listLength comps)]
    (if (<= n 1) "/" (str "/" (stringJoin (listTake comps (- n 1)) "/"))))

fn baseOf p: String -> String
  (match (listLast (pathComps p)) ((some b) b) ((none) ""))

fn pyRealpath! p: String -> String
  (let [a (pyAbspath! p)]
    (match (realPath a)
      ((ok r) r)
      ((err _) (if (= a "/") "/" (joinPath (pyRealpath! (parentOf a)) (baseOf a))))))

fn isUnder root: String target: String -> Bool
  (or (= root "/") (or (= target root) (stringStartsWith? target (str root "/"))))

fn commonPrefixLen xs: (List String) ys: (List String) k: Int64 -> Int64
  (if (or (listEmpty? xs) (listEmpty? ys))
    k
    (if (= (c/firstOf xs) (c/firstOf ys)) (commonPrefixLen (c/restOf xs) (c/restOf ys) (+ k 1)) k))

fn pyRelpath! path: String start: String -> String
  (let [ps (pathComps (pyAbspath! path))
        ss (pathComps (pyAbspath! start))
        k (commonPrefixLen ps ss 0)
        rel (listAppend (map (fn [_] "..") (listDrop ss k)) (listDrop ps k))]
    (if (listEmpty? rel) "." (stringJoin rel "/")))

fn isPathInRepo! path: String rootDir: String -> Bool
  (let [sPath (pyStrip path)]
    (if (stringEmpty? sPath)
      true
      (let [norm (pyNormpath sPath)
            root (if (stringEmpty? rootDir) (getCwd!) rootDir)]
        (if (or (= norm "..") (stringStartsWith? norm "../"))
          false
          (let [absTarget (pyAbspath! (joinPath root sPath))
                absRoot (pyAbspath! root)]
            (or (isUnder absRoot absTarget)
              (isUnder (pyRealpath! root) (pyRealpath! absTarget))))))))

fn opGet op: (List (Pair String c/KvVal)) key: String -> (Option c/KvVal)
  (match (listHead (filter (fn [p] (= (pairFirst p) key)) op))
    ((some p) (some (pairSecond p)))
    ((none) (none)))

fn kvText v: c/KvVal -> String
  (match v ((c/kvStr s) s) ((c/kvInt d) d))

fn kvTruthy v: c/KvVal -> Bool
  (match v
    ((c/kvStr s) (not (stringEmpty? s)))
    ((c/kvInt d) (!= (optionOr (stringToInt64 d) 0) 0)))

fn truthyText o: (Option c/KvVal) -> String
  (match o ((some v) (if (kvTruthy v) (kvText v) "")) ((none) ""))

fn allDigits s: String -> Bool
  (and (not (stringEmpty? s)) (listAll? (fn [ch] (and (>= ch "0") (<= ch "9"))) (stringChars s)))

fn digitValue s: String -> Int64
  (fold (fn [acc ch] (+ (* acc 10) (- (charCode ch) 48))) 0 (stringChars s))

fn lineArg o: (Option c/KvVal) -> LineArg
  (match o
    ((none) (laNone))
    ((some v)
      (match v
        ((c/kvInt d) (let [n (optionOr (stringToInt64 d) 0)] (if (>= n 1) (laNum n) (laBad))))
        ((c/kvStr s)
          (if (stringEmpty? s)
            (laNone)
            (let [t (pyStrip s)]
              (if (and (allDigits t) (>= (digitValue t) 1)) (laNum (digitValue t)) (laBad))))))))

fn pyIntDigits s: String -> Bool
  (and (allDigits (stringReplace s "_" ""))
    (and (not (stringStartsWith? s "_"))
      (and (not (stringEndsWith? s "_")) (not (stringContains? s "__")))))

fn pyInt s: String -> (Option Int64)
  (let [t (pyStrip s)
        neg (stringStartsWith? t "-")
        body (if (or neg (stringStartsWith? t "+")) (cpDrop t 1) t)]
    (if (pyIntDigits body)
      (let [v (digitValue (stringReplace body "_" ""))] (some (if neg (- 0 v) v)))
      (none)))

fn sliceWalk lines: (List String) left: Int64 cap: Int64 shown: (List String) size: Int64 -> (List String)
  (if (or (<= left 0) (listEmpty? lines))
    (listReverse shown)
    (let [ln (c/firstOf lines)
          len (cpLength ln)]
      (if (and (not (listEmpty? shown)) (> (+ size len) cap))
        (listReverse shown)
        (let [cut (cpTake ln cap)]
          (sliceWalk (c/restOf lines) (- left 1) cap (cons cut shown) (+ size (cpLength cut)))))))

fn gitSlice text: String start: (Option Int64) end: (Option Int64) cap: Int64 -> (Pair String (List Int64))
  (let [lines (pySplitLines text true)
        total (listLength lines)
        first (optionOr start 1)
        stop (match end ((some e) (min e total)) ((none) total))
        shown (sliceWalk (listDrop lines (- first 1)) (- stop (- first 1)) cap (list) 0)]
    (pair (stringJoin shown "") (list first (+ (- first 1) (listLength shown)) total)))

fn gitNextForm opName: String rev: String path: String base: String limit: (Option String) start: Int64 -> String
  (str "(:step :op \"" opName "\""
    (if (= opName "gitShow") (str " :rev \"" (c/escapeAsn (if (stringEmpty? rev) "HEAD" rev)) "\"") "")
    (if (stringEmpty? path) "" (str " :path \"" (c/escapeAsn path) "\""))
    (if (and (= opName "gitDiff") (not (stringEmpty? base))) (str " :base \"" (c/escapeAsn base) "\"") "")
    (match limit
      ((some l) (if (and (= opName "gitLog") (not (stringEmpty? l))) (str " :limit " l) ""))
      ((none) ""))
    " :start " (itos start) " :end n)")

fn envBase! env: (Option (List String)) -> (List String)
  (match env ((some rows) rows) ((none) (envList)))

fn envRowKey row: String -> String
  (match (stringIndexOf row "=") ((some i) (c/sliceOf row 0 i)) ((none) row))

fn envWith rows: (List String) key: String value: String -> (List String)
  (listAppend (filter (fn [r] (!= (envRowKey r) key)) rows) (list (str key "=" value)))

fn cwdErrno! cwd: (Option String) -> Int64
  (match cwd
    ((some d) (match (fileStat d) ((ok st) (if st.isDir 0 20)) ((err _) 2)))
    ((none) 0))

fn errnoText code: Int64 -> String
  (cond
    ((= code 2) "No such file or directory")
    ((= code 13) "Permission denied")
    ((= code 20) "Not a directory")
    (else "OS error"))

fn spawnMessage! kind: String cwd: (Option String) prog: String -> String
  (let [cwdCode (cwdErrno! cwd)]
    (if (!= cwdCode 0)
      (str "[Errno " (itos cwdCode) "] " (errnoText cwdCode) ": " (pyRepr (optionOr cwd "")))
      (let [code (cond ((= kind "notFound") 2) ((= kind "permission") 13) ((= kind "io:20") 20) (else 0))]
        (if (= code 0)
          (str "[Errno ?] " kind ": " (pyRepr prog))
          (str "[Errno " (itos code) "] " (errnoText code) ": " (pyRepr prog))))))

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

; (:m :ref LEON-ORPHAN-PARENT :do "a watched gate is pumped in half-second slices; between slices a gone watched pid kills the gate's group like a timeout")
fn ! watchedGone? watch: (Option Int64) -> Bool
  (match watch
    ((some pid) (and (> pid 0) (not (resultOr (procAlive? pid) true))))
    ((none) false))

fn ! pumpWatched! sp: SpawnedProc outOpen: Bool errOpen: Bool out: String errText: String deadline: (Option Int64) watch: (Option Int64) -> PumpEnd
  (match watch
    ((none) (pumpPipes! sp outOpen errOpen out errText deadline))
    ((some _)
      (let [slice (+ (monotonicNs) 500000000)
            d (match deadline ((some x) (min x slice)) ((none) slice))]
        (match (pumpPipes! sp outOpen errOpen out errText (some d))
          ((pumpLate oo eo o e)
            (if (or (match deadline ((some x) (>= (monotonicNs) x)) ((none) false)) (watchedGone? watch))
              (pumpLate oo eo o e)
              (pumpWatched! sp oo eo o e deadline watch)))
          ((pumpDone o e) (pumpDone o e))
          ((pumpFailed m) (pumpFailed m))))))

fn runBounded! argv: (List String) cwd: (Option String) timeoutSec: (Option Int64) env: (Option (List String)) watch: (Option Int64) -> (Result Bounded String)
  (match (procSpawnv argv cwd env)
    ((err kind) (err (spawnMessage! kind cwd (c/firstOf argv))))
    ((ok sp)
      (let [closed (fdClose sp.stdin)
            deadline (match timeoutSec ((some t) (some (+ (monotonicNs) (* t 1000000000)))) ((none) (none)))]
        (match (pumpWatched! sp true true "" "" deadline watch)
          ((pumpFailed m) (do (killGroup! sp.pid) (procWaitPid sp.pid false) (err m)))
          ((pumpLate oo eo o e) (do (killGroup! sp.pid) (afterKill! sp oo eo o e)))
          ((pumpDone o e)
            (match (waitExit! sp.pid deadline)
              ((err m) (err m))
              ((ok got)
                (match got
                  ((none) (do (killGroup! sp.pid) (afterKill! sp false false o e)))
                  ((some code) (ok (Bounded :code (some code) :out (universalNewlines o) :errText (universalNewlines e) :timedOut false)))))))))))

fn rs k: String v: String -> (Pair String RVal)
  (pair k (rStr v))

fn ri k: String v: Int64 -> (Pair String RVal)
  (pair k (rInt v))

fn rejectRec rid: String opName: String err: String message: String path: String -> (List (Pair String RVal))
  (listAppend (list (rs "id" rid) (rs "op" opName) (rs "status" "rejected") (rs "error" err) (rs "message" message))
    (if (stringEmpty? path) (list) (list (rs "path" path))))

fn reprKv o: (Option c/KvVal) -> String
  (match o ((none) "None") ((some v) (match v ((c/kvInt d) d) ((c/kvStr s) (pyRepr s)))))

fn dashArg args: (List (Pair String (Option String))) -> (Option (Pair String String))
  (if (listEmpty? args)
    (none)
    (let [a (c/firstOf args)]
      (match (pairSecond a)
        ((some v) (let [t (pyStrip v)] (if (stringStartsWith? t "-") (some (pair (pairFirst a) t)) (dashArg (c/restOf args)))))
        ((none) (dashArg (c/restOf args))))))

fn cleanPath! path: String rootDir: String -> String
  (if (stringEmpty? path)
    ""
    (let [root (if (stringEmpty? rootDir) (getCwd!) rootDir)
          rel (pyRelpath! (pyAbspath! (joinPath root (pyStrip path))) (pyAbspath! root))]
      (if (stringStartsWith? rel "./") (cpDrop rel 2) rel)))

fn diffArgv base: String cp: String -> (List String)
  (listAppend (listAppend (list "git" "diff") (if (and (not (stringEmpty? base)) (!= base "working tree")) (list base) (list)))
    (if (stringEmpty? cp) (list) (list "--" cp)))

fn logArgv lim: Int64 cp: String -> (List String)
  (listAppend (list "git" "log" "-n" (itos lim)) (if (stringEmpty? cp) (list) (list "--" cp)))

fn showArgv rev: String cp: String -> (List String)
  (let [r (if (stringEmpty? rev) "HEAD" rev)]
    (if (stringEmpty? cp) (list "git" "show" r) (list "git" "show" (str r ":" cp))))

fn truncated out: String -> String
  (if (> (cpLength out) 2000) (str (cpTake out 2000) "\n... [truncated]") out)

fn gitRunRec rid: String opName: String argv: (List String) b: Bounded path: String base: String rev: String rawBase: String limit: (Option String) start: LineArg end: LineArg cap: Int64 -> (List (Pair String RVal))
  (let [code (optionOr b.code -1)
        stdout b.out
        okRun (= code 0)
        startN (match start ((laNum n) (some n)) (_ (none)))
        endN (match end ((laNum n) (some n)) (_ (none)))
        sl (gitSlice stdout startN endN cap)
        nums (pairSecond sl)
        first (c/firstOf nums)
        last (c/firstOf (c/restOf nums))
        total (c/firstOf (c/restOf (c/restOf nums)))
        pastEnd (match startN ((some s) (and (> total 0) (> s total))) ((none) false))
        sliced (or (> first 1) (< last total))
        note (if sliced
               (str "\n... [lines " (itos first) "-" (itos last) " of " (itos total) " (" (itos (cpLength stdout)) " chars)"
                 (if (and (< last total) (match endN ((some e) (< last e)) ((none) true)))
                   (str "; next: " (gitNextForm opName rev path rawBase limit (+ last 1)))
                   "")
                 "]")
               "")
        out (if okRun (str (pairFirst sl) note) (truncated (if (stringEmpty? b.errText) stdout b.errText)))]
    (if (and okRun pastEnd)
      (list (rs "id" rid) (rs "op" opName) (pair "path" (if (stringEmpty? path) (rNull) (rStr path))) (rs "status" "rejected")
        (rs "error" "ERR_BAD_ARG") (rs "message" (str ":start " (itos (optionOr startN 0)) " is past the last line; the answer has " (itos total) " lines")))
      (listAppend
        (list (rs "id" rid) (rs "op" opName) (rs "status" (if okRun "ok" "rejected")) (rs "cmd" (stringJoin argv " ")) (ri "exit" code) (rs "stdout" stdout))
        (listAppend (if (stringEmpty? path) (list) (list (rs "path" path)))
          (listAppend (if (and okRun sliced) (list (pair "lines" (rPair first last)) (ri "totalLines" total) (ri "totalChars" (cpLength stdout))) (list))
            (listAppend
              (if (= opName "gitDiff")
                (listAppend (list (rs "diff" out)) (if (stringEmpty? base) (list) (list (rs "base" base))))
                (list (rs "content" out)))
              (if okRun
                (list)
                (list (rs "error" "ERR_GIT_FAILED")
                  (rs "message" (let [m (pyStrip b.errText)] (if (stringEmpty? m) (str "git " opName " failed") m)))))))))))

fn execGitOp! op: (List (Pair String c/KvVal)) ctx: GitCtx rid: String -> (List (Pair String RVal))
  (let [opName (match (opGet op "op") ((some v) (kvText v)) ((none) ""))
        path (let [p (truthyText (opGet op "path"))] (if (stringEmpty? p) (truthyText (opGet op "file")) p))
        rawBase (truthyText (opGet op "base"))
        mode ctx.mode
        base (if (and (= opName "gitDiff") (and (or (= mode "scout") (or (= mode "implement") (= mode "auto"))) (and (stringEmpty? rawBase) (not (stringEmpty? ctx.defaultBase)))))
               ctx.defaultBase
               rawBase)
        rev (truthyText (opGet op "rev"))
        limit (match (opGet op "limit") ((some v) (some (kvText v))) ((none) (none)))
        start (lineArg (opGet op "start"))
        end (lineArg (opGet op "end"))
        badLines (match start
                   ((laBad) true)
                   (_ (match end
                        ((laBad) true)
                        ((laNum e) (match start ((laNum s) (< e s)) (_ false)))
                        (_ false))))
        dash (dashArg (list (pair "base" (some base)) (pair "rev" (some rev)) (pair "path" (some path)) (pair "limit" limit)))
        rootDir ctx.root]
    (cond
      (badLines
        (rejectRec rid opName "ERR_BAD_ARG"
          (str ":start and :end are line numbers from 1, :end not before :start (got " (reprKv (opGet op "start")) ", " (reprKv (opGet op "end")) ")") path))
      ((some? dash)
        (let [d (optionOr dash (pair "" ""))]
          (rejectRec rid opName "ERR_BAD_ARG" (str "Argument '" (pairFirst d) "' starting with '-' is not allowed: " (pairSecond d)) path)))
      ((and (not (stringEmpty? path)) (not (isPathInRepo! path rootDir)))
        (list (rs "id" rid) (rs "op" opName) (rs "path" path) (rs "status" "rejected") (rs "error" "ERR_BOUNDARY_VIOLATION")
          (rs "message" (str "Path '" path "' leaves repository boundary"))))
      (else
        (let [cp (cleanPath! path rootDir)
              lim (match limit ((some l) (pyInt l)) ((none) (some 10)))]
          (cond
            ((= opName "gitDiff") (runGitArgv! rid opName (diffArgv base cp) ctx path base rev (truthyText (opGet op "base")) limit start end))
            ((= opName "gitLog")
              (match lim
                ((none) (rejectRec rid opName "ERR_BAD_ARG" (str "Invalid limit argument: " (optionOr limit "")) ""))
                ((some n) (if (< n 0)
                            (rejectRec rid opName "ERR_BAD_ARG" (str "Argument 'limit' must be non-negative: " (optionOr limit "")) "")
                            (runGitArgv! rid opName (logArgv n cp) ctx path base rev (truthyText (opGet op "base")) limit start end)))))
            ((= opName "gitShow") (runGitArgv! rid opName (showArgv rev cp) ctx path base rev (truthyText (opGet op "base")) limit start end))
            (else (list (rs "id" rid) (rs "op" opName) (rs "status" "rejected") (rs "error" "ERR_EFFECT_UNDECLARED"))))))))

fn runGitArgv! rid: String opName: String argv: (List String) ctx: GitCtx path: String base: String rev: String rawBase: String limit: (Option String) start: LineArg end: LineArg -> (List (Pair String RVal))
  (let [t ctx.timeoutSec]
    (match (runBounded! argv (some ctx.root) (some t) ctx.env (none))
      ((err m) (list (rs "id" rid) (rs "op" opName) (rs "status" "rejected") (rs "error" "ERR_GIT_FAILED") (rs "message" m) (ri "exit" 1)))
      ((ok b)
        (if b.timedOut
          (list (rs "id" rid) (rs "op" opName) (rs "status" "rejected") (rs "error" "ERR_GIT_FAILED")
            (rs "message" (str "git " opName " killed after " (itos t) " s")) (pair "timeout" (rBool true)) (ri "seconds" t) (ri "exit" 1))
          (gitRunRec rid opName argv b path base rev rawBase limit start end ctx.readCap)))))

; (:m :ref AGENTLOOP-GATE-KILLTREE :do "a gate runs under the fleet guard (fr/guardStart!): its deadline, a descendant limit and a tree kill with the groups and pins the guard recorded, so a test binary in its own process group under the gate CLI dies with it; runBounded!'s SIGKILL of the gate's group alone left such binaries running under systemd --user. A gone watched pid stops the guarded tree like a timeout")
; (:m :ref AGENTLOOP-GATE-KILLTREE :do "the descendant limit of a gate run is .asl.config.asn :agentLoop :gateMaxDescendants of the run root (a positive integer, checked by ac/configProblems), else 512")
fn ! gateMaxDesc! root: String -> Int64
  (match (ac/agentLoopValue (ac/configText! root) ":gateMaxDescendants")
    ((some v) (optionOr (ac/positiveInt v) 512))
    ((none) 512))

(schema GateEnd
  (:f out fr/ProcOut)
  (:f stopped Bool)
  (:f killed String))

fn ! gateLoop! g: fr/Guarded watch: (Option Int64) stopped: Bool -> GateEnd
  (let [s (fr/guardAdvance! g)]
    (match s.out
      ((some o) (GateEnd :out o :stopped stopped :killed s.guard.run.killed))
      ((none)
        (if (and (not stopped) (watchedGone? watch))
          (do (fr/stopGuard! s.guard) (gateLoop! s.guard watch true))
          (do (if s.progress () (do (fdPoll (fr/guardFds s.guard) 50) ())) (gateLoop! s.guard watch stopped))))))

fn guardNoteMark -> String
  "\n(:fleetRun :verdict :"

fn lastNoteAt text: String from: Int64 found: (Option Int64) -> (Option Int64)
  (match (stringIndexOf (c/sliceOf text from (stringLength text)) (guardNoteMark))
    ((some i) (lastNoteAt text (+ from (+ i 1)) (some (+ from i))))
    ((none) found))

; (:m :ref AGENTLOOP-GATE-KILLTREE-FIX :do "the guard appends its (:fleetRun :verdict ...) note to stderr only when it killed the gate; the note is stripped only then (its last occurrence, after whatever the gate printed), so a gate that prints such a line itself keeps its stderr whole")
fn withoutGuardNote text: String killed: String -> String
  (if (stringEmpty? killed) text
    (match (lastNoteAt text 0 none) ((some i) (c/sliceOf text 0 i)) ((none) text)))

; (:m :ref AGENTLOOP-GATE-KILLTREE-FIX :do "the guard verdict comes from the guard's own kill record (fr RunningSep killed: timeout or runaway), never from the gate's stderr: timeout, maxDesc for the descendant limit, \"\" for a gate that ended by itself or was stopped for a gone watched pid")
fn guardVerdict killed: String -> String
  (cond
    ((= killed "timeout") "timeout")
    ((= killed "runaway") "maxDesc")
    (else ""))

fn ! startFailMsg! d: fr/ProcOut root: String -> String
  (spawnMessage! (pyStrip (optionOr (listLast (stringSplit d.stderr ": ")) "")) (some root) "sh")

fn ! boundedOfEnd! root: String e: GateEnd -> Bounded
  (let [maxDesc (gateMaxDesc! root)
        o e.out
        verdict (guardVerdict e.killed)
        timedOut (or e.stopped (= verdict "timeout"))
        own (withoutGuardNote o.stderr e.killed)
        errText (if (= verdict "maxDesc") (str own (if (or (stringEmpty? own) (stringEndsWith? own "\n")) "" "\n") "(:guard :maxDesc :limit " maxDesc ")\n") own)]
    (Bounded :code (if timedOut none (some o.exitCode)) :out (universalNewlines o.stdout) :errText (universalNewlines errText) :timedOut timedOut :guard verdict))

fn ! runGate! cmd: String root: String timeoutSec: Int64 env: (List String) watch: (Option Int64) -> (Result Bounded String)
  (let [maxDesc (gateMaxDesc! root)]
    (match (fr/guardStart! (list "sh" "-c" cmd) root env (fr/limits timeoutSec maxDesc))
      ((err d) (err (startFailMsg! d root)))
      ((ok g) (ok (boundedOfEnd! root (gateLoop! g watch false))))))

fn runGatesWatched! gates: (List (Pair String String)) root: String timeoutSec: Int64 env: (Option (List String)) watch: (Option Int64) -> (List (List (Pair String RVal)))
  (runGates! gates root timeoutSec env watch)

fn runGates! gates: (List (Pair String String)) root: String timeoutSec: Int64 env: (Option (List String)) watch: (Option Int64) -> (List (List (Pair String RVal)))
  (runGatesIn! gates root timeoutSec env watch (gd/gateTimesPath))

fn recOfRun rid: String cmd: String sec: Int64 root: String res: (Result Bounded String) extra: (List (Pair String RVal)) -> (List (Pair String RVal))
  (match res
    ((err m) (list (rs "id" rid) (rs "cmd" cmd) (ri "exit" 1) (rs "stderr" m)))
    ((ok b)
     (listAppend
       (list (rs "id" rid) (rs "cmd" cmd) (pair "exit" (match b.code ((some x) (rInt x)) ((none) (rNull))))
         (rs "stdout" b.out) (rs "stderr" b.errText))
       (listAppend (if b.timedOut (list (pair "timeout" (rBool true)) (ri "seconds" sec)) (list))
         (listAppend (if (= b.guard "maxDesc") (list (rs "guard" "maxDesc") (ri "maxDescendants" (gateMaxDesc! root))) (list))
           extra)))))

fn ! gateRunRec! rid: String cmd: String root: String sec: Int64 childEnv: (List String) watch: (Option Int64) extra: (List (Pair String RVal)) -> (List (Pair String RVal))
  (recOfRun rid cmd sec root (runGate! cmd root sec childEnv watch) extra)

; (:m :ref LEONSPEED-PARGATES :do "the gates between two build.sh gates run concurrently, at most gateParallelism (3) at a time, each under its own guard (the same deadline, descendant limit and tree kill as a single gate); the pool is one loop in this process that advances every running guard and polls their pipes, so no child is started outside fr/guardStart!; receipts come back in the original gate order")
fn gateParallelism -> Int64
  3

(schema GateSpec
  (:f rid String)
  (:f cmd String)
  (:f sec Int64)
  (:f extra (List (Pair String RVal))))

(schema GateLive
  (:f idx Int64)
  (:f spec GateSpec)
  (:f g fr/Guarded)
  (:f stopped Bool))

fn ! liveFds live: (List GateLive) -> (List (Pair Int64 Int64))
  (fold (fn [acc r] (listAppend acc (fr/guardFds r.g))) (list) live)

fn ! parLoop! root: String childEnv: (List String) watch: (Option Int64) limit: Int64 pending: (List (Pair Int64 GateSpec)) running: (List GateLive) done: (List (Pair Int64 (List (Pair String RVal)))) -> (List (Pair Int64 (List (Pair String RVal))))
  (cond
    ((and (listEmpty? pending) (listEmpty? running)) done)
    ((and (not (listEmpty? pending)) (< (listLength running) limit))
      (match (listHead pending)
        ((none) done)
        ((some p)
          (let [spec (pairSecond p)
                rest (listDrop pending 1)]
            (match (fr/guardStart! (list "sh" "-c" spec.cmd) root childEnv (fr/limits spec.sec (gateMaxDesc! root)))
              ((err d) (parLoop! root childEnv watch limit rest running
                         (listAppend done (list (pair (pairFirst p) (recOfRun spec.rid spec.cmd spec.sec root (err (startFailMsg! d root)) spec.extra))))))
              ((ok g) (parLoop! root childEnv watch limit rest
                         (listAppend running (list (GateLive :idx (pairFirst p) :spec spec :g g :stopped false))) done)))))))
    (else
      (let [stepped (map (fn [r] (pair r (fr/guardAdvance! r.g))) running)
            ended (filter (fn [x] (let [s (pairSecond x)] (some? s.out))) stepped)
            doneNow (map (fn [x] (let [r (pairFirst x)
                                       s (pairSecond x)]
                                   (match s.out
                                     ((some o) (pair r.idx (recOfRun r.spec.rid r.spec.cmd r.spec.sec root
                                                 (ok (boundedOfEnd! root (GateEnd :out o :stopped r.stopped :killed s.guard.run.killed))) r.spec.extra)))
                                     ((none) (pair r.idx (list))))))
                      ended)
            alive (map (fn [x] (let [r (pairFirst x)
                                     s (pairSecond x)
                                     gone (and (not r.stopped) (watchedGone? watch))
                                     _ (if gone (stopGuardNote! s.guard) 0)]
                                 (GateLive :idx r.idx :spec r.spec :g s.guard :stopped (or r.stopped gone))))
                    (filter (fn [x] (let [s (pairSecond x)] (none? s.out))) stepped))
            progressed (listAny? (fn [x] (let [s (pairSecond x)] s.progress)) stepped)
            _ (if (or progressed (not (listEmpty? doneNow))) 0 (do (fdPoll (liveFds alive) 50) 0))]
        (parLoop! root childEnv watch limit pending alive (listAppend done doneNow)))))

fn ! stopGuardNote! g: fr/Guarded -> Int64
  (fr/stopGuard! g)

fn buildGate? g: (Pair String String) -> Bool
  (stringEndsWith? (pairSecond g) "build.sh")

fn chunksOf gates: (List (Pair String String)) -> (List (List (Pair String String)))
  (let [st (fold (fn [(st (Pair (List (List (Pair String String))) (List (Pair String String)))) (g (Pair String String))] -> (Pair (List (List (Pair String String))) (List (Pair String String)))
                   (if (buildGate? g)
                     (pair (listAppend (listAppend (pairFirst st) (if (listEmpty? (pairSecond st)) (list) (list (pairSecond st)))) (list (list g))) (list))
                     (pair (pairFirst st) (listAppend (pairSecond st) (list g)))))
                 (pair (list) (list)) gates)]
    (listAppend (pairFirst st) (if (listEmpty? (pairSecond st)) (list) (list (pairSecond st)))))

; (:m :ref LEONSPEED-PARGATES :do "gatePrep: the finished receipt when the gate needs no run (gateTimeoutFit skip), else the spec of the run to start")
fn ! gatePrep! g: (Pair String String) timesPath: String timeoutSec: Int64 -> (Pair (Option (List (Pair String RVal))) GateSpec)
  (let [rid (pairFirst g)
        cmd (pairSecond g)]
    (match (gd/gateTimeoutFit! timesPath cmd timeoutSec)
      ((some ms)
        (let [raised (gd/gateRaisedSec ms)]
          (if (> raised (gd/gateTimeoutCapSec))
            (pair (some (list (rs "id" rid) (rs "cmd" cmd) (pair "exit" (rNull)) (rs "skipped" "gateTimeoutFit") (ri "recordedMs" ms) (ri "timeoutSec" timeoutSec)
                          (rs "hint" "the suite's recorded time x 1.5 exceeds the gate timeout: move it to :done or raise :gateTimeout")))
                  (GateSpec :rid rid :cmd cmd :sec timeoutSec :extra (list)))
            (pair none (GateSpec :rid rid :cmd cmd :sec raised
                         :extra (list (ri "timeoutSec" raised) (ri "recordedMs" ms) (rs "raised" "gateTimes")))))))
      ((none) (pair none (GateSpec :rid rid :cmd cmd :sec timeoutSec :extra (list))))))

fn ! chunkRecs! chunk: (List (Pair String String)) root: String timeoutSec: Int64 childEnv: (List String) watch: (Option Int64) timesPath: String -> (List (List (Pair String RVal)))
  (let [preps (map (fn [g] (gatePrep! g timesPath timeoutSec)) chunk)
        jobs (map (fn [p] (pair (pairFirst p) (pairSecond (pairSecond p))))
               (filter (fn [p] (none? (pairFirst (pairSecond p)))) (enumerate preps)))
        got (parLoop! root childEnv watch (gateParallelism) jobs (list) (list))]
    (map (fn [p]
           (match (pairFirst (pairSecond p))
             ((some r) r)
             ((none) (match (listHead (filter (fn [d] (= (pairFirst d) (pairFirst p))) got))
                       ((some d) (pairSecond d))
                       ((none) (list (rs "id" "") (ri "exit" 1) (rs "stderr" "gate pool lost a receipt")))))))
      (enumerate preps)))

fn runGatesIn! gates: (List (Pair String String)) root: String timeoutSec: Int64 env: (Option (List String)) watch: (Option Int64) timesPath: String -> (List (List (Pair String RVal)))
  (let [childEnv (envWith (envBase! env) "PYTHONDONTWRITEBYTECODE" "1")
        st (fold (fn [(st (Pair Bool (List (List (Pair String RVal))))) (chunk (List (Pair String String)))] -> (Pair Bool (List (List (Pair String RVal))))
                   (let [failed (pairFirst st)
                         recs (if failed
                                (map (fn [g] (list (rs "id" (pairFirst g)) (rs "cmd" (pairSecond g)) (pair "exit" (rNull)) (rs "skipped" "afterBuildFail"))) chunk)
                                (chunkRecs! chunk root timeoutSec childEnv watch timesPath))
                         buildRed (and (not failed) (and (buildGate? (optionOr (listHead chunk) (pair "" "")))
                                   (match (listHead recs)
                                     ((some rec) (match (recGet rec "exit") ((some v) (match v ((rInt x) (not (= x 0))) (_ false))) ((none) false)))
                                     ((none) false))))]
                     (pair (or failed buildRed) (listAppend (pairSecond st) recs))))
                 (pair false (list))
                 (chunksOf gates))]
    (pairSecond st))

fn preflightOne! i: Int64 cmd: String root: String env: (Option (List String)) -> (Option (List (Pair String RVal)))
  (let [res (runBounded! (list "sh" "-n" "-c" cmd) (if (stringEmpty? root) (none) (some root)) (some 10) env (none))
        code (match res ((ok b) b.code) ((err _) (some 1)))
        errText (match res ((ok b) b.errText) ((err m) m))
        timedOut (match res ((ok b) b.timedOut) ((err _) false))]
    (if (or timedOut (!= (optionOr code 0) 0))
      (let [m (pyStrip errText)]
        (some (list (ri "n" i) (rs "cmd" cmd)
                (rs "message" (if (stringEmpty? m) (str "sh -n exited " (match code ((some x) (itos x)) ((none) "None"))) m)))))
      (none)))

fn gatePreflight! gates: (List String) root: String env: (Option (List String)) -> (List (List (Pair String RVal)))
  (let [numbered (enumerate gates)]
    (fold (fn [acc p]
            (match (preflightOne! (+ (pairFirst p) 1) (pairSecond p) root env)
              ((some r) (listAppend acc (list r)))
              ((none) acc)))
      (list) numbered))

fn recGet rec: (List (Pair String RVal)) key: String -> (Option RVal)
  (match (listHead (filter (fn [p] (= (pairFirst p) key)) rec))
    ((some p) (some (pairSecond p)))
    ((none) (none)))

fn recText rec: (List (Pair String RVal)) key: String -> String
  (match (recGet rec key)
    ((some v) (match v ((rStr s) s) ((rInt n) (itos n)) (_ "")))
    ((none) ""))

fn formatGatePreflight bad: (List (List (Pair String RVal))) -> String
  (stringJoin
    (map (fn [b] (str "(:n " (recText b "n") " :cmd \"" (c/escapeAsn (recText b "cmd")) "\" :shell \"sh\" :message \"" (c/escapeAsn (recText b "message")) "\")")) bad)
    " ")

fn changedOwnedFiles! owns: (List String) root: String env: (Option (List String)) -> (Result (List String) String)
  (if (listEmpty? owns)
    (ok (list))
    (match (runBounded! (listAppend (list "git" "status" "--porcelain" "--untracked-files=all" "--") owns) (some root) (none) env (none))
      ((err m) (err m))
      ((ok b)
        (ok (map (fn [l] (pyStrip (cpDrop l 3)))
              (filter (fn [l] (> (cpLength l) 3)) (pySplitLines b.out false)))))))

fn serVal v: RVal -> String
  (match v
    ((rStr s) (c/serString s))
    ((rInt n) (itos n))
    ((rBool b) (if b "true" "false"))
    ((rNull) "nil")
    ((rPair a b) (str "(" (itos a) " " (itos b) ")")))

fn serRec rec: (List (Pair String RVal)) -> String
  (str "(r" (stringJoin (map (fn [p] (str " (" (pairFirst p) " " (serVal (pairSecond p)) ")")) rec) "") ")")

fn serRecs head: String recs: (List (List (Pair String RVal))) -> String
  (str "(" head (stringJoin (map (fn [r] (str " " (serRec r))) recs) "") ")")

; (:m :ref LEON-ROUTE-SCRATCH-COST :do "a scratch tree for judging an answer: when root is a git worktree top, a detached worktree at HEAD plus the root's uncommitted tracked diff and its untracked unignored files (ignored files are not carried); otherwise, or when any step fails, a cp -a copy; scratchDrop! always removes it and prunes the worktree record")
fn ! gitText! argv: (List String) cwd: String -> (Option String)
  (match (runBounded! argv (some cwd) (some 120) none none)
    ((ok b) (if (= (optionOr b.code 1) 0) (some b.out) none))
    ((err _) none))

fn ! gitOk! argv: (List String) cwd: String -> Bool
  (some? (gitText! argv cwd))

fn ! copyUntracked! root: String scratch: String files: (List String) -> Bool
  (fold (fn [acc f]
          (and acc
            (let [parts (stringSplit f "/")
                  parent (stringJoin (listAppend (list scratch) (listTake parts (- (listLength parts) 1))) "/")]
              (and (gitOk! (list "mkdir" "-p" parent) root)
                   (gitOk! (list "cp" "-p" (str root "/" f) (str scratch "/" f)) root)))))
        true files)

fn ! scratchCopy! root: String scratch: String -> (Result String String)
  (match (runBounded! (list "cp" "-a" root scratch) none (some 300) none none)
    ((ok b) (if (= (optionOr b.code 1) 0) (ok "copy") (err (str "cp failed: " b.errText))))
    ((err e) (err e)))

fn ! scratchDrop! root: String scratch: String kind: String -> Bool
  (let [removed (if (= kind "worktree") (= (vg/worktreeRemove! root scratch).exit 0) true)
        _ (pathRemove scratch)
        _ (pathRemove (str scratch ".patch"))
        pruned (if (= kind "worktree") (= (vg/worktreePrune! root).exit 0) true)]
    true)

fn ! scratchTree! root: String scratch: String -> (Result String String)
  (let [top (gitText! (list "git" "rev-parse" "--show-toplevel") root)
        isTop (match top ((some t) (= (resultOr (realPath (stringTrim t)) (stringTrim t)) (resultOr (realPath root) root))) ((none) false))]
    (if (and isTop (= (vg/worktreeAdd! root scratch "HEAD").exit 0))
      (let [patch (str scratch ".patch")
            diff (gitText! (list "git" "diff" "--binary" "HEAD") root)
            patched (match diff
                      ((some d) (if (stringEmpty? d) true
                                  (and (ok? (fileWrite patch d)) (= (vg/applyPatch! scratch patch false).exit 0))))
                      ((none) false))
            untracked (gitText! (list "git" "ls-files" "--others" "--exclude-standard") root)
            copied (match untracked
                     ((some t) (copyUntracked! root scratch (filter (fn [l] (not (stringEmpty? l))) (stringSplit t "\n"))))
                     ((none) false))]
        (if (and patched copied)
          (ok "worktree")
          (do (scratchDrop! root scratch "worktree") (scratchCopy! root scratch))))
      (scratchCopy! root scratch)))
