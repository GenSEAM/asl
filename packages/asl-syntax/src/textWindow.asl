(module asl-syntax/textWindow
  :x [LineIndex
      buildLineIndex!
      buildLineIndexDefault!
      lineIndexTotalLines
      lineIndexFileSize
      lineIndexLineOffset
      readIndexedRange!
      readIndexedRangeReceipt!
      readWindowedRange!
      readWindowedRangeReceipt!
      readWindowedRangeFileReceipt!
      findAnchorInStream!
      readWindowedAnchor!
      readWindowedAnchorReceipt!
      readWindowedAnchorFileReceipt!
      readWindowedTail!
      readWindowedTailReceipt!
      readWindowedTailFileReceipt!
      countLinesInFile!]
  :i [(asl-syntax/core/source :a src)
      (asl-syntax/core/outline :a out)
      (asl-syntax/text :a txt)
      (asl-syntax/core/bytesText :a btxt)])

(schema LineIndex
  (:f path String)
  (:f fileSize Int64)
  (:f totalLines Int64)
  (:f lineStarts I64Array))

fn lineIndexTotalLines index: LineIndex -> Int64
  index.totalLines

fn lineIndexFileSize index: LineIndex -> Int64
  index.fileSize

fn lineIndexLineOffset index: LineIndex lineNum: Int64 -> (Option Int64)
  (let [(total index.totalLines)]
    (if (or (< lineNum 1) (> lineNum total))
      (none)
      (some (i64ArrayGet index.lineStarts (- lineNum 1)))))

fn checkBinaryPrefix! path: String -> (Option String)
  (mt (fileReadRange path 0 8192)
    ((ok bs)
     (let [(kind (src/binaryKind bs))]
       (if (!= kind "") (some kind) (none))))
    ((err _) (none)))

fn listToChunk xs: (List Int64) len: Int64 -> I64Array
  (i64ArrayGenerate len (fn [(i Int64)] -> Int64 (optionOr (listGet xs i) 0)))

fn scanWindowLineStarts bs: Bytes winLen: Int64 idx: Int64 winOffset: Int64 fileSize: Int64 curChunk: (List Int64) curCount: Int64 chunks: (List I64Array) -> (Pair (List Int64) (Pair Int64 (List I64Array)))
  (if (>= idx winLen)
    (pair curChunk (pair curCount chunks))
    (let [(b (bytesGet bs idx))]
      (cond
        ((= b 10)
         (let [(nextOff (+ winOffset (+ idx 1)))]
           (if (< nextOff fileSize)
             (if (>= curCount 127)
               (let [(chunk (listToChunk (listReverse (cons nextOff curChunk)) (+ curCount 1)))]
                 (scanWindowLineStarts bs winLen (+ idx 1) winOffset fileSize (list) 0 (cons chunk chunks)))
               (scanWindowLineStarts bs winLen (+ idx 1) winOffset fileSize (cons nextOff curChunk) (+ curCount 1) chunks))
             (scanWindowLineStarts bs winLen (+ idx 1) winOffset fileSize curChunk curCount chunks))))
        ((= b 13)
         (let [(isCrlf (and (< (+ idx 1) winLen) (= (bytesGet bs (+ idx 1)) 10)))
               (step (if isCrlf 2 1))
               (nextOff (+ winOffset (+ idx step)))]
           (if (< nextOff fileSize)
             (if (>= curCount 127)
               (let [(chunk (listToChunk (listReverse (cons nextOff curChunk)) (+ curCount 1)))]
                 (scanWindowLineStarts bs winLen (+ idx step) winOffset fileSize (list) 0 (cons chunk chunks)))
               (scanWindowLineStarts bs winLen (+ idx step) winOffset fileSize (cons nextOff curChunk) (+ curCount 1) chunks))
             (scanWindowLineStarts bs winLen (+ idx step) winOffset fileSize curChunk curCount chunks))))
        (else
         (scanWindowLineStarts bs winLen (+ idx 1) winOffset fileSize curChunk curCount chunks)))))

