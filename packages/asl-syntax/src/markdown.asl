(module asl-syntax/markdown
  :x [MarkdownHeading
      MarkdownSection
      MarkdownBlock
      MdLine
      headingTitle
      headingLevel
      headingKind
      headingStart
      headingEnd
      headingLine
      sectionTitle
      sectionLevel
      sectionKind
      sectionStart
      sectionEnd
      sectionHeadingStart
      sectionHeadingEnd
      sectionStartLine
      sectionEndLine
      parseMarkdown
      parseMarkdownSource
      markdownBlocks
      markdownHeadings
      markdownSections
      findSection
      markdownHeadingRange
      markdownSectionRange
      markdownReadSection
      isAtxHeading?
      isSetextUnderline?
      isFencedCodeStart?
      isThematicBreak?
      isBlockQuoteLine?
      isTableDelimiterLine?
      isListItemLine?
      isFrontMatterStart?
      isFrontMatterEnd? isFencedCodeEnd?]
  :i [(asl-syntax/core/source :a src)
      (asl-syntax/core/tree :a tr)
      (asl-syntax/core/print :a pr)
      (asl-syntax/core/symbols :a sym)
      (asl-syntax/core/outline :a out)])

(schema MarkdownHeading
  (:f title String)
  (:f level Int64)
  (:f kind String)
  (:f start Int64)
  (:f end Int64)
  (:f line Int64))

(schema MarkdownSection
  (:f title String)
  (:f level Int64)
  (:f kind String)
  (:f start Int64)
  (:f end Int64)
  (:f headingStart Int64)
  (:f headingEnd Int64)
  (:f startLine Int64)
  (:f endLine Int64))

(schema MarkdownBlock
  (:f kind String)
  (:f start Int64)
  (:f end Int64)
  (:f startLine Int64)
  (:f endLine Int64))

(schema MdLine
  (:f start Int64)
  (:f end Int64)
  (:f nextStart Int64)
  (:f lineNum Int64)
  (:f blank? Bool))

fn headingTitle h: MarkdownHeading -> String
  h.title

fn headingLevel h: MarkdownHeading -> Int64
  h.level

fn headingKind h: MarkdownHeading -> String
  h.kind

fn headingStart h: MarkdownHeading -> Int64
  h.start

fn headingEnd h: MarkdownHeading -> Int64
  h.end

fn headingLine h: MarkdownHeading -> Int64
  h.line

fn sectionTitle s: MarkdownSection -> String
  s.title

fn sectionLevel s: MarkdownSection -> Int64
  s.level

fn sectionKind s: MarkdownSection -> String
  s.kind

fn sectionStart s: MarkdownSection -> Int64
  s.start

fn sectionEnd s: MarkdownSection -> Int64
  s.end

fn sectionHeadingStart s: MarkdownSection -> Int64
  s.headingStart

fn sectionHeadingEnd s: MarkdownSection -> Int64
  s.headingEnd

fn sectionStartLine s: MarkdownSection -> Int64
  s.startLine

fn sectionEndLine s: MarkdownSection -> Int64
  s.endLine

fn blockKind b: MarkdownBlock -> String
  b.kind

fn blockStart b: MarkdownBlock -> Int64
  b.start

fn blockEnd b: MarkdownBlock -> Int64
  b.end

fn blockStartLine b: MarkdownBlock -> Int64
  b.startLine

fn blockEndLine b: MarkdownBlock -> Int64
  b.endLine

fn isSpaceOrTab? b: Int64 -> Bool
  (or (= b 32) (= b 9))

fn countLeadingSpaces bs: Bytes limit: Int64 idx: Int64 count: Int64 -> Int64
  (if (>= idx limit)
    count
    (if (= count 3)
      count
      (if (isSpaceOrTab? (bytesGet bs idx))
        (countLeadingSpaces bs limit (+ idx 1) (+ count 1))
        count)))

fn skipAllSpaces bs: Bytes limit: Int64 idx: Int64 -> Int64
  (if (>= idx limit)
    idx
    (if (isSpaceOrTab? (bytesGet bs idx))
      (skipAllSpaces bs limit (+ idx 1))
      idx))

fn countConsecutiveChar bs: Bytes limit: Int64 idx: Int64 target: Int64 count: Int64 -> Int64
  (if (>= idx limit)
    count
    (if (= (bytesGet bs idx) target)
      (countConsecutiveChar bs limit (+ idx 1) target (+ count 1))
      count))

fn rfindNonHash bs: Bytes idx: Int64 -> Int64
  (if (< idx 0)
    -1
    (let [(b (bytesGet bs idx))]
      (if (or (= b 35) (isSpaceOrTab? b))
        (rfindNonHash bs (- idx 1))
        idx)))

