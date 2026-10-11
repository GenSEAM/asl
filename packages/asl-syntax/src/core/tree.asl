(module asl-syntax/core/tree
  :x [Token
      Node
      Missing
      TreeElement
      elemToken
      elemNode
      makeToken
      makeNode
      makeErrorNode
      makeErrorNodeWithMissing
      makeMissing
      missingOffset
      missingText
      missingTok
      nodeMissing
      errorNodeMissing
      isMissingNode
      makeMissingNode
      missingNodeOffset
      missingNodeText
      treeMissing
      treeMissingNodes
      Delete
      makeDelete
      deleteStart
      deleteEnd
      isStrayNode
      makeStrayErrorNode
      treeDeletes
      treeStrayNodes
      isErrorNode
      isErrorToken
      isTriviaKind
      isTrivia
      isTriviaToken
      tokenKind
      tokenStart
      tokenEnd
      tokenLength
      nodeKind
      nodeStart
      nodeEnd
      nodeChildren
      nodeLength
      elementStart
      elementEnd
      elementLength
      nodeLeaves
      checkTiling
      checkTilingRoot
      checkTokensTiling
      ParseResult]
  :i [])

(schema Missing
  (:f offset Int64)
  (:f text String))

(schema Delete
  (:f start Int64)
  (:f end Int64))

(schema Token
  (:f kind String)
  (:f start Int64)
  (:f end Int64))

(schema Node
  (:f kind String)
  (:f start Int64)
  (:f end Int64)
  (:f children (List TreeElement))
  (:f missing (Option Missing) :default (none))
  (:f stray Bool :default false))

(schema ParseResult
  (:f node Node)
  (:f rest (List Token)))

(enum TreeElement
  (:c elemToken [(tok Token)] "Leaf token")
  (:c elemNode [(node Node)] "Interior node"))

fn makeToken kind: String start: Int64 end: Int64 -> Token
  (Token :kind kind :start start :end end)

fn makeNode kind: String start: Int64 end: Int64 children: (List TreeElement) -> Node
  (Node :kind kind :start start :end end :children children :missing (none) :stray false)

fn makeErrorNode start: Int64 end: Int64 children: (List TreeElement) -> Node
  (Node :kind "error" :start start :end end :children children :missing (none) :stray false)

fn makeErrorNodeWithMissing start: Int64 end: Int64 children: (List TreeElement) missing: Missing -> Node
  (Node :kind "error" :start start :end end :children children :missing (some missing) :stray false)

fn makeStrayErrorNode start: Int64 end: Int64 children: (List TreeElement) -> Node
  (Node :kind "error" :start start :end end :children children :missing (none) :stray true)

fn isStrayNode node: Node -> Bool
  (or (= node.kind "stray") node.stray)

fn makeDelete start: Int64 end: Int64 -> Delete
  (Delete :start start :end end)

fn deleteStart d: Delete -> Int64
  d.start

fn deleteEnd d: Delete -> Int64
  d.end

fn makeMissing offset: Int64 text: String -> Missing
  (Missing :offset offset :text text)

fn missingOffset m: Missing -> Int64
  m.offset

fn missingText m: Missing -> String
  m.text

fn missingTok m: Missing -> String
  m.text

fn nodeMissing node: Node -> (Option Missing)
  node.missing

fn errorNodeMissing node: Node -> (Option Missing)
  node.missing

fn isMissingNode node: Node -> Bool
  (or (= node.kind "missing") (some? node.missing))

fn makeMissingNode offset: Int64 text: String -> Node
  (Node :kind "missing" :start offset :end offset :children (list) :missing (some (Missing :offset offset :text text)) :stray false)

fn missingNodeText node: Node -> String
  (mt node.missing
    ((some m) m.text)
    ((none) ""))

fn missingNodeOffset node: Node -> Int64
  (mt node.missing
    ((some m) m.offset)
    ((none) node.start))

