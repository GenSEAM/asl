(module asl-ui/arena
  :d "Pure AgentScript Double-Buffered Frame Arena Allocator and Keyed VNode Diffing"
  :x [MutationRecord
      makeMutationRecord
      FrameArena
      makeFrameArena
      allocFrameNode
      tryAllocFrameNode
      swapArenas
      getArenaAllocatedBytes
      diffVNodes
      hasMutationKind]
  :i [(asl-ui/vnode :a ui)])

(dfs MutationRecord
  (:f kind String)
  (:f targetKey String)
  (:f node ui/VNode)
  (:f attrs (Map String String))
  (:f index Int64))

(df makeMutationRecord [(kind String)
                        (targetKey String)
                        (nodeType String)] -> MutationRecord
  :d "Constructs an atomic mutation record descriptor from kind, targetKey, and nodeType tag"
  (MutationRecord :kind kind
                  :targetKey targetKey
                  :node (ui/makeVNode nodeType targetKey "" (map-empty) (list) 0 0 true)
                  :attrs (map-empty)
                  :index 0))

(df makeMutationRecord [(kind String)
                        (targetKey String)
                        (node ui/VNode)
                        (attrs (Map String String))
                        (index Int64)] -> MutationRecord
  :d "Constructs an atomic mutation record descriptor"
  (MutationRecord :kind kind
                  :targetKey targetKey
                  :node node
                  :attrs attrs
                  :index index))

(dfs FrameArena
  (:f capacityBytes Int64)
  (:f activeIdx Int64)
  (:f offset0 Int64)
  (:f offset1 Int64)
  (:f nodesCount0 Int64)
  (:f nodesCount1 Int64))

(df makeFrameArena [(capacityBytes Int64)] -> FrameArena
  :d "Initializes double-buffered frame arena with specified capacity"
  (FrameArena :capacityBytes capacityBytes
              :activeIdx 0
              :offset0 0
              :offset1 0
              :nodesCount0 0
              :nodesCount1 0))

(df align8 [(n Int64)] -> Int64
  :d "Aligns integer size upward to next 8-byte boundary"
  (let [(rem (mod n 8))]
    (if (= rem 0)
      n
      (+ n (- 8 rem)))))

(df tryAllocFrameNode [(arena FrameArena) (key String) (tag String) (sizeBytes Int64)] -> (Result ui/VNode String)
  :d "Allocates node slot with 8-byte alignment and overflow protection"
  (let [(aligned (align8 sizeBytes))
        (curOffset (if (= (.-activeIdx arena) 0) (.-offset0 arena) (.-offset1 arena)))]
    (if (> (+ curOffset aligned) (.-capacityBytes arena))
      (err "ERR_ARENA_OVERFLOW")
      (let [(newNode (ui/makeVNode tag key "" (map-empty) (list) 0 0 true))]
        (ok newNode)))))

(df allocFrameNode [(arena FrameArena) (key String) (tag String) (sizeBytes Int64)] -> (Result ui/VNode String)
  :d "Allocates virtual node within active arena buffer"
  (tryAllocFrameNode arena key tag sizeBytes))

(df swapArenas [(arena FrameArena)] -> FrameArena
  :d "Ping-pongs active arena index and resets recycled arena memory offset"
  (if (= (.-activeIdx arena) 0)
    (FrameArena :capacityBytes (.-capacityBytes arena)
                :activeIdx 1
                :offset0 (.-offset0 arena)
                :offset1 0
                :nodesCount0 (.-nodesCount0 arena)
                :nodesCount1 0)
    (FrameArena :capacityBytes (.-capacityBytes arena)
                :activeIdx 0
                :offset0 0
                :offset1 (.-offset1 arena)
                :nodesCount0 0
                :nodesCount1 (.-nodesCount1 arena))))

(df getArenaAllocatedBytes [(arena FrameArena)] -> Int64
  :d "Returns allocated byte count for the currently active frame arena"
  (if (= (.-activeIdx arena) 0)
    (.-offset0 arena)
    (.-offset1 arena)))

(df buildKeyIndexMap [(children (List ui/VNode)) (idx Int64) (acc (Map String Int64))] -> (Map String Int64)
  :d "Indexes child list into map of key to index"
  (if (list-empty? children)
    acc
    (let [(head (option-or (list-head children) (ui/makeText "" "")))
          (tail (option-or (list-tail children) (list)))
          (k (.-key head))]
      (buildKeyIndexMap tail (+ idx 1) (if (string-empty? k) acc (map-set acc k idx))))))

(df buildChildKeyMap [(children (List ui/VNode)) (acc (Map String ui/VNode))] -> (Map String ui/VNode)
  :d "Indexes child list into map of key to VNode"
  (if (list-empty? children)
    acc
    (let [(head (option-or (list-head children) (ui/makeText "" "")))
          (tail (option-or (list-tail children) (list)))
          (k (.-key head))]
      (buildChildKeyMap tail (if (string-empty? k) acc (map-set acc k head))))))

