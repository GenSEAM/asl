(module asl-syntax/html/tree
  :x [parse
      parseBytes
      parseHtml
      parseHtmlBytes
      isWellFormed
      documentRootElement
      elementName
      elementChildren
      elementAttributes
      attributeValue
      elementId
      elementNameAttr
      extractSymbols
      extractSymbolsFromText
      extractOutlineSymbols
      formatOutline
      isVoidElement
      hasImpliedEndTag elementTextContent]
  :i [(asl-syntax/core/source :a src)
      (asl-syntax/core/tree :a tr)
      (asl-syntax/core/symbols :a sym)
      (asl-syntax/core/outline :a out)
      (asl-syntax/html/lex :a hlx)])

(schema OpenElem
  (:f tag String)
  (:f start Int64)
  (:f children (List tr/TreeElement))
  (:f implied? Bool))

(schema ParseState
  (:f openStack (List OpenElem))
  (:f rootElems (List tr/TreeElement)))

fn isVoidElement tag: String -> Bool
  (let [(t (stringLower tag))]
    (or (= t "area")
    (or (= t "base")
    (or (= t "br")
    (or (= t "col")
    (or (= t "embed")
    (or (= t "hr")
    (or (= t "img")
    (or (= t "input")
    (or (= t "link")
    (or (= t "meta")
    (or (= t "param")
    (or (= t "source")
    (or (= t "track")
        (= t "wbr")))))))))))))))

fn hasImpliedEndTag tag: String -> Bool
  (let [(t (stringLower tag))]
    (or (= t "p")
    (or (= t "li")
    (or (= t "dt")
    (or (= t "dd")
    (or (= t "tr")
    (or (= t "td")
    (or (= t "th")
    (or (= t "option")
    (or (= t "html")
    (or (= t "head")
        (= t "body"))))))))))))

fn pCloserStartTag? tag: String -> Bool
  (let [(t (stringLower tag))]
    (or (= t "p")
    (or (= t "div")
    (or (= t "h1")
    (or (= t "h2")
    (or (= t "h3")
    (or (= t "h4")
    (or (= t "h5")
    (or (= t "h6")
    (or (= t "ul")
    (or (= t "ol")
    (or (= t "li")
    (or (= t "dl")
    (or (= t "dt")
    (or (= t "dd")
    (or (= t "table")
    (or (= t "pre")
    (or (= t "blockquote")
    (or (= t "hr")
    (or (= t "address")
    (or (= t "article")
    (or (= t "aside")
    (or (= t "details")
    (or (= t "fieldset")
    (or (= t "figcaption")
    (or (= t "figure")
    (or (= t "footer")
    (or (= t "form")
    (or (= t "header")
    (or (= t "hgroup")
    (or (= t "main")
    (or (= t "menu")
    (or (= t "nav")
        (= t "section"))))))))))))))))))))))))))))))))))

fn liCloserStartTag? tag: String -> Bool
  (= (stringLower tag) "li")

fn dListCloserStartTag? tag: String -> Bool
  (let [(t (stringLower tag))]
    (or (= t "dt") (= t "dd")))

fn trCloserStartTag? tag: String -> Bool
  (= (stringLower tag) "tr")

fn cellCloserStartTag? tag: String -> Bool
  (let [(t (stringLower tag))]
    (or (= t "td") (or (= t "th") (= t "tr"))))

fn optionCloserStartTag? tag: String -> Bool
  (let [(t (stringLower tag))]
    (or (= t "option") (= t "optgroup")))

fn shouldCloseOnStartTag? topTag: String incomingTag: String -> Bool
  (cond
    ((= topTag "p") (pCloserStartTag? incomingTag))
    ((= topTag "li") (liCloserStartTag? incomingTag))
    ((or (= topTag "dt") (= topTag "dd")) (dListCloserStartTag? incomingTag))
    ((= topTag "tr") (trCloserStartTag? incomingTag))
    ((or (= topTag "td") (= topTag "th")) (cellCloserStartTag? incomingTag))
    ((= topTag "option") (optionCloserStartTag? incomingTag))
    (else false))

