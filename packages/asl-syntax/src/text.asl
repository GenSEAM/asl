(module asl-syntax/text
  :x [HeadingInfo
      TextBlock
      LineSpan
      headingName
      headingKind
      headingLevel
      headingLine
      headingStart
      headingEnd
      blockKind
      blockStart
      blockEnd
      blockStartLine
      blockEndLine
      cleanPath
      normalizeNewlines
      decodeUtf8Replace
      loadTextFile!
      splitLinesKeepEnds
      takeLinesBounded
      rfindNewline
      readRange
      readRangeReceipt
      readRangeFileReceipt!
      readAnchor
      readAnchorReceipt
      readAnchorFileReceipt!
      isSetextUnderline?
      isAllCapsHeading?
      isSectionHeading?
      isNumberedHeading?
      isKeyAtCol0?
      detectHeadings
      textSymbols
      textOutlineItems
      textOutlineReceipt
      parseText
      parseTextSource
      textBlocks
      textParagraphs
      textApplyAnchorEdit
      textApplyAnchorEditWithTree]
  :i [(asl-syntax/core/source :a src)
      (asl-syntax/core/tree :a tr)
      (asl-syntax/core/print :a pr)
      (asl-syntax/core/symbols :a sym)
      (asl-syntax/core/outline :a out)])

(schema HeadingInfo
  (:f name String)
  (:f kind String)
  (:f level Int64)
  (:f line Int64)
  (:f start Int64)
  (:f end Int64))

(schema TextBlock
  (:f kind String)
  (:f start Int64)
  (:f end Int64)
  (:f startLine Int64)
  (:f endLine Int64))

(schema LineSpan
  (:f start Int64)
  (:f end Int64)
  (:f nextStart Int64)
  (:f lineNum Int64)
  (:f blank? Bool))

fn headingName h: HeadingInfo -> String
  h.name

fn headingKind h: HeadingInfo -> String
  h.kind

fn headingLevel h: HeadingInfo -> Int64
  h.level

fn headingLine h: HeadingInfo -> Int64
  h.line

fn headingStart h: HeadingInfo -> Int64
  h.start

fn headingEnd h: HeadingInfo -> Int64
  h.end

fn blockKind b: TextBlock -> String
  b.kind

fn blockStart b: TextBlock -> Int64
  b.start

fn blockEnd b: TextBlock -> Int64
  b.end

fn blockStartLine b: TextBlock -> Int64
  b.startLine

fn blockEndLine b: TextBlock -> Int64
  b.endLine

fn normalizeNewlines text: String -> String
  (let [(t1 (stringReplace text "\r\n" "\n"))]
    (stringReplace t1 "\r" "\n"))

fn validCharLen bs: Bytes len: Int64 pos: Int64 -> Int64
  (if (>= pos len)
    0
    (let [(b0 (bytesGet bs pos))]
      (cond
        ((< b0 128) 1)
        ((and (>= b0 194) (<= b0 223))
         (if (and (< (+ pos 1) len)
                  (let [(b1 (bytesGet bs (+ pos 1)))]
                    (and (>= b1 128) (<= b1 191))))
           2
           0))
        ((and (>= b0 224) (<= b0 239))
         (if (and (< (+ pos 2) len)
                  (let [(b1 (bytesGet bs (+ pos 1)))
                        (b2 (bytesGet bs (+ pos 2)))]
                    (and (>= b1 128) (<= b1 191)
                         (>= b2 128) (<= b2 191)
                         (cond
                           ((= b0 224) (>= b1 160))
                           ((= b0 237) (<= b1 159))
                           (else true)))))
           3
           0))
        ((and (>= b0 240) (<= b0 244))
         (if (and (< (+ pos 3) len)
                  (let [(b1 (bytesGet bs (+ pos 1)))
                        (b2 (bytesGet bs (+ pos 2)))
                        (b3 (bytesGet bs (+ pos 3)))]
                    (and (>= b1 128) (<= b1 191)
                         (>= b2 128) (<= b2 191)
                         (>= b3 128) (<= b3 191)
                         (cond
                           ((= b0 240) (>= b1 144))
                           ((= b0 244) (<= b1 143))
                           (else true)))))
           4
           0))
        (else 0))))

