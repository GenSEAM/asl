(module asl-syntax/html/embed
  :x [EmbeddedSymbol
      makeEmbeddedSymbol
      embeddedSymbolName
      embeddedSymbolKind
      embeddedSymbolStart
      embeddedSymbolEnd
      embeddedSymbolStartLine
      embeddedSymbolEndLine
      embeddedSymbolContainer
      embeddedSymbolDepth
      embeddedSymbolLang
      embeddedSymbolToSymbolDef
      rebaseToken
      rebaseElement
      rebaseNode
      scriptLanguage
      styleLanguage
      embedScriptChildren
      embedStyleChildren
      embedHtmlNode
      embedHtmlElement
      embedHtmlTree
      parseHtmlWithEmbedded
      parseEmbedded
      parse
      extractScriptSymbols!
      extractStyleSymbols
      extractEmbeddedSymbols!
      extractSymbols!
      extractSymbolsFromText!
      extractOutlineSymbols!
      formatOutline!]
  :i [(asl-syntax/core/source :a src)
      (asl-syntax/core/tree :a tr)
      (asl-syntax/core/print :a pr)
      (asl-syntax/core/symbols :a sym)
      (asl-syntax/core/outline :a out)
      (asl-syntax/registry :a reg)
      (asl-syntax/html/lex :a hlx)
      (asl-syntax/html/tree :a htr)
      (asl-syntax/css/rules :a css)
      (asl-syntax/js/module :a jsm)
      (asl-syntax/js/symbols :a jss)])

(schema EmbeddedSymbol
  (:f name String)
  (:f kind String)
  (:f start Int64)
  (:f end Int64)
  (:f startLine Int64)
  (:f endLine Int64)
  (:f container String)
  (:f depth Int64)
  (:f lang String))

fn makeEmbeddedSymbol name: String kind: String start: Int64 end: Int64 startLine: Int64 endLine: Int64 container: String depth: Int64 lang: String -> EmbeddedSymbol
  (EmbeddedSymbol :name name :kind kind :start start :end end :startLine startLine :endLine endLine :container container :depth depth :lang lang)

fn embeddedSymbolName s: EmbeddedSymbol -> String
  s.name

fn embeddedSymbolKind s: EmbeddedSymbol -> String
  s.kind

fn embeddedSymbolStart s: EmbeddedSymbol -> Int64
  s.start

fn embeddedSymbolEnd s: EmbeddedSymbol -> Int64
  s.end

fn embeddedSymbolStartLine s: EmbeddedSymbol -> Int64
  s.startLine

fn embeddedSymbolEndLine s: EmbeddedSymbol -> Int64
  s.endLine

fn embeddedSymbolContainer s: EmbeddedSymbol -> String
  s.container

fn embeddedSymbolDepth s: EmbeddedSymbol -> Int64
  s.depth

fn embeddedSymbolLang s: EmbeddedSymbol -> String
  s.lang

fn embeddedSymbolToSymbolDef s: EmbeddedSymbol -> sym/SymbolDef
  (sym/makeScopedSymbolDef s.name s.kind s.start s.end s.container s.depth)

fn rebaseToken tok: tr/Token off: Int64 -> tr/Token
  (tr/makeToken (tr/tokenKind tok) (+ (tr/tokenStart tok) off) (+ (tr/tokenEnd tok) off))

fn rebaseElement elem: tr/TreeElement off: Int64 -> tr/TreeElement
  (mt elem
    ((tr/elemToken tok) (tr/elemToken (rebaseToken tok off)))
    ((tr/elemNode node) (tr/elemNode (rebaseNode node off))))

fn rebaseNode node: tr/Node off: Int64 -> tr/Node
  (let [(newStart (+ (tr/nodeStart node) off))
        (newEnd (+ (tr/nodeEnd node) off))
        (newChildren (map (fn [(child tr/TreeElement)] -> tr/TreeElement (rebaseElement child off))
                          (tr/nodeChildren node)))]
    (if (tr/isErrorNode node)
      (tr/makeErrorNode newStart newEnd newChildren)
      (tr/makeNode (tr/nodeKind node) newStart newEnd newChildren)))

