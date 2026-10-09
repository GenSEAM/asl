(module asl-syntax/core/format
  :x [LineEntry
      resolveLang
      langForPath
      checkRepairedLines
      touchedLinesFromRepaired
      formatText
      formatBytes
      formatRepair
      formatFile!
      formatSingleLine
      shouldSeparate
      isOpenDelim?
      isCloseDelim?
      isOnlyClosingDelims?
      lineEndsWithComment?]
  :i [(asl-syntax/core/source :a src)
      (asl-syntax/core/tree :a tr)
      (asl-syntax/asl/lex :a lx)
      (asl-syntax/core/bytesText :a bt)
      (asl-forms/repair :a rep)])

(schema LineEntry
  (:f text String)
  (:f touched Bool)
  (:f dropped Bool)
  (:f pinned Bool))

fn resolveLang lang: String -> (Result String String)
  (cond
    ((= lang "asl") (ok "asl"))
    ((= lang "asn") (ok "asn"))
    (else (langForPath lang)))

fn langForPath path: String -> (Result String String)
  (cond
    ((stringEndsWith? path ".asl") (ok "asl"))
    ((stringEndsWith? path ".asn") (ok "asn"))
    (else (err (str "cannot decide language for " path ": expected asl, asn or a .asl/.asn path"))))

fn checkRepairedLines origLines: (List String) repLines: (List String) touched: (List Int64) idx: Int64 -> (Result Bool String)
  (if (> idx (if (> (listLength repLines) (listLength origLines)) (listLength repLines) (listLength origLines)))
    (ok true)
    (let [(o (listGet origLines (- idx 1)))
          (r (listGet repLines (- idx 1)))
          (same (mt o
                  ((some ot) (mt r ((some rt) (= ot rt)) ((none) false)))
                  ((none) false)))]
      (if (or same (listContains? touched idx))
        (checkRepairedLines origLines repLines touched (+ idx 1))
        (err (str "repaired text changes line " (stringFromInt64 idx) ", which no repaired item names")))))

fn touchedLinesFromRepaired items: (List rep/RepairedItem) -> (List Int64)
  (fold (fn [(acc (List Int64)) (item rep/RepairedItem)] -> (List Int64)
          (let [(l item.line)]
            (if (listContains? acc l)
              acc
              (cons l acc))))
        (list) items)

fn isOpenDelim? kind: String -> Bool
  (or (= kind "lparen") (or (= kind "lbracket") (= kind "lbrace")))

fn isCloseDelim? kind: String -> Bool
  (or (= kind "rparen") (or (= kind "rbracket") (= kind "rbrace")))

fn isOnlyClosingDelims? s: String -> Bool
  (let [(trimmed (stringTrim s))]
    (and (not (stringEmpty? trimmed))
         (fold (fn [(acc Bool) (c String)] -> Bool
                 (and acc (or (= c ")") (or (= c "]") (= c "}")))))
               true (stringChars trimmed))))

fn contentTokens text: String -> (List tr/Token)
  (filter (fn [(t tr/Token)] -> Bool
            (and (!= t.kind "whitespace") (!= t.kind "newline")))
          (lx/tokenize text))

fn lineEndsWithComment? line: String -> Bool
  (let [(nonWhite (contentTokens line))]
    (if (listEmpty? nonWhite)
      false
      (let [(lastTok (optionOr (listGet nonWhite (- (listLength nonWhite) 1))
                               (tr/makeToken "" 0 0)))]
        (= lastTok.kind "comment"))))

fn takeWhileWhitespace chars: (List String) acc: (List String) -> (List String)
  (if (listEmpty? chars)
    (listReverse acc)
    (let [(c (optionOr (listHead chars) ""))
          (rest (optionOr (listTail chars) (list)))]
      (if (or (= c " ") (= c "\t"))
        (takeWhileWhitespace rest (cons c acc))
        (listReverse acc))))

fn leadingIndent line: String -> String
  (stringJoin (takeWhileWhitespace (stringChars line) (list)) "")