(df findRemovedChildren [(oldChildren (List ui/VNode)) (newKeyMap (Map String ui/VNode)) (acc (List MutationRecord))] -> (List MutationRecord)
  :d "Emits remove mutations for children in old tree absent from new tree"
  (if (list-empty? oldChildren)
    acc
    (let [(head (option-or (list-head oldChildren) (ui/makeText "" "")))
          (tail (option-or (list-tail oldChildren) (list)))
          (k (.-key head))]
      (if (and (not (string-empty? k)) (not (map-has? newKeyMap k)))
        (findRemovedChildren tail newKeyMap (list-append acc (list (makeMutationRecord "remove" k head (map-empty) 0))))
        (findRemovedChildren tail newKeyMap acc)))))

(df findInsertedOrReorderedChildren [(newChildren (List ui/VNode))
                                     (oldKeyMap (Map String ui/VNode))
                                     (oldIndexMap (Map String Int64))
                                     (newIdx Int64)
                                     (acc (List MutationRecord))] -> (List MutationRecord)
  :d "Emits insert or reorder mutations for children in new tree"
  (if (list-empty? newChildren)
    acc
    (let [(head (option-or (list-head newChildren) (ui/makeText "" "")))
          (tail (option-or (list-tail newChildren) (list)))
          (k (.-key head))]
      (if (string-empty? k)
        (findInsertedOrReorderedChildren tail oldKeyMap oldIndexMap (+ newIdx 1) acc)
        (if (not (map-has? oldKeyMap k))
          (findInsertedOrReorderedChildren tail oldKeyMap oldIndexMap (+ newIdx 1)
                                           (list-append acc (list (makeMutationRecord "insert" k head (map-empty) newIdx))))
          (let [(oldIdx (option-or (map-get oldIndexMap k) -1))]
            (if (not (= oldIdx newIdx))
              (findInsertedOrReorderedChildren tail oldKeyMap oldIndexMap (+ newIdx 1)
                                               (list-append acc (list (makeMutationRecord "reorder" k head (map-empty) newIdx))))
              (findInsertedOrReorderedChildren tail oldKeyMap oldIndexMap (+ newIdx 1) acc))))))))

(df checkKeysLoop [(m1 (Map String String)) (m2 (Map String String)) (rem (List String))] -> Bool
  :d "Recursively verifies that all keys have identical values across both maps"
  (if (list-empty? rem)
    true
    (let [(k (option-or (list-head rem) ""))
          (v1 (map-get m1 k))
          (v2 (map-get m2 k))]
      (if (not (= v1 v2))
        false
        (checkKeysLoop m1 m2 (option-or (list-tail rem) (list)))))))

(df mapsEqual [(m1 (Map String String)) (m2 (Map String String))] -> Bool
  :d "Compares two string maps for equality"
  (let [(k1 (map-keys m1))
        (k2 (map-keys m2))]
    (if (not (= (list-length k1) (list-length k2)))
      false
      (checkKeysLoop m1 m2 k1))))

(df diffVNodes [(oldNode ui/VNode) (newNode ui/VNode)] -> (List MutationRecord)
  :d "Computes minimal atomic MutationRecords converting old VNode tree to new VNode tree"
  (if (not (= (.-tag oldNode) (.-tag newNode)))
    (list (makeMutationRecord "replace" (.-key oldNode) newNode (map-empty) 0))
    (let [(attrMutations (if (not (mapsEqual (.-attrs oldNode) (.-attrs newNode)))
                           (list (makeMutationRecord "updateAttrs" (.-key newNode) newNode (.-attrs newNode) 0))
                           (list)))
          (oldChildren (.-children oldNode))
          (newChildren (.-children newNode))
          (oldKeyMap (buildChildKeyMap oldChildren (map-empty)))
          (newKeyMap (buildChildKeyMap newChildren (map-empty)))
          (oldIndexMap (buildKeyIndexMap oldChildren 0 (map-empty)))
          (removals (findRemovedChildren oldChildren newKeyMap (list)))
          (insertOrReorders (findInsertedOrReorderedChildren newChildren oldKeyMap oldIndexMap 0 (list)))]
      (list-concat attrMutations (list-concat removals insertOrReorders)))))

(df hasMutationKind [(mutations (List MutationRecord)) (targetKind String)] -> Bool
  :d "Checks whether a list of mutation records contains a specific mutation kind"
  (if (list-empty? mutations)
    false
    (let [(head (option-or (list-head mutations) (makeMutationRecord "" "" (ui/makeText "" "") (map-empty) 0)))
          (tail (option-or (list-tail mutations) (list)))]
      (if (= (.-kind head) targetKind)
        true
        (hasMutationKind tail targetKind)))))
