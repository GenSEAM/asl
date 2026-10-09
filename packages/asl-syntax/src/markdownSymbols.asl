(module asl-syntax/markdownSymbols
  :x [MarkdownHeadingSymbol
      MarkdownFence
      makeMarkdownFence
      headingSymbolName
      headingSymbolKind
      headingSymbolLevel
      headingSymbolPath
      headingSymbolContainer
      headingSymbolDepth
      headingSymbolStart
      headingSymbolEnd
      headingSymbolHeadingStart
      headingSymbolHeadingEnd
      headingSymbolStartLine
      headingSymbolEndLine
      fenceInfo
      fenceLanguage
      fenceStart
      fenceEnd
      fenceContentStart
      fenceContentEnd
      fenceContent
      fenceSubtree
      hasFenceSubtree?
      markdownHeadingSymbols
      markdownSymbols
      markdownSymbolsFromRoot
      markdownOutlineItems
      markdownOutlineReceipt
      resolveHeadingSymbol
      resolveSection
      findSectionByPath
      findHeadingSymbol
      findSymbol
      markdownReadSymbol
      markdownReadSymbolReceipt
      cleanHeadingQuery
      splitHeadingQuery
      extractFences
      delegateFence
      delegateMarkdownFences
      markdownFences
      delegateFenceNode
      delegateMarkdownTree]
  :i [(asl-syntax/core/source :a src)
      (asl-syntax/core/tree :a tr)
      (asl-syntax/core/symbols :a sym)
      (asl-syntax/core/outline :a out)
      (asl-syntax/registry :a reg)
      (asl-syntax/markdown :a md)
      (asl-syntax/json :a jcst)])

(schema HeadingFrame
  (:f level Int64)
  (:f title String)
  (:f path String)
  (:f depth Int64))

(schema MarkdownHeadingSymbol
  (:f name String)
  (:f kind String)
  (:f level Int64)
  (:f path String)
  (:f container String)
  (:f depth Int64)
  (:f start Int64)
  (:f end Int64)
  (:f headingStart Int64)
  (:f headingEnd Int64)
  (:f startLine Int64)
  (:f endLine Int64))

(schema MarkdownFence
  (:f info String)
  (:f language String)
  (:f start Int64)
  (:f end Int64)
  (:f contentStart Int64)
  (:f contentEnd Int64)
  (:f content String)
  (:f subtree (Option tr/Node)))

fn makeMarkdownFence info: String language: String start: Int64 end: Int64 contentStart: Int64 contentEnd: Int64 content: String subtree: (Option tr/Node) -> MarkdownFence
  (MarkdownFence :info info :language language :start start :end end :contentStart contentStart :contentEnd contentEnd :content content :subtree subtree)

fn headingSymbolName h: MarkdownHeadingSymbol -> String
  h.name

fn headingSymbolKind h: MarkdownHeadingSymbol -> String
  h.kind

fn headingSymbolLevel h: MarkdownHeadingSymbol -> Int64
  h.level

fn headingSymbolPath h: MarkdownHeadingSymbol -> String
  h.path

fn headingSymbolContainer h: MarkdownHeadingSymbol -> String
  h.container

fn headingSymbolDepth h: MarkdownHeadingSymbol -> Int64
  h.depth

fn headingSymbolStart h: MarkdownHeadingSymbol -> Int64
  h.start

fn headingSymbolEnd h: MarkdownHeadingSymbol -> Int64
  h.end

fn headingSymbolHeadingStart h: MarkdownHeadingSymbol -> Int64
  h.headingStart

fn headingSymbolHeadingEnd h: MarkdownHeadingSymbol -> Int64
  h.headingEnd

fn headingSymbolStartLine h: MarkdownHeadingSymbol -> Int64
  h.startLine

fn headingSymbolEndLine h: MarkdownHeadingSymbol -> Int64
  h.endLine

fn fenceInfo f: MarkdownFence -> String
  f.info

fn fenceLanguage f: MarkdownFence -> String
  f.language