fn buildLineIndexWindows! path: String offset: Int64 fileSize: Int64 winSize: Int64 curChunk: (List Int64) curCount: Int64 chunks: (List I64Array) -> (Result LineIndex String)
  (if (>= offset fileSize)
    (let [(finalChunks (if (> curCount 0)
                         (cons (listToChunk (listReverse curChunk) curCount) chunks)
                         chunks))
          (allStarts (i64ArrayConcat (listReverse finalChunks)))
          (lineCount (i64ArrayLen allStarts))]
      (ok (LineIndex :path path :fileSize fileSize :totalLines lineCount :lineStarts allStarts)))
    (let [(curLen (if (< (- fileSize offset) winSize) (- fileSize offset) winSize))
          (readRes (fileReadRange path offset curLen))]
      (mt readRes
        ((err e) (err e))
        ((ok bs)
         (let [(stepRes (scanWindowLineStarts bs (bytesLength bs) 0 offset fileSize curChunk curCount chunks))
               (newChunk (pairFirst stepRes))
               (countAndChunks (pairSecond stepRes))
               (newCount (pairFirst countAndChunks))
               (newChunks (pairSecond countAndChunks))]
           (buildLineIndexWindows! path (+ offset curLen) fileSize winSize newChunk newCount newChunks))))))

fn buildLineIndex! path: String windowSize: Int64 -> (Result LineIndex String)
  (mt (fileSize path)
    ((err e) (err e))
    ((ok sz)
     (if (= sz 0)
       (let [(emptyStarts (i64ArrayGenerate 0 (fn [(i Int64)] -> Int64 0)))]
         (ok (LineIndex :path path :fileSize 0 :totalLines 0 :lineStarts emptyStarts)))
       (let [(effectiveWin (if (> windowSize 0) windowSize 65536))
             (initialChunk (list 0))
             (initialCount 1)]
         (buildLineIndexWindows! path 0 sz effectiveWin initialChunk initialCount (list))))))

fn buildLineIndexDefault! path: String -> (Result LineIndex String)
  (buildLineIndex! path 65536)

fn countWindowNl bs: Bytes len: Int64 idx: Int64 cnt: Int64 -> Int64
  (if (>= idx len)
    cnt
    (let [(b (bytesGet bs idx))]
      (countWindowNl bs len (+ idx 1) (if (= b 10) (+ cnt 1) cnt))))

fn countLinesWindows! path: String offset: Int64 fileSize: Int64 winSize: Int64 totalNl: Int64 lastByte: Int64 -> (Result Int64 String)
  (if (>= offset fileSize)
    (let [(extra (if (or (= lastByte 10) (= lastByte 13)) 0 1))]
      (ok (+ totalNl extra)))
    (let [(curLen (if (< (- fileSize offset) winSize) (- fileSize offset) winSize))
          (readRes (fileReadRange path offset curLen))]
      (mt readRes
        ((err e) (err e))
        ((ok bs)
         (let [(blen (bytesLength bs))
               (nl (countWindowNl bs blen 0 0))
               (lb (if (> blen 0) (bytesGet bs (- blen 1)) lastByte))]
           (countLinesWindows! path (+ offset curLen) fileSize winSize (+ totalNl nl) lb))))))

fn countLinesInFile! path: String windowSize: Int64 -> (Result Int64 String)
  (mt (fileSize path)
    ((err e) (err e))
    ((ok sz)
     (if (= sz 0)
       (ok 0)
       (let [(win (if (> windowSize 0) windowSize 65536))]
         (countLinesWindows! path 0 sz win 0 0)))))


