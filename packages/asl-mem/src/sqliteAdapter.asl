(module sqliteAdapter :x [initSqliteStorage hasTable? sqliteWriteRecord sqliteReadRecord sqliteQueryRecords sqliteDeleteRecord makeEmptyRow SqliteStorageState SqliteRow] :i [])

(schema SqliteRow (:f id Str) (:f phase Str) (:f status Str) (:f payload Str))

(schema SqliteStorageState (:f dbPath Str) (:f tables (Map Str (Map Str SqliteRow))))

fn makeEmptyRow -> SqliteRow
  (SqliteRow :id "" :phase "" :status "" :payload "")

fn initSqliteStorage dbPath: Str -> SqliteStorageState
  (let [(t0 (mapEmpty)) (t1 (mapSet t0 "tasks" (mapEmpty))) (t2 (mapSet t1 "decisions" (mapEmpty))) (t3 (mapSet t2 "notes" (mapEmpty)))] (SqliteStorageState :dbPath dbPath :tables t3))

fn hasTable? st: SqliteStorageState tableName: Str -> Bool
  (mapHas? st.tables tableName)

fn sqliteWriteRecord st: SqliteStorageState table: Str id: Str phase: Str status: Str payload: Str -> (Result SqliteStorageState Str)
  (if (not (hasTable? st table)) (err "Table does not exist") (if (= id "") (err "Empty ID") (let [(tableMap (optionOr (mapGet st.tables table) (mapEmpty))) (newRow (SqliteRow :id id :phase phase :status status :payload payload)) (updatedTableMap (mapSet tableMap id newRow)) (updatedTables (mapSet st.tables table updatedTableMap))] (ok (with st :tables updatedTables)))))

fn sqliteReadRecord st: SqliteStorageState table: Str id: Str -> (Result SqliteRow Str)
  (if (not (hasTable? st table)) (err "Table does not exist") (if (= id "") (err "Empty ID") (let [(tableMap (optionOr (mapGet st.tables table) (mapEmpty)))] (mt (mapGet tableMap id) ((some row) (ok row)) ((none) (err "Record not found"))))))

fn filterRowsLoop rows: (List SqliteRow) phase: Str status: Str acc: (List SqliteRow) -> (List SqliteRow)
  (if (listEmpty? rows) acc (let [(headRow (optionOr (listHead rows) (makeEmptyRow))) (tailRows (optionOr (listTail rows) (list)))] (if (and (= headRow.phase phase) (= headRow.status status)) (filterRowsLoop tailRows phase status (listAppend acc (list headRow))) (filterRowsLoop tailRows phase status acc))))

fn sqliteQueryRecords st: SqliteStorageState table: Str phase: Str status: Str -> (Result (List SqliteRow) Str)
  (if (not (hasTable? st table)) (err "Table does not exist") (let [(tableMap (optionOr (mapGet st.tables table) (mapEmpty))) (rows (mapValues tableMap)) (filtered (filterRowsLoop rows phase status (list)))] (ok filtered)))

fn sqliteDeleteRecord st: SqliteStorageState table: Str id: Str -> (Result SqliteStorageState Str)
  (if (not (hasTable? st table)) (err "Table does not exist") (if (= id "") (err "Empty ID") (let [(tableMap (optionOr (mapGet st.tables table) (mapEmpty)))] (if (not (mapHas? tableMap id)) (err "Record not found") (let [(updatedTableMap (mapRemove tableMap id)) (updatedTables (mapSet st.tables table updatedTableMap))] (ok (with st :tables updatedTables)))))))
