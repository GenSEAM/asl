(module asl-ui/vnode
  :d "Pure AgentScript Declarative UI Virtual Node Primitives and Key Validation"
  :x [VNode
      makeVNode
      makeText
      makeButton
      makeInput
      makeContainer
      makeCanvas
      makeModal
      makeList
      validateKeyUniqueness])

(dfs VNode
  (:f tag String)
  (:f key String)
  (:f text String)
  (:f attrs (Map String String))
  (:f children (List VNode))
  (:f width Int64)
  (:f height Int64)
  (:f visible Bool))

(df makeVNode [(tag String)
               (key String)
               (text String)
               (attrs (Map String String))
               (children (List VNode))
               (width Int64)
               (height Int64)
               (visible Bool)] -> VNode
  :d "Constructs a generic VNode record"
  (VNode :tag tag
         :key key
         :text text
         :attrs attrs
         :children children
         :width width
         :height height
         :visible visible))

(df makeText [(content String) (key String)] -> VNode
  :d "Constructs a text virtual node primitive"
  (VNode :tag "text"
         :key key
         :text content
         :attrs (map-empty)
         :children (list)
         :width 0
         :height 0
         :visible true))

(df makeButton [(key String) (attrs (Map String String)) (children (List VNode))] -> VNode
  :d "Constructs a button virtual node primitive"
  (VNode :tag "button"
         :key key
         :text ""
         :attrs attrs
         :children children
         :width 0
         :height 0
         :visible true))

(df makeInput [(key String) (attrs (Map String String))] -> VNode
  :d "Constructs an input virtual node primitive"
  (VNode :tag "input"
         :key key
         :text ""
         :attrs attrs
         :children (list)
         :width 0
         :height 0
         :visible true))

(df makeContainer [(key String) (attrs (Map String String)) (children (List VNode))] -> VNode
  :d "Constructs a layout container virtual node primitive"
  (VNode :tag "container"
         :key key
         :text ""
         :attrs attrs
         :children children
         :width 0
         :height 0
         :visible true))

(df makeCanvas [(key String) (width Int64) (height Int64)] -> VNode
  :d "Constructs a canvas drawing surface virtual node primitive"
  (VNode :tag "canvas"
         :key key
         :text ""
         :attrs (map-empty)
         :children (list)
         :width width
         :height height
         :visible true))

(df makeModal [(key String) (visible Bool) (children (List VNode))] -> VNode
  :d "Constructs a modal dialog container virtual node primitive"
  (VNode :tag "modal"
         :key key
         :text ""
         :attrs (map-empty)
         :children children
         :width 0
         :height 0
         :visible visible))

(df makeList [(key String) (items (List VNode))] -> VNode
  :d "Constructs a list container virtual node primitive"
  (VNode :tag "list"
         :key key
         :text ""
         :attrs (map-empty)
         :children items
         :width 0
         :height 0
         :visible true))

(df checkDuplicateKeysInList [(seen (Map String Bool)) (remaining (List VNode))] -> (Result Bool String)
  :d "Recursively checks child list for duplicate non-empty keys"
  (if (list-empty? remaining)
    (ok true)
    (let [(head (option-or (list-head remaining) (makeText "" "")))
          (k (.-key head))]
      (if (and (not (string-empty? k)) (map-has? seen k))
        (err "ERR_VNODE_DUPLICATE_KEY")
        (let [(nextSeen (if (string-empty? k) seen (map-set seen k true)))
              (tail (option-or (list-tail remaining) (list)))]
          (checkDuplicateKeysInList nextSeen tail))))))

(df validateKeyUniqueness [(node VNode)] -> (Result Bool String)
  :d "Validates that all immediate children of a VNode have unique keys"
  (checkDuplicateKeysInList (map-empty) (.-children node)))