fn fenceStart f: MarkdownFence -> Int64
  f.start

fn fenceEnd f: MarkdownFence -> Int64
  f.end

fn fenceContentStart f: MarkdownFence -> Int64
  f.contentStart

fn fenceContentEnd f: MarkdownFence -> Int64
  f.contentEnd

fn fenceContent f: MarkdownFence -> String
  f.content

fn fenceSubtree f: MarkdownFence -> (Option tr/Node)
  f.subtree

fn hasFenceSubtree? f: MarkdownFence -> Bool
  (some? f.subtree)

fn headingSymbolToSymbolDef h: MarkdownHeadingSymbol -> sym/SymbolDef
  (sym/makeScopedSymbolDef h.name h.kind h.start h.end h.container h.depth)

fn popStack stack: (List HeadingFrame) level: Int64 -> (List HeadingFrame)
  (if (listEmpty? stack)
    (list)
    (let [(hd (optionOr (listHead stack) (HeadingFrame :level 0 :title "" :path "" :depth 0)))
          (tl (optionOr (listTail stack) (list)))]
      (if (>= hd.level level)
        (popStack tl level)
        stack)))

fn buildSymbolsLoop secs: (List md/MarkdownSection) s: src/Source stack: (List HeadingFrame) acc: (List MarkdownHeadingSymbol) -> (List MarkdownHeadingSymbol)
  (if (listEmpty? secs)
    (listReverse acc)
    (let [(sec (optionOr (listHead secs) (md/MarkdownSection :title "" :level 0 :kind "" :start 0 :end 0 :headingStart 0 :headingEnd 0 :startLine 0 :endLine 0)))
          (rest (optionOr (listTail secs) (list)))
          (lvl sec.level)
          (title sec.title)
          (popped (popStack stack lvl))
          (hasParent? (not (listEmpty? popped)))
          (parent (if hasParent?
                    (optionOr (listHead popped) (HeadingFrame :level 0 :title "" :path "" :depth 0))
                    (HeadingFrame :level 0 :title "" :path "" :depth 0)))
          (container (if hasParent? parent.title ""))
          (parentPath (if hasParent? parent.path ""))
          (depth (if hasParent? (+ parent.depth 1) 0))
          (fullPath (if hasParent? (str parentPath "/" title) title))
          (stLine (optionOr (src/sourceLineAt s sec.start) 1))
          (lastOff (if (> sec.end sec.start) (- sec.end 1) sec.start))
          (enLine (optionOr (src/sourceLineAt s lastOff) stLine))
          (sym (MarkdownHeadingSymbol :name title
                                      :kind "section"
                                      :level lvl
                                      :path fullPath
                                      :container container
                                      :depth depth
                                      :start sec.start
                                      :end sec.end
                                      :headingStart sec.headingStart
                                      :headingEnd sec.headingEnd
                                      :startLine stLine
                                      :endLine enLine))
          (newFrame (HeadingFrame :level lvl :title title :path fullPath :depth depth))
          (newStack (cons newFrame popped))]
      (buildSymbolsLoop rest s newStack (cons sym acc))))

fn markdownHeadingSymbols text: String -> (List MarkdownHeadingSymbol)
  (let [(root (md/parseMarkdown text))
        (secs (md/markdownSections root text))
        (s (src/sourceFromString "" text))]
    (buildSymbolsLoop secs s (list) (list)))

fn markdownSymbols text: String -> (List sym/SymbolDef)
  (map (fn [(h MarkdownHeadingSymbol)] -> sym/SymbolDef (headingSymbolToSymbolDef h))
       (markdownHeadingSymbols text))

fn markdownSymbolsFromRoot root: tr/Node text: String -> (List sym/SymbolDef)
  (markdownSymbols text)

fn markdownOutlineItems root: tr/Node s: src/Source text: String -> (List out/OutlineItem)
  (let [(syms (markdownHeadingSymbols text))]
    (map (fn [(h MarkdownHeadingSymbol)] -> out/OutlineItem
           (out/makeOutlineItem h.name h.kind h.startLine h.endLine))
         syms))

