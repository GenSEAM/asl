(module asl-store-fs/log
  :x [Recovered LogCfg recoverSegment defaultRecover logAppend! logRead! logCommit! logCursor! ensureTree! lockUntil! dirName replaceFile! segBases! segPath]
  :i [(asl-store/types :a ty) (asl-store/kv :a kv) (asl-store-fs/wal :a wal)])

; (:m :ref VS-CORE :do "what a segment file holds: the records that parse in sequence, the text to keep, whether a torn tail was dropped, and err non-empty when the damage is not a tail (a bad line with records after it, or a gap) and the segment cannot be trusted")
(schema Recovered (:f rows (List ty/LogRow)) (:f keep String) (:f torn Bool) (:f err String))

; (:m :ref VS-CORE :do "recover is a field so a test can inject a worse policy; lockWaitMs bounds how long a writer waits for the stream lock before answering busy")
(schema LogCfg (:f root String) (:f segmentMax Int64) (:f lockWaitMs Int64) (:f recover (fn [String Int64] -> Recovered)))

fn ! ensureTree! p: String -> (Result Unit String)
  (match (fileStat p)
    ((ok st) (if st.isDir (ok ()) (err (str p ": not a directory"))))
    ((err _) (match (dirCreate p)
               ((ok _) (ok ()))
               ((err e) (match (fileStat p) ((ok st) (if st.isDir (ok ()) (err e))) ((err _) (err (str p ": " e))))))))

fn dirName p: String -> String
  (let [(parts (stringSplit p "/"))]
    (stringJoin (listTake parts (- (listLength parts) 1)) "/"))

fn ! lockUntil! path: String untilNs: Int64 -> (Result Int64 String)
  (match (fileLock path true)
    ((ok fd) (ok fd))
    ((err e) (cond
               ((!= e "busy") (err (str "lock " path ": " e)))
               ((< (monotonicNs) untilNs) (do (sleepMs 5) (lockUntil! path untilNs)))
               (else (err (str "lock " path ": busy"))))))

; (:m :ref VS-CORE :do "a file is replaced by writing a tmp sibling, fsyncing it and renaming over the target, so a crash leaves the old text or the new text and never a mix")
fn ! replaceFile! path: String text: String -> (Result Unit String)
  (let [(tmp (str path ".tmp." (stringFromInt64 (procSelf)) "." (stringFromInt64 (nowNs))))]
    (match (fileWrite tmp (stringToBytes text))
      ((err e) (do (pathRemove tmp) (err (str "write " tmp ": " e))))
      ((ok _) (match (fileFsync tmp)
                ((err e) (do (pathRemove tmp) (err (str "fsync " tmp ": " e))))
                ((ok _) (match (pathRename tmp path)
                          ((err e) (do (pathRemove tmp) (err (str "rename " tmp ": " e))))
                          ((ok _) (ok ()))))))))

fn rowOf e: wal/WalEntry -> ty/LogRow
  (ty/LogRow :offset e.seqNum :value e.payload :at e.timestampEpoch)

fn parseLine line: String want: Int64 -> (Pair String (Option ty/LogRow))
  (match (wal/parseWalFrame line)
    ((none) (pair "corrupt" (none)))
    ((some e) (if (= e.seqNum want) (pair "ok" (some (rowOf e))) (pair "gap" (none)))))

fn scanLines lines: (List String) base: Int64 acc: (List ty/LogRow) -> (Pair String (List ty/LogRow))
  (if (listEmpty? lines)
    (pair "ok" (listReverse acc))
    (let [(r (parseLine (optionOr (listHead lines) "") (+ base (listLength acc))))]
      (match (pairSecond r)
        ((some row) (scanLines (optionOr (listTail lines) (list)) base (cons row acc)))
        ((none) (pair (str (pairFirst r) " at line " (stringFromInt64 (+ (listLength acc) 1))) (listReverse acc))))))

fn framesText rows: (List ty/LogRow) stream: String -> String
  (stringJoin (map (fn [(r ty/LogRow)] -> String (str (wal/formatWalFrame (wal/makeWalEntry r.offset r.at (wal/opLogAppend) stream r.value)) "\n")) rows) "")