fn decodeUtf8Loop rawText: String bs: Bytes len: Int64 pos: Int64 start: Int64 acc: (List String) -> (List String)
  (if (>= pos len)
    (if (> pos start)
      (let [(slice (optionOr (stringSlice rawText start pos) ""))]
        (listReverse (cons slice acc)))
      (listReverse acc))
    (let [(k (validCharLen bs len pos))]
      (if (> k 0)
        (decodeUtf8Loop rawText bs len (+ pos k) start acc)
        (let [(prefix (if (> pos start)
                        (cons (optionOr (stringSlice rawText start pos) "") acc)
                        acc))]
          (decodeUtf8Loop rawText bs len (+ pos 1) (+ pos 1) (cons "\uFFFD" prefix))))))

fn decodeUtf8Replace rawText: String bs: Bytes -> String
  (let [(len (bytesLength bs))]
    (if (= len 0)
      ""
      (stringJoin (decodeUtf8Loop rawText bs len 0 0 (list)) "")))

fn loadTextFile! file: String -> (Result String String)
  (mt (fileReadBytes file)
    ((err e) (err e))
    ((ok bs)
     (mt (fileReadString file)
       ((err e) (err e))
       ((ok rawText)
        (let [(decoded (decodeUtf8Replace rawText bs))]
          (ok (normalizeNewlines decoded)))))))

fn cleanPath p: String -> String
  (if (stringStartsWith? p "./")
    (optionOr (stringSlice p 2 (stringLength p)) p)
    p)

fn splitLinesLoop text: String bs: Bytes len: Int64 cur: Int64 start: Int64 acc: (List String) -> (List String)
  (if (>= cur len)
    (if (< start len)
      (let [(lastLine (optionOr (stringSlice text start len) ""))]
        (listReverse (cons lastLine acc)))
      (listReverse acc))
    (let [(b (bytesGet bs cur))]
      (cond
        ((= b 10)
         (let [(nextStart (+ cur 1))
               (line (optionOr (stringSlice text start nextStart) ""))]
           (splitLinesLoop text bs len nextStart nextStart (cons line acc))))
        ((= b 13)
         (let [(isCrlf (and (< (+ cur 1) len) (= (bytesGet bs (+ cur 1)) 10)))
               (nextStart (if isCrlf (+ cur 2) (+ cur 1)))
               (line (optionOr (stringSlice text start nextStart) ""))]
           (splitLinesLoop text bs len nextStart nextStart (cons line acc))))
        (else
         (splitLinesLoop text bs len (+ cur 1) start acc)))))

fn splitLinesKeepEnds text: String bs: Bytes len: Int64 cur: Int64 start: Int64 acc: (List String) -> (List String)
  (if (= len 0)
    (list)
    (splitLinesLoop text bs len cur start acc))

fn takeLinesBounded lines: (List String) cap: Int64 byteCap: Int64 keep: Int64 used: Int64 acc: (List String) -> (Pair Int64 (List String))
  (if (listEmpty? lines)
    (pair keep (listReverse acc))
    (if (>= keep cap)
      (pair keep (listReverse acc))
      (let [(line (optionOr (listHead lines) ""))
            (lineLen (stringLength line))
            (newUsed (+ used lineLen))]
        (if (and (> keep 0) (> newUsed byteCap))
          (pair keep (listReverse acc))
          (takeLinesBounded (optionOr (listTail lines) (list)) cap byteCap (+ keep 1) newUsed (cons line acc))))))

fn rfindNewline bs: Bytes idx: Int64 -> Int64
  (if (< idx 0)
    -1
    (if (= (bytesGet bs idx) 10)
      idx
      (rfindNewline bs (- idx 1))))