fn markdownOutlineReceipt file: String text: String -> String
  (let [(s (src/sourceFromString file text))
        (symDefs (markdownSymbols text))]
    (out/formatOutlineReceipt file "markdown" symDefs s))

fn stripLeadingHashes bs: Bytes len: Int64 idx: Int64 text: String -> String
  (if (>= idx len)
    ""
    (if (or (= (bytesGet bs idx) 35) (or (= (bytesGet bs idx) 32) (= (bytesGet bs idx) 9)))
      (stripLeadingHashes bs len (+ idx 1) text)
      (optionOr (stringSlice text idx len) "")))

fn cleanSegment s: String -> String
  (let [(trimmed (stringTrim s))]
    (if (stringStartsWith? trimmed "#")
      (stringTrim (stripLeadingHashes (stringToBytes trimmed) (stringLength trimmed) 0 trimmed))
      trimmed))

fn cleanHeadingQuery q: String -> String
  (let [(trimmed (stringTrim q))
        (noColon (if (and (stringStartsWith? trimmed ":") (> (stringLength trimmed) 1))
                   (optionOr (stringSlice trimmed 1 (stringLength trimmed)) trimmed)
                   trimmed))]
    (cleanSegment noColon))

fn splitHeadingQuery q: String -> (List String)
  (let [(cleanQ (cleanHeadingQuery q))]
    (if (stringContains? cleanQ "/")
      (let [(rawParts (stringSplit cleanQ "/"))]
        (filter (fn [(part String)] -> Bool (not (stringEmpty? part)))
                (map (fn [(part String)] -> String (cleanSegment part)) rawParts)))
      (if (stringContains? cleanQ ".")
        (let [(rawParts (stringSplit cleanQ "."))]
          (filter (fn [(part String)] -> Bool (not (stringEmpty? part)))
                  (map (fn [(part String)] -> String (cleanSegment part)) rawParts)))
        (list cleanQ))))

fn matchesTitle? actual: String query: String -> Bool
  (or (= actual query)
      (= (stringLower (stringTrim actual)) (stringLower (stringTrim query))))

fn isAncestorSubsequence? qParts: (List String) aParts: (List String) -> Bool
  (if (listEmpty? qParts)
    true
    (if (listEmpty? aParts)
      false
      (let [(qHead (optionOr (listHead qParts) ""))
            (qTail (optionOr (listTail qParts) (list)))
            (aHead (optionOr (listHead aParts) ""))
            (aTail (optionOr (listTail aParts) (list)))]
        (if (matchesTitle? aHead qHead)
          (isAncestorSubsequence? qTail aTail)
          (isAncestorSubsequence? qParts aTail)))))

fn headingMatchesQuery? h: MarkdownHeadingSymbol queryParts: (List String) -> Bool
  (let [(qLen (listLength queryParts))]
    (cond
      ((= qLen 0) false)
      ((= qLen 1)
       (let [(target (optionOr (listHead queryParts) ""))]
         (matchesTitle? h.name target)))
      (else
       (let [(target (optionOr (listGet queryParts (- qLen 1)) ""))
             (targetMatches? (matchesTitle? h.name target))]
         (if (not targetMatches?)
           false
           (let [(symParts (stringSplit h.path "/"))
                 (sLen (listLength symParts))
                 (ancestorSyms (if (> sLen 1) (listTake symParts (- sLen 1)) (list)))
                 (ancestorQueries (listTake queryParts (- qLen 1)))]
             (isAncestorSubsequence? ancestorQueries ancestorSyms)))))))

fn filterHeadings syms: (List MarkdownHeadingSymbol) queryParts: (List String) -> (List MarkdownHeadingSymbol)
  (filter (fn [(h MarkdownHeadingSymbol)] -> Bool (headingMatchesQuery? h queryParts)) syms)

