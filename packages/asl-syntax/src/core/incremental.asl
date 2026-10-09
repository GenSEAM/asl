(module asl-syntax/core/incremental
  :x [FatalError
      IncrementalVerdict
      IncrementalState
      incrementalStart!
      incrementalFeed!
      incrementalFeedBytes!
      incrementalFeedString!
      incrementalVerdict
      incrementalTree
      incrementalFatalError
      incrementalHasFatalError?
      incrementalChunkCount
      incrementalTotalBytes
      incrementalStableOffset
      verdictOk?
      verdictMessage
      verdictErrorOffset
      verdictTree
      fatalErrorKind
      fatalErrorOffset
      fatalErrorMessage]
  :i [(asl-syntax/core/tree :a tr)
      (asl-syntax/asl/lex :a lx)
      (asl-syntax/asl/paren :a prn)])

(schema FatalError
  (:f kind String)
  (:f offset Int64)
  (:f message String))

(schema IncrementalVerdict
  (:f ok Bool)
  (:f message String)
  (:f errorOffset (Option Int64))
  (:f tree (Option tr/Node)))

(schema IncrementalState
  (:f buf Bytes)
  (:f claim Bytes)
  (:f bufLen Int64)
  (:f tokenStart Int64)
  (:f resume Int64)
  (:f pendingError Bool)
  (:f stack (List prn/ParenFrame))
  (:f topKids (List tr/TreeElement))
  (:f fatalError (Option FatalError))
  (:f chunkCount Int64))

(schema ScanOutcome
  (:f tokenStart Int64)
  (:f resume Int64)
  (:f pendingError Bool)
  (:f stack (List prn/ParenFrame))
  (:f topKids (List tr/TreeElement))
  (:f fatalError (Option FatalError)))

fn fatalErrorKind fe: FatalError -> String
  fe.kind

fn fatalErrorOffset fe: FatalError -> Int64
  fe.offset

fn fatalErrorMessage fe: FatalError -> String
  fe.message

fn verdictOk? v: IncrementalVerdict -> Bool
  v.ok

fn verdictMessage v: IncrementalVerdict -> String
  v.message

fn verdictErrorOffset v: IncrementalVerdict -> (Option Int64)
  v.errorOffset

fn verdictTree v: IncrementalVerdict -> (Option tr/Node)
  v.tree

fn incrementalFatalError state: IncrementalState -> (Option FatalError)
  state.fatalError

fn incrementalHasFatalError? state: IncrementalState -> Bool
  (some? state.fatalError)

fn incrementalChunkCount state: IncrementalState -> Int64
  state.chunkCount

fn incrementalTotalBytes state: IncrementalState -> Int64
  state.bufLen

fn incrementalStableOffset state: IncrementalState -> Int64
  state.tokenStart

fn cellGetLoop cell: Bytes i: Int64 acc: Int64 -> Int64
  (if (< i 0)
    acc
    (cellGetLoop cell (- i 1) (+ (* acc 256) (bytesGet cell i))))

fn cellGet cell: Bytes -> Int64
  (cellGetLoop cell 7 0)

fn cellSetLoop! cell: Bytes i: Int64 v: Int64 -> Unit
  (if (>= i 8)
    ()
    (do
      (bytesSet cell i (mod v 256))
      (cellSetLoop! cell (+ i 1) (/ v 256))))

fn newCell! v: Int64 -> Bytes
  (let [(cell (bytesAlloc 8))]
    (cellSetLoop! cell 0 v)
    cell)

fn incrementalStart! -> IncrementalState
  (IncrementalState :buf (bytesAlloc 4096)
                    :claim (newCell! 0)
                    :bufLen 0
                    :tokenStart 0
                    :resume 0
                    :pendingError false
                    :stack (list)
                    :topKids (list)
                    :fatalError (none)
                    :chunkCount 0)

fn copySlice! src: Bytes srcIdx: Int64 dst: Bytes dstIdx: Int64 count: Int64 -> Unit
  (if (<= count 0)
    ()
    (do
      (bytesSet dst dstIdx (bytesGet src srcIdx))
      (copySlice! src (+ srcIdx 1) dst (+ dstIdx 1) (- count 1))))

fn appendChunk! buf: Bytes claim: Bytes bufLen: Int64 chunk: Bytes -> (Pair Bytes Bytes)
  (let [(chunkLen (bytesLength chunk))
        (newLen (+ bufLen chunkLen))]
    (if (and (= (cellGet claim) bufLen) (<= newLen (bytesLength buf)))
      (do
        (copySlice! chunk 0 buf bufLen chunkLen)
        (cellSetLoop! claim 0 newLen)
        (pair buf claim))
      (let [(newBuf (bytesAlloc (max 4096 (* newLen 2))))]
        (copySlice! buf 0 newBuf 0 bufLen)
        (copySlice! chunk 0 newBuf bufLen chunkLen)
        (pair newBuf (newCell! newLen)))))

