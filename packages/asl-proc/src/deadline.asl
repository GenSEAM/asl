(module asl-proc/deadline :x [RssVerdict DeadlockVerdict PortVerdict StepDeadlineVerdict makeRssVerdict checkRssCeiling makeDeadlockVerdict detectDeadlock detectDeadlockEscalation makePortVerdict detectBoundPort parsePortNumber makeStepDeadlineVerdict checkStepDeadline])

(schema RssVerdict (:f exceeded Bool) (:f rssMb Int64) (:f ceilingMb Int64) (:f signal String) (:f event String))

fn makeRssVerdict exceeded: Bool rssMb: Int64 ceilingMb: Int64 signal: String event: String -> RssVerdict
  (RssVerdict :exceeded exceeded :rssMb rssMb :ceilingMb ceilingMb :signal signal :event event)

fn checkRssCeiling currentRssMb: Int64 ceilingMb: Int64 -> RssVerdict
  (let [(limit (if (<= ceilingMb 0) 512 ceilingMb))] (if (> currentRssMb limit) (makeRssVerdict true currentRssMb limit "SIGKILL" ":oom-killed") (makeRssVerdict false currentRssMb limit "NONE" ":ok")))

(schema DeadlockVerdict (:f deadlocked Bool) (:f idleMs Int64) (:f ceilingMs Int64) (:f event String) (:f signal String) (:f exitCode Int64) (:f killCeilingMs Int64))

fn makeDeadlockVerdict deadlocked: Bool idleMs: Int64 ceilingMs: Int64 event: String -> DeadlockVerdict
  (DeadlockVerdict :deadlocked deadlocked :idleMs idleMs :ceilingMs ceilingMs :event event :signal (if deadlocked "SIGTERM" "NONE") :exitCode (if deadlocked -15 0) :killCeilingMs 12000)

fn detectDeadlock idleMs: Int64 ceilingMs: Int64 -> DeadlockVerdict
  (let [(cap (if (<= ceilingMs 0) 10000 ceilingMs))] (if (>= idleMs cap) (makeDeadlockVerdict true idleMs cap ":deadlock-detected") (makeDeadlockVerdict false idleMs cap ":ok")))

fn detectDeadlockEscalation idleMs: Int64 termMs: Int64 killMs: Int64 -> DeadlockVerdict
  (let [(tCap (if (<= termMs 0) 10000 termMs)) (kCap (if (<= killMs 0) 12000 killMs))] (cond ((>= idleMs kCap) (DeadlockVerdict :deadlocked true :idleMs idleMs :ceilingMs tCap :event ":deadlock-sigkill" :signal "SIGKILL" :exitCode -9 :killCeilingMs kCap)) ((>= idleMs tCap) (DeadlockVerdict :deadlocked true :idleMs idleMs :ceilingMs tCap :event ":deadlock-sigterm" :signal "SIGTERM" :exitCode -15 :killCeilingMs kCap)) (else (DeadlockVerdict :deadlocked false :idleMs idleMs :ceilingMs tCap :event ":ok" :signal "NONE" :exitCode 0 :killCeilingMs kCap))))

(schema StepDeadlineVerdict (:f timedOut Bool) (:f elapsedMs Int64) (:f ceilingMs Int64) (:f errorCode String) (:f event String))

fn makeStepDeadlineVerdict timedOut: Bool elapsedMs: Int64 ceilingMs: Int64 errorCode: String event: String -> StepDeadlineVerdict
  (StepDeadlineVerdict :timedOut timedOut :elapsedMs elapsedMs :ceilingMs ceilingMs :errorCode errorCode :event event)

fn checkStepDeadline elapsedMs: Int64 ceilingMs: Int64 -> StepDeadlineVerdict
  (let [(cap (if (<= ceilingMs 0) 10000 ceilingMs))] (if (>= elapsedMs cap) (makeStepDeadlineVerdict true elapsedMs cap ":ERR_STEP_TIMEOUT" ":step-timeout-recycled") (makeStepDeadlineVerdict false elapsedMs cap ":none" ":ok")))

(schema PortVerdict (:f detected Bool) (:f port Int64) (:f event String))

fn makePortVerdict detected: Bool port: Int64 event: String -> PortVerdict
  (PortVerdict :detected detected :port port :event event)