fn resolveHeadingSymbol text: String query: String -> (Result MarkdownHeadingSymbol String)
  (let [(qParts (splitHeadingQuery query))]
    (if (listEmpty? qParts)
      (err (str "heading not found: " query))
      (let [(allSyms (markdownHeadingSymbols text))
            (matches (filterHeadings allSyms qParts))
            (cnt (listLength matches))]
        (cond
          ((= cnt 0)
           (err (str "heading not found: " query)))
          ((> cnt 1)
           (err (str "ambiguous heading: " (stringFromInt64 cnt) " occurrences of " query)))
          (else
           (ok (optionOr (listHead matches)
                         (MarkdownHeadingSymbol :name "" :kind "" :level 0 :path "" :container "" :depth 0 :start 0 :end 0 :headingStart 0 :headingEnd 0 :startLine 0 :endLine 0))))))))

fn resolveSection text: String query: String -> (Result md/MarkdownSection String)
  (mt (resolveHeadingSymbol text query)
    ((err msg) (err msg))
    ((ok sym)
     (ok (md/MarkdownSection :title sym.name
                             :level sym.level
                             :kind sym.kind
                             :start sym.start
                             :end sym.end
                             :headingStart sym.headingStart
                             :headingEnd sym.headingEnd
                             :startLine sym.startLine
                             :endLine sym.endLine))))

fn findSectionByPath text: String query: String -> (Result md/MarkdownSection String)
  (resolveSection text query)

fn findHeadingSymbol text: String query: String -> (Result MarkdownHeadingSymbol String)
  (resolveHeadingSymbol text query)

fn findSymbol text: String query: String -> (Result sym/SymbolDef String)
  (mt (resolveHeadingSymbol text query)
    ((err msg) (err msg))
    ((ok sym) (ok (headingSymbolToSymbolDef sym))))

fn markdownReadSymbol text: String query: String -> (Result String String)
  (mt (resolveHeadingSymbol text query)
    ((err msg) (err msg))
    ((ok sym)
     (ok (optionOr (stringSlice text sym.start sym.end) ""))))

fn markdownReadSymbolReceipt file: String text: String query: String -> String
  (mt (resolveHeadingSymbol text query)
    ((err msg)
     (if (stringContains? msg "ambiguous")
       (let [(matches (filterHeadings (markdownHeadingSymbols text) (splitHeadingQuery query)))
             (cnt (listLength matches))]
         (str "(:read :status :rejected :error ERR_AMBIGUOUS_SYMBOL :file \"" (out/escapeAsnValue file)
              "\" :symbol \"" (out/escapeAsnValue query) "\" :count " (stringFromInt64 cnt)
              " :message \"" (out/escapeAsnValue msg) "\" :language \"markdown\")"))
       (str "(:read :status :rejected :error ERR_SYMBOL_NOT_FOUND :file \"" (out/escapeAsnValue file)
            "\" :symbol \"" (out/escapeAsnValue query) "\" :language \"markdown\")")))
    ((ok sym)
     (let [(content (optionOr (stringSlice text sym.start sym.end) ""))]
       (str "(:read :file \"" (out/escapeAsnValue file) "\" :symbol \"" (out/escapeAsnValue query)
            "\" :kind \"section\" :language \"markdown\" :start " (stringFromInt64 sym.startLine)
            " :end " (stringFromInt64 sym.endLine) " :content \"" (out/escapeAsnValue content) "\")"))))

