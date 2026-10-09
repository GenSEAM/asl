(module asl-engine/wire
  :x [escapeStr unescapeStr validSessionId? isSpace? tokenizeLoop
      stripLeadingColon parseSimpleSExpr getArg getArgRaw getArgOr
      formatReceiptOk formatReceiptError formatReceiptErrorCode
      formatReceiptInvalidId formatReceiptNotFound
      formatPongOk formatPongOffline formatPongUnresponsive
      formatEngineStatusReceipt formatEngineStoppingReceipt formatEnginePongReceipt
      formatSleepReceipt formatSocketPathTooLong
      formatSpawnActiveReceipt formatPollRunningReceipt formatPollFinishedReceipt
      formatTailReceipt formatKillReceipt formatSendReceipt formatListSessionsReceipt
      formatCliStatusActive formatCliStatusStopped]
  :i [])

fn escapeStr s: String -> String
  (let [(s1 (stringReplace s "\\" "\\\\"))
        (s2 (stringReplace s1 "\"" "\\\""))]
    (stringReplace s2 "\n" "\\n"))

fn unescapeStr s: String -> String
  (let [(s1 (stringReplace s "\\n" "\n"))
        (s2 (stringReplace s1 "\\\"" "\""))]
    (stringReplace s2 "\\\\" "\\"))

fn isIdChar? c: String -> Bool
  (or (and (>= c "a") (<= c "z"))
      (or (and (>= c "A") (<= c "Z"))
          (or (and (>= c "0") (<= c "9"))
              (or (= c ".") (or (= c "_") (= c "-"))))))

fn allIdChars? s: String i: Int64 len: Int64 -> Bool
  (if (>= i len)
    true
    (let [(c (optionOr (stringSlice s i (+ i 1)) ""))]
      (if (isIdChar? c)
        (allIdChars? s (+ i 1) len)
        false)))

fn validSessionId? id: String -> Bool
  (let [(n (stringLength id))]
    (if (and (> n 0) (<= n 128))
      (if (stringContains? id "..")
        false
        (allIdChars? id 0 n))
      false))

fn isSpace? c: String -> Bool
  (or (= c " ") (or (= c "\t") (or (= c "\n") (= c "\r"))))

fn stripLeadingColon s: String -> String
  (if (stringStartsWith? s ":")
    (optionOr (stringSlice s 1 (stringLength s)) "")
    s)

fn skipSpaces s: String i: Int64 len: Int64 -> Int64
  (if (>= i len)
    i
    (let [(c (optionOr (stringSlice s i (+ i 1)) ""))]
      (if (isSpace? c)
        (skipSpaces s (+ i 1) len)
        i)))

fn scanStringLiteral s: String i: Int64 len: Int64 -> Int64
  (if (>= i len)
    i
    (let [(c (optionOr (stringSlice s i (+ i 1)) ""))]
      (cond
        ((= c "\\")
          (scanStringLiteral s (+ i 2) len))
        ((= c "\"")
          (+ i 1))
        (else
          (scanStringLiteral s (+ i 1) len)))))

fn scanBareToken s: String i: Int64 len: Int64 -> Int64
  (if (>= i len)
    i
    (let [(c (optionOr (stringSlice s i (+ i 1)) ""))]
      (if (or (isSpace? c) (or (= c ")") (= c "(")))
        i
        (scanBareToken s (+ i 1) len))))

fn tokenizeLoop s: String i: Int64 len: Int64 acc: (List String) -> (List String)
  (let [(cur (skipSpaces s i len))]
    (if (>= cur len)
      (listReverse acc)
      (let [(c (optionOr (stringSlice s cur (+ cur 1)) ""))]
        (cond
          ((or (= c "(") (= c ")"))
            (tokenizeLoop s (+ cur 1) len acc))
          ((= c "\"")
            (let [(endIdx (scanStringLiteral s (+ cur 1) len))
                  (tok (optionOr (stringSlice s cur endIdx) ""))]
              (tokenizeLoop s endIdx len (cons tok acc))))
          (else
            (let [(endIdx (scanBareToken s cur len))
                  (tok (optionOr (stringSlice s cur endIdx) ""))]
              (tokenizeLoop s endIdx len (cons tok acc))))))))