fn stripTrailingHashes text: String -> String
  (let [(trimmed (stringTrim text))
        (len (stringLength trimmed))]
    (if (stringEndsWith? trimmed "#")
      (let [(bs (stringToBytes trimmed))
            (pos (rfindNonHash bs (- len 1)))]
        (if (< pos 0)
          ""
          (let [(sub (optionOr (stringSlice trimmed 0 (+ pos 1)) ""))]
            (stringTrim sub))))
      trimmed))

fn isAtxHeading? line: String -> (Option (Pair Int64 String))
  (let [(len (stringLength line))]
    (if (< len 1)
      (none)
      (let [(bs (stringToBytes line))
            (spCount (countLeadingSpaces bs len 0 0))
            (afterSp (+ 0 spCount))]
        (if (>= afterSp len)
          (none)
          (let [(hashCount (countConsecutiveChar bs len afterSp 35 0))]
            (if (or (< hashCount 1) (> hashCount 6))
              (none)
              (let [(afterHash (+ afterSp hashCount))]
                (if (>= afterHash len)
                  (some (pair hashCount ""))
                  (let [(nextB (bytesGet bs afterHash))]
                    (if (or (isSpaceOrTab? nextB) (or (= nextB 10) (= nextB 13)))
                      (let [(rawTitle (optionOr (stringSlice line afterHash len) ""))
                            (cleanTitle (stripTrailingHashes rawTitle))]
                        (some (pair hashCount cleanTitle)))
                      (none)))))))))))

fn isSetextUnderline? line: String -> (Option Int64)
  (let [(len (stringLength line))]
    (if (< len 1)
      (none)
      (let [(bs (stringToBytes line))
            (spCount (countLeadingSpaces bs len 0 0))
            (idx (+ 0 spCount))]
        (if (>= idx len)
          (none)
          (let [(firstB (bytesGet bs idx))]
            (if (and (!= firstB 61) (!= firstB 45))
              (none)
              (let [(uCount (countConsecutiveChar bs len idx firstB 0))
                    (afterU (+ idx uCount))
                    (restIdx (skipAllSpaces bs len afterU))]
                (if (or (>= restIdx len)
                        (or (= (bytesGet bs restIdx) 10)
                            (= (bytesGet bs restIdx) 13)))
                  (if (= firstB 61) (some 1) (some 2))
                  (none)))))))))

fn countThematicBreakChars bs: Bytes len: Int64 idx: Int64 target: Int64 count: Int64 -> Int64
  (if (>= idx len)
    count
    (let [(b (bytesGet bs idx))]
      (if (= b target)
        (countThematicBreakChars bs len (+ idx 1) target (+ count 1))
        (if (or (isSpaceOrTab? b) (or (= b 10) (= b 13)))
          (countThematicBreakChars bs len (+ idx 1) target count)
          -1))))

fn isThematicBreak? line: String -> Bool
  (let [(len (stringLength line))]
    (if (< len 3)
      false
      (let [(bs (stringToBytes line))
            (spCount (countLeadingSpaces bs len 0 0))
            (idx (+ 0 spCount))]
        (if (>= idx len)
          false
          (let [(b (bytesGet bs idx))]
            (if (and (!= b 42) (and (!= b 45) (!= b 95)))
              false
              (let [(c (countThematicBreakChars bs len idx b 0))]
                (>= c 3))))))))

fn bytesContainByte bs: Bytes start: Int64 end: Int64 target: Int64 -> Bool
  (if (>= start end)
    false
    (if (= (bytesGet bs start) target)
      true
      (bytesContainByte bs (+ start 1) end target)))

fn isFencedCodeStart? line: String -> (Option (Pair String String))
  (let [(len (stringLength line))]
    (if (< len 3)
      (none)
      (let [(bs (stringToBytes line))
            (spCount (countLeadingSpaces bs len 0 0))
            (idx (+ 0 spCount))]
        (if (>= idx len)
          (none)
          (let [(fc (bytesGet bs idx))]
            (if (and (!= fc 96) (!= fc 126))
              (none)
              (let [(fCount (countConsecutiveChar bs len idx fc 0))]
                (if (< fCount 3)
                  (none)
                  (let [(afterFences (+ idx fCount))]
                    (if (and (= fc 96) (bytesContainByte bs afterFences len 96))
                      (none)
                      (let [(fenceStr (if (= fc 96) "`" "~"))
                            (info (stringTrim (optionOr (stringSlice line afterFences len) "")))]
                        (some (pair fenceStr info)))))))))))))

fn isFencedCodeEnd? line: String fenceChar: String fenceLen: Int64 -> Bool
  (let [(len (stringLength line))]
    (if (< len fenceLen)
      false
      (let [(bs (stringToBytes line))
            (spCount (countLeadingSpaces bs len 0 0))
            (idx (+ 0 spCount))
            (fcByte (if (= fenceChar "`") 96 126))]
        (if (>= idx len)
          false
          (if (!= (bytesGet bs idx) fcByte)
            false
            (let [(c (countConsecutiveChar bs len idx fcByte 0))]
              (if (< c fenceLen)
                false
                (let [(afterF (+ idx c))
                      (rest (skipAllSpaces bs len afterF))]
                  (or (>= rest len)
                      (or (= (bytesGet bs rest) 10)
                          (= (bytesGet bs rest) 13)))))))))))

