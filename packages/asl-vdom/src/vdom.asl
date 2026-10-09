(module aslVdom/vdom :x [VNode AXNode MutationRecord DomDiff t txt text elem el elemPlain elPlain comp c compPlain cPlain isValidNode isComponentTag? vnodeIsComp? vnodeAttrs vnodeTag vnodeText vnodeChildren makeAxNode axLeaf isRetainedAttr? isSafeAttrValue? filterAttributes shouldPruneTag? isRedundantWrapper? downsampleNode downsampleChildren diffAttributes diffChildrenIndexed diffChildrenKeyed diffChildren vnodeKey isKeyedList? diffNodes vnodeStructuralHash partitionDiff domDiff formatDiffFrame])

(enum VNode (:c textNode [(content String)] "Text DOM node") (:c elementNode [(tag String) (attrs (Map String String)) (children (List VNode))] "Element DOM node"))

(schema AXNode (:f role String) (:f name String) (:f ref String) (:f description String) (:f disabled Bool) (:f focused Bool) (:f children (List AXNode)))

(enum MutationRecord (:c added [(target String) (node VNode)] "Added node at target path or ref") (:c removed [(target String) (ref String)] "Removed node at target path or ref") (:c mutated [(target String) (key String) (newVal String)] "Mutated attribute or text content"))

(schema DomDiff (:f route String) (:f mutations (List MutationRecord)) (:f added (List VNode)) (:f removed (List String)) (:f mutated (List MutationRecord)))

fn t content: String -> VNode
  (textNode content)

fn txt content: String -> VNode
  (textNode content)

fn text content: String -> VNode
  (textNode content)

fn el tag: String attrs: (Map String String) children: (List VNode) -> VNode
  (elementNode tag attrs children)

fn elem tag: String attrs: (Map String String) children: (List VNode) -> VNode
  (elementNode tag attrs children)

fn elPlain tag: String children: (List VNode) -> VNode
  (elementNode tag (mapEmpty) children)

fn elemPlain tag: String children: (List VNode) -> VNode
  (elementNode tag (mapEmpty) children)

fn comp name: String props: (Map String String) children: (List VNode) -> VNode
  (elementNode name props children)

fn c name: String props: (Map String String) children: (List VNode) -> VNode
  (elementNode name props children)

fn compPlain name: String children: (List VNode) -> VNode
  (elementNode name (mapEmpty) children)

fn cPlain name: String children: (List VNode) -> VNode
  (elementNode name (mapEmpty) children)

fn isComponentTag? tag: String -> Bool
  (if (stringEmpty? tag) false (let [(firstCh (optionOr (stringSlice tag 0 1) ""))] (and (>= firstCh "A") (<= firstCh "Z"))))

fn vnodeIsComp? node: VNode -> Bool
  (mt node ((textNode _) false) ((elementNode tag _ _) (isComponentTag? tag)))

fn vnodeAttrs node: VNode -> (Map String String)
  (mt node ((textNode _) (mapEmpty)) ((elementNode _ attrs _) attrs))

fn isValidNode node: VNode -> Bool
  (mt node ((textNode content) (not (stringEmpty? content))) ((elementNode tag _ _) (not (stringEmpty? tag))))

fn vnodeTag node: VNode -> String
  (mt node ((textNode _) "") ((elementNode tag _ _) tag))

fn vnodeText node: VNode -> String
  (mt node ((textNode content) content) ((elementNode _ _ _) ""))

fn vnodeChildren node: VNode -> (List VNode)
  (mt node ((textNode _) (list)) ((elementNode _ _ children) children))

fn makeAxNode role: String name: String ref: String desc: String disabled: Bool focused: Bool children: (List AXNode) -> AXNode
  (AXNode :role role :name name :ref ref :description desc :disabled disabled :focused focused :children children)

fn axLeaf role: String name: String ref: String -> AXNode
  (AXNode :role role :name name :ref ref :description "" :disabled false :focused false :children (list))

fn isRetainedAttr? key: String -> Bool
  (cond ((= key "key") true) ((= key "id") true) ((= key "name") true) ((= key "role") true) ((= key "type") true) ((= key "aria-label") true) ((= key "aria-describedby") true) ((= key "aria-expanded") true) ((= key "aria-checked") true) ((= key "aria-selected") true) ((= key "aria-disabled") true) ((= key "placeholder") true) ((= key "href") true) ((= key "src") true) ((= key "value") true) ((= key "alt") true) ((= key "title") true) ((= key "ref") true) ((= key "data-testid") true) ((= key "disabled") true) (else false))

fn isSafeAttrValue? key: String val: String -> Bool
  (let [(kLower (stringLower (stringTrim key)))] (if (or (= kLower "href") (= kLower "src")) (let [(trimmed (stringTrim val)) (lower (stringLower trimmed))] (and (not (stringStartsWith? lower "javascript:")) (and (not (stringStartsWith? lower "vbscript:")) (and (not (stringStartsWith? lower "data:text/html")) (not (stringStartsWith? lower "data:application/javascript")))))) true))