fn readIndexedRange! index: LineIndex startLine: Int64 endLine: Int64 limit: Int64 maxBytes: Int64 -> (Result String String)
  (let [(totalLines index.totalLines)
        (lo (if (> startLine 0) startLine 1))
        (hi (if (> endLine 0) endLine totalLines))]
    (if (or (> lo totalLines) (< hi lo))
      (err (str "range out of bounds: " (stringFromInt64 lo) " to " (stringFromInt64 hi)))
      (let [(effectiveHi (if (> hi totalLines) totalLines hi))
            (startByte (i64ArrayGet index.lineStarts (- lo 1)))
            (endByte (if (< effectiveHi totalLines)
                       (i64ArrayGet index.lineStarts effectiveHi)
                       index.fileSize))
            (byteLen (- endByte startByte))
            (readRes (fileReadRange index.path startByte byteLen))]
        (mt readRes
          ((err e) (err e))
          ((ok bs)
           (let [(rawText (btxt/bytesToString bs))
                 (decoded (txt/decodeUtf8Replace rawText bs))
                 (text (txt/normalizeNewlines decoded))
                 (lines (txt/splitLinesKeepEnds text (stringToBytes text) (stringLength text) 0 0 (list)))
                 (sliceCount (+ (- effectiveHi lo) 1))
                 (selectedLines (listTake lines sliceCount))
                 (cap (if (> limit 0) limit 200))
                 (byteCap (if (>= maxBytes 256) maxBytes 12000))
                 (boundRes (txt/takeLinesBounded selectedLines cap byteCap 0 0 (list)))
                 (keptLines (pairSecond boundRes))]
             (ok (stringJoin keptLines ""))))))))

fn readIndexedRangeReceipt! index: LineIndex startLine: Int64 endLine: Int64 limit: Int64 maxBytes: Int64 -> String
  (let [(rel (txt/cleanPath index.path))
        (totalLines index.totalLines)
        (lo (if (> startLine 0) startLine 1))
        (hi (if (> endLine 0) endLine totalLines))]
    (if (or (> lo totalLines) (< hi lo))
      (str "(:read :status :rejected :error ERR_RANGE_OUT_OF_BOUNDS :file \"" (out/escapeAsnValue rel)
           "\" :start " (stringFromInt64 lo)
           " :end " (stringFromInt64 hi)
           " :lines " (stringFromInt64 totalLines)
           " :see \"(:help :op read)\")")
      (let [(effectiveHi (if (> hi totalLines) totalLines hi))
            (startByte (i64ArrayGet index.lineStarts (- lo 1)))
            (endByte (if (< effectiveHi totalLines)
                       (i64ArrayGet index.lineStarts effectiveHi)
                       index.fileSize))
            (byteLen (- endByte startByte))
            (readRes (fileReadRange index.path startByte byteLen))]
        (mt readRes
          ((err e) (str "(:read :status :rejected :error ERR_IO :file \"" (out/escapeAsnValue rel) "\" :message \"" (out/escapeAsnValue e) "\")"))
          ((ok bs)
           (let [(rawText (btxt/bytesToString bs))
                 (decoded (txt/decodeUtf8Replace rawText bs))
                 (text (txt/normalizeNewlines decoded))
                 (lines (txt/splitLinesKeepEnds text (stringToBytes text) (stringLength text) 0 0 (list)))
                 (sliceCount (+ (- effectiveHi lo) 1))
                 (selectedLines (listTake lines sliceCount))
                 (cap (if (> limit 0) limit 200))
                 (byteCap (if (>= maxBytes 256) maxBytes 12000))
                 (boundRes (txt/takeLinesBounded selectedLines cap byteCap 0 0 (list)))
                 (keep (pairFirst boundRes))
                 (keptLines (pairSecond boundRes))
                 (content (stringJoin keptLines ""))
                 (trunc (if (< keep sliceCount)
                          (str " :truncated true :limit " (stringFromInt64 cap)
                               " :maxBytes " (stringFromInt64 byteCap)
                               " :totalLines " (stringFromInt64 sliceCount)
                               " :more (:start " (stringFromInt64 (+ lo keep))
                               " :end " (stringFromInt64 (+ (- (+ lo sliceCount) 1) 0)) ")")
                          ""))
                 (sliceInfo (str " :start " (stringFromInt64 lo) " :end " (stringFromInt64 effectiveHi)))]
             (str "(:read :file \"" (out/escapeAsnValue rel) "\"" sliceInfo trunc
                  " :content \"" (out/escapeAsnValue content) "\")")))))))

fn readWindowedRange! file: String startLine: Int64 endLine: Int64 limit: Int64 maxBytes: Int64 windowSize: Int64 -> (Result String String)
  (mt (buildLineIndex! file windowSize)
    ((err e) (err e))
    ((ok idx)
     (readIndexedRange! idx startLine endLine limit maxBytes)))

