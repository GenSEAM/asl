(module asl-proc/apm :x [LockVerdict StreamFrame SupervisorVerdict DaemonEntry OobDemuxer makeLockVerdict resolveLock makeStreamFrame countParenBalance isBalancedFrame? extractContentLength parseStreamFrame findBalancedNewlineFrame computeRingBytes makeSupervisorVerdict superviseStep makeDaemonEntry formatDaemonTable makeOobDemuxer oobDemuxChunk oobDemuxFinish] :i [(asl-proc/coreProcess :a cp) (deadline :a wd) (spool :a spool) (reducer :a red)])

(schema LockVerdict (:f acquired Bool) (:f lockPath String) (:f holderPid Int64) (:f status String) (:f event String))

fn makeLockVerdict acquired: Bool lockPath: String holderPid: Int64 status: String event: String -> LockVerdict
  (LockVerdict :acquired acquired :lockPath lockPath :holderPid holderPid :status status :event event)

fn resolveLock lockPath: String currentPid: Int64 holderPid: Int64 holderAlive: Bool -> LockVerdict
  (if (or (= holderPid 0) (= holderPid currentPid)) (makeLockVerdict true lockPath currentPid ":acquired" ":lock-acquired") (if holderAlive (makeLockVerdict false lockPath holderPid ":collision" ":lock-refused") (makeLockVerdict true lockPath currentPid ":stale" ":lock-reclaimed")))

(schema StreamFrame (:f kind String) (:f payload String) (:f length Int64) (:f valid Bool))

fn makeStreamFrame kind: String payload: String length: Int64 valid: Bool -> StreamFrame
  (StreamFrame :kind kind :payload payload :length length :valid valid)

fn countParenBalance text: String -> Int64
  (let [(chars (stringChars text)) (st (fold (fn [(acc (pair Int64 (pair Bool Bool))) (c String)] -> (Pair Int64 (Pair Bool Bool)) (let [(depth (pairFirst acc)) (inStr (pairFirst (pairSecond acc))) (esc (pairSecond (pairSecond acc)))] (if esc (pair depth (pair inStr false)) (if (= c "\\") (if inStr (pair depth (pair inStr true)) (pair depth (pair inStr false))) (if (= c "\"") (pair depth (pair (not inStr) false)) (if inStr acc (if (< depth 0) acc (if (= c "(") (pair (+ depth 1) (pair inStr false)) (if (= c ")") (pair (- depth 1) (pair inStr false)) acc))))))))) (pair 0 (pair false false)) chars))] (pairFirst st))

fn isBalancedFrame? text: String -> Bool
  (let [(clean (stringTrim text))] (if (stringEmpty? clean) false (= (countParenBalance clean) 0)))

fn extractContentLength header: String -> (Option Int64)
  (let [(lower (stringLower header))] (if (stringStartsWith? lower "content-length:") (let [(after (optionOr (stringSlice header 15 (stringLength header)) "")) (clean (stringTrim after))] (stringToInt64 clean)) (none)))

fn findBalancedNewlineFrame buffer: String offset: Int64 -> (Pair (Option StreamFrame) String)
  (let [(bufLen (stringLength buffer))] (if (>= offset bufLen) (pair (none) buffer) (let [(searchFrom (optionOr (stringSlice buffer offset bufLen) "")) (nlRel (stringIndexOf searchFrom "\n"))] (mt nlRel ((some relIdx) (let [(absIdx (+ offset relIdx)) (candidate (optionOr (stringSlice buffer 0 absIdx) "")) (rem (optionOr (stringSlice buffer (+ absIdx 1) bufLen) ""))] (if (= (countParenBalance candidate) 0) (let [(payload (stringTrim candidate))] (if (stringEmpty? payload) (findBalancedNewlineFrame rem 0) (pair (some (makeStreamFrame "newline" payload (int32ToInt64 (stringLength payload)) true)) rem))) (findBalancedNewlineFrame buffer (+ absIdx 1))))) ((none) (pair (none) buffer))))))

fn leadingSpaceEnd s: String i: Int64 -> Int64
  (if (and (< i (stringLength s)) (stringContains? " \t\n\r" (optionOr (stringSlice s i (+ i 1)) "x"))) (leadingSpaceEnd s (+ i 1)) i)

fn trimLeftSpace s: String -> String
  (optionOr (stringSlice s (leadingSpaceEnd s 0) (stringLength s)) s)

fn parseStreamFrame buffer: String -> (Pair (Option StreamFrame) String)
  (let [(trimmed (trimLeftSpace buffer))] (if (stringStartsWith? (stringLower trimmed) "content-length:") (let [(hdrEnd (stringIndexOf trimmed "\n\n")) (hdrDelim (if (some? hdrEnd) hdrEnd (stringIndexOf trimmed "\r\n\r\n")))] (mt hdrDelim ((some idx) (let [(hdrLen (if (stringContains? trimmed "\r\n\r\n") (+ idx 4) (+ idx 2))) (hdrPart (optionOr (stringSlice trimmed 0 idx) "")) (valOpt (extractContentLength hdrPart))] (mt valOpt ((some cl) (let [(bodyStart hdrLen) (totalNeed (+ bodyStart cl)) (bufLen (int32ToInt64 (stringLength trimmed)))] (if (>= bufLen totalNeed) (let [(payload (optionOr (stringSlice trimmed bodyStart totalNeed) "")) (rem (optionOr (stringSlice trimmed totalNeed bufLen) "")) (frame (makeStreamFrame "content-length" payload cl true))] (pair (some frame) rem)) (pair (none) buffer)))) ((none) (pair (none) buffer))))) ((none) (pair (none) buffer)))) (findBalancedNewlineFrame buffer 0)))