fn collectMissingInElement elem: TreeElement acc: (List Missing) -> (List Missing)
  (mt elem
    ((elemToken _) acc)
    ((elemNode node) (collectMissingInNode node acc)))

fn collectMissingInChildren children: (List TreeElement) acc: (List Missing) -> (List Missing)
  (if (listEmpty? children)
    acc
    (let [(head (optionOr (listHead children) (elemToken (Token :kind "" :start 0 :end 0))))
          (tail (optionOr (listTail children) (list)))]
      (collectMissingInChildren tail (collectMissingInElement head acc))))

fn collectMissingInNode node: Node acc: (List Missing) -> (List Missing)
  (let [(kidsAcc (collectMissingInChildren node.children acc))]
    (mt node.missing
      ((some m) (cons m kidsAcc))
      ((none) kidsAcc)))

fn treeMissing root: Node -> (List Missing)
  (listReverse (collectMissingInNode root (list)))

fn collectMissingNodesInElement elem: TreeElement acc: (List Node) -> (List Node)
  (mt elem
    ((elemToken _) acc)
    ((elemNode node) (collectMissingNodesInNode node acc)))

fn collectMissingNodesInChildren children: (List TreeElement) acc: (List Node) -> (List Node)
  (if (listEmpty? children)
    acc
    (let [(head (optionOr (listHead children) (elemToken (Token :kind "" :start 0 :end 0))))
          (tail (optionOr (listTail children) (list)))]
      (collectMissingNodesInChildren tail (collectMissingNodesInElement head acc))))

fn collectMissingNodesInNode node: Node acc: (List Node) -> (List Node)
  (let [(kidsAcc (collectMissingNodesInChildren node.children acc))]
    (if (or (= node.kind "missing") (some? node.missing))
      (cons node kidsAcc)
      kidsAcc))

fn treeMissingNodes root: Node -> (List Node)
  (listReverse (collectMissingNodesInNode root (list)))

fn collectDeletesInElement elem: TreeElement acc: (List Delete) -> (List Delete)
  (mt elem
    ((elemToken _) acc)
    ((elemNode node) (collectDeletesInNode node acc)))

fn collectDeletesInChildren children: (List TreeElement) acc: (List Delete) -> (List Delete)
  (if (listEmpty? children)
    acc
    (let [(head (optionOr (listHead children) (elemToken (Token :kind "" :start 0 :end 0))))
          (tail (optionOr (listTail children) (list)))]
      (collectDeletesInChildren tail (collectDeletesInElement head acc))))

fn collectDeletesInNode node: Node acc: (List Delete) -> (List Delete)
  (let [(kidsAcc (collectDeletesInChildren node.children acc))]
    (if (isStrayNode node)
      (cons (makeDelete node.start node.end) kidsAcc)
      kidsAcc))

fn treeDeletes root: Node -> (List Delete)
  (listReverse (collectDeletesInNode root (list)))

fn collectStrayNodesInElement elem: TreeElement acc: (List Node) -> (List Node)
  (mt elem
    ((elemToken _) acc)
    ((elemNode node) (collectStrayNodesInNode node acc)))

fn collectStrayNodesInChildren children: (List TreeElement) acc: (List Node) -> (List Node)
  (if (listEmpty? children)
    acc
    (let [(head (optionOr (listHead children) (elemToken (Token :kind "" :start 0 :end 0))))
          (tail (optionOr (listTail children) (list)))]
      (collectStrayNodesInChildren tail (collectStrayNodesInElement head acc))))

fn collectStrayNodesInNode node: Node acc: (List Node) -> (List Node)
  (let [(kidsAcc (collectStrayNodesInChildren node.children acc))]
    (if (isStrayNode node)
      (cons node kidsAcc)
      kidsAcc))

fn treeStrayNodes root: Node -> (List Node)
  (listReverse (collectStrayNodesInNode root (list)))

fn isErrorNode node: Node -> Bool
  (= node.kind "error")

fn isErrorToken tok: Token -> Bool
  (= tok.kind "error")