fn filterAttributes attrs: (Map String String) -> (Map String String)
  (fold (fn [(acc (Map String String)) (k String)] -> (Map String String) (mt (mapGet attrs k) ((some v) (if (and (isRetainedAttr? k) (isSafeAttrValue? k v)) (mapSet acc k v) acc)) ((none) acc))) (mapEmpty) (mapKeys attrs))

fn shouldPruneTag? tag: String -> Bool
  (cond ((= tag "script") true) ((= tag "style") true) ((= tag "noscript") true) ((= tag "template") true) ((= tag "head") true) ((= tag "meta") true) ((= tag "link") true) ((= tag "comment") true) ((= tag "svg") true) (else false))

fn isRedundantWrapper? tag: String attrs: (Map String String) childrenCount: Int64 -> Bool
  (and (= childrenCount 1) (and (or (= tag "div") (= tag "span")) (= (mapSize attrs) 0)))

fn downsampleChildren children: (List VNode) -> (List VNode)
  (fold (fn [(acc (List VNode)) (child VNode)] -> (List VNode) (mt (downsampleNode child) ((some validChild) (listAppend acc (list validChild))) ((none) acc))) (list) children)

fn downsampleNode node: VNode -> (Option VNode)
  (mt node ((textNode content) (let [(trimmed (stringTrim content))] (if (stringEmpty? trimmed) (none) (some (textNode trimmed))))) ((elementNode tag attrs children) (if (shouldPruneTag? tag) (none) (let [(filteredAttrs (filterAttributes attrs)) (filteredChildren (downsampleChildren children)) (childCount (listLength filteredChildren))] (if (isRedundantWrapper? tag filteredAttrs childCount) (listHead filteredChildren) (some (elementNode tag filteredAttrs filteredChildren)))))))

fn diffAttributes attrs1: (Map String String) attrs2: (Map String String) path: String -> (List MutationRecord)
  (let [(pairs2 (mapPairs attrs2)) (pairs1 (mapPairs attrs1)) (changes (fold (fn [(acc (List MutationRecord)) (p (pair String String))] -> (List MutationRecord) (let [(k (pairFirst p)) (v (pairSecond p))] (mt (mapGet attrs1 k) ((some oldV) (if (= oldV v) acc (cons (mutated path k v) acc))) ((none) (cons (mutated path k v) acc))))) (list) pairs2)) (deletions (fold (fn [(acc (List MutationRecord)) (p (pair String String))] -> (List MutationRecord) (let [(k (pairFirst p))] (if (mapHas? attrs2 k) acc (cons (mutated path k "") acc)))) (list) pairs1))] (listAppend changes deletions))

fn diffChildrenIndexed oldCh: (List VNode) newCh: (List VNode) idx: Int64 path: String -> (List MutationRecord)
  (let [(oldLen (listLength oldCh)) (newLen (listLength newCh)) (maxLen (if (> oldLen newLen) oldLen newLen))] (fold (fn [(acc (List MutationRecord)) (i Int64)] -> (List MutationRecord) (let [(childPath (str path "/" (stringFromInt64 i))) (oOpt (listGet oldCh i)) (nOpt (listGet newCh i))] (mt oOpt ((some o) (mt nOpt ((some n) (listAppend acc (diffNodes o n childPath))) ((none) (listAppend acc (list (removed childPath (stringFromInt64 i))))))) ((none) (mt nOpt ((some n) (listAppend acc (list (added childPath n)))) ((none) acc)))))) (list) (range idx maxLen)))

fn vnodeKey node: VNode -> (Option String)
  (mt node ((elementNode _ attrs _) (mapGet attrs "key")) (_ (none)))

fn isKeyedList? ch: (List VNode) -> Bool
  (not (listEmpty? (filter (fn [(n VNode)] (some? (vnodeKey n))) ch)))

fn listIndexedHelper xs: (List VNode) curIdx: Int64 -> (List (Pair Int64 VNode))
  (mt (listHead xs)
    ((none) (list))
    ((some h)
      (let [(rest (optionOr (listTail xs) (list)))]
        (cons (pair curIdx h) (listIndexedHelper rest (+ curIdx 1))))))

fn listIndexed xs: (List VNode) -> (List (Pair Int64 VNode))
  (listIndexedHelper xs 0)

fn indexKeyedChildren children: (List VNode) -> (Map String (Pair Int64 VNode))
  (fold (fn [(acc (Map String (pair Int64 VNode))) (item (pair Int64 VNode))] -> (Map String (Pair Int64 VNode)) (let [(idx (pairFirst item)) (node (pairSecond item))] (mt (vnodeKey node) ((some k) (mapSet acc k (pair idx node))) ((none) acc)))) (mapEmpty) (listIndexed children))