fn scriptLanguage node: tr/Node text: String -> String
  (let [(typeOpt (htr/attributeValue node text "type"))]
    (mt typeOpt
      ((none) "javascript")
      ((some tVal)
       (let [(trimmed (stringLower (stringTrim tVal)))]
         (if (or (= trimmed "application/ld+json")
             (or (= trimmed "application/json")
             (or (= trimmed "importmap")
                 (stringContains? trimmed "json"))))
           "json"
           (let [(regLang (reg/languageByHtmlType trimmed))]
             (if (stringEmpty? regLang)
               "javascript"
               regLang)))))))

fn styleLanguage node: tr/Node text: String -> String
  (let [(typeOpt (htr/attributeValue node text "type"))]
    (mt typeOpt
      ((none) "css")
      ((some tVal)
       (let [(trimmed (stringLower (stringTrim tVal)))
             (regLang (reg/languageByHtmlType trimmed))]
         (if (stringEmpty? regLang)
           "css"
           regLang)))))

fn embedScriptChildren children: (List tr/TreeElement) text: String lang: String acc: (List tr/TreeElement) -> (List tr/TreeElement)
  (if (listEmpty? children)
    (listReverse acc)
    (let [(hd (optionOr (listHead children) (tr/elemToken (tr/makeToken "" 0 0))))
          (tl (optionOr (listTail children) (list)))]
      (mt hd
        ((tr/elemToken tok)
         (let [(k (tr/tokenKind tok))]
           (if (or (= k "scriptData") (or (= k "rawtext") (= k "character")))
             (let [(st (tr/tokenStart tok))
                   (en (tr/tokenEnd tok))
                   (content (optionOr (stringSlice text st en) ""))]
               (cond
                 ((= lang "javascript")
                  (mt (jsm/parse content)
                    ((ok jsTree)
                     (let [(rebased (rebaseNode jsTree st))]
                       (embedScriptChildren tl text lang (cons (tr/elemNode rebased) acc))))
                    ((err msg)
                     (let [(errTok (tr/makeToken "error" st en))
                           (errNode (tr/makeErrorNode st en (list (tr/elemToken errTok))))]
                       (embedScriptChildren tl text lang (cons (tr/elemNode errNode) acc))))))
                 ((= lang "css")
                  (let [(cssTree (css/parseStylesheet content))
                        (rebased (rebaseNode cssTree st))]
                    (embedScriptChildren tl text lang (cons (tr/elemNode rebased) acc))))
                 (else
                  (embedScriptChildren tl text lang (cons hd acc)))))
             (embedScriptChildren tl text lang (cons hd acc)))))
        ((tr/elemNode n)
         (let [(embeddedChild (embedHtmlNode n text))]
           (embedScriptChildren tl text lang (cons (tr/elemNode embeddedChild) acc)))))))

fn embedStyleChildren children: (List tr/TreeElement) text: String lang: String acc: (List tr/TreeElement) -> (List tr/TreeElement)
  (if (listEmpty? children)
    (listReverse acc)
    (let [(hd (optionOr (listHead children) (tr/elemToken (tr/makeToken "" 0 0))))
          (tl (optionOr (listTail children) (list)))]
      (mt hd
        ((tr/elemToken tok)
         (let [(k (tr/tokenKind tok))]
           (if (or (= k "rawtext") (or (= k "scriptData") (= k "character")))
             (let [(st (tr/tokenStart tok))
                   (en (tr/tokenEnd tok))
                   (content (optionOr (stringSlice text st en) ""))]
               (if (= lang "css")
                 (let [(cssTree (css/parseStylesheet content))
                       (rebased (rebaseNode cssTree st))]
                   (embedStyleChildren tl text lang (cons (tr/elemNode rebased) acc)))
                 (embedStyleChildren tl text lang (cons hd acc))))
             (embedStyleChildren tl text lang (cons hd acc)))))
        ((tr/elemNode n)
         (let [(embeddedChild (embedHtmlNode n text))]
           (embedStyleChildren tl text lang (cons (tr/elemNode embeddedChild) acc)))))))

