(module asl-target-llvm/tests/gcDocLayoutTest
  :x [runTests]
  :i [])

; (:m :ref GC-DOC-OFFSET-GATE :do "the page layout numbers in the gcAsl module doc row equal the source: the named constants pageHeader recipAt inUseBits markBits headerUsed read from gcAsl.asl, and slotSize 24, slotCount 32, allocCount 40, bump slot index 56, scan cursor 64 read from the SSA builders' literals; editing a doc number or a source constant goes red")
fn ! docText -> String
  (resultOr (fileReadString "asl/packages/asl-target-llvm/doc.asn") "")

fn ! srcText -> String
  (resultOr (fileReadString "asl/packages/asl-target-llvm/src/gcAsl.asl") "")

fn digitRun s: String i: Int64 -> Int64
  (if (>= i (stringLength s)) i
    (let [(c (charCode (optionOr (stringSlice s i (+ i 1)) "")))]
      (if (and (>= c 48) (<= c 57)) (digitRun s (+ i 1)) i)))

fn numAfter text: String marker: String -> Int64
  (match (stringIndexOf text marker)
    ((none) -1)
    ((some at)
      (let [(start (+ at (stringLength marker)))
            (stop (digitRun text start))]
        (if (= stop start) -1 (optionOr (stringToInt64 (optionOr (stringSlice text start stop) "")) -1)))))

fn docRow text: String -> String
  (match (stringIndexOf text "gcAsl.asl#\" :text \"The collector of native programs")
    ((none) "")
    ((some at) (optionOr (stringSlice text at (+ at 4200)) "")))

fn constOf src: String name: String -> Int64
  (numAfter src (str "fn " name " -> Int64\n  "))

fn ! pairCheck row: String src: String docMarker: String srcMarker: String label: String -> Bool
  (let [(d (numAfter row docMarker))
        (s (numAfter src srcMarker))]
    (do (assert (> d 0) (str label ": the doc row states a number after '" docMarker "'"))
        (assert (> s 0) (str label ": the source has a number after '" srcMarker "'"))
        (assert (= d s) (str label ": doc says " (stringFromInt64 d) ", source says " (stringFromInt64 s)))
        true))

fn ! runTests -> Bool
  (let [(row (docRow (docText)))
        (src (srcText))]
    (do (assert (not (stringEmpty? row)) "the gcAsl module doc row is found")
        (assert (not (stringEmpty? src)) "gcAsl.asl is readable")
        (assert (pairCheck row src "pages with a " "fn pageHeader -> Int64\n  " "pageHeader"))
        (assert (pairCheck row src "recip " "fn recipAt -> Int64\n  " "recipAt"))
        (assert (pairCheck row src "the inUse bitmap at " "fn inUseBits -> Int64\n  " "inUseBits"))
        (assert (pairCheck row src "mark bitmap at " "fn markBits -> Int64\n  " "markBits"))
        (assert (pairCheck row src "16 words each, " "fn headerUsed -> Int64\n  " "headerUsed"))
        (assert (pairCheck row src ", slotSize " "(st \"wss\" \"p\" " "slotSize"))
        (assert (pairCheck row src "slotCount " "(st \"wcnt\" \"p\" " "slotCount"))
        (assert (pairCheck row src "allocCount " "(ld \"ac\" \"hp\" " "allocCount"))
        (assert (pairCheck row src "the bump slot index at " "(ld \"b\" \"bp\" " "bump slot index"))
        (assert (pairCheck row src "the free-slot scan cursor at " "(st \"wc\" \"fp\" " "scan cursor"))
        true))