fn readRange text: String startLine: Int64 endLine: Int64 limit: Int64 maxBytes: Int64 -> (Result String String)
  (let [(lines (splitLinesKeepEnds text (stringToBytes text) (stringLength text) 0 0 (list)))
        (totalLines (listLength lines))
        (lo (if (> startLine 0) startLine 1))
        (hi (if (> endLine 0) endLine totalLines))]
    (if (or (> lo totalLines) (< hi lo))
      (err (str "range out of bounds: " (stringFromInt64 lo) " to " (stringFromInt64 hi)))
      (let [(effectiveHi (if (> hi totalLines) totalLines hi))
            (sliceCount (+ (- effectiveHi lo) 1))
            (selectedLines (listTake (listDrop lines (- lo 1)) sliceCount))
            (cap (if (> limit 0) limit 200))
            (byteCap (if (>= maxBytes 256) maxBytes 12000))
            (boundRes (takeLinesBounded selectedLines cap byteCap 0 0 (list)))
            (keptLines (pairSecond boundRes))]
        (ok (stringJoin keptLines "")))))

fn readRangeReceipt file: String text: String startLine: Int64 endLine: Int64 limit: Int64 maxBytes: Int64 -> String
  (let [(rel (cleanPath file))
        (lines (splitLinesKeepEnds text (stringToBytes text) (stringLength text) 0 0 (list)))
        (totalLines (listLength lines))
        (lo (if (> startLine 0) startLine 1))
        (hi (if (> endLine 0) endLine totalLines))]
    (if (or (> lo totalLines) (< hi lo))
      (str "(:read :status :rejected :error ERR_RANGE_OUT_OF_BOUNDS :file \"" (out/escapeAsnValue rel)
           "\" :start " (stringFromInt64 lo)
           " :end " (stringFromInt64 hi)
           " :lines " (stringFromInt64 totalLines)
           " :see \"(:help :op read)\")")
      (let [(effectiveHi (if (> hi totalLines) totalLines hi))
            (sliceCount (+ (- effectiveHi lo) 1))
            (selectedLines (listTake (listDrop lines (- lo 1)) sliceCount))
            (cap (if (> limit 0) limit 200))
            (byteCap (if (>= maxBytes 256) maxBytes 12000))
            (boundRes (takeLinesBounded selectedLines cap byteCap 0 0 (list)))
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
             " :content \"" (out/escapeAsnValue content) "\")"))))

fn readRangeFileReceipt! file: String startLine: Int64 endLine: Int64 limit: Int64 maxBytes: Int64 -> (Result String String)
  (mt (fileReadBytes file)
    ((err e) (err e))
    ((ok bs)
     (let [(kind (src/binaryKind bs))]
       (if (!= kind "")
         (ok (str "(:read :status :rejected :error ERR_BINARY :file \"" (out/escapeAsnValue (cleanPath file))
                  "\" :bytes " (stringFromInt64 (bytesLength bs))
                  " :kind \"" kind
                  "\" :hint \"binary files are never returned as text; inspect them with a native tool such as file, otool or xxd\" :see \"(:help :op read)\")"))
         (mt (loadTextFile! file)
           ((err e) (err e))
           ((ok text)
            (ok (readRangeReceipt file text startLine endLine limit maxBytes))))))))

fn readAnchor text: String anchor: String occurrence: Int64 limit: Int64 -> (Result String String)
  (let [(matches (sym/anchorOccurrences text anchor))
        (cnt (listLength matches))]
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
             (bs (stringToBytes text))
             (startPos (let [(p (rfindNewline bs (- idxAnc 1)))] (if (< p 0) 0 (+ p 1))))
             (lim (if (> limit 0) limit 1000))
             (totalLen (stringLength text))
             (endPos (let [(p (+ startPos lim))] (if (> p totalLen) totalLen p)))]
         (ok (optionOr (stringSlice text startPos endPos) ""))))))