; (:m :ref VS-CORE :do "the torn-tail rule: only the end of the last segment may be damaged. An unterminated last line, or one corrupt line that is the last terminated line, is a torn tail and is dropped; a corrupt line with records after it, or a sequence gap, is err logCorrupt and nothing is repaired")
fn recoverSegment text: String base: Int64 -> Recovered
  (let [(parts (stringSplit text "\n"))
        (tail (optionOr (listLast parts) ""))
        (complete (listTake parts (- (listLength parts) 1)))
        (r (scanLines complete base (list)))
        (rows (pairSecond r))
        (kept (listLength rows))
        (rest (- (listLength complete) kept))]
    (cond
      ((= (pairFirst r) "ok")
        (Recovered :rows rows :keep (stringJoin (map (fn [(l String)] -> String (str l "\n")) complete) "") :torn (not (stringEmpty? tail)) :err ""))
      ((and (stringStartsWith? (pairFirst r) "corrupt") (and (= rest 1) (stringEmpty? tail)))
        (Recovered :rows rows :keep (stringJoin (map (fn [(l String)] -> String (str l "\n")) (listTake complete kept)) "") :torn true :err ""))
      (else (Recovered :rows rows :keep text :torn false :err (str "logCorrupt: " (pairFirst r))))))

fn defaultRecover -> (fn [String Int64] -> Recovered)
  (fn [(text String) (base Int64)] -> Recovered (recoverSegment text base))

fn pad12 n: Int64 -> String
  (let [(s (stringFromInt64 n))] (str (stringRepeat "0" (max 0 (- 12 (stringLength s)))) s))

fn streamDir cfg: LogCfg stream: String -> String
  (str cfg.root "/log/" stream)

fn segPath cfg: LogCfg stream: String base: Int64 -> String
  (str (streamDir cfg stream) "/" (pad12 base) ".seg")

fn ! segBases! cfg: LogCfg stream: String -> (List Int64)
  (match (dirList (streamDir cfg stream))
    ((err _) (list))
    ((ok names) (fold (fn [(acc (List Int64)) (n String)] -> (List Int64)
                        (if (stringEndsWith? n ".seg")
                          (match (stringToInt64 (stripZeros (optionOr (stringSlice n 0 12) "0"))) ((some b) (listAppend acc (list b))) ((none) acc))
                          acc))
                      (list) (listSort names))))

fn stripZeros s: String -> String
  (if (and (> (stringLength s) 1) (stringStartsWith? s "0")) (stripZeros (optionOr (stringSlice s 1 (stringLength s)) "0")) s)

fn ! segText! cfg: LogCfg stream: String base: Int64 -> (Result String String)
  (let [(p (segPath cfg stream base))]
    (if (fileExists? p)
      (match (fileReadString p) ((ok t) (ok t)) ((err e) (err (str "read " p ": " e))))
      (ok "")))

fn codeOf e: String -> String
  (if (stringStartsWith? e "logCorrupt") "logCorrupt" "io")

fn errOf code: String text: String -> ty/Reply
  (ty/rErr code text)

fn ! lastState! cfg: LogCfg stream: String -> (Result (Pair Int64 Recovered) String)
  (let [(bases (segBases! cfg stream))]
    (match (listLast bases)
      ((none) (ok (pair 0 (Recovered :rows (list) :keep "" :torn false :err ""))))
      ((some b) (match (segText! cfg stream b)
                  ((err e) (err e))
                  ((ok text) (let [(rec (cfg.recover text b))] (if (stringEmpty? rec.err) (ok (pair b rec)) (err rec.err))))))))

; (:m :ref VS-CORE :do "append recovers the last segment under the stream lock, truncates a torn tail by replacing the file, rolls to a new segment named by its first offset after segmentMax records, then appends one framed line and fsyncs it")
fn ! logAppend! cfg: LogCfg stream: String value: String now: Int64 -> ty/Reply
  (match (ensureTree! (streamDir cfg stream))
    ((err e) (errOf "io" e))
    ((ok _) (match (lockUntil! (str (streamDir cfg stream) "/.lock") (+ (monotonicNs) (* cfg.lockWaitMs 1000000)))
              ((err e) (errOf (if (stringEndsWith? e "busy") "busy" "io") e))
              ((ok fd) (let [(r (appendLocked! cfg stream value now)) (_ (fdClose fd))] r)))))

fn ! appendLocked! cfg: LogCfg stream: String value: String now: Int64 -> ty/Reply
  (match (lastState! cfg stream)
    ((err e) (errOf (codeOf e) e))
    ((ok st)
      (let [(base (pairFirst st))
            (rec (pairSecond st))
            (n (listLength rec.rows))
            (healed (if (and rec.torn (> (listLength (stringSplit rec.keep "\n")) 0)) (replaceFile! (segPath cfg stream base) rec.keep) (ok ())))]
        (match healed
          ((err e) (errOf "io" e))
          ((ok _)
            (let [(rolled (>= n cfg.segmentMax))
                  (segBase (if rolled (+ base n) base))
                  (offset (+ base n))
                  (path (segPath cfg stream segBase))
                  (frame (str (wal/formatWalFrame (wal/makeWalEntry offset now (wal/opLogAppend) stream value)) "\n"))]
              (match (fileAppend path (stringToBytes frame))
                ((err e) (errOf "io" (str "append " path ": " e)))
                ((ok _) (match (fileFsync path)
                          ((err e) (errOf "io" (str "fsync " path ": " e)))
                          ((ok _) (ty/rAppended offset)))))))))))