fn cleanQuotedToken tok: String -> String
  (let [(n (stringLength tok))]
    (if (and (>= n 2) (and (stringStartsWith? tok "\"") (stringEndsWith? tok "\"")))
      (unescapeStr (optionOr (stringSlice tok 1 (- n 1)) ""))
      tok))

fn parseKwargs tokens: (List String) acc: (List (Pair String String)) -> (List (Pair String String))
  (mt (listHead tokens)
    ((none) (listReverse acc))
    ((some tok)
      (let [(rest (optionOr (listTail tokens) (list)))]
        (if (stringStartsWith? tok ":")
          (let [(key (stripLeadingColon tok))]
            (mt (listHead rest)
              ((none) (listReverse (cons (pair key "true") acc)))
              ((some valTok)
                (let [(val (cleanQuotedToken valTok))
                      (afterVal (optionOr (listTail rest) (list)))]
                  (parseKwargs afterVal (cons (pair key val) acc))))))
          (parseKwargs rest acc)))))

fn parseSimpleSExpr rawText: String -> (Pair String (List (Pair String String)))
  (let [(trimmed (stringTrim rawText))
        (n (stringLength trimmed))
        (inner (if (and (>= n 2) (and (stringStartsWith? trimmed "(") (stringEndsWith? trimmed ")")))
                 (stringTrim (optionOr (stringSlice trimmed 1 (- n 1)) ""))
                 trimmed))
        (tokens (tokenizeLoop inner 0 (stringLength inner) (list)))]
    (mt (listHead tokens)
      ((none) (pair "" (list)))
      ((some opTok)
        (let [(op (stripLeadingColon opTok))
              (rest (optionOr (listTail tokens) (list)))
              (kwargs (parseKwargs rest (list)))]
          (pair op kwargs)))))

fn getArg args: (List (Pair String String)) key: String -> (Option String)
  (let [(targetKey (stripLeadingColon key))]
    (mt (listHead args)
      ((none) (none))
      ((some p)
        (if (= (stripLeadingColon (pairFirst p)) targetKey)
          (some (stripLeadingColon (pairSecond p)))
          (getArg (optionOr (listTail args) (list)) key)))))

fn getArgRaw args: (List (Pair String String)) key: String -> (Option String)
  (let [(targetKey (stripLeadingColon key))]
    (mt (listHead args)
      ((none) (none))
      ((some p)
        (if (= (stripLeadingColon (pairFirst p)) targetKey)
          (some (pairSecond p))
          (getArgRaw (optionOr (listTail args) (list)) key)))))

fn getArgOr args: (List (Pair String String)) key: String fallback: String -> String
  (optionOr (getArg args key) fallback)

fn formatReceiptOk payload: String -> String
  (str "(:receipt :status :ok " payload ")")

fn formatReceiptError msg: String -> String
  (str "(:receipt :status :error :message \"" (escapeStr msg) "\")")

fn formatReceiptErrorCode code: String msg: String -> String
  (str "(:receipt :status :error :error-code \"" (escapeStr code) "\" :message \"" (escapeStr msg) "\")")

fn formatReceiptInvalidId id: String -> String
  (str "(:receipt :status :error :error-code \":ERR_INVALID_ID\" :id \"" (escapeStr id) "\" :message \"Session id must match [A-Za-z0-9._-]{1,128} and must not contain ..\")")

fn formatReceiptNotFound id: String -> String
  (str "(:receipt :status :not-found :id \"" (escapeStr id) "\")")

fn formatPongOk pid: Int64 uptimeSec: Int64 scope: String -> String
  (str "(:pong :status :ok :pid " (stringFromInt64 pid) " :uptimeSec " (stringFromInt64 uptimeSec) " :scope \"" (escapeStr scope) "\")")

fn formatPongOffline scope: String -> String
  (str "(:pong :status :offline :scope \"" (escapeStr scope) "\")")

fn formatPongUnresponsive err: String -> String
  (str "(:pong :status :unresponsive :error \"" (escapeStr err) "\")")

