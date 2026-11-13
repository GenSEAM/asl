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

fn pairOk? d: Int64 s: Int64 -> Bool
  (and (>= d 0) (and (>= s 0) (= d s)))

fn ! checkPair row: String src: String docMarker: String srcMarker: String label: String -> Bool
  (let [(d (numAfter row docMarker))
        (s (numAfter src srcMarker))]
    (do (assert (pairOk? d s) (str label ": doc says " (stringFromInt64 d) " after '" docMarker "', source says " (stringFromInt64 s) " after '" srcMarker "'"))
        true))

; (:m :ref GC-DOC-GATE-LOWS :do "every load and store of a page field, not only the first: each site marker occurs once in gcAsl.asl and its offset equals the doc's number, so a drift at any site (the sweep's allocCount store and cursor reset, the bump path, the free-slot scan) is red")
fn ! checkSites row: String src: String docMarker: String sites: (List String) label: String -> Bool
  (do (map (fn [(m String)] -> Bool
             (do (assert (= (- (listLength (stringSplit src m)) 1) 1) (str label ": site '" m "' occurs once in gcAsl.asl"))
                 (checkPair row src docMarker m (str label " at '" m "'"))))
           sites)
      true)

fn ! runTests -> Bool
  (let [(row (docRow (docText)))
        (src (srcText))]
    (do (assert (not (stringEmpty? row)) "the gcAsl module doc row is found")
        (assert (not (stringEmpty? src)) "gcAsl.asl is readable")
        (checkPair row src "(here: next " "(ld \"pnx\" \"p\" " "next")
        (checkPair row src ", nextFree " "(st \"w10\" \"p\" " "nextFree")
        (checkPair row src "pages with a " "fn pageHeader -> Int64\n  " "pageHeader")
        (checkPair row src "recip " "fn recipAt -> Int64\n  " "recipAt")
        (checkPair row src "the inUse bitmap at " "fn inUseBits -> Int64\n  " "inUseBits")
        (checkPair row src "mark bitmap at " "fn markBits -> Int64\n  " "markBits")
        (checkPair row src "16 words each, " "fn headerUsed -> Int64\n  " "headerUsed")
        (checkPair row src ", slotSize " "(st \"wss\" \"p\" " "slotSize")
        (checkPair row src "slotCount " "(st \"wcnt\" \"p\" " "slotCount")
        (checkSites row src "allocCount " (list "(ld \"ac\" \"hp\" " "(st \"w9\" \"hp\" " "(ld \"ac\" \"p\" " "(ld \"pac\" \"p\" " "(st \"w8\" \"p\" ") "allocCount")
        (checkSites row src "the bump slot index at " (list "(ld \"b\" \"bp\" " "(st \"w7\" \"bp\" " "(ld \"bi\" \"ap\" " "(ld \"lim\" \"fp\" " "(ld \"lim\" \"p\" ") "bump slot index")
        (checkSites row src "the free-slot scan cursor at " (list "(st \"wc\" \"fp\" " "(ld \"cur\" \"fp\" " "(st \"w7\" \"p\" ") "scan cursor")
        true))
