(module aslMem/store :x [VectorItem VectorStore VectorSlab makeVectorSlab slabSlotOffset slabInsert sqrtApprox dot normalizeVector dotNormalized validateVectorDim safeInsertItem] :i [(math :a m)])

(schema VectorItem (:f id Str) (:f text Str) (:f vector (List F64)))

(schema VectorStore (:f name Str) (:f dimensions I64) (:f items (List VectorItem)))

fn newtonStep guess: F64 x: F64 -> F64
  (* 0.5 (+ guess (/ x guess)))

fn sqrtApprox x: F64 -> F64
  (if (<= x 0.0) 0.0 (fold (fn [(g F64) (i I64)] -> F64 (newtonStep g x)) x (range 0 24)))

fn dotHelper a: (List F64) b: (List F64) acc: F64 -> F64
  (if (or (listEmpty? a) (listEmpty? b)) acc (let [(hA (optionOr (listHead a) 0.0)) (hB (optionOr (listHead b) 0.0)) (tA (optionOr (listTail a) (list))) (tB (optionOr (listTail b) (list)))] (dotHelper tA tB (+ acc (* hA hB)))))

fn dot a: (List F64) b: (List F64) -> F64
  (dotHelper a b 0.0)

fn normalizeVector v: (List F64) -> (List F64)
  (let [(norm (m/vectorNorm v))] (if (= norm 0.0) v (map (fn [(x F64)] -> F64 (/ x norm)) v)))

fn dotNormalized a: (List F64) b: (List F64) -> F64
  (dot a b)

fn validateVectorDim store: VectorStore v: (List F64) -> Bool
  (= (listLength v) store.dimensions)

fn safeInsertItem store: VectorStore item: VectorItem -> (Option VectorStore)
  (if (validateVectorDim store item.vector) (some (with store :items (listAppend store.items (list item)))) (none))

(schema VectorSlab (:f dimensions I64) (:f capacity I64) (:f count I64) (:f ids (List Str)) (:f data (List F64)))

fn makeVectorSlab dim: I64 cap: I64 -> VectorSlab
  (VectorSlab :dimensions dim :capacity cap :count 0 :ids (list) :data (list))

fn slabSlotOffset slot: I64 dim: I64 -> I64
  (* slot dim)

fn slabInsert slab: VectorSlab id: Str vec: (List F64) -> (Option VectorSlab)
  (if (and (= (listLength vec) slab.dimensions) (< slab.count slab.capacity)) (some (with slab :count (+ slab.count 1) :ids (listAppend slab.ids (list id)) :data (listAppend slab.data vec))) (none))