fn formatEngineStatusReceipt pid: Int64 uptimeSec: Int64 rssMb: String activeSessions: Int64 socket: String scope: String version: String diskVersion: String stale: Bool updates: Int64 updatedFrom: String -> String
  (str "(:receipt :status :ok :engine :active :pid " (stringFromInt64 pid)
       " :uptimeSec " (stringFromInt64 uptimeSec)
       " :rssMb " rssMb
       " :activeSessions " (stringFromInt64 activeSessions)
       " :socket \"" (escapeStr socket) "\""
       " :scope \"" (escapeStr scope) "\""
       " :version \"" (escapeStr version) "\""
       " :diskVersion \"" (escapeStr diskVersion) "\""
       " :stale " (if stale "true" "false")
       " :updates " (stringFromInt64 updates)
       " :updatedFrom \"" (escapeStr updatedFrom) "\")")

fn formatEngineStoppingReceipt pid: Int64 scope: String -> String
  (str "(:receipt :status :ok :engine :stopping :pid " (stringFromInt64 pid) " :scope \"" (escapeStr scope) "\")")

fn formatEnginePongReceipt pid: Int64 uptimeSec: Int64 scope: String -> String
  (str "(:receipt :status :ok :op :pong :pid " (stringFromInt64 pid) " :uptimeSec " (stringFromInt64 uptimeSec) " :scope \"" (escapeStr scope) "\")")

fn formatSleepReceipt slept: String -> String
  (str "(:receipt :status :ok :op :sleep :slept " slept ")")

fn formatSocketPathTooLong path: String bytes: Int64 limit: Int64 -> String
  (str "(:engine :status :error :error-code ERR_SOCKET_PATH_TOO_LONG :path \"" (escapeStr path) "\" :bytes " (stringFromInt64 bytes) " :limit " (stringFromInt64 limit) ")")

fn formatSpawnActiveReceipt id: String pid: Int64 -> String
  (str "(:receipt :status :ok :id \"" (escapeStr id) "\" :pid " (stringFromInt64 pid) " :state :active)")

fn formatPollRunningReceipt id: String durationMs: Int64 -> String
  (str "(:receipt :status :ok :id \"" (escapeStr id) "\" :state :running :durationMs " (stringFromInt64 durationMs) ")")

fn formatPollFinishedReceipt id: String state: String exitCode: Int64 durationMs: Int64 -> String
  (str "(:receipt :status :ok :id \"" (escapeStr id) "\" :state " state " :exitCode " (stringFromInt64 exitCode) " :durationMs " (stringFromInt64 durationMs) ")")

fn formatTailReceipt id: String lines: (List String) -> String
  (let [(escapedLines (map (fn [(l String)] -> String (str "\"" (escapeStr l) "\"")) lines))
        (inner (stringJoin escapedLines " "))]
    (str "(:receipt :status :ok :id \"" (escapeStr id) "\" :lines [" inner "])"))

fn formatKillReceipt id: String -> String
  (str "(:receipt :status :ok :id \"" (escapeStr id) "\" :state :terminated)")

fn formatSendReceipt id: String sentBytes: Int64 -> String
  (str "(:receipt :status :ok :id \"" (escapeStr id) "\" :sent " (stringFromInt64 sentBytes) ")")

fn formatListSessionsReceipt sessions: (List String) -> String
  (str "(:receipt :status :ok :sessions [" (stringJoin sessions " ") "])")

fn formatCliStatusActive pid: Int64 scope: String socketPath: String rssMb: Int64 ceilingMb: Int64 pidFile: String -> String
  (str "=== ASL ENGINE STATUS ===\n"
       "State:            ACTIVE (PID " (stringFromInt64 pid) ")\n"
       "Scope:            " scope "\n"
       "UNIX Socket:      " socketPath "\n"
       "Memory RSS:       " (stringFromInt64 rssMb) " MB (Ceiling: " (stringFromInt64 ceilingMb) " MB)\n"
       "PID File:         " pidFile "\n"
       "Authority:        ADR0081 / D120 Dual-Mode Context Isolation\n"
       "Ingress Channels: unix-socket, terminal-cli, rpc")

fn formatCliStatusStopped scope: String socketPath: String pidFile: String -> String
  (str "=== ASL ENGINE STATUS ===\n"
       "State:            STOPPED\n"
       "Scope:            " scope "\n"
       "UNIX Socket:      " socketPath "\n"
       "PID File:         " pidFile "\n"
       "Authority:        ADR0081 / D120 Dual-Mode Context Isolation")