fn readAnchorReceipt file: String text: String anchor: String occurrence: Int64 limit: Int64 -> String
  (let [(rel (cleanPath file))
        (escAnchor (out/escapeAsnValue anchor))
        (matches (sym/anchorOccurrences text anchor))
        (cnt (listLength matches))]
    (cond
      ((= cnt 0)
       (str "(:read :status :rejected :error ERR_ANCHOR_NOT_FOUND :file \"" (out/escapeAsnValue rel)
            "\" :anchor \"" escAnchor "\" :see \"(:help :op read)\")"))
      ((and (<= occurrence 0) (> cnt 1))
       (str "(:read :status :rejected :error ERR_AMBIGUOUS_ANCHOR :file \"" (out/escapeAsnValue rel)
            "\" :anchor \"" escAnchor "\" :count " (stringFromInt64 cnt)
            " :see \"(:help :op read)\")"))
      ((and (> occurrence 0) (> occurrence cnt))
       (str "(:read :status :rejected :error ERR_ANCHOR_NOT_FOUND :file \"" (out/escapeAsnValue rel)
            "\" :anchor \"" escAnchor "\" :see \"(:help :op read)\")"))
      (else
       (let [(want (if (> occurrence 0) occurrence 1))
             (idxAnc (optionOr (listGet matches (- want 1)) 0))
             (bs (stringToBytes text))
             (startPos (let [(p (rfindNewline bs (- idxAnc 1)))] (if (< p 0) 0 (+ p 1))))
             (lim (if (> limit 0) limit 1000))
             (totalLen (stringLength text))
             (endPos (let [(p (+ startPos lim))] (if (> p totalLen) totalLen p)))
             (content (optionOr (stringSlice text startPos endPos) ""))
             (sliceInfo (str " :anchor \"" escAnchor "\" :occurrence " (stringFromInt64 want)))]
         (str "(:read :file \"" (out/escapeAsnValue rel) "\"" sliceInfo
              " :content \"" (out/escapeAsnValue content) "\")")))))

fn readAnchorFileReceipt! file: String anchor: String occurrence: Int64 limit: Int64 -> (Result String String)
  (mt (fileReadBytes file)
    ((err e) (err e))
    ((ok bs)
     (let [(kind (src/binaryKind bs))]
       (if (!= kind "")
         (ok (str "(:read :status :rejected :error ERR_BINARY :file \"" (out/escapeAsnValue (cleanPath file))
                  "\" :bytes " (stringFromInt64 (bytesLength bs))
                  " :kind \"" kind
                  "\" :hint \"binary files are never returned as text; inspect them with a native tool such as file, otool or xxd\" :see \"(:help :op read)\")"))
         (mt (loadTextFile! file)
           ((err e) (err e))
           ((ok text)
            (ok (readAnchorReceipt file text anchor occurrence limit))))))))

fn allCharsEqual bs: Bytes len: Int64 idx: Int64 target: Int64 -> Bool
  (if (>= idx len)
    true
    (if (= (bytesGet bs idx) target)
      (allCharsEqual bs len (+ idx 1) target)
      false))

fn isSetextUnderline? line: String -> (Option Int64)
  (let [(lineTrim (stringTrim line))
        (len (stringLength lineTrim))]
    (if (< len 2)
      (none)
      (let [(bs (stringToBytes lineTrim))]
        (cond
          ((allCharsEqual bs len 0 61) (some 1))
          ((allCharsEqual bs len 0 45) (some 2))
          (else (none))))))

fn checkAllCapsChars bs: Bytes len: Int64 idx: Int64 upperCount: Int64 -> (Option Int64)
  (if (>= idx len)
    (if (>= upperCount 2) (some upperCount) (none))
    (let [(b (bytesGet bs idx))]
      (if (and (>= b 97) (<= b 122))
        (none)
        (if (and (>= b 65) (<= b 90))
          (checkAllCapsChars bs len (+ idx 1) (+ upperCount 1))
          (checkAllCapsChars bs len (+ idx 1) upperCount)))))

fn isAllCapsHeading? line: String -> Bool
  (let [(lineTrim (stringTrim line))
        (len (stringLength lineTrim))]
    (if (< len 2)
      false
      (let [(bs (stringToBytes lineTrim))]
        (mt (checkAllCapsChars bs len 0 0)
          ((some _) true)
          ((none) false)))))

fn isSectionHeading? line: String -> (Option String)
  (let [(lineTrim (stringTrim line))
        (len (stringLength lineTrim))]
    (if (and (>= len 3) (stringStartsWith? lineTrim "[") (stringEndsWith? lineTrim "]"))
      (stringSlice lineTrim 1 (- len 1))
      (none)))

