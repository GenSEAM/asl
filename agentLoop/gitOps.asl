(module asl/agentLoop/gitOps
  :x [RVal rStr rInt rBool rNull rPair LineArg laNone laBad laNum Bounded GitCtx
      makeGitCtx runBounded! isPathInRepo! lineArg gitSlice gitNextForm execGitOp!
      runGates! gatePreflight! formatGatePreflight changedOwnedFiles!
      serRec serRecs recGet pyStrip pySplitLines pyNormpath pyRelpath! pyRealpath! pyRepr cpLength]
  :i [(asl/agentLoop/core :a c)])

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
  (:f timedOut Bool))

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
  (mt (listLast (pathComps p)) ((some b) b) ((none) ""))

fn pyRealpath! p: String -> String
  (let [a (pyAbspath! p)]
    (mt (realPath a)
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
  (mt (listHead (filter (fn [p] (= (pairFirst p) key)) op))
    ((some p) (some (pairSecond p)))
    ((none) (none)))

fn kvText v: c/KvVal -> String
  (mt v ((c/kvStr s) s) ((c/kvInt d) d))

fn kvTruthy v: c/KvVal -> Bool
  (mt v
    ((c/kvStr s) (not (stringEmpty? s)))
    ((c/kvInt d) (!= (optionOr (stringToInt64 d) 0) 0)))

fn truthyText o: (Option c/KvVal) -> String
  (mt o ((some v) (if (kvTruthy v) (kvText v) "")) ((none) ""))

fn allDigits s: String -> Bool
  (and (not (stringEmpty? s)) (listAll? (fn [ch] (and (>= ch "0") (<= ch "9"))) (stringChars s)))

fn digitValue s: String -> Int64
  (fold (fn [acc ch] (+ (* acc 10) (- (charCode ch) 48))) 0 (stringChars s))

fn lineArg o: (Option c/KvVal) -> LineArg
  (mt o
    ((none) (laNone))
    ((some v)
      (mt v
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
        stop (mt end ((some e) (min e total)) ((none) total))
        shown (sliceWalk (listDrop lines (- first 1)) (- stop (- first 1)) cap (list) 0)]
    (pair (stringJoin shown "") (list first (+ (- first 1) (listLength shown)) total)))

fn gitNextForm opName: String rev: String path: String base: String limit: (Option String) start: Int64 -> String
  (str "(:step :op \"" opName "\""
    (if (= opName "gitShow") (str " :rev \"" (c/escapeAsn (if (stringEmpty? rev) "HEAD" rev)) "\"") "")
    (if (stringEmpty? path) "" (str " :path \"" (c/escapeAsn path) "\""))
    (if (and (= opName "gitDiff") (not (stringEmpty? base))) (str " :base \"" (c/escapeAsn base) "\"") "")
    (mt limit
      ((some l) (if (and (= opName "gitLog") (not (stringEmpty? l))) (str " :limit " l) ""))
      ((none) ""))
    " :start " (itos start) " :end n)")

fn envBase! env: (Option (List String)) -> (List String)
  (mt env ((some rows) rows) ((none) (envList)))

fn envRowKey row: String -> String
  (mt (stringIndexOf row "=") ((some i) (c/sliceOf row 0 i)) ((none) row))

fn envWith rows: (List String) key: String value: String -> (List String)
  (listAppend (filter (fn [r] (!= (envRowKey r) key)) rows) (list (str key "=" value)))

fn cwdErrno! cwd: (Option String) -> Int64
  (mt cwd
    ((some d) (mt (fileStat d) ((ok st) (if st.isDir 0 20)) ((err _) 2)))
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

fn runBounded! argv: (List String) cwd: (Option String) timeoutSec: (Option Int64) env: (Option (List String)) -> (Result Bounded String)
  (mt (procSpawnv argv cwd env)
    ((err kind) (err (spawnMessage! kind cwd (c/firstOf argv))))
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

fn rs k: String v: String -> (Pair String RVal)
  (pair k (rStr v))

fn ri k: String v: Int64 -> (Pair String RVal)
  (pair k (rInt v))

fn rejectRec rid: String opName: String err: String message: String path: String -> (List (Pair String RVal))
  (listAppend (list (rs "id" rid) (rs "op" opName) (rs "status" "rejected") (rs "error" err) (rs "message" message))
    (if (stringEmpty? path) (list) (list (rs "path" path))))

fn reprKv o: (Option c/KvVal) -> String
  (mt o ((none) "None") ((some v) (mt v ((c/kvInt d) d) ((c/kvStr s) (pyRepr s)))))

fn dashArg args: (List (Pair String (Option String))) -> (Option (Pair String String))
  (if (listEmpty? args)
    (none)
    (let [a (c/firstOf args)]
      (mt (pairSecond a)
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
        startN (mt start ((laNum n) (some n)) (_ (none)))
        endN (mt end ((laNum n) (some n)) (_ (none)))
        sl (gitSlice stdout startN endN cap)
        nums (pairSecond sl)
        first (c/firstOf nums)
        last (c/firstOf (c/restOf nums))
        total (c/firstOf (c/restOf (c/restOf nums)))
        pastEnd (mt startN ((some s) (and (> total 0) (> s total))) ((none) false))
        sliced (or (> first 1) (< last total))
        note (if sliced
               (str "\n... [lines " (itos first) "-" (itos last) " of " (itos total) " (" (itos (cpLength stdout)) " chars)"
                 (if (and (< last total) (mt endN ((some e) (< last e)) ((none) true)))
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
  (let [opName (mt (opGet op "op") ((some v) (kvText v)) ((none) ""))
        path (let [p (truthyText (opGet op "path"))] (if (stringEmpty? p) (truthyText (opGet op "file")) p))
        rawBase (truthyText (opGet op "base"))
        mode ctx.mode
        base (if (and (= opName "gitDiff") (and (or (= mode "scout") (or (= mode "implement") (= mode "auto"))) (and (stringEmpty? rawBase) (not (stringEmpty? ctx.defaultBase)))))
               ctx.defaultBase
               rawBase)
        rev (truthyText (opGet op "rev"))
        limit (mt (opGet op "limit") ((some v) (some (kvText v))) ((none) (none)))
        start (lineArg (opGet op "start"))
        end (lineArg (opGet op "end"))
        badLines (mt start
                   ((laBad) true)
                   (_ (mt end
                        ((laBad) true)
                        ((laNum e) (mt start ((laNum s) (< e s)) (_ false)))
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
              lim (mt limit ((some l) (pyInt l)) ((none) (some 10)))]
          (cond
            ((= opName "gitDiff") (runGitArgv! rid opName (diffArgv base cp) ctx path base rev (truthyText (opGet op "base")) limit start end))
            ((= opName "gitLog")
              (mt lim
                ((none) (rejectRec rid opName "ERR_BAD_ARG" (str "Invalid limit argument: " (optionOr limit "")) ""))
                ((some n) (if (< n 0)
                            (rejectRec rid opName "ERR_BAD_ARG" (str "Argument 'limit' must be non-negative: " (optionOr limit "")) "")
                            (runGitArgv! rid opName (logArgv n cp) ctx path base rev (truthyText (opGet op "base")) limit start end)))))
            ((= opName "gitShow") (runGitArgv! rid opName (showArgv rev cp) ctx path base rev (truthyText (opGet op "base")) limit start end))
            (else (list (rs "id" rid) (rs "op" opName) (rs "status" "rejected") (rs "error" "ERR_EFFECT_UNDECLARED"))))))))

fn runGitArgv! rid: String opName: String argv: (List String) ctx: GitCtx path: String base: String rev: String rawBase: String limit: (Option String) start: LineArg end: LineArg -> (List (Pair String RVal))
  (let [t ctx.timeoutSec]
    (mt (runBounded! argv (some ctx.root) (some t) ctx.env)
      ((err m) (list (rs "id" rid) (rs "op" opName) (rs "status" "rejected") (rs "error" "ERR_GIT_FAILED") (rs "message" m) (ri "exit" 1)))
      ((ok b)
        (if b.timedOut
          (list (rs "id" rid) (rs "op" opName) (rs "status" "rejected") (rs "error" "ERR_GIT_FAILED")
            (rs "message" (str "git " opName " killed after " (itos t) " s")) (pair "timeout" (rBool true)) (ri "seconds" t) (ri "exit" 1))
          (gitRunRec rid opName argv b path base rev rawBase limit start end ctx.readCap)))))

fn runGates! gates: (List (Pair String String)) root: String timeoutSec: Int64 env: (Option (List String)) -> (List (List (Pair String RVal)))
  (let [childEnv (some (envWith (envBase! env) "PYTHONDONTWRITEBYTECODE" "1"))]
    (map (fn [g]
           (let [rid (pairFirst g)
                 cmd (pairSecond g)]
             (mt (runBounded! (list "sh" "-c" cmd) (some root) (some timeoutSec) childEnv)
               ((err m) (list (rs "id" rid) (rs "cmd" cmd) (ri "exit" 1) (rs "stderr" m)))
               ((ok b)
                 (listAppend
                   (list (rs "id" rid) (rs "cmd" cmd) (pair "exit" (mt b.code ((some x) (rInt x)) ((none) (rNull))))
                     (rs "stdout" b.out) (rs "stderr" b.errText))
                   (if b.timedOut (list (pair "timeout" (rBool true)) (ri "seconds" timeoutSec)) (list)))))))
      gates))

fn preflightOne! i: Int64 cmd: String root: String env: (Option (List String)) -> (Option (List (Pair String RVal)))
  (let [res (runBounded! (list "sh" "-n" "-c" cmd) (if (stringEmpty? root) (none) (some root)) (some 10) env)
        code (mt res ((ok b) b.code) ((err _) (some 1)))
        errText (mt res ((ok b) b.errText) ((err m) m))
        timedOut (mt res ((ok b) b.timedOut) ((err _) false))]
    (if (or timedOut (!= (optionOr code 0) 0))
      (let [m (pyStrip errText)]
        (some (list (ri "n" i) (rs "cmd" cmd)
                (rs "message" (if (stringEmpty? m) (str "sh -n exited " (mt code ((some x) (itos x)) ((none) "None"))) m)))))
      (none)))

fn gatePreflight! gates: (List String) root: String env: (Option (List String)) -> (List (List (Pair String RVal)))
  (let [numbered (enumerate gates)]
    (fold (fn [acc p]
            (mt (preflightOne! (+ (pairFirst p) 1) (pairSecond p) root env)
              ((some r) (listAppend acc (list r)))
              ((none) acc)))
      (list) numbered))

fn recGet rec: (List (Pair String RVal)) key: String -> (Option RVal)
  (mt (listHead (filter (fn [p] (= (pairFirst p) key)) rec))
    ((some p) (some (pairSecond p)))
    ((none) (none)))

fn recText rec: (List (Pair String RVal)) key: String -> String
  (mt (recGet rec key)
    ((some v) (mt v ((rStr s) s) ((rInt n) (itos n)) (_ "")))
    ((none) ""))

fn formatGatePreflight bad: (List (List (Pair String RVal))) -> String
  (stringJoin
    (map (fn [b] (str "(:n " (recText b "n") " :cmd \"" (c/escapeAsn (recText b "cmd")) "\" :shell \"sh\" :message \"" (c/escapeAsn (recText b "message")) "\")")) bad)
    " ")

fn changedOwnedFiles! owns: (List String) root: String env: (Option (List String)) -> (Result (List String) String)
  (if (listEmpty? owns)
    (ok (list))
    (mt (runBounded! (listAppend (list "git" "status" "--porcelain" "--untracked-files=all" "--") owns) (some root) (none) env)
      ((err m) (err m))
      ((ok b)
        (ok (map (fn [l] (pyStrip (cpDrop l 3)))
              (filter (fn [l] (> (cpLength l) 3)) (pySplitLines b.out false)))))))

fn serVal v: RVal -> String
  (mt v
    ((rStr s) (c/serString s))
    ((rInt n) (itos n))
    ((rBool b) (if b "true" "false"))
    ((rNull) "nil")
    ((rPair a b) (str "(" (itos a) " " (itos b) ")")))

fn serRec rec: (List (Pair String RVal)) -> String
  (str "(r" (stringJoin (map (fn [p] (str " (" (pairFirst p) " " (serVal (pairSecond p)) ")")) rec) "") ")")

fn serRecs head: String recs: (List (List (Pair String RVal))) -> String
  (str "(" head (stringJoin (map (fn [r] (str " " (serRec r))) recs) "") ")")
