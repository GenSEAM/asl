(module asl-vdom/vdom
  :d "Declarative S-Expression Virtual DOM and Dual Perception Compactor in ASL"
  :x [VNode AXNode MutationRecord DomDiff
      text elem elem-plain is-valid-node
      vnode-tag vnode-text vnode-children
      make-ax-node ax-leaf
      is-retained-attr? filter-attributes should-prune-tag? is-redundant-wrapper?
      downsample-node downsample-children
      diff-attributes diff-children-indexed diff-nodes partition-diff dom-diff
      format-diff-frame])

(dfe VNode
  (:c text-node [(content String)] "Text DOM node")
  (:c element-node [(tag String) (attrs (Map String String)) (children (List VNode))] "Element DOM node"))

(dfs AXNode
  (:f role String "ARIA role or control role: button, link, heading, input")
  (:f name String "Accessible name or primary human label")
  (:f ref String "Target element reference selector e.g. @e1, @e2")
  (:f description String "Accessible description, hint, or tooltip")
  (:f disabled Bool "Whether element is currently disabled")
  (:f focused Bool "Whether element currently holds keyboard focus")
  (:f children (List AXNode) "Sub-tree accessibility children"))

(dfe MutationRecord
  (:c added [(target String) (node VNode)] "Added node at target path or ref")
  (:c removed [(target String) (ref String)] "Removed node at target path or ref")
  (:c mutated [(target String) (key String) (new-val String)] "Mutated attribute or text content"))

(dfs DomDiff
  (:f route String "Current page route or URL")
  (:f mutations (List MutationRecord) "Full ordered list of atomic mutations")
  (:f added (List VNode) "Newly added nodes")
  (:f removed (List String) "Removed element selectors or refs")
  (:f mutated (List MutationRecord) "Modified node records"))

(df text [(content String)] -> VNode
  :d "Creates a text VNode"
  (text-node content))

(df elem [(tag String) (attrs (Map String String)) (children (List VNode))] -> VNode
  :d "Creates an element VNode with explicit attributes and children"
  (element-node tag attrs children))

(df elem-plain [(tag String) (children (List VNode))] -> VNode
  :d "Creates an element VNode with empty attributes and given children"
  (element-node tag (map-empty) children))

(df is-valid-node [(node VNode)] -> Bool
  :d "Validates that a VNode has non-empty tag or content"
  (mt node
    ((text-node content) (not (string-empty? content)))
    ((element-node tag _ _) (not (string-empty? tag)))))

(df vnode-tag [(node VNode)] -> String
  :d "Returns the tag of an element VNode, or empty string for text nodes"
  (mt node
    ((text-node _) "")
    ((element-node tag _ _) tag)))

(df vnode-text [(node VNode)] -> String
  :d "Returns the content of a text VNode, or empty string for element nodes"
  (mt node
    ((text-node content) content)
    ((element-node _ _ _) "")))

(df vnode-children [(node VNode)] -> (List VNode)
  :d "Returns the children list of an element VNode, or empty list for text nodes"
  (mt node
    ((text-node _) (list))
    ((element-node _ _ children) children)))

(df make-ax-node [(role String) (name String) (ref String) (desc String) (disabled Bool) (focused Bool) (children (List AXNode))] -> AXNode
  :d "Constructs an AXNode record"
  (AXNode
    :role role
    :name name
    :ref ref
    :description desc
    :disabled disabled
    :focused focused
    :children children))

(df ax-leaf [(role String) (name String) (ref String)] -> AXNode
  :d "Constructs an interactive leaf AXNode with default active states"
  (AXNode
    :role role
    :name name
    :ref ref
    :description ""
    :disabled false
    :focused false
    :children (list)))

(df is-retained-attr? [(key String)] -> Bool
  :d "Checks if an HTML attribute is semantic and should be retained during downsampling"
  (cond
    ((= key "id") true)
    ((= key "name") true)
    ((= key "role") true)
    ((= key "type") true)
    ((= key "aria-label") true)
    ((= key "aria-describedby") true)
    ((= key "aria-expanded") true)
    ((= key "aria-checked") true)
    ((= key "aria-selected") true)
    ((= key "aria-disabled") true)
    ((= key "placeholder") true)
    ((= key "href") true)
    ((= key "src") true)
    ((= key "value") true)
    ((= key "alt") true)
    ((= key "title") true)
    ((= key "ref") true)
    ((= key "data-testid") true)
    ((= key "disabled") true)
    (:else false)))

(df filter-attributes [(attrs (Map String String))] -> (Map String String)
  :d "Filters DOM element attributes, removing CSS noise and keeping semantic properties"
  (fold (fn [(acc (Map String String)) (entry (Pair String String))] -> (Map String String)
          (if (is-retained-attr? (.-first entry))
            (map-set acc (.-first entry) (.-second entry))
            acc))
        (map-empty)
        (map-pairs attrs)))

(df should-prune-tag? [(tag String)] -> Bool
  :d "Checks if a tag represents scripts, styles, or non-semantic wrappers that should be pruned"
  (cond
    ((= tag "script") true)
    ((= tag "style") true)
    ((= tag "noscript") true)
    ((= tag "template") true)
    ((= tag "head") true)
    ((= tag "meta") true)
    ((= tag "link") true)
    ((= tag "comment") true)
    ((= tag "svg") true)
    (:else false)))

(df is-redundant-wrapper? [(tag String) (attrs (Map String String)) (children-count Int64)] -> Bool
  :d "Checks if an element is a redundant transparent wrapper that can be collapsed"
  (and (= children-count 1)
       (and (or (= tag "div") (= tag "span"))
            (= (map-size attrs) 0))))

