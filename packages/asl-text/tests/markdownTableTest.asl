(module asl-text/tests/markdownTableTest :x [runTests] :i [(asl-text/markdownTable :a mt)])

fn sampleRows -> (List (List String))
  (list (list "Name" "Qty" "Price")
        (list "apple" "3" "1.50")
        (list "kiwi" "12" "0.75"))

fn sampleAligns -> (List String)
  (list "l" "r" "c")

fn expectedTable -> String
  "| Name  | Qty | Price |\n| ----- | --: | :---: |\n| apple |   3 | 1.50  |\n| kiwi  |  12 | 0.75  |"

fn testRender -> Bool
  (let [(rows (sampleRows))
        (aligns (sampleAligns))]
    (do (assert (= (mt/renderTable rows aligns) (expectedTable)) "render pads cells and marks alignment")
        (assert (= (mt/renderTable (list) aligns) "") "no rows renders nothing")
        true))

fn testParse -> Bool
  (let [(rows (sampleRows))
        (aligns (sampleAligns))
        (text (mt/renderTable rows aligns))]
    (do (assert (= (mt/parseTable text) (ok rows)) "parse recovers the rows")
        (assert (= (mt/parseAligns text) (ok aligns)) "parse recovers the alignments")
        true))

fn testParseEdges -> Bool
  (do (assert (err? (mt/parseTable "")) "empty text is an err")
      (assert (err? (mt/parseTable "| a | b |")) "a header without a separator is an err")
      (assert (= (mt/parseTable "a | b\n--- | ---\n1 | 2")
                 (ok (list (list "a" "b") (list "1" "2"))))
              "a table without outer pipes parses")
      (assert (= (mt/parseTable "\n| a | b |\n| --- | --- |\n| 1 | 2 |\n")
                 (ok (list (list "a" "b") (list "1" "2"))))
              "blank lines around the table are ignored")
      true)

fn testRoundTripEmptyCells -> Bool
  (let [(rows (list (list "" "b") (list "c" "")))
        (aligns (list "l" "l"))
        (text (mt/renderTable rows aligns))]
    (do (assert (= (mt/parseTable text) (ok rows)) "empty first and last cells round-trip")
        true))

fn testNarrowAligns -> Bool
  (let [(rrows (list (list "A") (list "B")))
        (raligns (list "r"))
        (rtext (mt/renderTable rrows raligns))
        (crows (list (list "A") (list "B")))
        (caligns (list "c"))
        (ctext (mt/renderTable crows caligns))]
    (do (assert (= (mt/parseTable rtext) (ok rrows)) "a width-1 right-aligned column parses back")
        (assert (= (mt/parseAligns rtext) (ok raligns)) "its alignment is r")
        (assert (= (mt/parseTable ctext) (ok crows)) "a width-1 centered column parses back")
        (assert (= (mt/parseAligns ctext) (ok caligns)) "its alignment is c")
        true))

fn runTests -> Bool
  (and (testRender) (and (testParse) (and (testParseEdges) (and (testRoundTripEmptyCells) (testNarrowAligns)))))