fn isBlockQuoteLine? line: String -> Bool
  (let [(len (stringLength line))]
    (if (< len 1)
      false
      (let [(bs (stringToBytes line))
            (spCount (countLeadingSpaces bs len 0 0))
            (idx (+ 0 spCount))]
        (if (>= idx len)
          false
          (= (bytesGet bs idx) 62)))))

fn allDashes? bs: Bytes idx: Int64 end: Int64 -> Bool
  (if (>= idx end)
    true
    (if (!= (bytesGet bs idx) 45)
      false
      (allDashes? bs (+ idx 1) end)))

fn isDelimiterCell? cell: String -> Bool
  (let [(len (stringLength cell))]
    (if (< len 1)
      false
      (let [(bs (stringToBytes cell))
            (startIdx (if (= (bytesGet bs 0) 58) 1 0))
            (endIdx (if (and (> len 1) (= (bytesGet bs (- len 1)) 58)) (- len 1) len))]
        (if (>= startIdx endIdx)
          false
          (allDashes? bs startIdx endIdx)))))

fn allCellsDelimiter? cells: (List String) -> Bool
  (if (listEmpty? cells)
    true
    (let [(c (optionOr (listHead cells) ""))
          (rest (optionOr (listTail cells) (list)))]
      (if (isDelimiterCell? (stringTrim c))
        (allCellsDelimiter? rest)
        false)))

fn isTableDelimiterLine? line: String -> Bool
  (let [(trimmed (stringTrim line))]
    (if (not (stringContains? trimmed "|"))
      false
      (let [(cells (stringSplit trimmed "|"))
            (nonEmptyCells (filter (fn [(c String)] -> Bool (not (stringEmpty? (stringTrim c)))) cells))]
        (if (listEmpty? nonEmptyCells)
          false
          (allCellsDelimiter? nonEmptyCells)))))

fn isHtmlBlockStart? line: String -> (Option Int64)
  (let [(trimmed (stringTrim line))
        (lower (stringLower trimmed))]
    (if (not (stringStartsWith? lower "<"))
      (none)
      (cond
        ((or (stringStartsWith? lower "<script")
         (or (stringStartsWith? lower "<pre")
             (stringStartsWith? lower "<style")))
         (some 1))
        ((stringStartsWith? lower "<!--")
         (some 2))
        ((stringStartsWith? lower "<?")
         (some 3))
        ((and (stringStartsWith? lower "<!")
              (and (> (stringLength trimmed) 2)
                   (let [(b (bytesGet (stringToBytes trimmed) 2))]
                     (and (>= b 65) (<= b 90)))))
         (some 4))
        ((stringStartsWith? lower "<![cdata[")
         (some 5))
        ((or (stringStartsWith? lower "<div")
         (or (stringStartsWith? lower "<table")
         (or (stringStartsWith? lower "<p")
         (or (stringStartsWith? lower "<form")
         (or (stringStartsWith? lower "<ul")
         (or (stringStartsWith? lower "<ol")
         (or (stringStartsWith? lower "<dl")
         (or (stringStartsWith? lower "<blockquote")
         (or (stringStartsWith? lower "</div")
         (or (stringStartsWith? lower "</table")
         (or (stringStartsWith? lower "</p")
         (or (stringStartsWith? lower "<hr")
         (or (stringStartsWith? lower "<details")
         (or (stringStartsWith? lower "</details")
         (or (stringStartsWith? lower "<section")
         (or (stringStartsWith? lower "</section")
             (stringStartsWith? lower "<article")))))))))))))))))
         (some 6))
        (else (none)))))

fn isDigit b: Int64 -> Bool
  (and (>= b 48) (<= b 57))

fn countDigits bs: Bytes limit: Int64 idx: Int64 count: Int64 -> Int64
  (if (>= idx limit)
    count
    (if (isDigit (bytesGet bs idx))
      (countDigits bs limit (+ idx 1) (+ count 1))
      count))