fn shouldSeparate line: String prevTok: tr/Token nextTok: tr/Token -> Bool
  (let [(gap (optionOr (stringSlice line prevTok.end nextTok.start) ""))]
    (cond
      ((stringEmpty? gap) false)
      ((isOpenDelim? prevTok.kind) false)
      ((isCloseDelim? nextTok.kind) false)
      ((= nextTok.kind "comma") false)
      (else true)))

fn formatTokensLoop line: String toks: (List tr/Token) prevTok: tr/Token acc: String -> String
  (if (listEmpty? toks)
    acc
    (let [(curTok (optionOr (listHead toks) (tr/makeToken "" 0 0)))
          (rest (optionOr (listTail toks) (list)))
          (sep (if (shouldSeparate line prevTok curTok) " " ""))]
      (formatTokensLoop line rest curTok (str acc sep (lx/tokenSliceString line curTok)))))

fn formatSingleLine line: String -> String
  (if (stringEndsWith? line "\r")
    (str (formatLineBody (optionOr (stringSlice line 0 (- (stringLength line) 1)) "")) "\r")
    (formatLineBody line))

fn formatLineBody line: String -> String
  (let [(toks (contentTokens line))]
    (if (listEmpty? toks)
      ""
      (let [(firstTok (optionOr (listHead toks) (tr/makeToken "" 0 0)))
            (rest (optionOr (listTail toks) (list)))]
        (formatTokensLoop line rest firstTok (str (leadingIndent line) (lx/tokenSliceString line firstTok))))))

fn appendBeforeCr line: String closers: String -> String
  (if (stringEndsWith? line "\r")
    (str (optionOr (stringSlice line 0 (- (stringLength line) 1)) "") closers "\r")
    (str line closers))

fn splitLines text: String -> (List String)
  (let [(raw (stringSplit text "\n"))]
    (if (and (stringEndsWith? text "\n") (not (listEmpty? raw)))
      (listTake raw (- (listLength raw) 1))
      raw))

fn dominantTerminator text: String -> String
  (let [(lf (- (listLength (stringSplit text "\n")) 1))
        (crlf (- (listLength (stringSplit text "\r\n")) 1))]
    (if (and (> crlf 0) (> (* crlf 2) lf)) "\r\n" "\n"))

fn joinLines lines: (List String) origText: String -> String
  (let [(body (stringJoin lines "\n"))]
    (cond
      ((not (stringEndsWith? origText "\n")) body)
      ((stringEndsWith? body "\r") (str body "\n"))
      (else (str body (dominantTerminator origText)))))

fn findPrevContentEntry entries: (List LineEntry) curIdx: Int64 -> (Option Int64)
  (if (<= curIdx 0)
    (none)
    (let [(prevIdx (- curIdx 1))
          (e (optionOr (listGet entries prevIdx) (LineEntry :text "" :touched false :dropped true :pinned false)))]
      (if (or e.dropped (stringEmpty? (stringTrim e.text)))
        (findPrevContentEntry entries prevIdx)
        (some prevIdx))))

fn updateEntryAt entries: (List LineEntry) targetIdx: Int64 newEntry: LineEntry curIdx: Int64 acc: (List LineEntry) -> (List LineEntry)
  (if (listEmpty? entries)
    (listReverse acc)
    (let [(h (optionOr (listHead entries) (LineEntry :text "" :touched false :dropped true :pinned false)))
          (tl (optionOr (listTail entries) (list)))]
      (updateEntryAt tl targetIdx newEntry (+ curIdx 1) (cons (if (= curIdx targetIdx) newEntry h) acc))))