fn addTreeElement state: ParseState elem: tr/TreeElement -> ParseState
  (let [(stack state.openStack)
        (roots state.rootElems)]
    (mt (listHead stack)
      ((none)
       (ParseState :openStack (list) :rootElems (cons elem roots)))
      ((some top)
       (let [(updatedTop (OpenElem :tag top.tag
                                   :start top.start
                                   :children (cons elem top.children)
                                   :implied? top.implied?))
             (newStack (cons updatedTop (optionOr (listTail stack) (list))))]
         (ParseState :openStack newStack :rootElems roots)))))

fn closeTopImplicitly state: ParseState closeOffset: Int64 -> ParseState
  (let [(stack state.openStack)]
    (mt (listHead stack)
      ((none) state)
      ((some top)
       (let [(restStack (optionOr (listTail stack) (list)))
             (children (listReverse top.children))
             (elemNode (tr/makeNode (str "element:" top.tag) top.start closeOffset children))
             (stateWithoutTop (with state :openStack restStack))]
         (addTreeElement stateWithoutTop (tr/elemNode elemNode))))))

fn closeImpliedBeforeStartTag state: ParseState incomingTag: String startOffset: Int64 -> ParseState
  (let [(stack state.openStack)]
    (mt (listHead stack)
      ((none) state)
      ((some top)
       (if (shouldCloseOnStartTag? top.tag incomingTag)
         (let [(nextState (closeTopImplicitly state startOffset))]
           (closeImpliedBeforeStartTag nextState incomingTag startOffset))
         state))))

fn stackContainsTag? stack: (List OpenElem) targetTag: String -> Bool
  (mt (listHead stack)
    ((none) false)
    ((some top)
     (if (= top.tag targetTag)
       true
       (stackContainsTag? (optionOr (listTail stack) (list)) targetTag))))

fn unwindToTargetTag state: ParseState targetTag: String endTok: tr/Token -> ParseState
  (let [(stack state.openStack)]
    (mt (listHead stack)
      ((none) state)
      ((some top)
       (let [(restStack (optionOr (listTail stack) (list)))]
         (if (= top.tag targetTag)
           (let [(children (listReverse (cons (tr/elemToken endTok) top.children)))
                 (elemNode (tr/makeNode (str "element:" targetTag) top.start endTok.end children))
                 (stateWithoutTop (with state :openStack restStack))]
             (addTreeElement stateWithoutTop (tr/elemNode elemNode)))
           (let [(children (listReverse top.children))
                 (isImplied top.implied?)
                 (elemNode (if isImplied
                             (tr/makeNode (str "element:" top.tag) top.start endTok.start children)
                             (tr/makeErrorNode top.start endTok.start children)))
                 (stateWithoutTop (with state :openStack restStack))
                 (nextState (addTreeElement stateWithoutTop (tr/elemNode elemNode)))]
             (unwindToTargetTag nextState targetTag endTok)))))))

fn unwindStackAtEof state: ParseState totalLen: Int64 -> (List tr/TreeElement)
  (let [(stack state.openStack)]
    (mt (listHead stack)
      ((none) state.rootElems)
      ((some top)
       (let [(restStack (optionOr (listTail stack) (list)))
             (children (listReverse top.children))
             (isImplied top.implied?)
             (elemNode (if isImplied
                         (tr/makeNode (str "element:" top.tag) top.start totalLen children)
                         (tr/makeErrorNode top.start totalLen children)))
             (stateWithoutTop (with state :openStack restStack))
             (nextState (addTreeElement stateWithoutTop (tr/elemNode elemNode)))]
         (unwindStackAtEof nextState totalLen)))))

fn isTagDelimByte b: Int64 -> Bool
  (or (= b 32)
  (or (= b 9)
  (or (= b 10)
  (or (= b 13)
  (or (= b 47)
      (= b 62))))))

fn scanNameEndByte bs: Bytes len: Int64 idx: Int64 -> Int64
  (if (>= idx len)
    idx
    (let [(b (bytesGet bs idx))]
      (if (isTagDelimByte b)
        idx
        (scanNameEndByte bs len (+ idx 1)))))