fn extractFenceFromNode node: tr/Node text: String -> (Option MarkdownFence)
  (let [(elems node.children)]
    (if (listEmpty? elems)
      (none)
      (let [(firstElem (optionOr (listHead elems) (tr/elemToken (tr/Token :kind "" :start 0 :end 0))))
            (s0 (tr/elementStart firstElem))
            (e0 (tr/elementEnd firstElem))
            (firstLine (optionOr (stringSlice text s0 e0) ""))
            (fcPairOpt (md/isFencedCodeStart? firstLine))]
        (mt fcPairOpt
          ((none) (none))
          ((some fcPair)
           (let [(fenceChar (pairFirst fcPair))
                 (rawInfo (pairSecond fcPair))
                 (lang (reg/languageByMarkdownInfo rawInfo))
                 (cStart e0)
                 (numElems (listLength elems))
                 (lastElem (optionOr (listGet elems (- numElems 1)) firstElem))
                 (lastLine (optionOr (stringSlice text (tr/elementStart lastElem) (tr/elementEnd lastElem)) ""))
                 (closed? (and (> numElems 1) (md/isFencedCodeEnd? lastLine fenceChar 3)))
                 (cEnd (if closed? (tr/elementStart lastElem) (tr/elementEnd lastElem)))
                 (content (if (< cEnd cStart) "" (optionOr (stringSlice text cStart cEnd) "")))]
             (some (MarkdownFence :info rawInfo
                                  :language lang
                                  :start node.start
                                  :end node.end
                                  :contentStart cStart
                                  :contentEnd cEnd
                                  :content content
                                  :subtree (none)))))))))

fn collectFencesLoop elems: (List tr/TreeElement) text: String acc: (List MarkdownFence) -> (List MarkdownFence)
  (if (listEmpty? elems)
    (listReverse acc)
    (let [(hd (optionOr (listHead elems) (tr/elemToken (tr/Token :kind "" :start 0 :end 0))))
          (tl (optionOr (listTail elems) (list)))]
      (mt hd
        ((tr/elemToken _) (collectFencesLoop tl text acc))
        ((tr/elemNode node)
         (if (= node.kind "fencedCode")
           (mt (extractFenceFromNode node text)
             ((some f) (collectFencesLoop tl text (cons f acc)))
             ((none) (collectFencesLoop tl text acc)))
           (let [(inner (collectFencesLoop node.children text (list)))]
             (collectFencesLoop tl text (listAppend (listReverse inner) acc))))))))

fn extractFences root: tr/Node text: String -> (List MarkdownFence)
  (collectFencesLoop root.children text (list))

fn markdownFences text: String -> (List MarkdownFence)
  (extractFences (md/parseMarkdown text) text)

fn delegateLanguageContent lang: String content: String -> (Option tr/Node)
  (cond
    ((= lang "json") (some (jcst/parseJson content)))
    (else (none)))

fn delegateFence fence: MarkdownFence -> MarkdownFence
  (let [(lang fence.language)]
    (mt (delegateLanguageContent lang fence.content)
      ((some tree)
       (with fence :subtree (some tree)))
      ((none) fence)))

fn delegateMarkdownFences root: tr/Node text: String -> (List MarkdownFence)
  (map (fn [(f MarkdownFence)] -> MarkdownFence (delegateFence f))
       (extractFences root text))

fn delegateFenceNode node: tr/Node text: String -> (Option tr/Node)
  (mt (extractFenceFromNode node text)
    ((none) (none))
    ((some f)
     (delegateLanguageContent f.language f.content)))

fn delegateTreeElement elem: tr/TreeElement text: String -> tr/TreeElement
  (mt elem
    ((tr/elemToken _) elem)
    ((tr/elemNode node)
     (if (= node.kind "fencedCode")
       (mt (delegateFenceNode node text)
         ((some sub)
          (tr/elemNode (tr/makeNode "fencedCode" node.start node.end
                                    (list (tr/elemNode sub)))))
         ((none) elem))
       (tr/elemNode (tr/makeNode node.kind node.start node.end
                                 (map (fn [(child tr/TreeElement)] -> tr/TreeElement
                                        (delegateTreeElement child text))
                                      node.children))))))

fn delegateMarkdownTree root: tr/Node text: String -> tr/Node
  (let [(newChildren (map (fn [(child tr/TreeElement)] -> tr/TreeElement
                            (delegateTreeElement child text))
                          root.children))]
    (tr/makeNode root.kind root.start root.end newChildren))
