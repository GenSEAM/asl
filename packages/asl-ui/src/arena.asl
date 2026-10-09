(module asl-ui/arena :x [MutationRecord makeMutationRecord makeMutationRecordOfType FrameArena makeFrameArena FrameArenaPair makeFrameArenaPair allocFrameNode tryAllocFrameNode swapArenas swapFrameArena resetInactiveArena getArenaAllocatedBytes diffVNodes hasMutationKind] :i [(asl-ui/vnode :a ui)])

(schema MutationRecord (:f kind String) (:f targetKey String) (:f node ui/VNode) (:f attrs (Map String String)) (:f index Int64))

fn makeMutationRecordOfType kind: String targetKey: String nodeType: String -> MutationRecord
  (MutationRecord :kind kind :targetKey targetKey :node (ui/makeVNode nodeType targetKey "" (mapEmpty) (list) 0 0 true) :attrs (mapEmpty) :index 0)

fn makeMutationRecord kind: String targetKey: String node: ui/VNode attrs: (Map String String) index: Int64 -> MutationRecord
  (MutationRecord :kind kind :targetKey targetKey :node node :attrs attrs :index index)

(schema FrameArena (:f capacityBytes Int64) (:f activeIdx Int64) (:f offset0 Int64) (:f offset1 Int64) (:f nodesCount0 Int64) (:f nodesCount1 Int64))

fn makeFrameArena capacityBytes: Int64 -> FrameArena
  (FrameArena :capacityBytes capacityBytes :activeIdx 0 :offset0 0 :offset1 0 :nodesCount0 0 :nodesCount1 0)

(schema FrameArenaPair (:f arenaA FrameArena) (:f arenaB FrameArena) (:f currentTick Int64) (:f isAActive Bool))

fn makeFrameArenaPair capacityBytes: Int64 -> FrameArenaPair
  (FrameArenaPair :arenaA (makeFrameArena capacityBytes) :arenaB (makeFrameArena capacityBytes) :currentTick 0 :isAActive true)

fn align8 n: Int64 -> Int64
  (let [(rem (mod n 8))] (if (= rem 0) n (+ n (- 8 rem))))

fn tryAllocFrameNode arena: FrameArena key: String tag: String sizeBytes: Int64 -> (Result ui/VNode String)
  (let [(aligned (align8 sizeBytes)) (curOffset (if (= arena.activeIdx 0) arena.offset0 arena.offset1))] (if (> (+ curOffset aligned) arena.capacityBytes) (err "ERR_ARENA_OVERFLOW") (let [(newNode (ui/makeVNode tag key "" (mapEmpty) (list) 0 0 true))] (ok newNode))))

fn allocFrameNode arena: FrameArena key: String tag: String sizeBytes: Int64 -> (Result ui/VNode String)
  (tryAllocFrameNode arena key tag sizeBytes)

fn swapArenas arena: FrameArena -> FrameArena
  (if (= arena.activeIdx 0) (with arena :activeIdx 1 :offset1 0 :nodesCount1 0) (with arena :activeIdx 0 :offset0 0 :nodesCount0 0))

fn swapFrameArena pair: FrameArenaPair -> FrameArenaPair
  (let [(nextTick (+ pair.currentTick 1)) (nextAActive (not pair.isAActive))] (FrameArenaPair :arenaA (swapArenas pair.arenaA) :arenaB (swapArenas pair.arenaB) :currentTick nextTick :isAActive nextAActive))

fn resetInactiveArena pair: FrameArenaPair -> FrameArenaPair
  (if pair.isAActive (with pair :arenaB (makeFrameArena pair.arenaB.capacityBytes) :isAActive true) (with pair :arenaA (makeFrameArena pair.arenaA.capacityBytes) :isAActive false))

fn getArenaAllocatedBytes arena: FrameArena -> Int64
  (if (= arena.activeIdx 0) arena.offset0 arena.offset1)

fn buildKeyIndexMap children: (List ui/VNode) idx: Int64 acc: (Map String Int64) -> (Map String Int64)
  (if (listEmpty? children) acc (let [(head (optionOr (listHead children) (ui/makeText "" ""))) (tail (optionOr (listTail children) (list))) (k head.key)] (buildKeyIndexMap tail (+ idx 1) (if (stringEmpty? k) acc (mapSet acc k idx)))))