fn isListItemLine? line: String -> Bool
  (let [(len (stringLength line))]
    (if (< len 2)
      false
      (let [(bs (stringToBytes line))
            (spCount (countLeadingSpaces bs len 0 0))
            (idx (+ 0 spCount))]
        (if (>= idx len)
          false
          (let [(b (bytesGet bs idx))]
            (cond
              ((or (= b 45) (or (= b 42) (= b 43)))
               (if (>= (+ idx 1) len)
                 true
                 (let [(nextB (bytesGet bs (+ idx 1)))]
                   (or (isSpaceOrTab? nextB) (or (= nextB 10) (= nextB 13))))))
              ((isDigit b)
               (let [(dCount (countDigits bs len idx 0))]
                 (if (or (< dCount 1) (> dCount 9))
                   false
                   (let [(afterD (+ idx dCount))]
                     (if (>= afterD len)
                       false
                       (let [(markerB (bytesGet bs afterD))]
                         (if (and (!= markerB 46) (!= markerB 41))
                           false
                           (if (>= (+ afterD 1) len)
                             true
                             (let [(afterMarkerB (bytesGet bs (+ afterD 1)))]
                               (or (isSpaceOrTab? afterMarkerB) (or (= afterMarkerB 10) (= afterMarkerB 13))))))))))))
              (else false)))))))

fn isFrontMatterStart? line: String lineNum: Int64 -> (Option String)
  (if (!= lineNum 1)
    (none)
    (let [(trimmed (stringTrim line))]
      (cond
        ((= trimmed "---") (some "yaml"))
        ((= trimmed "+++") (some "toml"))
        (else (none)))))

fn isFrontMatterEnd? line: String kind: String -> Bool
  (let [(trimmed (stringTrim line))]
    (if (= kind "yaml")
      (or (= trimmed "---") (= trimmed "..."))
      (= trimmed "+++")))

fn findLineEnd bs: Bytes len: Int64 j: Int64 -> (Pair Int64 Int64)
  (if (>= j len)
    (pair len len)
    (let [(b (bytesGet bs j))]
      (cond
        ((= b 10)
         (pair j (+ j 1)))
        ((= b 13)
         (if (and (< (+ j 1) len) (= (bytesGet bs (+ j 1)) 10))
           (pair j (+ j 2))
           (pair j (+ j 1))))
        (else
         (findLineEnd bs len (+ j 1))))))

fn scanMdLinesLoop text: String bs: Bytes len: Int64 cur: Int64 lineNum: Int64 acc: (List MdLine) -> (List MdLine)
  (if (>= cur len)
    (listReverse acc)
    (let [(start cur)
          (endRes (findLineEnd bs len cur))
          (contentEnd (pairFirst endRes))
          (nextStart (pairSecond endRes))
          (content (optionOr (stringSlice text start contentEnd) ""))
          (blank? (stringEmpty? (stringTrim content)))
          (line (MdLine :start start :end contentEnd :nextStart nextStart :lineNum lineNum :blank? blank?))]
      (scanMdLinesLoop text bs len nextStart (+ lineNum 1) (cons line acc))))

fn scanMdLines text: String -> (List MdLine)
  (let [(len (stringLength text))]
    (if (= len 0)
      (list)
      (scanMdLinesLoop text (stringToBytes text) len 0 1 (list))))

fn lineToToken line: MdLine kind: String -> tr/TreeElement
  (tr/elemToken (tr/makeToken kind line.start line.nextStart))

fn linesToTokens lines: (List MdLine) kind: String acc: (List tr/TreeElement) -> (List tr/TreeElement)
  (if (listEmpty? lines)
    (listReverse acc)
    (let [(l (optionOr (listHead lines) (MdLine :start 0 :end 0 :nextStart 0 :lineNum 1 :blank? true)))
          (rest (optionOr (listTail lines) (list)))]
      (linesToTokens rest kind (cons (lineToToken l kind) acc))))

fn makeBlockNode kind: String lines: (List MdLine) tokenKind: String -> tr/Node
  (let [(firstLine (optionOr (listHead lines) (MdLine :start 0 :end 0 :nextStart 0 :lineNum 1 :blank? true)))
        (lastLine (optionOr (listGet lines (- (listLength lines) 1)) firstLine))
        (s firstLine.start)
        (e lastLine.nextStart)
        (tokens (linesToTokens lines tokenKind (list)))]
    (tr/makeNode kind s e tokens))

fn collectFrontMatterLoop lines: (List MdLine) text: String kind: String acc: (List MdLine) -> (Pair (List MdLine) (List MdLine))
  (if (listEmpty? lines)
    (pair (listReverse acc) (list))
    (let [(cur (optionOr (listHead lines) (MdLine :start 0 :end 0 :nextStart 0 :lineNum 1 :blank? true)))
          (rest (optionOr (listTail lines) (list)))
          (lineStr (optionOr (stringSlice text cur.start cur.end) ""))]
      (if (isFrontMatterEnd? lineStr kind)
        (pair (listReverse (cons cur acc)) rest)
        (collectFrontMatterLoop rest text kind (cons cur acc)))))