fn ! gather! cfg: LogCfg stream: String bases: (List Int64) from: Int64 want: Int64 acc: (List ty/LogRow) -> (Result (List ty/LogRow) String)
  (if (or (listEmpty? bases) (>= (listLength acc) want))
    (ok acc)
    (let [(b (optionOr (listHead bases) 0))
          (rest (optionOr (listTail bases) (list)))
          (nextBase (optionOr (listHead rest) -1))]
      (if (and (>= nextBase 0) (<= nextBase from))
        (gather! cfg stream rest from want acc)
        (match (segText! cfg stream b)
          ((err e) (err e))
          ((ok text)
            (let [(rec (cfg.recover text b))]
              (if (not (stringEmpty? rec.err))
                (err rec.err)
                (gather! cfg stream rest from want (listAppend acc (filter (fn [(r ty/LogRow)] -> Bool (>= r.offset from)) rec.rows))))))))))

fn ! logRead! cfg: LogCfg stream: String from: Int64 limit: Int64 -> ty/Reply
  (match (gather! cfg stream (segBases! cfg stream) from (ty/capLimit limit) (list))
    ((err e) (errOf (codeOf e) e))
    ((ok rows) (kv/readPage rows from limit)))

fn ! streamLength! cfg: LogCfg stream: String -> (Result Int64 String)
  (match (lastState! cfg stream)
    ((err e) (err e))
    ((ok st) (ok (+ (pairFirst st) (listLength (pairSecond st).rows)))))

fn cursorPath cfg: LogCfg stream: String consumer: String -> String
  (str (streamDir cfg stream) "/cursor." consumer)

; (:m :ref VS-CORE :do "a missing cursor file is offset 0; a cursor file that exists and does not hold a non-negative integer is err cursorCorrupt, never a silent restart from 0")
fn ! cursorOf! cfg: LogCfg stream: String consumer: String -> (Result Int64 String)
  (let [(p (cursorPath cfg stream consumer))]
    (if (not (fileExists? p))
      (ok 0)
      (match (fileReadString p)
        ((err e) (err (str "cursorCorrupt: read " p ": " e)))
        ((ok t) (match (stringToInt64 (stringTrim t))
                  ((some n) (if (>= n 0) (ok n) (err (str "cursorCorrupt: " p))))
                  ((none) (err (str "cursorCorrupt: " p))))))))

fn ! logCursor! cfg: LogCfg stream: String consumer: String -> ty/Reply
  (match (cursorOf! cfg stream consumer)
    ((ok n) (ty/rOffset n))
    ((err e) (errOf (if (stringStartsWith? e "cursorCorrupt") "cursorCorrupt" "io") e)))

; (:m :ref VS-CORE :do "commit holds the stream lock so the length it checks against cannot move under it, and stores the cursor by replacing its file")
fn ! logCommit! cfg: LogCfg stream: String consumer: String offset: Int64 -> ty/Reply
  (match (ensureTree! (streamDir cfg stream))
    ((err e) (errOf "io" e))
    ((ok _) (match (lockUntil! (str (streamDir cfg stream) "/.lock") (+ (monotonicNs) (* cfg.lockWaitMs 1000000)))
              ((err e) (errOf (if (stringEndsWith? e "busy") "busy" "io") e))
              ((ok fd) (let [(r (commitLocked! cfg stream consumer offset)) (_ (fdClose fd))] r)))))

fn ! commitLocked! cfg: LogCfg stream: String consumer: String offset: Int64 -> ty/Reply
  (match (streamLength! cfg stream)
    ((err e) (errOf (codeOf e) e))
    ((ok len)
      (match (cursorOf! cfg stream consumer)
        ((err e) (errOf "cursorCorrupt" e))
        ((ok cur) (match (kv/commitCheck len cur offset)
        ((some bad) bad)
        ((none) (match (replaceFile! (cursorPath cfg stream consumer) (stringFromInt64 offset))
                  ((err e) (errOf "io" e))
                  ((ok _) (ty/rCommitted offset)))))))))