fn embedHtmlNode node: tr/Node text: String -> tr/Node
  (let [(k (tr/nodeKind node))]
    (cond
      ((= k "element:script")
       (let [(lang (scriptLanguage node text))
             (newChildren (embedScriptChildren (tr/nodeChildren node) text lang (list)))]
         (tr/makeNode k (tr/nodeStart node) (tr/nodeEnd node) newChildren)))
      ((= k "element:style")
       (let [(lang (styleLanguage node text))
             (newChildren (embedStyleChildren (tr/nodeChildren node) text lang (list)))]
         (tr/makeNode k (tr/nodeStart node) (tr/nodeEnd node) newChildren)))
      (else
       (let [(newChildren (map (fn [(child tr/TreeElement)] -> tr/TreeElement
                                 (embedHtmlElement child text))
                               (tr/nodeChildren node)))]
         (if (tr/isErrorNode node)
           (tr/makeErrorNode (tr/nodeStart node) (tr/nodeEnd node) newChildren)
           (tr/makeNode k (tr/nodeStart node) (tr/nodeEnd node) newChildren))))))

fn embedHtmlElement elem: tr/TreeElement text: String -> tr/TreeElement
  (mt elem
    ((tr/elemToken tok) elem)
    ((tr/elemNode node) (tr/elemNode (embedHtmlNode node text))))

fn embedHtmlTree root: tr/Node text: String -> tr/Node
  (embedHtmlNode root text)

fn parseHtmlWithEmbedded text: String -> tr/Node
  (let [(baseTree (htr/parseHtml text))]
    (embedHtmlTree baseTree text))

fn parseEmbedded text: String -> tr/Node
  (parseHtmlWithEmbedded text)

fn parse text: String -> tr/Node
  (parseHtmlWithEmbedded text)

fn nodeContainerName node: tr/Node text: String -> String
  (let [(tag (htr/elementName node))
        (idOpt (htr/elementId node text))]
    (mt idOpt
      ((some idVal) (if (stringEmpty? idVal) tag idVal))
      ((none) tag)))

fn extractScriptChildSymbols! children: (List tr/TreeElement) text: String sFile: src/Source container: String depth: Int64 acc: (List EmbeddedSymbol) -> (List EmbeddedSymbol)
  (if (listEmpty? children)
    acc
    (let [(hd (optionOr (listHead children) (tr/elemToken (tr/makeToken "" 0 0))))
          (tl (optionOr (listTail children) (list)))]
      (mt hd
        ((tr/elemToken tok)
         (let [(k (tr/tokenKind tok))]
           (if (or (= k "scriptData") (or (= k "rawtext") (= k "character")))
             (let [(st (tr/tokenStart tok))
                   (en (tr/tokenEnd tok))
                   (content (optionOr (stringSlice text st en) ""))]
               (if (stringEmpty? (stringTrim content))
                 (extractScriptChildSymbols! tl text sFile container depth acc)
                 (let [(rawJsSyms (jss/extractSymbols! content))
                       (converted (map (fn [(jsSym jss/JsSymbol)] -> EmbeddedSymbol
                                         (let [(fStart (+ (jss/jsSymbolStart jsSym) st))
                                               (fEnd (+ (jss/jsSymbolEnd jsSym) st))
                                               (stLine (optionOr (src/sourceLineAt sFile fStart) (jss/jsSymbolStartLine jsSym)))
                                               (lastChar (if (> fEnd fStart) (- fEnd 1) fStart))
                                               (enLine (optionOr (src/sourceLineAt sFile lastChar) stLine))]
                                           (EmbeddedSymbol :name (jss/jsSymbolName jsSym)
                                                           :kind (jss/jsSymbolKind jsSym)
                                                           :start fStart
                                                           :end fEnd
                                                           :startLine stLine
                                                           :endLine enLine
                                                           :container container
                                                           :depth depth
                                                           :lang "javascript")))
                                       rawJsSyms))]
                   (extractScriptChildSymbols! tl text sFile container depth (listAppend (listReverse converted) acc)))))
             (extractScriptChildSymbols! tl text sFile container depth acc))))
        ((tr/elemNode n)
         (let [(st (tr/nodeStart n))
               (en (tr/nodeEnd n))
               (content (optionOr (stringSlice text st en) ""))]
           (if (stringEmpty? (stringTrim content))
             (extractScriptChildSymbols! tl text sFile container depth acc)
             (let [(rawJsSyms (jss/extractSymbols! content))
                   (converted (map (fn [(jsSym jss/JsSymbol)] -> EmbeddedSymbol
                                     (let [(fStart (+ (jss/jsSymbolStart jsSym) st))
                                           (fEnd (+ (jss/jsSymbolEnd jsSym) st))
                                           (stLine (optionOr (src/sourceLineAt sFile fStart) (jss/jsSymbolStartLine jsSym)))
                                           (lastChar (if (> fEnd fStart) (- fEnd 1) fStart))
                                           (enLine (optionOr (src/sourceLineAt sFile lastChar) stLine))]
                                       (EmbeddedSymbol :name (jss/jsSymbolName jsSym)
                                                       :kind (jss/jsSymbolKind jsSym)
                                                       :start fStart
                                                       :end fEnd
                                                       :startLine stLine
                                                       :endLine enLine
                                                       :container container
                                                       :depth depth
                                                       :lang "javascript")))
                                   rawJsSyms))]
               (extractScriptChildSymbols! tl text sFile container depth (listAppend (listReverse converted) acc)))))))))