(df downsample-children [(children (List VNode))] -> (List VNode)
  :d "Recursively downsamples a list of children VNodes, pruning empty or non-semantic nodes"
  (fold (fn [(acc (List VNode)) (child VNode)] -> (List VNode)
          (mt (downsample-node child)
            ((some valid-child) (list-append acc (list valid-child)))
            ((none) acc)))
        (list)
        children))

(df downsample-node [(node VNode)] -> (Option VNode)
  :d "Downsamples a VNode: filters attributes, prunes non-semantic tags, and collapses redundant wrappers"
  (mt node
    ((text-node content)
     (let [(trimmed (string-trim content))]
       (if (string-empty? trimmed)
         (none)
         (some (text-node trimmed)))))
    ((element-node tag attrs children)
     (if (should-prune-tag? tag)
       (none)
       (let [(filtered-attrs (filter-attributes attrs))
             (filtered-children (downsample-children children))
             (child-count (list-length filtered-children))]
         (if (is-redundant-wrapper? tag filtered-attrs child-count)
           (list-head filtered-children)
           (some (element-node tag filtered-attrs filtered-children))))))))

(df diff-attributes [(attrs1 (Map String String)) (attrs2 (Map String String)) (path String)] -> (List MutationRecord)
  :d "Diffs two attribute maps and returns mutated records for added/changed/removed keys"
  (let [(pairs2 (map-pairs attrs2))
        (pairs1 (map-pairs attrs1))
        (changes (fold (fn [(acc (List MutationRecord)) (p (Pair String String))] -> (List MutationRecord)
                         (let [(k (.-first p))
                               (v (.-second p))]
                           (mt (map-get attrs1 k)
                             ((some old-v)
                              (if (= old-v v)
                                acc
                                (list-cons (mutated path k v) acc)))
                             ((none)
                              (list-cons (mutated path k v) acc)))))
                       (list)
                       pairs2))
        (deletions (fold (fn [(acc (List MutationRecord)) (p (Pair String String))] -> (List MutationRecord)
                           (let [(k (.-first p))]
                             (if (map-has? attrs2 k)
                               acc
                               (list-cons (mutated path k "") acc))))
                         (list)
                         pairs1))]
    (list-append changes deletions)))

(df diff-children-indexed [(old-ch (List VNode)) (new-ch (List VNode)) (idx Int64) (path String)] -> (List MutationRecord)
  :d "Diffs children lists by index, producing added, removed, and mutated records"
  (let [(child-path (str path "/" (string-from-int64 idx)))]
    (mt old-ch
      ((list)
       (mt new-ch
         ((list) (list))
         ((cons nh nt)
          (list-cons (added child-path nh)
                     (diff-children-indexed (list) nt (+ idx 1) path)))))
      ((cons oh ot)
       (mt new-ch
         ((list)
          (list-cons (removed child-path (string-from-int64 idx))
                     (diff-children-indexed ot (list) (+ idx 1) path)))
         ((cons nh nt)
          (list-append (diff-nodes oh nh child-path)
                       (diff-children-indexed ot nt (+ idx 1) path))))))))

(df diff-nodes [(n1 VNode) (n2 VNode) (path String)] -> (List MutationRecord)
  :d "Recursively diffs two VNodes and returns atomic mutation records"
  (mt n1
    ((text-node c1)
     (mt n2
       ((text-node c2)
        (if (= c1 c2)
          (list)
          (list (mutated path "text" c2))))
       ((element-node _ _ _)
        (list (removed path "text") (added path n2)))))
    ((element-node t1 a1 ch1)
     (mt n2
       ((text-node _)
        (list (removed path t1) (added path n2)))
       ((element-node t2 a2 ch2)
        (if (= t1 t2)
          (list-append (diff-attributes a1 a2 path)
                       (diff-children-indexed ch1 ch2 0 path))
          (list (removed path t1) (added path n2))))))))

(df partition-diff [(route String) (records (List MutationRecord))] -> DomDiff
  :d "Partitions mutation records into categorized added, removed, and mutated lists"
  (let [(adds (fold (fn [(acc (List VNode)) (m MutationRecord)] -> (List VNode)
                      (mt m
                        ((added _ n) (list-append acc (list n)))
                        (_ acc)))
                    (list)
                    records))
        (rems (fold (fn [(acc (List String)) (m MutationRecord)] -> (List String)
                      (mt m
                        ((removed t r) (list-append acc (list (if (string-empty? r) t (str t ":" r)))))
                        (_ acc)))
                    (list)
                    records))
        (muts (fold (fn [(acc (List MutationRecord)) (m MutationRecord)] -> (List MutationRecord)
                      (mt m
                        ((mutated _ _ _) (list-append acc (list m)))
                        (_ acc)))
                    (list)
                    records))]
    (DomDiff
      :route route
      :mutations records
      :added adds
      :removed rems
      :mutated muts)))

(df dom-diff [(old-tree VNode) (new-tree VNode) (route String)] -> DomDiff
  :d "Computes incremental DOM mutations between two VNode trees for an agent execution cycle"
  (let [(records (diff-nodes old-tree new-tree "root"))]
    (partition-diff route records)))

(df format-diff-frame [(diff DomDiff)] -> String
  :d "Formats a DomDiff record into a compact S-expression frame for agent transmission"
  (str "(! dom/diff :route \"" (.-route diff) "\""
       " :added-count " (string-from-int64 (list-length (.-added diff)))
       " :removed-count " (string-from-int64 (list-length (.-removed diff)))
       " :mutated-count " (string-from-int64 (list-length (.-mutated diff)))
       ")"))