fn scanNumberedPrefix bs: Bytes len: Int64 idx: Int64 dotCount: Int64 -> (Option (Pair Int64 Int64))
  (if (>= idx len)
    (none)
    (let [(b (bytesGet bs idx))]
      (cond
        ((and (>= b 48) (<= b 57))
         (scanNumberedPrefix bs len (+ idx 1) dotCount))
        ((= b 46)
         (if (and (< (+ idx 1) len) (= (bytesGet bs (+ idx 1)) 32))
           (some (pair (+ dotCount 1) (+ idx 2)))
           (scanNumberedPrefix bs len (+ idx 1) (+ dotCount 1))))
        ((= b 41)
         (if (and (< (+ idx 1) len) (= (bytesGet bs (+ idx 1)) 32))
           (some (pair (+ dotCount 1) (+ idx 2)))
           (none)))
        ((and (= b 32) (> dotCount 0))
         (some (pair (+ dotCount 1) (+ idx 1))))
        (else (none)))))

fn isNumberedHeading? line: String -> (Option (Pair Int64 String))
  (let [(lineTrim (stringTrim line))
        (len (stringLength lineTrim))]
    (if (< len 3)
      (none)
      (let [(bs (stringToBytes lineTrim))]
        (if (and (>= (bytesGet bs 0) 48) (<= (bytesGet bs 0) 57))
          (mt (scanNumberedPrefix bs len 0 0)
            ((some p) (some (pair (pairFirst p) lineTrim)))
            ((none) (none)))
          (none)))))

fn scanKeyCol0 bs: Bytes len: Int64 idx: Int64 -> (Option Int64)
  (if (>= idx len)
    (none)
    (let [(b (bytesGet bs idx))]
      (cond
        ((or (and (>= b 65) (<= b 90))
         (or (and (>= b 97) (<= b 122))
         (or (and (>= b 48) (<= b 57))
         (or (= b 95) (= b 45)))))
         (scanKeyCol0 bs len (+ idx 1)))
        ((= b 58)
         (if (or (= (+ idx 1) len)
                 (= (bytesGet bs (+ idx 1)) 32)
                 (= (bytesGet bs (+ idx 1)) 10)
                 (= (bytesGet bs (+ idx 1)) 13))
           (some idx)
           (none)))
        (else (none)))))

fn isKeyAtCol0? line: String -> (Option (Pair String String))
  (let [(len (stringLength line))]
    (if (< len 2)
      (none)
      (let [(bs (stringToBytes line))]
        (mt (scanKeyCol0 bs len 0)
          ((some colIdx)
           (let [(key (optionOr (stringSlice line 0 colIdx) ""))
                 (val (stringTrim (optionOr (stringSlice line (+ colIdx 1) len) "")))]
             (some (pair key val))))
          ((none) (none))))))

fn findLineEnd bs: Bytes len: Int64 j: Int64 -> (Pair Int64 Int64)
  (if (>= j len)
    (pair len len)
    (let [(b (bytesGet bs j))]
      (cond
        ((= b 10)
         (pair j (+ j 1)))
        ((= b 13)
         (let [(isCrlf (and (< (+ j 1) len) (= (bytesGet bs (+ j 1)) 10)))]
           (pair j (if isCrlf (+ j 2) (+ j 1)))))
        (else
         (findLineEnd bs len (+ j 1))))))

fn scanLineSpansLoop text: String bs: Bytes len: Int64 cur: Int64 lineNum: Int64 acc: (List LineSpan) -> (List LineSpan)
  (if (>= cur len)
    (listReverse acc)
    (let [(start cur)
          (endRes (findLineEnd bs len cur))
          (contentEnd (pairFirst endRes))
          (nextStart (pairSecond endRes))
          (content (optionOr (stringSlice text start contentEnd) ""))
          (blank? (stringEmpty? (stringTrim content)))
          (span (LineSpan :start start :end contentEnd :nextStart nextStart :lineNum lineNum :blank? blank?))]
      (scanLineSpansLoop text bs len nextStart (+ lineNum 1) (cons span acc))))

fn scanLineSpans text: String -> (List LineSpan)
  (let [(len (stringLength text))]
    (if (= len 0)
      (list)
      (scanLineSpansLoop text (stringToBytes text) len 0 1 (list))))