fn collectFencedCodeLoop lines: (List MdLine) text: String fc: String flen: Int64 acc: (List MdLine) -> (Pair (List MdLine) (List MdLine))
  (if (listEmpty? lines)
    (pair (listReverse acc) (list))
    (let [(cur (optionOr (listHead lines) (MdLine :start 0 :end 0 :nextStart 0 :lineNum 1 :blank? true)))
          (rest (optionOr (listTail lines) (list)))
          (lineStr (optionOr (stringSlice text cur.start cur.end) ""))]
      (if (isFencedCodeEnd? lineStr fc flen)
        (pair (listReverse (cons cur acc)) rest)
        (collectFencedCodeLoop rest text fc flen (cons cur acc)))))

fn isHtmlBlockClosedOnSameLine? line: String htype: Int64 -> Bool
  (let [(lower (stringLower line))]
    (cond
      ((= htype 1)
       (or (stringContains? lower "</script>")
       (or (stringContains? lower "</pre>")
           (stringContains? lower "</style>"))))
      ((= htype 2) (stringContains? line "-->"))
      ((= htype 3) (stringContains? line "?>"))
      ((= htype 4) (stringContains? line ">"))
      ((= htype 5) (stringContains? line "]]>"))
      (else false)))

fn collectHtmlBlockLoop lines: (List MdLine) text: String htype: Int64 acc: (List MdLine) -> (Pair (List MdLine) (List MdLine))
  (if (listEmpty? lines)
    (pair (listReverse acc) (list))
    (let [(cur (optionOr (listHead lines) (MdLine :start 0 :end 0 :nextStart 0 :lineNum 1 :blank? true)))
          (rest (optionOr (listTail lines) (list)))
          (lineStr (optionOr (stringSlice text cur.start cur.end) ""))
          (lower (stringLower lineStr))]
      (cond
        ((= htype 1)
         (if (or (stringContains? lower "</script>")
             (or (stringContains? lower "</pre>")
                 (stringContains? lower "</style>")))
           (pair (listReverse (cons cur acc)) rest)
           (collectHtmlBlockLoop rest text htype (cons cur acc))))
        ((= htype 2)
         (if (stringContains? lineStr "-->")
           (pair (listReverse (cons cur acc)) rest)
           (collectHtmlBlockLoop rest text htype (cons cur acc))))
        ((= htype 3)
         (if (stringContains? lineStr "?>")
           (pair (listReverse (cons cur acc)) rest)
           (collectHtmlBlockLoop rest text htype (cons cur acc))))
        ((= htype 4)
         (if (stringContains? lineStr ">")
           (pair (listReverse (cons cur acc)) rest)
           (collectHtmlBlockLoop rest text htype (cons cur acc))))
        ((= htype 5)
         (if (stringContains? lineStr "]]>")
           (pair (listReverse (cons cur acc)) rest)
           (collectHtmlBlockLoop rest text htype (cons cur acc))))
        (else
         (if cur.blank?
           (pair (listReverse acc) lines)
           (collectHtmlBlockLoop rest text htype (cons cur acc)))))))

fn collectBlockQuoteLoop lines: (List MdLine) text: String acc: (List MdLine) -> (Pair (List MdLine) (List MdLine))
  (if (listEmpty? lines)
    (pair (listReverse acc) (list))
    (let [(cur (optionOr (listHead lines) (MdLine :start 0 :end 0 :nextStart 0 :lineNum 1 :blank? true)))
          (rest (optionOr (listTail lines) (list)))
          (lineStr (optionOr (stringSlice text cur.start cur.end) ""))]
      (if (isBlockQuoteLine? lineStr)
        (collectBlockQuoteLoop rest text (cons cur acc))
        (pair (listReverse acc) lines))))

fn collectTableRowsLoop lines: (List MdLine) text: String acc: (List tr/TreeElement) -> (Pair (List tr/TreeElement) (List MdLine))
  (if (listEmpty? lines)
    (pair (listReverse acc) (list))
    (let [(cur (optionOr (listHead lines) (MdLine :start 0 :end 0 :nextStart 0 :lineNum 1 :blank? true)))
          (rest (optionOr (listTail lines) (list)))
          (lineStr (optionOr (stringSlice text cur.start cur.end) ""))]
      (if (and (not cur.blank?) (stringContains? lineStr "|"))
        (let [(rowNode (makeBlockNode "tableRow" (list cur) "tableRow"))]
          (collectTableRowsLoop rest text (cons (tr/elemNode rowNode) acc)))
        (pair (listReverse acc) lines))))

fn collectListItemsLoop lines: (List MdLine) text: String acc: (List tr/TreeElement) -> (Pair (List tr/TreeElement) (List MdLine))
  (if (listEmpty? lines)
    (pair (listReverse acc) (list))
    (let [(cur (optionOr (listHead lines) (MdLine :start 0 :end 0 :nextStart 0 :lineNum 1 :blank? true)))
          (rest (optionOr (listTail lines) (list)))
          (lineStr (optionOr (stringSlice text cur.start cur.end) ""))]
      (if (isListItemLine? lineStr)
        (let [(itemNode (makeBlockNode "listItem" (list cur) "listItem"))]
          (collectListItemsLoop rest text (cons (tr/elemNode itemNode) acc)))
        (pair (listReverse acc) lines))))