fn extractScriptSymbols! node: tr/Node text: String sFile: src/Source container: String depth: Int64 -> (List EmbeddedSymbol)
  (let [(lang (scriptLanguage node text))]
    (if (= lang "javascript")
      (listReverse (extractScriptChildSymbols! (tr/nodeChildren node) text sFile container depth (list)))
      (list)))

fn extractStyleSymbols node: tr/Node text: String sFile: src/Source container: String depth: Int64 -> (List EmbeddedSymbol)
  (let [(lang (styleLanguage node text))]
    (if (= lang "css")
      (let [(children (tr/nodeChildren node))]
        (listReverse
          (fold (fn [(acc (List EmbeddedSymbol)) (child tr/TreeElement)] -> (List EmbeddedSymbol)
                  (mt child
                    ((tr/elemToken tok)
                     (let [(k (tr/tokenKind tok))]
                       (if (or (= k "rawtext") (or (= k "character") (= k "scriptData")))
                         (let [(st (tr/tokenStart tok))
                               (en (tr/tokenEnd tok))
                               (content (optionOr (stringSlice text st en) ""))]
                           (if (stringEmpty? (stringTrim content))
                             acc
                             (let [(cssTree (css/parseStylesheet content))
                                   (rebased (rebaseNode cssTree st))
                                   (cssSyms (css/extractSymbols rebased text))
                                   (converted (map (fn [(cs sym/SymbolDef)] -> EmbeddedSymbol
                                                     (let [(fStart (sym/symbolStart cs))
                                                           (fEnd (sym/symbolEnd cs))
                                                           (stLine (optionOr (src/sourceLineAt sFile fStart) 1))
                                                           (lastChar (if (> fEnd fStart) (- fEnd 1) fStart))
                                                           (enLine (optionOr (src/sourceLineAt sFile lastChar) stLine))]
                                                       (EmbeddedSymbol :name (sym/symbolName cs)
                                                                       :kind (sym/symbolKind cs)
                                                                       :start fStart
                                                                       :end fEnd
                                                                       :startLine stLine
                                                                       :endLine enLine
                                                                       :container container
                                                                       :depth depth
                                                                       :lang "css")))
                                                   cssSyms))]
                               (listAppend (listReverse converted) acc))))
                         acc)))
                    ((tr/elemNode n)
                     (let [(cssSyms (css/extractSymbols n text))
                           (converted (map (fn [(cs sym/SymbolDef)] -> EmbeddedSymbol
                                             (let [(fStart (sym/symbolStart cs))
                                                   (fEnd (sym/symbolEnd cs))
                                                   (stLine (optionOr (src/sourceLineAt sFile fStart) 1))
                                                   (lastChar (if (> fEnd fStart) (- fEnd 1) fStart))
                                                   (enLine (optionOr (src/sourceLineAt sFile lastChar) stLine))]
                                               (EmbeddedSymbol :name (sym/symbolName cs)
                                                               :kind (sym/symbolKind cs)
                                                               :start fStart
                                                               :end fEnd
                                                               :startLine stLine
                                                               :endLine enLine
                                                               :container container
                                                               :depth depth
                                                               :lang "css")))
                                           cssSyms))]
                       (listAppend (listReverse converted) acc)))))
                (list)
                children)))
      (list)))