fn detectHeadingsLoop spans: (List LineSpan) text: String acc: (List HeadingInfo) -> (List HeadingInfo)
  (if (listEmpty? spans)
    (listReverse acc)
    (let [(sp (optionOr (listHead spans) (LineSpan :start 0 :end 0 :nextStart 0 :lineNum 1 :blank? true)))
          (rest (optionOr (listTail spans) (list)))
          (content (optionOr (stringSlice text sp.start sp.end) ""))]
      (if sp.blank?
        (detectHeadingsLoop rest text acc)
        (let [(nextSpOpt (listHead rest))]
          (mt nextSpOpt
            ((some nextSp)
             (let [(nextContent (optionOr (stringSlice text nextSp.start nextSp.end) ""))]
               (mt (isSetextUnderline? nextContent)
                 ((some lvl)
                  (let [(h (HeadingInfo :name (stringTrim content)
                                        :kind "heading"
                                        :level lvl
                                        :line sp.lineNum
                                        :start sp.start
                                        :end nextSp.end))
                        (afterRest (optionOr (listTail rest) (list)))]
                    (detectHeadingsLoop afterRest text (cons h acc))))
                 ((none)
                  (detectHeadingLineStep sp rest text acc)))))
            ((none)
             (detectHeadingLineStep sp rest text acc)))))))

fn detectHeadingLineStep sp: LineSpan rest: (List LineSpan) text: String acc: (List HeadingInfo) -> (List HeadingInfo)
  (let [(content (optionOr (stringSlice text sp.start sp.end) ""))]
    (mt (isSetextUnderline? content)
      ((some _)
       (detectHeadingsLoop rest text acc))
      ((none)
       (mt (isSectionHeading? content)
         ((some secName)
          (let [(h (HeadingInfo :name secName :kind "section" :level 2 :line sp.lineNum :start sp.start :end sp.end))]
            (detectHeadingsLoop rest text (cons h acc))))
         ((none)
          (mt (isNumberedHeading? content)
            ((some np)
             (let [(h (HeadingInfo :name (pairSecond np) :kind "heading" :level (pairFirst np) :line sp.lineNum :start sp.start :end sp.end))]
               (detectHeadingsLoop rest text (cons h acc))))
            ((none)
             (mt (isKeyAtCol0? content)
               ((some kp)
                (let [(h (HeadingInfo :name (pairFirst kp) :kind "key" :level 3 :line sp.lineNum :start sp.start :end sp.end))]
                  (detectHeadingsLoop rest text (cons h acc))))
               ((none)
                (if (isAllCapsHeading? content)
                  (let [(h (HeadingInfo :name (stringTrim content) :kind "heading" :level 1 :line sp.lineNum :start sp.start :end sp.end))]
                    (detectHeadingsLoop rest text (cons h acc)))
                  (detectHeadingsLoop rest text acc)))))))))))

fn detectHeadings s: src/Source text: String -> (List HeadingInfo)
  (let [(spans (scanLineSpans text))]
    (detectHeadingsLoop spans text (list)))

fn textSymbols s: src/Source text: String -> (List sym/SymbolDef)
  (let [(hs (detectHeadings s text))]
    (map (fn [(h HeadingInfo)] -> sym/SymbolDef
           (sym/makeSymbolDef h.name h.kind h.start h.end))
         hs))

fn textOutlineItems s: src/Source text: String -> (List out/OutlineItem)
  (let [(hs (detectHeadings s text))]
    (map (fn [(h HeadingInfo)] -> out/OutlineItem
           (let [(en h.end)
                 (st h.start)
                 (lastOff (if (> en st) (- en 1) st))
                 (endLine (optionOr (src/sourceLineAt s lastOff) h.line))]
             (out/makeOutlineItem h.name h.kind h.line endLine)))
         hs))

fn textOutlineReceipt file: String text: String -> String
  (let [(s (src/sourceFromString file text))
        (syms (textSymbols s text))]
    (out/formatOutlineReceipt file "text" syms s))

