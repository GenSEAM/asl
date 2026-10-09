(module asl-syntax/core/cursor
  :x [Cursor
      LineRange
      makeCursor
      cursorNode
      cursorAncestors
      cursorSiblings
      cursorParent
      cursorNextSibling
      cursorPrevSibling
      cursorAt
      nodeAt
      tokenAt
      ancestors
      parentNode
      siblings
      nextSibling
      prevSibling
      nodeLineRange
      lineRange
      nodeStartLine
      nodeEndLine]
  :i [(asl-syntax/core/source :a src)
      (asl-syntax/core/tree :a tr)])

(schema LineRange
  (:f startLine Int64)
  (:f endLine Int64))

(schema Cursor
  (:f root tr/Node)
  (:f node tr/Node)
  (:f ancestors (List tr/Node))
  (:f siblings (List tr/Node)))

fn nodeEquals? a: tr/Node b: tr/Node -> Bool
  (and (= a.start b.start)
  (and (= a.end b.end)
       (= a.kind b.kind)))

fn childContainsOffset elem: tr/TreeElement offset: Int64 -> Bool
  (and (<= (tr/elementStart elem) offset)
       (< offset (tr/elementEnd elem)))

fn findChildAt offset: Int64 children: (List tr/TreeElement) -> (Option tr/TreeElement)
  (if (listEmpty? children)
    (none)
    (let [(head (optionOr (listHead children) (tr/elemToken (tr/Token :kind "" :start 0 :end 0))))
          (tail (optionOr (listTail children) (list)))]
      (if (childContainsOffset head offset)
        (some head)
        (findChildAt offset tail))))

fn nodeAt root: tr/Node offset: Int64 -> (Option tr/Node)
  (if (or (< offset root.start) (>= offset root.end))
    (none)
    (mt (findChildAt offset root.children)
      ((none) (some root))
      ((some child)
       (mt child
         ((tr/elemToken _) (some root))
         ((tr/elemNode childNode)
          (mt (nodeAt childNode offset)
            ((some inner) (some inner))
            ((none) (some childNode))))))))

fn tokenAt root: tr/Node offset: Int64 -> (Option tr/Token)
  (if (or (< offset root.start) (>= offset root.end))
    (none)
    (mt (findChildAt offset root.children)
      ((none) (none))
      ((some child)
       (mt child
         ((tr/elemToken tok) (some tok))
         ((tr/elemNode childNode) (tokenAt childNode offset))))))

fn findAncestorsInChildren children: (List tr/TreeElement) target: tr/Node path: (List tr/Node) -> (Option (List tr/Node))
  (if (listEmpty? children)
    (none)
    (let [(head (optionOr (listHead children) (tr/elemToken (tr/Token :kind "" :start 0 :end 0))))
          (tail (optionOr (listTail children) (list)))]
      (mt head
        ((tr/elemToken _) (findAncestorsInChildren tail target path))
        ((tr/elemNode childNode)
         (if (nodeEquals? childNode target)
           (some path)
           (mt (findAncestorsInChildren childNode.children target (listAppend path (list childNode)))
             ((some res) (some res))
             ((none) (findAncestorsInChildren tail target path))))))))

fn ancestors root: tr/Node target: tr/Node -> (List tr/Node)
  (if (nodeEquals? root target)
    (list)
    (optionOr (findAncestorsInChildren root.children target (list root)) (list)))

fn parentNode root: tr/Node target: tr/Node -> (Option tr/Node)
  (let [(ancs (ancestors root target))]
    (if (listEmpty? ancs)
      (none)
      (listGet ancs (- (listLength ancs) 1))))

fn collectChildNodes children: (List tr/TreeElement) -> (List tr/Node)
  (if (listEmpty? children)
    (list)
    (let [(head (optionOr (listHead children) (tr/elemToken (tr/Token :kind "" :start 0 :end 0))))
          (tail (optionOr (listTail children) (list)))
          (rest (collectChildNodes tail))]
      (mt head
        ((tr/elemToken _) rest)
        ((tr/elemNode n) (cons n rest)))))

fn filterOutNode nodes: (List tr/Node) target: tr/Node -> (List tr/Node)
  (filter (fn [(n tr/Node)] -> Bool (not (nodeEquals? n target))) nodes)

fn siblings root: tr/Node target: tr/Node -> (List tr/Node)
  (mt (parentNode root target)
    ((none) (list))
    ((some parent)
     (filterOutNode (collectChildNodes parent.children) target)))

fn findNextInList nodes: (List tr/Node) target: tr/Node -> (Option tr/Node)
  (if (listEmpty? nodes)
    (none)
    (let [(head (optionOr (listHead nodes) (tr/Node :kind "" :start 0 :end 0 :children (list))))
          (tail (optionOr (listTail nodes) (list)))]
      (if (nodeEquals? head target)
        (listHead tail)
        (findNextInList tail target))))

fn nextSibling root: tr/Node target: tr/Node -> (Option tr/Node)
  (mt (parentNode root target)
    ((none) (none))
    ((some parent)
     (findNextInList (collectChildNodes parent.children) target)))

fn findPrevInList nodes: (List tr/Node) prev: (Option tr/Node) target: tr/Node -> (Option tr/Node)
  (if (listEmpty? nodes)
    (none)
    (let [(head (optionOr (listHead nodes) (tr/Node :kind "" :start 0 :end 0 :children (list))))
          (tail (optionOr (listTail nodes) (list)))]
      (if (nodeEquals? head target)
        prev
        (findPrevInList tail (some head) target))))

fn prevSibling root: tr/Node target: tr/Node -> (Option tr/Node)
  (mt (parentNode root target)
    ((none) (none))
    ((some parent)
     (findPrevInList (collectChildNodes parent.children) (none) target)))

fn makeCursor root: tr/Node node: tr/Node -> Cursor
  (Cursor :root root :node node :ancestors (ancestors root node) :siblings (siblings root node))

fn cursorNode c: Cursor -> tr/Node
  c.node

fn cursorAncestors c: Cursor -> (List tr/Node)
  c.ancestors

fn cursorSiblings c: Cursor -> (List tr/Node)
  c.siblings

fn cursorParent c: Cursor -> (Option tr/Node)
  (parentNode c.root c.node)

fn cursorNextSibling c: Cursor -> (Option tr/Node)
  (nextSibling c.root c.node)

fn cursorPrevSibling c: Cursor -> (Option tr/Node)
  (prevSibling c.root c.node)

fn cursorAt root: tr/Node offset: Int64 -> (Option Cursor)
  (mt (nodeAt root offset)
    ((some n) (some (makeCursor root n)))
    ((none) (none)))

fn nodeLineRange s: src/Source node: tr/Node -> (Option LineRange)
  (let [(st node.start)
        (en node.end)]
    (mt (src/sourceLineAt s st)
      ((some sl)
       (let [(endOff (if (> en st) (- en 1) st))]
         (mt (src/sourceLineAt s endOff)
           ((some el) (some (LineRange :startLine sl :endLine el)))
           ((none) (some (LineRange :startLine sl :endLine sl))))))
      ((none) (none))))

fn lineRange s: src/Source node: tr/Node -> (Option LineRange)
  (nodeLineRange s node)

fn nodeStartLine s: src/Source node: tr/Node -> (Option Int64)
  (mt (nodeLineRange s node)
    ((some lr) (some lr.startLine))
    ((none) (none)))

fn nodeEndLine s: src/Source node: tr/Node -> (Option Int64)
  (mt (nodeLineRange s node)
    ((some lr) (some lr.endLine))
    ((none) (none)))
