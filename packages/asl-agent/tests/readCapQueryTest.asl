(module aslAgent/tests/readCapQueryTest
  :x [runTests]
  :i [(aslAgent/main :a m) (asl-json/json :a j)])

; (:m :ref LEON-READCAP-QUERY :do "a turn whose steps are only query, search, intel or outline reads and persists nothing, so readOnlyEntry? counts it toward the read-only cap")
fn entry ops: String wrote: String -> j/Json
  (j/jobj (list (pair "ops" (j/jstr ops)) (pair "wrote" (j/jstr wrote))))

fn ! runTests -> Bool
  (do
    (assert (m/readOnlyEntry? (entry "query" "0")) "a query-only turn is read-only")
    (assert (m/readOnlyEntry? (entry "search" "0")) "a search-only turn is read-only")
    (assert (m/readOnlyEntry? (entry "intel" "0")) "an intel-only turn is read-only")
    (assert (m/readOnlyEntry? (entry "outline" "0")) "an outline-only turn is read-only")
    (assert (m/readOnlyEntry? (entry "query search intel outline" "0")) "a turn mixing only read ops is read-only")
    (assert (not (m/readOnlyEntry? (entry "query" "1"))) "a turn that persisted a write is not read-only")
    (assert (not (m/readOnlyEntry? (entry "run" "0"))) "a run turn is not read-only")
    (assert (not (m/readOnlyEntry? (entry "read write" "0"))) "a turn with a refused write is not a read-only turn")
    (assert (m/refusedWriteEntry? (entry "read edit" "0")) "a read beside a refused edit is a refused-write turn")
    (assert (not (m/refusedWriteEntry? (entry "edit" "1"))) "a persisted edit is not a refused-write turn")
    (assert (= (m/readOnlyTail (list (entry "read" "0") (entry "write" "0") (entry "txn" "0") (entry "read" "0"))) 2) "refused writes between reads neither count nor reset: two reads count 2")
    (assert (= (m/readOnlyTail (list (entry "read" "0") (entry "run" "0") (entry "read" "0"))) 1) "a run step still resets the count")
    (assert (= (m/readOnlyTail (list (entry "edit" "0") (entry "edit" "0") (entry "edit" "0"))) 0) "a streak of refused edits adds nothing to the read-only count")
    true)
