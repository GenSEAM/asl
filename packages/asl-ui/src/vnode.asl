(module asl-ui/vnode :x [VNode makeVNode makeText makeButton makeInput makeContainer makeCanvas makeModal makeList validateKeyUniqueness])

(schema VNode (:f tag String) (:f key String) (:f text String) (:f attrs (Map String String)) (:f children (List VNode)) (:f width Int64) (:f height Int64) (:f visible Bool))

fn makeVNode tag: String key: String text: String attrs: (Map String String) children: (List VNode) width: Int64 height: Int64 visible: Bool -> VNode
  (VNode :tag tag :key key :text text :attrs attrs :children children :width width :height height :visible visible)

fn makeText content: String key: String -> VNode
  (VNode :tag "text" :key key :text content :attrs (mapEmpty) :children (list) :width 0 :height 0 :visible true)

fn makeButton key: String attrs: (Map String String) children: (List VNode) -> VNode
  (VNode :tag "button" :key key :text "" :attrs attrs :children children :width 0 :height 0 :visible true)

fn makeInput key: String attrs: (Map String String) -> VNode
  (VNode :tag "input" :key key :text "" :attrs attrs :children (list) :width 0 :height 0 :visible true)

fn makeContainer key: String attrs: (Map String String) children: (List VNode) -> VNode
  (VNode :tag "container" :key key :text "" :attrs attrs :children children :width 0 :height 0 :visible true)

fn makeCanvas key: String width: Int64 height: Int64 -> VNode
  (VNode :tag "canvas" :key key :text "" :attrs (mapEmpty) :children (list) :width width :height height :visible true)

fn makeModal key: String visible: Bool children: (List VNode) -> VNode
  (VNode :tag "modal" :key key :text "" :attrs (mapEmpty) :children children :width 0 :height 0 :visible visible)

fn makeList key: String items: (List VNode) -> VNode
  (VNode :tag "list" :key key :text "" :attrs (mapEmpty) :children items :width 0 :height 0 :visible true)

fn checkDuplicateKeysInList seen: (Map String Bool) remaining: (List VNode) -> (Result Bool String)
  (if (listEmpty? remaining) (ok true) (let [(head (optionOr (listHead remaining) (makeText "" ""))) (k head.key)] (if (and (not (stringEmpty? k)) (mapHas? seen k)) (err "ERR_VNODE_DUPLICATE_KEY") (let [(nextSeen (if (stringEmpty? k) seen (mapSet seen k true))) (tail (optionOr (listTail remaining) (list)))] (checkDuplicateKeysInList nextSeen tail)))))

fn validateKeyUniqueness node: VNode -> (Result Bool String)
  (checkDuplicateKeysInList (mapEmpty) node.children)