fn parsePortNumber text: String -> (Option Int64)
  (let [(clean (stringTrim text)) (chars (stringChars clean)) (digits (fold (fn [(acc (pair (List String) Bool)) (c String)] -> (Pair (List String) Bool) (if (pairSecond acc) acc (if (or (= c "0") (or (= c "1") (or (= c "2") (or (= c "3") (or (= c "4") (or (= c "5") (or (= c "6") (or (= c "7") (or (= c "8") (= c "9")))))))))) (pair (listAppend (pairFirst acc) (list c)) false) (pair (pairFirst acc) true)))) (pair (list) false) chars)) (digitStr (stringJoin (pairFirst digits) ""))] (if (stringEmpty? digitStr) (none) (mt (stringToInt64 digitStr) ((some p) (if (and (> p 0) (<= p 65535)) (some p) (none))) ((none) (none)))))

fn detectBoundPort line: String -> PortVerdict
  (let [(lower (stringLower line))] (cond ((stringContains? lower ":port-bound ") (let [(idx (stringIndexOf lower ":port-bound "))] (mt idx ((some i) (let [(after (optionOr (stringSlice lower (+ i 12) (stringLength lower)) "")) (parts (stringSplit (stringTrim after) " ")) (token (optionOr (listHead parts) ""))] (mt (parsePortNumber token) ((some p) (makePortVerdict true p ":port-bound")) ((none) (makePortVerdict false 0 ":none"))))) ((none) (makePortVerdict false 0 ":none"))))) ((stringContains? lower "listening on port ") (let [(idx (stringIndexOf lower "listening on port "))] (mt idx ((some i) (let [(after (optionOr (stringSlice lower (+ i 18) (stringLength lower)) "")) (parts (stringSplit (stringTrim after) " ")) (token (optionOr (listHead parts) ""))] (mt (parsePortNumber token) ((some p) (makePortVerdict true p ":port-bound")) ((none) (makePortVerdict false 0 ":none"))))) ((none) (makePortVerdict false 0 ":none"))))) ((stringContains? lower "localhost:") (let [(idx (stringIndexOf lower "localhost:"))] (mt idx ((some i) (let [(after (optionOr (stringSlice lower (+ i 10) (stringLength lower)) "")) (parts (stringSplit (stringTrim after) " ")) (token (optionOr (listHead parts) ""))] (mt (parsePortNumber token) ((some p) (makePortVerdict true p ":port-bound")) ((none) (makePortVerdict false 0 ":none"))))) ((none) (makePortVerdict false 0 ":none"))))) ((stringContains? lower "127.0.0.1:") (let [(idx (stringIndexOf lower "127.0.0.1:"))] (mt idx ((some i) (let [(after (optionOr (stringSlice lower (+ i 10) (stringLength lower)) "")) (parts (stringSplit (stringTrim after) " ")) (token (optionOr (listHead parts) ""))] (mt (parsePortNumber token) ((some p) (makePortVerdict true p ":port-bound")) ((none) (makePortVerdict false 0 ":none"))))) ((none) (makePortVerdict false 0 ":none"))))) ((stringContains? lower "0.0.0.0:") (let [(idx (stringIndexOf lower "0.0.0.0:"))] (mt idx ((some i) (let [(after (optionOr (stringSlice lower (+ i 8) (stringLength lower)) "")) (parts (stringSplit (stringTrim after) " ")) (token (optionOr (listHead parts) ""))] (mt (parsePortNumber token) ((some p) (makePortVerdict true p ":port-bound")) ((none) (makePortVerdict false 0 ":none"))))) ((none) (makePortVerdict false 0 ":none"))))) ((stringContains? lower "[::1]:") (let [(idx (stringIndexOf lower "[::1]:"))] (mt idx ((some i) (let [(after (optionOr (stringSlice lower (+ i 6) (stringLength lower)) "")) (parts (stringSplit (stringTrim after) " ")) (token (optionOr (listHead parts) ""))] (mt (parsePortNumber token) ((some p) (makePortVerdict true p ":port-bound")) ((none) (makePortVerdict false 0 ":none"))))) ((none) (makePortVerdict false 0 ":none"))))) ((stringContains? lower "[::]:") (let [(idx (stringIndexOf lower "[::]:"))] (mt idx ((some i) (let [(after (optionOr (stringSlice lower (+ i 5) (stringLength lower)) "")) (parts (stringSplit (stringTrim after) " ")) (token (optionOr (listHead parts) ""))] (mt (parsePortNumber token) ((some p) (makePortVerdict true p ":port-bound")) ((none) (makePortVerdict false 0 ":none"))))) ((none) (makePortVerdict false 0 ":none"))))) (else (makePortVerdict false 0 ":none"))))
