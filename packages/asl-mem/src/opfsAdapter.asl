(module opfsAdapter :x [initOpfsStorage opfsWriteRecord opfsReadRecord opfsFlush opfsListRecords opfsDeleteRecord OpfsStorageState] :i [(reader :a rd)])

(schema OpfsStorageState (:f rootPrefix Str) (:f records (List Str)) (:f files (Map Str Str)))

fn isValidOpfsPath? path: Str -> Bool
  (and (not (= path "")) (and (not (stringStartsWith? path "/")) (not (stringContains? path ".."))))

fn initOpfsStorage rootPrefix: Str -> OpfsStorageState
  (OpfsStorageState :rootPrefix rootPrefix :records (list) :files (mapEmpty))

fn opfsWriteRecord st: OpfsStorageState path: Str content: Str -> (Result OpfsStorageState Str)
  (if (not (isValidOpfsPath? path)) (err "Sandbox path violation: invalid path") (let [(updatedFiles (mapSet st.files path content)) (currentRecords st.records) (updatedRecords (if (listContains? currentRecords path) currentRecords (listAppend currentRecords (list path))))] (ok (with st :records updatedRecords :files updatedFiles))))

fn opfsReadRecord st: OpfsStorageState path: Str -> (Result Str Str)
  (if (not (isValidOpfsPath? path)) (err "Sandbox path violation: invalid path") (mt (mapGet st.files path) ((some content) (ok content)) ((none) (err "Record not found"))))

fn opfsFlush st: OpfsStorageState -> (Result OpfsStorageState Str)
  (ok st)

fn opfsListRecords st: OpfsStorageState -> (Result (List Str) Str)
  (ok st.records)

fn opfsDeleteRecord st: OpfsStorageState path: Str -> (Result OpfsStorageState Str)
  (if (not (isValidOpfsPath? path)) (err "Sandbox path violation: invalid path") (if (not (mapHas? st.files path)) (err "Record not found") (let [(updatedFiles (mapRemove st.files path)) (updatedRecords (filter (fn [(p Str)] -> Bool (!= p path)) st.records))] (ok (with st :records updatedRecords :files updatedFiles)))))