fn buildChildKeyMap children: (List ui/VNode) acc: (Map String ui/VNode) -> (Map String ui/VNode)
  (if (listEmpty? children) acc (let [(head (optionOr (listHead children) (ui/makeText "" ""))) (tail (optionOr (listTail children) (list))) (k head.key)] (buildChildKeyMap tail (if (stringEmpty? k) acc (mapSet acc k head)))))

fn findRemovedChildren oldChildren: (List ui/VNode) newKeyMap: (Map String ui/VNode) acc: (List MutationRecord) -> (List MutationRecord)
  (if (listEmpty? oldChildren) acc (let [(head (optionOr (listHead oldChildren) (ui/makeText "" ""))) (tail (optionOr (listTail oldChildren) (list))) (k head.key)] (if (and (not (stringEmpty? k)) (not (mapHas? newKeyMap k))) (findRemovedChildren tail newKeyMap (listAppend acc (list (makeMutationRecord "remove" k head (mapEmpty) 0)))) (findRemovedChildren tail newKeyMap acc))))

fn findInsertedOrReorderedChildren newChildren: (List ui/VNode) oldKeyMap: (Map String ui/VNode) oldIndexMap: (Map String Int64) newIdx: Int64 acc: (List MutationRecord) -> (List MutationRecord)
  (if (listEmpty? newChildren) acc (let [(head (optionOr (listHead newChildren) (ui/makeText "" ""))) (tail (optionOr (listTail newChildren) (list))) (k head.key)] (if (stringEmpty? k) (findInsertedOrReorderedChildren tail oldKeyMap oldIndexMap (+ newIdx 1) acc) (if (not (mapHas? oldKeyMap k)) (findInsertedOrReorderedChildren tail oldKeyMap oldIndexMap (+ newIdx 1) (listAppend acc (list (makeMutationRecord "insert" k head (mapEmpty) newIdx)))) (let [(oldIdx (optionOr (mapGet oldIndexMap k) -1))] (if (not (= oldIdx newIdx)) (findInsertedOrReorderedChildren tail oldKeyMap oldIndexMap (+ newIdx 1) (listAppend acc (list (makeMutationRecord "reorder" k head (mapEmpty) newIdx)))) (findInsertedOrReorderedChildren tail oldKeyMap oldIndexMap (+ newIdx 1) acc)))))))

fn checkKeysLoop m1: (Map String String) m2: (Map String String) rem: (List String) -> Bool
  (if (listEmpty? rem) true (let [(k (optionOr (listHead rem) "")) (v1 (mapGet m1 k)) (v2 (mapGet m2 k))] (if (not (= v1 v2)) false (checkKeysLoop m1 m2 (optionOr (listTail rem) (list))))))

fn mapsEqual m1: (Map String String) m2: (Map String String) -> Bool
  (let [(k1 (mapKeys m1)) (k2 (mapKeys m2))] (if (not (= (listLength k1) (listLength k2))) false (checkKeysLoop m1 m2 k1)))

fn diffVNodes oldNode: ui/VNode newNode: ui/VNode -> (List MutationRecord)
  (if (not (= oldNode.tag newNode.tag)) (list (makeMutationRecord "replace" oldNode.key newNode (mapEmpty) 0)) (let [(attrMutations (if (not (mapsEqual oldNode.attrs newNode.attrs)) (list (makeMutationRecord "updateAttrs" newNode.key newNode newNode.attrs 0)) (list))) (oldChildren oldNode.children) (newChildren newNode.children) (oldKeyMap (buildChildKeyMap oldChildren (mapEmpty))) (newKeyMap (buildChildKeyMap newChildren (mapEmpty))) (oldIndexMap (buildKeyIndexMap oldChildren 0 (mapEmpty))) (removals (findRemovedChildren oldChildren newKeyMap (list))) (insertOrReorders (findInsertedOrReorderedChildren newChildren oldKeyMap oldIndexMap 0 (list)))] (listAppend attrMutations (listAppend removals insertOrReorders))))

fn hasMutationKind mutations: (List MutationRecord) targetKind: String -> Bool
  (if (listEmpty? mutations) false (let [(head (optionOr (listHead mutations) (makeMutationRecord "" "" (ui/makeText "" "") (mapEmpty) 0))) (tail (optionOr (listTail mutations) (list)))] (if (= head.kind targetKind) true (hasMutationKind tail targetKind))))