fn isTriviaKind kind: String -> Bool
  (or (= kind "whitespace")
  (or (= kind "ws")
  (or (= kind "newline")
  (or (= kind "nl")
  (or (= kind "comment")
  (or (= kind "lineComment")
  (or (= kind "blockComment")
  (or (= kind "bom")
  (or (= kind "invalid")
      (= kind "invalidBytes"))))))))))

fn isTrivia tok: Token -> Bool
  (isTriviaKind tok.kind)

fn isTriviaToken tok: Token -> Bool
  (isTrivia tok)

fn tokenKind tok: Token -> String
  tok.kind

fn tokenStart tok: Token -> Int64
  tok.start

fn tokenEnd tok: Token -> Int64
  tok.end

fn tokenLength tok: Token -> Int64
  (- tok.end tok.start)

fn nodeKind node: Node -> String
  node.kind

fn nodeStart node: Node -> Int64
  node.start

fn nodeEnd node: Node -> Int64
  node.end

fn nodeChildren node: Node -> (List TreeElement)
  node.children

fn nodeLength node: Node -> Int64
  (- node.end node.start)

fn elementStart elem: TreeElement -> Int64
  (mt elem
    ((elemToken tok) tok.start)
    ((elemNode node) node.start))

fn elementEnd elem: TreeElement -> Int64
  (mt elem
    ((elemToken tok) tok.end)
    ((elemNode node) node.end))

fn elementLength elem: TreeElement -> Int64
  (- (elementEnd elem) (elementStart elem))

fn collectLeafTokens elem: TreeElement acc: (List Token) -> (List Token)
  (mt elem
    ((elemToken tok) (cons tok acc))
    ((elemNode node)
     (if (= node.kind "missing")
       acc
       (if (listEmpty? node.children)
         (if (< node.start node.end)
           (cons (Token :kind node.kind :start node.start :end node.end) acc)
           acc)
         (collectChildrenLeafTokens node.children acc)))))

fn collectChildrenLeafTokens children: (List TreeElement) acc: (List Token) -> (List Token)
  (if (listEmpty? children)
    acc
    (let [(head (optionOr (listHead children) (elemToken (Token :kind "" :start 0 :end 0))))
          (tail (optionOr (listTail children) (list)))]
      (collectChildrenLeafTokens tail (collectLeafTokens head acc))))

fn nodeLeaves node: Node -> (List Token)
  (if (listEmpty? node.children)
    (if (< node.start node.end)
      (list (Token :kind node.kind :start node.start :end node.end))
      (list))
    (listReverse (collectChildrenLeafTokens node.children (list))))

fn checkTokensTilingLoop tokens: (List Token) cur: Int64 len: Int64 -> (Result Bool String)
  (if (listEmpty? tokens)
    (if (< cur len)
      (err (str "gap at offset " (stringFromInt64 cur)))
      (if (> cur len)
        (err (str "overlap at offset " (stringFromInt64 len)))
        (ok true)))
    (let [(tok (optionOr (listHead tokens) (Token :kind "" :start 0 :end 0)))
          (rest (optionOr (listTail tokens) (list)))
          (s tok.start)
          (e tok.end)]
      (if (< s cur)
        (err (str "overlap at offset " (stringFromInt64 s)))
        (if (> s cur)
          (err (str "gap at offset " (stringFromInt64 cur)))
          (if (< e s)
            (err (str "invalid token end " (stringFromInt64 e) " before start " (stringFromInt64 s)))
            (checkTokensTilingLoop rest e len))))))

fn checkTokensTiling tokens: (List Token) len: Int64 -> (Result Bool String)
  (if (< len 0)
    (err "invalid negative length")
    (checkTokensTilingLoop tokens 0 len))

fn checkTiling root: Node len: Int64 -> (Result Bool String)
  (checkTokensTiling (nodeLeaves root) len)

fn checkTilingRoot root: Node -> (Result Bool String)
  (checkTiling root root.end)