fn textBlocksLoop spans: (List LineSpan) curKind: String curStart: Int64 curEnd: Int64 curStartLine: Int64 curEndLine: Int64 acc: (List TextBlock) -> (List TextBlock)
  (if (listEmpty? spans)
    (if (!= curKind "")
      (listReverse (cons (TextBlock :kind curKind :start curStart :end curEnd :startLine curStartLine :endLine curEndLine) acc))
      (listReverse acc))
    (let [(sp (optionOr (listHead spans) (LineSpan :start 0 :end 0 :nextStart 0 :lineNum 1 :blank? true)))
          (rest (optionOr (listTail spans) (list)))
          (k (if sp.blank? "blank" "paragraph"))]
      (if (= curKind "")
        (textBlocksLoop rest k sp.start sp.nextStart sp.lineNum sp.lineNum acc)
        (if (= curKind k)
          (textBlocksLoop rest curKind curStart sp.nextStart curStartLine sp.lineNum acc)
          (let [(b (TextBlock :kind curKind :start curStart :end curEnd :startLine curStartLine :endLine curEndLine))]
            (textBlocksLoop rest k sp.start sp.nextStart sp.lineNum sp.lineNum (cons b acc)))))))

fn textBlocks text: String -> (List TextBlock)
  (let [(spans (scanLineSpans text))]
    (textBlocksLoop spans "" 0 0 1 1 (list)))

fn textParagraphs text: String -> (List TextBlock)
  (filter (fn [(b TextBlock)] -> Bool (= b.kind "paragraph")) (textBlocks text))

fn spansToTokens spans: (List LineSpan) acc: (List tr/TreeElement) -> (List tr/TreeElement)
  (if (listEmpty? spans)
    (listReverse acc)
    (let [(sp (optionOr (listHead spans) (LineSpan :start 0 :end 0 :nextStart 0 :lineNum 1 :blank? true)))
          (rest (optionOr (listTail spans) (list)))
          (tok (tr/makeToken (if sp.blank? "blank" "text") sp.start sp.nextStart))]
      (spansToTokens rest (cons (tr/elemToken tok) acc))))

fn makeBlockNode text: String spans: (List LineSpan) -> tr/TreeElement
  (let [(firstSp (optionOr (listHead spans) (LineSpan :start 0 :end 0 :nextStart 0 :lineNum 1 :blank? true)))
        (lastSp (optionOr (listGet spans (- (listLength spans) 1)) firstSp))
        (bStart firstSp.start)
        (bEnd lastSp.nextStart)
        (kind (if firstSp.blank? "blank" "paragraph"))
        (tokens (spansToTokens spans (list)))]
    (tr/elemNode (tr/makeNode kind bStart bEnd tokens)))

fn groupBlocksLoop spans: (List LineSpan) curGroup: (List LineSpan) curBlank?: Bool acc: (List tr/TreeElement) text: String -> (List tr/TreeElement)
  (if (listEmpty? spans)
    (if (listEmpty? curGroup)
      (listReverse acc)
      (let [(elem (makeBlockNode text (listReverse curGroup)))]
        (listReverse (cons elem acc))))
    (let [(sp (optionOr (listHead spans) (LineSpan :start 0 :end 0 :nextStart 0 :lineNum 1 :blank? true)))
          (rest (optionOr (listTail spans) (list)))]
      (if (listEmpty? curGroup)
        (groupBlocksLoop rest (list sp) sp.blank? acc text)
        (if (= curBlank? sp.blank?)
          (groupBlocksLoop rest (cons sp curGroup) curBlank? acc text)
          (let [(elem (makeBlockNode text (listReverse curGroup)))]
            (groupBlocksLoop rest (list sp) sp.blank? (cons elem acc) text))))))

fn parseText text: String -> tr/Node
  (let [(len (stringLength text))]
    (if (= len 0)
      (tr/makeNode "document" 0 0 (list))
      (let [(spans (scanLineSpans text))
            (children (groupBlocksLoop spans (list) false (list) text))]
        (tr/makeNode "document" 0 len children))))

fn parseTextSource s: src/Source text: String -> tr/Node
  (parseText text)

fn textApplyAnchorEdit text: String anchor: String replacement: String -> (Result String String)
  (mt (sym/applyAnchorEdit text anchor replacement (fn [(t String)] -> (Result tr/Node String) (ok (parseText t))))
    ((ok res) (ok res.newText))
    ((err msg) (err msg)))

fn textApplyAnchorEditWithTree text: String anchor: String replacement: String -> (Result sym/EditResult String)
  (sym/applyAnchorEdit text anchor replacement (fn [(t String)] -> (Result tr/Node String) (ok (parseText t))))