fn readWindowedRangeReceipt! file: String startLine: Int64 endLine: Int64 limit: Int64 maxBytes: Int64 windowSize: Int64 -> (Result String String)
  (mt (buildLineIndex! file windowSize)
    ((err e) (err e))
    ((ok idx)
     (ok (readIndexedRangeReceipt! idx startLine endLine limit maxBytes))))

fn readWindowedRangeFileReceipt! file: String startLine: Int64 endLine: Int64 limit: Int64 maxBytes: Int64 -> (Result String String)
  (mt (fileSize file)
    ((err e) (err e))
    ((ok sz)
     (mt (checkBinaryPrefix! file)
       ((some kind)
        (ok (str "(:read :status :rejected :error ERR_BINARY :file \"" (out/escapeAsnValue (txt/cleanPath file))
                 "\" :bytes " (stringFromInt64 sz)
                 " :kind \"" kind
                 "\" :hint \"binary files are never returned as text; inspect them with a native tool such as file, otool or xxd\" :see \"(:help :op read)\")")))
       ((none)
        (readWindowedRangeReceipt! file startLine endLine limit maxBytes 65536)))))

fn scanBytesSub matchIdx: Int64 pat: Bytes patLen: Int64 src: Bytes srcLen: Int64 sIdx: Int64 -> Bool
  (if (>= matchIdx patLen)
    true
    (if (>= (+ sIdx matchIdx) srcLen)
      false
      (if (= (bytesGet pat matchIdx) (bytesGet src (+ sIdx matchIdx)))
        (scanBytesSub (+ matchIdx 1) pat patLen src srcLen sIdx)
        false)))

fn findAnchorInWindow bs: Bytes winLen: Int64 sIdx: Int64 pat: Bytes patLen: Int64 winOffset: Int64 acc: (List Int64) -> (List Int64)
  (if (> (+ sIdx patLen) winLen)
    (listReverse acc)
    (if (scanBytesSub 0 pat patLen bs winLen sIdx)
      (findAnchorInWindow bs winLen (+ sIdx 1) pat patLen winOffset (cons (+ winOffset sIdx) acc))
      (findAnchorInWindow bs winLen (+ sIdx 1) pat patLen winOffset acc)))

fn searchAnchorWindows! path: String offset: Int64 fileSize: Int64 winSize: Int64 pat: Bytes patLen: Int64 acc: (List Int64) -> (Result (List Int64) String)
  (if (>= offset fileSize)
    (ok (listReverse acc))
    (let [(curLen (if (< (- fileSize offset) winSize) (- fileSize offset) winSize))
          (readRes (fileReadRange path offset curLen))]
      (mt readRes
        ((err e) (err e))
        ((ok bs)
         (let [(matches (findAnchorInWindow bs (bytesLength bs) 0 pat patLen offset (list)))
               (nextOffset (if (>= (+ offset curLen) fileSize)
                             fileSize
                             (+ (- (+ offset curLen) patLen) 1)))
               (newAcc (listAppend (listReverse matches) acc))]
           (searchAnchorWindows! path nextOffset fileSize winSize pat patLen newAcc))))))

fn findAnchorInStream! file: String anchor: String windowSize: Int64 -> (Result (List Int64) String)
  (let [(pat (stringToBytes anchor))
        (patLen (bytesLength pat))]
    (if (= patLen 0)
      (ok (list))
      (mt (fileSize file)
        ((err e) (err e))
        ((ok sz)
         (let [(win (if (> windowSize (* patLen 2)) windowSize (* patLen 4)))]
           (searchAnchorWindows! file 0 sz win pat patLen (list)))))))

fn findPrecedingNewline! file: String targetOffset: Int64 -> Int64
  (let [(scanLen (if (> targetOffset 4096) 4096 targetOffset))
        (scanStart (- targetOffset scanLen))]
    (if (<= scanLen 0)
      0
      (mt (fileReadRange file scanStart scanLen)
        ((err _) 0)
        ((ok bs)
         (let [(p (txt/rfindNewline bs (- scanLen 1)))]
           (if (< p 0)
             (if (> scanStart 0) (findPrecedingNewline! file scanStart) 0)
             (+ (+ scanStart p) 1)))))))