fn sliceAsciiBytes bs: Bytes start: Int64 end: Int64 -> String
  (let [(len (- end start))]
    (if (<= len 0)
      ""
      (let [(table " !\"#$%&'()*+,-./0123456789:;<=>?@ABCDEFGHIJKLMNOPQRSTUVWXYZ[\\]^_`abcdefghijklmnopqrstuvwxyz{|}~")
            (chars (map (fn [(i Int64)] -> String
                          (let [(b (bytesGet bs (+ start i)))]
                            (if (and (>= b 32) (<= b 126))
                              (optionOr (stringSlice table (- b 32) (- b 31)) "")
                              "")))
                        (range 0 len)))]
        (stringLower (stringJoin chars "")))))

fn scanTagNameFromBytes bs: Bytes start: Int64 end: Int64 isEnd: Bool -> String
  (let [(nameStart (if isEnd (+ start 2) (+ start 1)))
        (nameEnd (scanNameEndByte bs end nameStart))]
    (sliceAsciiBytes bs nameStart nameEnd))

fn scanSelfClosingFromBytes bs: Bytes start: Int64 end: Int64 -> Bool
  (if (< (- end start) 3)
    false
    (and (= (bytesGet bs (- end 2)) 47)
         (= (bytesGet bs (- end 1)) 62)))

fn resolveTagName bs: Bytes tok: tr/Token textOpt: (Option String) isEnd: Bool -> String
  (mt textOpt
    ((some text)
     (if isEnd
       (hlx/endTagTokenName text tok)
       (hlx/tagTokenName text tok)))
    ((none)
     (scanTagNameFromBytes bs tok.start tok.end isEnd)))

fn resolveTagSelfClosing bs: Bytes tok: tr/Token textOpt: (Option String) -> Bool
  (mt textOpt
    ((some text)
     (hlx/tagTokenSelfClosing text tok))
    ((none)
     (scanSelfClosingFromBytes bs tok.start tok.end)))

fn parseTokensLoop toks: (List tr/Token) state: ParseState bs: Bytes textOpt: (Option String) totalLen: Int64 -> tr/Node
  (mt (listHead toks)
    ((none)
     (let [(roots (listReverse (unwindStackAtEof state totalLen)))]
       (tr/makeNode "document" 0 totalLen roots)))
    ((some tok)
     (let [(rest (optionOr (listTail toks) (list)))
           (k tok.kind)]
       (cond
         ((= k "startTag")
          (let [(tagName (resolveTagName bs tok textOpt false))
                (selfClosing (resolveTagSelfClosing bs tok textOpt))
                (isVoid (or (isVoidElement tagName) selfClosing))
                (stateAfterImplied (closeImpliedBeforeStartTag state tagName tok.start))]
            (if isVoid
              (let [(elemNode (tr/makeNode (str "element:" tagName) tok.start tok.end (list (tr/elemToken tok))))
                    (nextState (addTreeElement stateAfterImplied (tr/elemNode elemNode)))]
                (parseTokensLoop rest nextState bs textOpt totalLen))
              (let [(newTop (OpenElem :tag tagName
                                      :start tok.start
                                      :children (list (tr/elemToken tok))
                                      :implied? (hasImpliedEndTag tagName)))
                    (newStack (cons newTop stateAfterImplied.openStack))
                    (nextState (ParseState :openStack newStack :rootElems stateAfterImplied.rootElems))]
                (parseTokensLoop rest nextState bs textOpt totalLen)))))
         ((= k "endTag")
          (let [(tagName (resolveTagName bs tok textOpt true))]
            (if (isVoidElement tagName)
              (let [(errNode (tr/makeErrorNode tok.start tok.end (list (tr/elemToken tok))))
                    (nextState (addTreeElement state (tr/elemNode errNode)))]
                (parseTokensLoop rest nextState bs textOpt totalLen))
              (if (stackContainsTag? state.openStack tagName)
                (let [(nextState (unwindToTargetTag state tagName tok))]
                  (parseTokensLoop rest nextState bs textOpt totalLen))
                (let [(errNode (tr/makeErrorNode tok.start tok.end (list (tr/elemToken tok))))
                      (nextState (addTreeElement state (tr/elemNode errNode)))]
                  (parseTokensLoop rest nextState bs textOpt totalLen))))))
         ((= k "error")
          (let [(errNode (tr/makeErrorNode tok.start tok.end (list (tr/elemToken tok))))
                (nextState (addTreeElement state (tr/elemNode errNode)))]
            (parseTokensLoop rest nextState bs textOpt totalLen)))
         (else
          (let [(nextState (addTreeElement state (tr/elemToken tok)))]
            (parseTokensLoop rest nextState bs textOpt totalLen)))))))

