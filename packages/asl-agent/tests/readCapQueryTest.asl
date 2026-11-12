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
    true)