fn collectParagraphLoop lines: (List MdLine) text: String acc: (List MdLine) -> (Pair (List MdLine) (List MdLine))
  (if (listEmpty? lines)
    (pair (listReverse acc) (list))
    (let [(cur (optionOr (listHead lines) (MdLine :start 0 :end 0 :nextStart 0 :lineNum 1 :blank? true)))
          (rest (optionOr (listTail lines) (list)))
          (lineStr (optionOr (stringSlice text cur.start cur.end) ""))]
      (if (or cur.blank?
          (or (some? (isAtxHeading? lineStr))
          (or (some? (isFencedCodeStart? lineStr))
          (or (isBlockQuoteLine? lineStr)
          (or (isThematicBreak? lineStr)
          (or (isListItemLine? lineStr)
              (some? (isHtmlBlockStart? lineStr))))))))
        (pair (listReverse acc) lines)
        (if (some? (isSetextUnderline? lineStr))
          (pair (listReverse acc) lines)
          (collectParagraphLoop rest text (cons cur acc))))))

fn parseBlocksLoop lines: (List MdLine) text: String acc: (List tr/TreeElement) -> (List tr/TreeElement)
  (if (listEmpty? lines)
    (listReverse acc)
    (let [(cur (optionOr (listHead lines) (MdLine :start 0 :end 0 :nextStart 0 :lineNum 1 :blank? true)))
          (rest (optionOr (listTail lines) (list)))
          (lineStr (optionOr (stringSlice text cur.start cur.end) ""))]
      (cond
        (cur.blank?
         (let [(bn (makeBlockNode "blankLine" (list cur) "blank"))]
           (parseBlocksLoop rest text (cons (tr/elemNode bn) acc))))
        ((and (= cur.lineNum 1) (some? (isFrontMatterStart? lineStr 1)))
         (let [(kind (optionOr (isFrontMatterStart? lineStr 1) "yaml"))
               (fmRes (collectFrontMatterLoop rest text kind (list cur)))
               (fmLines (pairFirst fmRes))
               (remaining (pairSecond fmRes))
               (bn (makeBlockNode "frontMatter" fmLines "frontMatter"))]
           (parseBlocksLoop remaining text (cons (tr/elemNode bn) acc))))
        ((some? (isFencedCodeStart? lineStr))
         (let [(fcPair (optionOr (isFencedCodeStart? lineStr) (pair "`" "")))
               (fc (pairFirst fcPair))
               (flen (stringLength fc))
               (fcRes (collectFencedCodeLoop rest text fc 3 (list cur)))
               (fcLines (pairFirst fcRes))
               (remaining (pairSecond fcRes))
               (bn (makeBlockNode "fencedCode" fcLines "fencedCode"))]
           (parseBlocksLoop remaining text (cons (tr/elemNode bn) acc))))
        ((some? (isHtmlBlockStart? lineStr))
         (let [(htype (optionOr (isHtmlBlockStart? lineStr) 6))
               (htRes (if (isHtmlBlockClosedOnSameLine? lineStr htype)
                        (pair (list cur) rest)
                        (collectHtmlBlockLoop rest text htype (list cur))))
               (htLines (pairFirst htRes))
               (remaining (pairSecond htRes))
               (bn (makeBlockNode "htmlBlock" htLines "htmlBlock"))]
           (parseBlocksLoop remaining text (cons (tr/elemNode bn) acc))))
        ((some? (isAtxHeading? lineStr))
         (let [(bn (makeBlockNode "atxHeading" (list cur) "atxHeading"))]
           (parseBlocksLoop rest text (cons (tr/elemNode bn) acc))))
        ((isThematicBreak? lineStr)
         (let [(bn (makeBlockNode "thematicBreak" (list cur) "thematicBreak"))]
           (parseBlocksLoop rest text (cons (tr/elemNode bn) acc))))
        ((isBlockQuoteLine? lineStr)
         (let [(bqRes (collectBlockQuoteLoop rest text (list cur)))
               (bqLines (pairFirst bqRes))
               (remaining (pairSecond bqRes))
               (bn (makeBlockNode "blockQuote" bqLines "blockQuote"))]
           (parseBlocksLoop remaining text (cons (tr/elemNode bn) acc))))
        ((and (stringContains? lineStr "|")
              (and (not (listEmpty? rest))
                   (let [(nextLine (optionOr (listHead rest) cur))
                         (nextStr (optionOr (stringSlice text nextLine.start nextLine.end) ""))]
                     (isTableDelimiterLine? nextStr))))
         (let [(headerLine cur)
               (delimLine (optionOr (listHead rest) cur))
               (afterDelim (optionOr (listTail rest) (list)))
               (headerNode (makeBlockNode "tableHeader" (list headerLine) "tableHeader"))
               (delimNode (makeBlockNode "tableDelimiter" (list delimLine) "tableDelimiter"))
               (rowsRes (collectTableRowsLoop afterDelim text (list)))
               (rowElements (pairFirst rowsRes))
               (remaining (pairSecond rowsRes))
               (allChildren (cons (tr/elemNode headerNode) (cons (tr/elemNode delimNode) rowElements)))
               (lastOffset (if (listEmpty? rowElements)
                             delimLine.nextStart
                             (let [(lastElem (optionOr (listGet rowElements (- (listLength rowElements) 1)) (tr/elemNode delimNode)))]
                               (tr/elementEnd lastElem))))
               (tableNode (tr/makeNode "table" headerLine.start lastOffset allChildren))]
           (parseBlocksLoop remaining text (cons (tr/elemNode tableNode) acc))))
        ((isListItemLine? lineStr)
         (let [(listRes (collectListItemsLoop rest text (list (tr/elemNode (makeBlockNode "listItem" (list cur) "listItem")))))
               (itemElements (pairFirst listRes))
               (remaining (pairSecond listRes))
               (lastElem (optionOr (listGet itemElements (- (listLength itemElements) 1)) (tr/elemNode (makeBlockNode "listItem" (list cur) "listItem"))))
               (listNode (tr/makeNode "list" cur.start (tr/elementEnd lastElem) itemElements))]
           (parseBlocksLoop remaining text (cons (tr/elemNode listNode) acc))))
        (else
         (let [(paraRes (collectParagraphLoop rest text (list cur)))
               (paraLines (pairFirst paraRes))
               (remaining (pairSecond paraRes))]
           (if (and (not (listEmpty? remaining))
                    (let [(nextLine (optionOr (listHead remaining) cur))
                          (nextStr (optionOr (stringSlice text nextLine.start nextLine.end) ""))]
                      (some? (isSetextUnderline? nextStr))))
             (let [(underlineLine (optionOr (listHead remaining) cur))
                   (afterUnderline (optionOr (listTail remaining) (list)))
                   (allLines (listReverse (cons underlineLine (listReverse paraLines))))
                   (bn (makeBlockNode "setextHeading" allLines "setextHeading"))]
               (parseBlocksLoop afterUnderline text (cons (tr/elemNode bn) acc)))
             (let [(bn (makeBlockNode "paragraph" paraLines "paragraph"))]
               (parseBlocksLoop remaining text (cons (tr/elemNode bn) acc)))))))))