fn parseInternal bs: Bytes len: Int64 textOpt: (Option String) -> tr/Node
  (if (= len 0)
    (tr/makeNode "document" 0 0 (list))
    (let [(toks (hlx/tokenizeBytes bs))
          (initialState (ParseState :openStack (list) :rootElems (list)))]
      (parseTokensLoop toks initialState bs textOpt len)))

fn parseHtml text: String -> tr/Node
  (let [(bs (stringToBytes text))
        (len (stringLength text))]
    (parseInternal bs len (some text)))

fn parseHtmlBytes bs: Bytes -> tr/Node
  (let [(len (bytesLength bs))]
    (parseInternal bs len (none)))

fn parse text: String -> tr/Node
  (parseHtml text)

fn parseBytes bs: Bytes -> tr/Node
  (parseHtmlBytes bs)

fn isWellFormed root: tr/Node -> Bool
  (not (sym/hasErrorNode root))

fn findFirstElement elems: (List tr/TreeElement) -> (Option tr/Node)
  (mt (listHead elems)
    ((none) (none))
    ((some elem)
     (mt elem
       ((elemToken _) (findFirstElement (optionOr (listTail elems) (list))))
       ((elemNode n)
        (if (stringStartsWith? (tr/nodeKind n) "element:")
          (some n)
          (findFirstElement (optionOr (listTail elems) (list))))))))

fn documentRootElement root: tr/Node -> (Option tr/Node)
  (findFirstElement (tr/nodeChildren root))

fn elementName node: tr/Node -> String
  (let [(k (tr/nodeKind node))]
    (if (stringStartsWith? k "element:")
      (optionOr (stringSlice k 8 (stringLength k)) "")
      ""))

fn filterElementChildren elems: (List tr/TreeElement) acc: (List tr/Node) -> (List tr/Node)
  (mt (listHead elems)
    ((none) (listReverse acc))
    ((some elem)
     (mt elem
       ((elemToken _) (filterElementChildren (optionOr (listTail elems) (list)) acc))
       ((elemNode n)
        (if (stringStartsWith? (tr/nodeKind n) "element:")
          (filterElementChildren (optionOr (listTail elems) (list)) (cons n acc))
          (filterElementChildren (optionOr (listTail elems) (list)) acc))))))

fn elementChildren node: tr/Node -> (List tr/Node)
  (filterElementChildren (tr/nodeChildren node) (list))

fn elementFirstTagToken node: tr/Node -> (Option tr/Token)
  (mt (listHead (tr/nodeChildren node))
    ((none) (none))
    ((some elem)
     (mt elem
       ((elemToken tok) (some tok))
       ((elemNode _) (none)))))

fn elementAttributes node: tr/Node text: String -> (List hlx/HtmlAttribute)
  (mt (elementFirstTagToken node)
    ((none) (list))
    ((some tok) (hlx/tagTokenAttrs text tok)))

fn attributeValue node: tr/Node text: String name: String -> (Option String)
  (mt (elementFirstTagToken node)
    ((none) (none))
    ((some tok) (hlx/tagTokenAttrValue text tok name)))

fn elementId node: tr/Node text: String -> (Option String)
  (attributeValue node text "id")

fn elementNameAttr node: tr/Node text: String -> (Option String)
  (attributeValue node text "name")


fn pathBasename p: String -> String
  (let [(parts (stringSplit p "/"))]
    (optionOr (listLast parts) p))