fn invalidTokenError offset: Int64 -> FatalError
  (FatalError :kind "invalidToken"
              :offset offset
              :message (str "Invalid escape in string at offset " (stringFromInt64 offset)))

fn closerFatal tok: tr/Token stack: (List prn/ParenFrame) -> (Option FatalError)
  (mt (listHead stack)
    ((none)
     (some (FatalError :kind "unmatchedCloser"
                       :offset tok.start
                       :message (str "Closer with no open form at offset " (stringFromInt64 tok.start)))))
    ((some top)
     (if (prn/closerMatchesOpen? tok.kind top.kind)
       (none)
       (some (FatalError :kind "mismatchedCloser"
                         :offset tok.start
                         :message (str "Closer of wrong kind for innermost open bracket at offset " (stringFromInt64 tok.start)))))))

fn stringFatalOffset bs: Bytes len: Int64 start: Int64 -> Int64
  (let [(at (lx/stringErrorAt bs len (+ start 1)))]
    (if (>= at 0) at start))

fn tokenFatal bs: Bytes tok: tr/Token stack: (List prn/ParenFrame) -> (Option FatalError)
  (let [(k tok.kind)]
    (cond
      ((= k "error") (some (invalidTokenError (stringFatalOffset bs tok.end tok.start))))
      ((or (= k "rparen") (or (= k "rbracket") (= k "rbrace"))) (closerFatal tok stack))
      (else (none))))

fn pendingFatal bs: Bytes len: Int64 tok: tr/Token -> (Option FatalError)
  (if (= tok.kind "pendingError")
    (some (invalidTokenError (stringFatalOffset bs len tok.start)))
    (none))

fn scanLoop bs: Bytes len: Int64 start: Int64 resume: Int64 pendingError: Bool stack: (List prn/ParenFrame) topKids: (List tr/TreeElement) fatal: (Option FatalError) -> ScanOutcome
  (if (>= start len)
    (ScanOutcome :tokenStart start :resume start :pendingError false
                 :stack stack :topKids topKids :fatalError fatal)
    (let [(tok (lx/lexResume bs len start resume pendingError false))]
      (if (lx/isPendingToken tok)
        (ScanOutcome :tokenStart start :resume tok.end :pendingError (= tok.kind "pendingError")
                     :stack stack :topKids topKids
                     :fatalError (if (some? fatal) fatal (pendingFatal bs len tok)))
        (let [(fatal2 (if (some? fatal) fatal (tokenFatal bs tok stack)))
              (res (prn/parseStep stack topKids tok))]
          (scanLoop bs len tok.end tok.end false (pairFirst res) (pairSecond res) fatal2)))))

fn incrementalFeed! state: IncrementalState chunk: Bytes -> IncrementalState
  (let [(chunkLen (bytesLength chunk))
        (bufLen state.bufLen)
        (appended (if (= chunkLen 0)
                    (pair state.buf state.claim)
                    (appendChunk! state.buf state.claim bufLen chunk)))
        (bs (pairFirst appended))
        (len (+ bufLen chunkLen))
        (out (scanLoop bs len state.tokenStart state.resume state.pendingError
                       state.stack state.topKids state.fatalError))]
    (IncrementalState :buf bs
                      :claim (pairSecond appended)
                      :bufLen len
                      :tokenStart out.tokenStart
                      :resume out.resume
                      :pendingError out.pendingError
                      :stack out.stack
                      :topKids out.topKids
                      :fatalError out.fatalError
                      :chunkCount (+ state.chunkCount 1)))

fn incrementalFeedBytes! state: IncrementalState chunk: Bytes -> IncrementalState
  (incrementalFeed! state chunk)

fn incrementalFeedString! state: IncrementalState chunk: String -> IncrementalState
  (incrementalFeed! state (stringToBytes chunk))

fn flushLoop bs: Bytes len: Int64 start: Int64 resume: Int64 pendingError: Bool stack: (List prn/ParenFrame) topKids: (List tr/TreeElement) -> (List tr/TreeElement)
  (if (>= start len)
    (prn/unwindAllFrames stack topKids)
    (let [(tok (lx/lexResume bs len start resume pendingError true))
          (res (prn/parseStep stack topKids tok))]
      (flushLoop bs len tok.end tok.end false (pairFirst res) (pairSecond res))))

fn incrementalTree state: IncrementalState -> tr/Node
  (let [(len state.bufLen)
        (kids (flushLoop state.buf len state.tokenStart state.resume state.pendingError
                         state.stack state.topKids))]
    (tr/makeNode "asl" 0 len (listReverse kids)))

fn incrementalVerdict state: IncrementalState -> IncrementalVerdict
  (mt state.fatalError
    ((some fe)
     (IncrementalVerdict :ok false
                         :message fe.message
                         :errorOffset (some fe.offset)
                         :tree (none)))
    ((none)
     (IncrementalVerdict :ok true
                         :message "ok"
                         :errorOffset (none)
                         :tree (some (incrementalTree state)))))