fn readWindowedAnchor! file: String anchor: String occurrence: Int64 limit: Int64 -> (Result String String)
  (mt (fileSize file)
    ((err e) (err e))
    ((ok sz)
     (mt (findAnchorInStream! file anchor 65536)
    ((err e) (err e))
    ((ok matches)
     (let [(cnt (listLength matches))]
       (cond
         ((= cnt 0)
          (err (str "anchor not found: " anchor)))
         ((and (<= occurrence 0) (> cnt 1))
          (err (str "ambiguous anchor: " (stringFromInt64 cnt) " occurrences of " anchor)))
         ((and (> occurrence 0) (> occurrence cnt))
          (err (str "occurrence " (stringFromInt64 occurrence) " out of bounds")))
         (else
          (let [(want (if (> occurrence 0) occurrence 1))
                (idxAnc (optionOr (listGet matches (- want 1)) 0))
                (startPos (findPrecedingNewline! file idxAnc))
                (lim (if (> limit 0) limit 1000))
                (readRawLen (let [(avail (- sz startPos))] (if (< avail (* lim 2)) avail (* lim 2))))
                (readRes (fileReadRange file startPos readRawLen))]
            (mt readRes
              ((err e) (err e))
              ((ok bs)
               (let [(rawText (btxt/bytesToString bs))
                     (decoded (txt/decodeUtf8Replace rawText bs))
                     (norm (txt/normalizeNewlines decoded))
                     (content (if (> (stringLength norm) lim) (optionOr (stringSlice norm 0 lim) norm) norm))]
                 (ok content))))))))))))

fn readWindowedAnchorReceipt! file: String sz: Int64 anchor: String occurrence: Int64 limit: Int64 matches: (List Int64) -> (Result String String)
  (let [(rel (txt/cleanPath file))
        (escAnchor (out/escapeAsnValue anchor))
        (cnt (listLength matches))]
    (cond
      ((= cnt 0)
       (ok (str "(:read :status :rejected :error ERR_ANCHOR_NOT_FOUND :file \"" (out/escapeAsnValue rel)
                "\" :anchor \"" escAnchor "\" :see \"(:help :op read)\")")))
      ((and (<= occurrence 0) (> cnt 1))
       (ok (str "(:read :status :rejected :error ERR_AMBIGUOUS_ANCHOR :file \"" (out/escapeAsnValue rel)
                "\" :anchor \"" escAnchor "\" :count " (stringFromInt64 cnt)
                " :see \"(:help :op read)\")")))
      ((and (> occurrence 0) (> occurrence cnt))
       (ok (str "(:read :status :rejected :error ERR_ANCHOR_NOT_FOUND :file \"" (out/escapeAsnValue rel)
                "\" :anchor \"" escAnchor "\" :see \"(:help :op read)\")")))
      (else
       (let [(want (if (> occurrence 0) occurrence 1))
             (idxAnc (optionOr (listGet matches (- want 1)) 0))
             (startPos (findPrecedingNewline! file idxAnc))
             (lim (if (> limit 0) limit 1000))
             (readRawLen (let [(avail (- sz startPos))] (if (< avail (* lim 2)) avail (* lim 2))))
             (readRes (fileReadRange file startPos readRawLen))]
         (mt readRes
           ((err e) (err e))
           ((ok bs)
            (let [(rawText (btxt/bytesToString bs))
                  (decoded (txt/decodeUtf8Replace rawText bs))
                  (norm (txt/normalizeNewlines decoded))
                  (content (if (> (stringLength norm) lim) (optionOr (stringSlice norm 0 lim) norm) norm))
                  (sliceInfo (str " :anchor \"" escAnchor "\" :occurrence " (stringFromInt64 want)))]
              (ok (str "(:read :file \"" (out/escapeAsnValue rel) "\"" sliceInfo
                       " :content \"" (out/escapeAsnValue content) "\")")))))))))