fn diffKeyedRemovals oldCh: (List VNode) newMap: (Map String (Pair Int64 VNode)) path: String -> (List MutationRecord)
  (fold (fn [(acc (List MutationRecord)) (oldNode VNode)] -> (List MutationRecord) (mt (vnodeKey oldNode) ((some k) (if (mapHas? newMap k) acc (listAppend acc (list (removed (str path "/" k) (vnodeTag oldNode)))))) ((none) acc))) (list) oldCh)

fn diffKeyedChildrenPass newCh: (List VNode) oldMap: (Map String (Pair Int64 VNode)) path: String -> (List MutationRecord)
  (fold (fn [(acc (List MutationRecord)) (item (pair Int64 VNode))] -> (List MutationRecord) (let [(idx (pairFirst item)) (nh (pairSecond item)) (kOpt (vnodeKey nh)) (childPath (str path "/" (mt kOpt ((some k) k) ((none) (stringFromInt64 idx)))))] (mt kOpt ((some k) (mt (mapGet oldMap k) ((some oldPair) (let [(oldIdx (pairFirst oldPair)) (oldNode (pairSecond oldPair)) (nodeDiffs (diffNodes oldNode nh childPath)) (moveDiffs (if (= oldIdx idx) (list) (list (mutated childPath "key-index" (stringFromInt64 idx)))))] (listAppend acc (listAppend nodeDiffs moveDiffs)))) ((none) (listAppend acc (list (added childPath nh)))))) ((none) (listAppend acc (list (added childPath nh))))))) (list) (listIndexed newCh))

fn diffChildrenKeyed oldCh: (List VNode) newCh: (List VNode) path: String -> (List MutationRecord)
  (let [(oldMap (indexKeyedChildren oldCh)) (newMap (indexKeyedChildren newCh)) (removals (diffKeyedRemovals oldCh newMap path)) (updatesAndAdds (diffKeyedChildrenPass newCh oldMap path))] (listAppend removals updatesAndAdds))

fn diffChildren oldCh: (List VNode) newCh: (List VNode) path: String -> (List MutationRecord)
  (if (or (isKeyedList? oldCh) (isKeyedList? newCh)) (diffChildrenKeyed oldCh newCh path) (diffChildrenIndexed oldCh newCh 0 path))

fn vnodeStructuralHash node: VNode -> String
  (mt node
    ((textNode content) (str "t:" (stringLength content) ":" content))
    ((elementNode tag attrs children)
      (let [(pairs (mapPairs attrs))
            (attrStrs (map (fn [(p (pair String String))] -> String (str (pairFirst p) "=" (pairSecond p) ";")) pairs))
            (attrSummary (stringJoin attrStrs ""))
            (childHashes (map (fn [(c VNode)] -> String (vnodeStructuralHash c)) children))
            (childrenSummary (stringJoin childHashes ","))]
        (str "e:" tag "{" attrSummary "}" "[" childrenSummary "]"))))

fn diffNodes n1: VNode n2: VNode path: String -> (List MutationRecord)
  (if (= (vnodeStructuralHash n1) (vnodeStructuralHash n2))
    (list)
    (mt n1
      ((textNode c1)
        (mt n2
          ((textNode c2) (if (= c1 c2) (list) (list (mutated path "text" c2))))
          ((elementNode _ _ _) (list (removed path "text") (added path n2)))))
      ((elementNode t1 a1 ch1)
        (mt n2
          ((textNode _) (list (removed path t1) (added path n2)))
          ((elementNode t2 a2 ch2)
            (if (= t1 t2)
              (listAppend (diffAttributes a1 a2 path) (diffChildren ch1 ch2 path))
              (list (removed path t1) (added path n2))))))))

fn partitionDiff route: String records: (List MutationRecord) -> DomDiff
  (let [(adds (fold (fn [(acc (List VNode)) (m MutationRecord)] -> (List VNode) (mt m ((added _ n) (listAppend acc (list n))) (_ acc))) (list) records)) (rems (fold (fn [(acc (List String)) (m MutationRecord)] -> (List String) (mt m ((removed t r) (listAppend acc (list (if (stringEmpty? r) t (str t ":" r))))) (_ acc))) (list) records)) (muts (fold (fn [(acc (List MutationRecord)) (m MutationRecord)] -> (List MutationRecord) (mt m ((mutated _ _ _) (listAppend acc (list m))) (_ acc))) (list) records))] (DomDiff :route route :mutations records :added adds :removed rems :mutated muts))

fn domDiff oldTree: VNode newTree: VNode route: String -> DomDiff
  (let [(records (diffNodes oldTree newTree "root"))] (partitionDiff route records))

fn formatDiffFrame diff: DomDiff -> String
  (str "(! dom/diff :route \"" diff.route "\"" " :added-count " (stringFromInt64 (listLength diff.added)) " :removed-count " (stringFromInt64 (listLength diff.removed)) " :mutated-count " (stringFromInt64 (listLength diff.mutated)) ")")
