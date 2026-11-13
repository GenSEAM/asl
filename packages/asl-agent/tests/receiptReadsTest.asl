(module aslAgent/tests/receiptReadsTest
  :x [runTests]
  :i [(aslAgent/main :a m) (aslAgent/core :a c)])

; (:m :ref LEON-RECEIPT-READS :do "the receipt's :reads and :streak from a journal the way a live run writes it: op rows with :at, read-only ops counted, writes and notes not, places ranked by count then latest turn, the top capped at readsTop with keys cut at readsKeyChars, and the streak read from the readStreak signal row")

fn row turn: Int64 name: String file: String at: String -> String
  (m/opRowAt turn name file at "ok" "")

fn longName i: Int64 -> String
  (str "asl/packages/asl-agent/src/" (stringRepeat "deep/" 40) "file" (stringFromInt64 i) ".asl")

fn ! runTests -> Bool
  (let [journal (stringJoin (list "(:session :id \"s\" :task \"t\")"
                                  (row 1 "read" "a.asl" "#foo")
                                  (row 2 "read" "a.asl" "#foo")
                                  (row 3 "read" "b.asl" ":10-40")
                                  (row 3 "outline" "c.asl" "")
                                  (row 4 "query" "" "")
                                  (row 4 "note" "n.asl" "")
                                  (row 5 "write" "w.asl" "")
                                  (row 6 "read" "a.asl" "#foo")
                                  (row 7 "read" "b.asl" ":10-40")
                                  "(:turn 7 :signal :readStreak :cause :readOnly :reason \"12 turns in a row read and nothing else, no write and no gate run\")")
                            "\n")
        reads (m/readsIn journal)
        streak (m/streakIn journal)
        many (stringJoin (map (fn [i] (row i "read" (longName i) "")) (range 1 41)) "\n")
        manyReads (m/readsIn many)
        topItems (- (listLength (stringSplit manyReads "(:at \"")) 1)
        firstKey (optionOr (listGet (stringSplit (optionOr (listGet (stringSplit manyReads "(:at \"") 1) "") "\"") 0) "")
        opSym (list (pair "op" (c/kvStr "read")) (pair "file" (c/kvStr "x.asl")) (pair "symbol" (c/kvStr "main")))
        opRange (list (pair "op" (c/kvStr "read")) (pair "file" (c/kvStr "x.asl")) (pair "start" (c/kvInt "5")) (pair "end" (c/kvInt "9")))
        opPlain (list (pair "op" (c/kvStr "read")) (pair "file" (c/kvStr "x.asl")))]
    (do
      (assert (stringStartsWith? reads " :reads (:n 7 :distinct 4 :top (") (str "seven read-only rows at four places (writes and notes not counted): " reads))
      (assert (stringContains? reads "(:at \"a.asl#foo\" :count 3 :last 6) (:at \"b.asl:10-40\" :count 2 :last 7)") (str "places rank by count, with symbol and range kept: " reads))
      (assert (stringContains? reads "(:at \"query\" :count 1 :last 4)") (str "a read op with no file is named by its op: " reads))
      (refute (stringContains? reads "w.asl") "a write is not a read")
      (refute (stringContains? reads "n.asl") "a note is not a read")
      (assert (= streak 12) (str "the streak is the readStreak signal's count: " (stringFromInt64 streak)))
      (assert (= (m/streakIn "(:turn 1 :signal :turnBudget)\n") 0) "no readStreak stop, no streak")
      (assert (= (m/readsIn "(:session :id \"s\")\n") "") "a run that read nothing adds no :reads")
      (assert (stringStartsWith? manyReads " :reads (:n 40 :distinct 40 :top (") (str "40 places all counted: " (optionOr (stringSlice manyReads 0 60) "")))
      (assert (= topItems (m/readsTop)) (str "the top list stops at readsTop (20), got " (stringFromInt64 topItems)))
      (assert (= (stringLength firstKey) (m/readsKeyChars)) (str "a long place is cut at readsKeyChars (120), got " (stringFromInt64 (stringLength firstKey))))
      (assert (< (stringLength manyReads) 4096) (str "the :reads field stays under 4 KB however many places: " (stringFromInt64 (stringLength manyReads))))
      (assert (= (m/readAtOf opSym) "#main") "a symbol read is at #symbol")
      (assert (= (m/readAtOf opRange) ":5-9") "a ranged read is at :start-end")
      (assert (= (m/readAtOf opPlain) "") "a whole-file read has no :at")
      (assert (= (row 1 "read" "a" "") (m/opRowText 1 "read" "a" "ok" "")) "an op row without :at is the old row")
      (assert (= (row 1 "read" "a" "#f") "(:op :turn 1 :name \"read\" :file \"a\" :at \"#f\" :status ok)") "an op row with :at places it before :status")
      true))