fn parseMarkdown text: String -> tr/Node
  (let [(len (stringLength text))]
    (if (= len 0)
      (tr/makeNode "document" 0 0 (list))
      (let [(lines (scanMdLines text))
            (children (parseBlocksLoop lines text (list)))]
        (tr/makeNode "document" 0 len children))))

fn parseMarkdownSource s: src/Source text: String -> tr/Node
  (parseMarkdown text)

fn collectBlocksLoop elems: (List tr/TreeElement) acc: (List MarkdownBlock) -> (List MarkdownBlock)
  (if (listEmpty? elems)
    (listReverse acc)
    (let [(head (optionOr (listHead elems) (tr/elemToken (tr/Token :kind "" :start 0 :end 0))))
          (rest (optionOr (listTail elems) (list)))]
      (mt head
        ((tr/elemToken _) (collectBlocksLoop rest acc))
        ((tr/elemNode node)
         (let [(b (MarkdownBlock :kind node.kind
                                :start node.start
                                :end node.end
                                :startLine 0
                                :endLine 0))]
           (collectBlocksLoop rest (cons b acc)))))))

fn markdownBlocks text: String -> (List MarkdownBlock)
  (let [(root (parseMarkdown text))]
    (collectBlocksLoop root.children (list)))

fn extractHeadingNode node: tr/Node text: String -> (Option MarkdownHeading)
  (let [(k node.kind)]
    (cond
      ((= k "atxHeading")
       (let [(line (optionOr (stringSlice text node.start node.end) ""))]
         (mt (isAtxHeading? line)
           ((some p)
            (some (MarkdownHeading :title (pairSecond p)
                                   :level (pairFirst p)
                                   :kind "atxHeading"
                                   :start node.start
                                   :end node.end
                                   :line 0)))
           ((none) (none)))))
      ((= k "setextHeading")
       (let [(children node.children)
             (firstToken (optionOr (listHead children) (tr/elemToken (tr/Token :kind "" :start 0 :end 0))))
             (lastToken (optionOr (listGet children (- (listLength children) 1)) firstToken))
             (underLineStr (optionOr (stringSlice text (tr/elementStart lastToken) (tr/elementEnd lastToken)) ""))
             (titleStr (stringTrim (optionOr (stringSlice text node.start (tr/elementStart lastToken)) "")))
             (lvl (optionOr (isSetextUnderline? underLineStr) 1))]
         (some (MarkdownHeading :title titleStr
                                :level lvl
                                :kind "setextHeading"
                                :start node.start
                                :end node.end
                                :line 0))))
      (else (none))))

