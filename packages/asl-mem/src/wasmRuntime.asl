(module wasmRuntime :x [initWasmRuntime growLinearMemory writeLinearMemory readLinearMemory WasmRuntimeState] :i [])

(schema WasmRuntimeState (:f pageCount Int) (:f maxPages Int) (:f totalBytes Int) (:f memory (Map Int Int)))

fn initWasmRuntime initialPages: Int maxPages: Int -> WasmRuntimeState
  (let [(initP (if (< initialPages 1) 1 initialPages)) (maxP (if (< maxPages initP) initP maxPages))] (WasmRuntimeState :pageCount initP :maxPages maxP :totalBytes (* initP 65536) :memory (mapEmpty)))

fn growLinearMemory st: WasmRuntimeState deltaPages: Int -> (Result WasmRuntimeState Str)
  (if (= deltaPages 0) (ok st) (if (< deltaPages 0) (err "Negative delta pages rejected") (let [(newPageCount (+ st.pageCount deltaPages))] (if (> newPageCount st.maxPages) (err "Exceeds max page ceiling") (ok (with st :pageCount newPageCount :totalBytes (+ st.totalBytes (* deltaPages 65536))))))))

fn writeBytesLoop mem: (Map Int Int) offset: Int bytes: (List Int) -> (Map Int Int)
  (if (listEmpty? bytes) mem (let [(b (optionOr (listHead bytes) 0)) (rest (optionOr (listTail bytes) (list)))] (writeBytesLoop (mapSet mem offset b) (+ offset 1) rest)))

fn writeLinearMemory st: WasmRuntimeState offset: Int bytes: (List Int) -> (Result WasmRuntimeState Str)
  (if (listEmpty? bytes) (ok st) (if (< offset 0) (err "Negative offset") (if (> (+ offset (listLength bytes)) st.totalBytes) (err "Write out of bounds") (let [(updatedMem (writeBytesLoop st.memory offset bytes))] (ok (with st :memory updatedMem))))))

fn readBytesLoop mem: (Map Int Int) offset: Int remaining: Int acc: (List Int) -> (List Int)
  (if (<= remaining 0) acc (let [(val (optionOr (mapGet mem offset) 0))] (readBytesLoop mem (+ offset 1) (- remaining 1) (listAppend acc (list val)))))

fn readLinearMemory st: WasmRuntimeState offset: Int count: Int -> (Result (List Int) Str)
  (if (= count 0) (ok (list)) (if (< offset 0) (err "Negative offset") (if (< count 0) (err "Negative count") (if (> (+ offset count) st.totalBytes) (err "Read out of bounds") (ok (readBytesLoop st.memory offset count (list)))))))