(schema SupervisorVerdict (:f status String) (:f exitCode Int64) (:f errorCode String) (:f workerRecycled Bool) (:f summary String))

fn makeSupervisorVerdict status: String exitCode: Int64 errorCode: String workerRecycled: Bool summary: String -> SupervisorVerdict
  (SupervisorVerdict :status status :exitCode exitCode :errorCode errorCode :workerRecycled workerRecycled :summary summary)

fn superviseStep elapsedMs: Int64 deadlineMs: Int64 opName: String -> SupervisorVerdict
  (let [(ceiling (if (<= deadlineMs 0) 10000 deadlineMs)) (verdict (wd/checkStepDeadline elapsedMs ceiling))] (if verdict.timedOut (makeSupervisorVerdict ":recycled" 124 ":ERR_STEP_TIMEOUT" true (str "Step deadline exceeded (10s) on step: " opName)) (makeSupervisorVerdict ":ok" 0 ":OK" false (str "Step completed within deadline: " opName))))

(schema DaemonEntry (:f daemonId String) (:f pid Int64) (:f rssMb Int64) (:f status String) (:f activeOp String))

fn makeDaemonEntry daemonId: String pid: Int64 rssMb: Int64 status: String activeOp: String -> DaemonEntry
  (DaemonEntry :daemonId daemonId :pid pid :rssMb rssMb :status status :activeOp activeOp)

fn formatDaemonTable entries: (List DaemonEntry) -> String
  (let [(header "DAEMON ID  PID     STATUS   RSS(MB)  ACTIVE OP\n---------  ------  -------  -------  ---------") (rows (map (fn [(e DaemonEntry)] -> String (str e.daemonId "  " (stringFromInt64 e.pid) "  " e.status "  " (stringFromInt64 e.rssMb) "MB  " e.activeOp)) entries))] (stringJoin (listAppend (list header) rows) "\n"))

(schema OobDemuxer (:f maxBufferBytes Int64) (:f bufferBytes Int64) (:f totalBytes Int64) (:f spool spool/TwoTierSpool) (:f isTerminated Bool) (:f terminationReason String))

fn makeOobDemuxer spoolPath: String maxBufferBytes: Int64 -> OobDemuxer
  (let [(limit (if (<= maxBufferBytes 0) 67108864 maxBufferBytes)) (tt (spool/makeTwoTierSpool spoolPath 200 10485760))] (OobDemuxer :maxBufferBytes limit :bufferBytes 0 :totalBytes 0 :spool tt :isTerminated false :terminationReason ":none"))

fn computeRingBytes rb: spool/RingBuffer -> Int64
  (fold (fn [(acc Int64) (line String)] -> Int64 (+ acc (int32ToInt64 (stringLength line)))) 0 rb.lines)

fn oobDemuxChunk demuxer: OobDemuxer chunk: String -> OobDemuxer
  (let [(chunkLen (int32ToInt64 (stringLength chunk))) (newTotal (+ demuxer.totalBytes chunkLen)) (maxBuf demuxer.maxBufferBytes)] (if demuxer.isTerminated (with demuxer :maxBufferBytes maxBuf :totalBytes newTotal :isTerminated true) (let [(updatedSpool (spool/twoTierPush demuxer.spool chunk)) (activeRam (computeRingBytes updatedSpool.ring))] (if (> activeRam maxBuf) (OobDemuxer :maxBufferBytes maxBuf :bufferBytes activeRam :totalBytes newTotal :spool updatedSpool :isTerminated true :terminationReason ":buffer-overflow") (OobDemuxer :maxBufferBytes maxBuf :bufferBytes activeRam :totalBytes newTotal :spool updatedSpool :isTerminated false :terminationReason ":none")))))

fn ! oobDemuxFinish demuxer: OobDemuxer exitCode: Int64 durationMs: Int64 -> (Result cp/ProcessReceipt String)
  (mt (spool/twoTierCloseSync! demuxer.spool)
    ((err e) (err e))
    ((ok closedSpool) (let [(spoolPath closedSpool.disk.path) (finalExit (if demuxer.isTerminated -9 exitCode)) (finalSummary (if demuxer.isTerminated "OOB stream terminated: memory bound < 64MB exceeded" (if (= exitCode 0) "Command succeeded" (let [(ringText (spool/ringToString demuxer.spool.ring))] (red/extractErrorSummary ringText "" exitCode)))))] (ok (cp/makeProcessReceipt finalExit durationMs 32 spoolPath finalSummary)))))