fn attachClosingPass entries: (List LineEntry) curIdx: Int64 -> (List LineEntry)
  (if (< curIdx 0)
    entries
    (let [(entry (optionOr (listGet entries curIdx) (LineEntry :text "" :touched false :dropped true :pinned false)))]
      (if (or entry.dropped (or (not entry.touched) (not (isOnlyClosingDelims? entry.text))))
        (attachClosingPass entries (- curIdx 1))
        (mt (findPrevContentEntry entries curIdx)
          ((none) (attachClosingPass entries (- curIdx 1)))
          ((some prevIdx)
           (let [(prevEntry (optionOr (listGet entries prevIdx) (LineEntry :text "" :touched false :dropped true :pinned false)))]
             (if (lineEndsWithComment? prevEntry.text)
               (attachClosingPass entries (- curIdx 1))
               (let [(updatedPrev (LineEntry :text (appendBeforeCr prevEntry.text (stringTrim entry.text)) :touched true :dropped false :pinned prevEntry.pinned))
                     (updatedCur (LineEntry :text "" :touched true :dropped true :pinned false))
                     (e1 (updateEntryAt entries prevIdx updatedPrev 0 (list)))
                     (e2 (updateEntryAt e1 curIdx updatedCur 0 (list)))]
                 (attachClosingPass e2 (- curIdx 1))))))))))

fn keepEntry? e: LineEntry -> Bool
  (not (or e.dropped (and e.touched (stringEmpty? (stringTrim e.text)))))

fn pinnedLines text: String -> (List Int64)
  (let [(s (src/sourceFromString "<repaired>" text))]
    (fold (fn [(acc (List Int64)) (t tr/Token)] -> (List Int64)
            (if (or (= t.kind "whitespace") (or (= t.kind "newline") (not (stringContains? (lx/tokenSliceString text t) "\n"))))
              acc
              (listAppend (range (optionOr (src/sourceLineAt s t.start) 1) (+ (optionOr (src/sourceLineAt s t.end) 1) 1)) acc)))
          (list) (lx/tokenize text)))

fn formatLines origText: String repairedText: String touched: (List Int64) -> String
  (let [(lines (splitLines repairedText))
        (pinned (if (listEmpty? touched) (list) (pinnedLines repairedText)))
        (entries (map (fn [(idx Int64)] -> LineEntry
                        (LineEntry :text (optionOr (listGet lines idx) "")
                                   :touched (listContains? touched (+ idx 1))
                                   :dropped false
                                   :pinned (listContains? pinned (+ idx 1))))
                      (range 0 (listLength lines))))
        (attached (attachClosingPass entries (- (listLength entries) 1)))
        (outLines (map (fn [(e LineEntry)] -> String
                         (if (and e.touched (not e.pinned)) (formatSingleLine e.text) e.text))
                       (filter keepEntry? attached)))]
    (joinLines outLines origText))

fn formatText origText: String res: rep/RepairResult lang: String -> (Result String String)
  (mt (resolveLang lang)
    ((err e) (err e))
    ((ok l)
     (if (not (listEmpty? (rep/repairResultLeft res)))
       (err (str "repair left defects: " (rep/repairResultReceipt res)))
       (let [(repairedText (rep/repairResultText res))
             (touched (touchedLinesFromRepaired (rep/repairResultRepaired res)))]
         (mt (checkRepairedLines (splitLines origText) (splitLines repairedText) touched 1)
           ((err e) (err e))
           ((ok _)
            (ok (formatLines origText repairedText touched))))))))

fn formatBytes origBytes: Bytes res: rep/RepairResult lang: String -> (Result Bytes String)
  (mt (formatText (bt/bytesToString origBytes) res lang)
    ((err e) (err e))
    ((ok out) (ok (stringToBytes out))))

fn formatRepair origText: String lang: String -> (Result String String)
  (mt (resolveLang lang)
    ((err e) (err e))
    ((ok l) (formatText origText (rep/repairAtSite origText l) l)))

fn formatFile! path: String -> (Result String String)
  (mt (langForPath path)
    ((err e) (err e))
    ((ok lang)
     (mt (fileReadString path)
       ((err e) (err (str "cannot read " path ": " e)))
       ((ok content) (formatRepair content lang)))))