fn readWindowedAnchorFileReceipt! file: String anchor: String occurrence: Int64 limit: Int64 -> (Result String String)
  (mt (fileSize file)
    ((err e) (err e))
    ((ok sz)
     (mt (checkBinaryPrefix! file)
       ((some kind)
        (ok (str "(:read :status :rejected :error ERR_BINARY :file \"" (out/escapeAsnValue (txt/cleanPath file))
                 "\" :bytes " (stringFromInt64 sz)
                 " :kind \"" kind
                 "\" :hint \"binary files are never returned as text; inspect them with a native tool such as file, otool or xxd\" :see \"(:help :op read)\")")))
       ((none)
        (mt (findAnchorInStream! file anchor 65536)
          ((err e) (err e))
          ((ok matches)
           (readWindowedAnchorReceipt! file sz anchor occurrence limit matches)))))))

fn scanTailNewlines bs: Bytes idx: Int64 targetLines: Int64 foundLines: Int64 -> (Pair Int64 Int64)
  (if (< idx 0)
    (pair -1 foundLines)
    (if (= (bytesGet bs idx) 10)
      (let [(newFound (+ foundLines 1))]
        (if (>= newFound targetLines)
          (pair idx newFound)
          (scanTailNewlines bs (- idx 1) targetLines newFound)))
      (scanTailNewlines bs (- idx 1) targetLines foundLines)))

fn scanTailWindowsBackwards! file: String curEnd: Int64 winSize: Int64 targetLines: Int64 foundLines: Int64 -> (Result Int64 String)
  (if (<= curEnd 0)
    (ok 0)
    (let [(curStart (if (> curEnd winSize) (- curEnd winSize) 0))
          (curLen (- curEnd curStart))
          (readRes (fileReadRange file curStart curLen))]
      (mt readRes
        ((err e) (err e))
        ((ok bs)
         (let [(blen (bytesLength bs))
               (lastIdx (- blen 1))
               (stepRes (scanTailNewlines bs lastIdx targetLines foundLines))
               (matchIdx (pairFirst stepRes))
               (newFound (pairSecond stepRes))]
           (if (>= matchIdx 0)
             (ok (+ (+ curStart matchIdx) 1))
             (if (<= curStart 0)
               (ok 0)
               (scanTailWindowsBackwards! file curStart winSize targetLines newFound))))))))

fn readWindowedTail! file: String lineCount: Int64 windowSize: Int64 -> (Result String String)
  (if (<= lineCount 0)
    (ok "")
    (mt (fileSize file)
      ((err e) (err e))
      ((ok sz)
       (if (= sz 0)
         (ok "")
         (let [(win (if (> windowSize 0) windowSize 65536))
               (tailRes (scanTailWindowsBackwards! file sz win (+ lineCount 1) 0))]
           (mt tailRes
             ((err e) (err e))
             ((ok tailStart)
              (let [(readLen (- sz tailStart))
                    (readRes (fileReadRange file tailStart readLen))]
                (mt readRes
                  ((err e) (err e))
                  ((ok bs)
                   (let [(rawText (btxt/bytesToString bs))
                         (decoded (txt/decodeUtf8Replace rawText bs))
                         (text (txt/normalizeNewlines decoded))]
                     (ok text))))))))))))

fn readWindowedTailReceipt! file: String lineCount: Int64 -> (Result String String)
  (mt (readWindowedTail! file lineCount 65536)
    ((err e) (err e))
    ((ok content)
     (let [(rel (txt/cleanPath file))]
       (ok (str "(:tail :file \"" (out/escapeAsnValue rel) "\" :lines " (stringFromInt64 lineCount)
                " :content \"" (out/escapeAsnValue content) "\")")))))

fn readWindowedTailFileReceipt! file: String lineCount: Int64 -> (Result String String)
  (mt (fileSize file)
    ((err e) (err e))
    ((ok sz)
     (mt (checkBinaryPrefix! file)
       ((some kind)
        (ok (str "(:tail :status :rejected :error ERR_BINARY :file \"" (out/escapeAsnValue (txt/cleanPath file))
                 "\" :bytes " (stringFromInt64 sz)
                 " :kind \"" kind
                 "\" :hint \"binary files are never returned as text; inspect them with a native tool such as file, otool or xxd\" :see \"(:help :op read)\")")))
       ((none)
        (readWindowedTailReceipt! file lineCount)))))