fn isHeadingTag tag: String -> Bool
  (or (= tag "h1")
  (or (= tag "h2")
  (or (= tag "h3")
  (or (= tag "h4")
  (or (= tag "h5")
      (= tag "h6"))))))

fn collectTextFromElem elem: tr/TreeElement text: String acc: (List String) -> (List String)
  (mt elem
    ((elemToken tok)
     (if (hlx/isCharacterToken tok)
       (cons (optionOr (stringSlice text tok.start tok.end) "") acc)
       acc))
    ((elemNode n)
     (fold (fn [(currAcc (List String)) (child tr/TreeElement)] -> (List String)
             (collectTextFromElem child text currAcc))
           acc
           (tr/nodeChildren n))))

fn elementTextContent node: tr/Node text: String -> String
  (let [(parts (collectTextFromElem (tr/elemNode node) text (list)))
        (joined (stringJoin (listReverse parts) ""))]
    (stringTrim joined))

fn collectNodeSymbols node: tr/Node text: String container: String depth: Int64 acc: (List sym/SymbolDef) -> (List sym/SymbolDef)
  (let [(k (tr/nodeKind node))]
    (if (not (stringStartsWith? k "element:"))
      acc
      (let [(tag (elementName node))
            (start (tr/nodeStart node))
            (end (tr/nodeEnd node))
            (idOpt (elementId node text))
            (nameOpt (elementNameAttr node text))
            (acc1 (mt idOpt
                    ((none) acc)
                    ((some idVal)
                     (if (stringEmpty? idVal)
                       acc
                       (cons (sym/makeScopedSymbolDef idVal "id" start end container depth) acc)))))
            (acc2 (mt nameOpt
                    ((none) acc1)
                    ((some nameVal)
                     (if (stringEmpty? nameVal)
                       acc1
                       (cons (sym/makeScopedSymbolDef nameVal "name" start end container depth) acc1)))))
            (acc3 (if (isHeadingTag tag)
                    (let [(hText (elementTextContent node text))
                          (hName (if (stringEmpty? hText) tag hText))]
                      (cons (sym/makeScopedSymbolDef hName "heading" start end container depth) acc2))
                    (if (= tag "script")
                      (let [(sName (mt idOpt
                                     ((some idVal) (if (stringEmpty? idVal) "script" idVal))
                                     ((none)
                                      (mt (attributeValue node text "src")
                                        ((some s) (let [(base (pathBasename s))] (if (stringEmpty? base) s base)))
                                        ((none) "script")))))]
                        (cons (sym/makeScopedSymbolDef sName "script" start end container depth) acc2))
                      (if (= tag "style")
                        (let [(stName (mt idOpt
                                        ((some idVal) (if (stringEmpty? idVal) "style" idVal))
                                        ((none) "style")))]
                          (cons (sym/makeScopedSymbolDef stName "style" start end container depth) acc2))
                        acc2))))
            (nextContainer (mt idOpt
                             ((some idVal) (if (stringEmpty? idVal) tag idVal))
                             ((none) tag)))
            (nextDepth (+ depth 1))
            (children (elementChildren node))]
        (fold (fn [(currAcc (List sym/SymbolDef)) (child tr/Node)] -> (List sym/SymbolDef)
                (collectNodeSymbols child text nextContainer nextDepth currAcc))
              acc3
              children))))

fn extractSymbols root: tr/Node text: String -> (List sym/SymbolDef)
  (let [(docChildren (elementChildren root))]
    (listReverse
      (fold (fn [(acc (List sym/SymbolDef)) (child tr/Node)] -> (List sym/SymbolDef)
              (collectNodeSymbols child text "" 0 acc))
            (list)
            docChildren)))

fn extractSymbolsFromText text: String -> (List sym/SymbolDef)
  (let [(root (parseHtml text))]
    (extractSymbols root text))

fn extractOutlineSymbols root: tr/Node text: String -> (List sym/SymbolDef)
  (extractSymbols root text)

fn formatOutline file: String text: String -> String
  (let [(root (parseHtml text))
        (syms (extractSymbols root text))
        (s (src/sourceFromString file text))]
    (out/formatOutlineReceipt file "html" syms s))