fn collectEmbeddedSymbols! node: tr/Node text: String sFile: src/Source container: String depth: Int64 acc: (List EmbeddedSymbol) -> (List EmbeddedSymbol)
  (let [(k (tr/nodeKind node))]
    (if (not (stringStartsWith? k "element:"))
      (let [(children (htr/elementChildren node))]
        (fold (fn [(curr (List EmbeddedSymbol)) (ch tr/Node)] -> (List EmbeddedSymbol)
                (collectEmbeddedSymbols! ch text sFile container depth curr))
              acc
              children))
      (let [(tag (htr/elementName node))
            (cont (nodeContainerName node text))]
        (cond
          ((= tag "script")
           (let [(syms (extractScriptSymbols! node text sFile cont (+ depth 1)))]
             (listAppend (listReverse syms) acc)))
          ((= tag "style")
           (let [(syms (extractStyleSymbols node text sFile cont (+ depth 1)))]
             (listAppend (listReverse syms) acc)))
          (else
           (let [(children (htr/elementChildren node))]
             (fold (fn [(curr (List EmbeddedSymbol)) (ch tr/Node)] -> (List EmbeddedSymbol)
                     (collectEmbeddedSymbols! ch text sFile cont (+ depth 1) curr))
                   acc
                   children)))))))

fn extractEmbeddedSymbols! root: tr/Node text: String -> (List EmbeddedSymbol)
  (let [(sFile (src/sourceFromString "" text))
        (docChildren (htr/elementChildren root))]
    (listReverse
      (fold (fn [(acc (List EmbeddedSymbol)) (ch tr/Node)] -> (List EmbeddedSymbol)
              (collectEmbeddedSymbols! ch text sFile "" 0 acc))
            (list)
            docChildren)))

fn symbolSortBefore? a: sym/SymbolDef b: sym/SymbolDef -> Bool
  (if (< (sym/symbolStart a) (sym/symbolStart b))
    true
    (if (> (sym/symbolStart a) (sym/symbolStart b))
      false
      (> (sym/symbolEnd a) (sym/symbolEnd b))))

fn mergeSymbolLists left: (List sym/SymbolDef) right: (List sym/SymbolDef) acc: (List sym/SymbolDef) -> (List sym/SymbolDef)
  (mt (listHead left)
    ((none) (listAppend (listReverse acc) right))
    ((some lhd)
     (mt (listHead right)
       ((none) (listAppend (listReverse acc) left))
       ((some rhd)
        (if (symbolSortBefore? lhd rhd)
          (mergeSymbolLists (optionOr (listTail left) (list)) right (cons lhd acc))
          (mergeSymbolLists left (optionOr (listTail right) (list)) (cons rhd acc)))))))

fn sortSymbols syms: (List sym/SymbolDef) -> (List sym/SymbolDef)
  (let [(n (listLength syms))]
    (if (<= n 1)
      syms
      (let [(mid (/ n 2))
            (left (sortSymbols (listTake syms mid)))
            (right (sortSymbols (listDrop syms mid)))]
        (mergeSymbolLists left right (list)))))

fn extractSymbols! root: tr/Node text: String -> (List sym/SymbolDef)
  (let [(htmlSyms (htr/extractSymbols root text))
        (embSyms (extractEmbeddedSymbols! root text))
        (embDefs (map (fn [(s EmbeddedSymbol)] -> sym/SymbolDef (embeddedSymbolToSymbolDef s)) embSyms))
        (allSyms (listAppend htmlSyms embDefs))]
    (sortSymbols allSyms))

fn extractSymbolsFromText! text: String -> (List sym/SymbolDef)
  (let [(root (parseHtmlWithEmbedded text))]
    (extractSymbols! root text))

fn extractOutlineSymbols! root: tr/Node text: String -> (List sym/SymbolDef)
  (extractSymbols! root text)

fn formatOutline! file: String text: String -> String
  (let [(root (parseHtmlWithEmbedded text))
        (syms (extractSymbols! root text))
        (s (src/sourceFromString file text))]
    (out/formatOutlineReceipt file "html" syms s))