fn collectHeadingsLoop elems: (List tr/TreeElement) text: String acc: (List MarkdownHeading) -> (List MarkdownHeading)
  (if (listEmpty? elems)
    (listReverse acc)
    (let [(head (optionOr (listHead elems) (tr/elemToken (tr/Token :kind "" :start 0 :end 0))))
          (rest (optionOr (listTail elems) (list)))]
      (mt head
        ((tr/elemToken _) (collectHeadingsLoop rest text acc))
        ((tr/elemNode node)
         (mt (extractHeadingNode node text)
           ((some h) (collectHeadingsLoop rest text (cons h acc)))
           ((none) (collectHeadingsLoop rest text acc)))))))

fn markdownHeadings root: tr/Node text: String -> (List MarkdownHeading)
  (collectHeadingsLoop root.children text (list))

fn computeSectionEnd headings: (List MarkdownHeading) curLevel: Int64 defaultEnd: Int64 -> Int64
  (if (listEmpty? headings)
    defaultEnd
    (let [(nextH (optionOr (listHead headings) (MarkdownHeading :title "" :level 0 :kind "" :start 0 :end 0 :line 0)))
          (rest (optionOr (listTail headings) (list)))]
      (if (<= nextH.level curLevel)
        nextH.start
        (computeSectionEnd rest curLevel defaultEnd))))

fn buildSectionsLoop headings: (List MarkdownHeading) docLen: Int64 acc: (List MarkdownSection) -> (List MarkdownSection)
  (if (listEmpty? headings)
    (listReverse acc)
    (let [(h (optionOr (listHead headings) (MarkdownHeading :title "" :level 0 :kind "" :start 0 :end 0 :line 0)))
          (rest (optionOr (listTail headings) (list)))
          (secStart h.start)
          (secEnd (computeSectionEnd rest h.level docLen))
          (sec (MarkdownSection :title h.title
                                :level h.level
                                :kind h.kind
                                :start secStart
                                :end secEnd
                                :headingStart h.start
                                :headingEnd h.end
                                :startLine h.line
                                :endLine 0))]
      (buildSectionsLoop rest docLen (cons sec acc))))

fn markdownSections root: tr/Node text: String -> (List MarkdownSection)
  (let [(headings (markdownHeadings root text))
        (docLen (stringLength text))]
    (buildSectionsLoop headings docLen (list)))

fn stripQueryLeadingHashes bs: Bytes len: Int64 idx: Int64 text: String -> String
  (if (>= idx len)
    ""
    (if (or (= (bytesGet bs idx) 35) (isSpaceOrTab? (bytesGet bs idx)))
      (stripQueryLeadingHashes bs len (+ idx 1) text)
      (optionOr (stringSlice text idx len) "")))

fn cleanQuery q: String -> String
  (let [(trimmed (stringTrim q))]
    (if (stringStartsWith? trimmed "#")
      (stringTrim (stripQueryLeadingHashes (stringToBytes trimmed) (stringLength trimmed) 0 trimmed))
      trimmed))

fn matchesTitle? actual: String query: String -> Bool
  (or (= actual query)
      (= (stringLower (stringTrim actual)) (stringLower (stringTrim query))))

fn findSection sections: (List MarkdownSection) title: String -> (Option MarkdownSection)
  (if (listEmpty? sections)
    (none)
    (let [(s (optionOr (listHead sections) (MarkdownSection :title "" :level 0 :kind "" :start 0 :end 0 :headingStart 0 :headingEnd 0 :startLine 0 :endLine 0)))
          (rest (optionOr (listTail sections) (list)))
          (cleanQ (cleanQuery title))]
      (if (matchesTitle? s.title cleanQ)
        (some s)
        (findSection rest title))))

fn markdownHeadingRange text: String query: String -> (Option (Pair Int64 Int64))
  (let [(root (parseMarkdown text))
        (secs (markdownSections root text))]
    (mt (findSection secs query)
      ((some sec) (some (pair sec.headingStart sec.headingEnd)))
      ((none) (none))))

fn markdownSectionRange text: String query: String -> (Option (Pair Int64 Int64))
  (let [(root (parseMarkdown text))
        (secs (markdownSections root text))]
    (mt (findSection secs query)
      ((some sec) (some (pair sec.start sec.end)))
      ((none) (none))))

fn markdownReadSection text: String query: String -> (Option String)
  (let [(root (parseMarkdown text))
        (secs (markdownSections root text))]
    (mt (findSection secs query)
      ((some sec) (stringSlice text sec.start sec.end))
      ((none) (none))))
