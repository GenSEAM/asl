(module aslAgent/tests/absorbRawLowsTest
  :x [runTests]
  :i [(aslAgent/reply :a r)])

; (:m :ref ABSORB-AGENT-LOWS :do "grader lows of 2026-11-18 on the raw binder: a foreign-key :raw refuses the reply, an edit binds its tail blocks in the order its fields are written, and only blank or caption lines may stand between two tail blocks")
fn q -> String
  "```"

fn block body: String -> String
  (str (q) "\n" body "\n" (q) "\n")

fn ! runTests -> Bool
  (let [foreign (r/bindRawBlocks (str "(:step :op \"write\" :file \"a.txt\" :contents :raw)\n" (block "AAA")))
        foreignBody (r/bindRawBlocks (str "(:step :op \"write\" :file \"a.txt\" :body :raw)\n" (block "AAA")))
        swapped (r/bindRawBlocks (str "(:step :op \"edit\" :file \"a.txt\" :new :raw :old :raw)\n" (block "NNN") (block "OOO")))
        prose (r/bindRawBlocks (str "(:step :op \"edit\" :file \"a.txt\" :old :raw :new :raw)\n" (block "OOO") "and then the file reads\n" (block "NNN")))
        caption (r/bindRawBlocks (str "(:step :op \"edit\" :file \"a.txt\" :old :raw :new :raw)\n" (block "OOO") "\nnew text:\n\n" (block "NNN")))
        before (r/bindRawBlocks (str "Here is the file:\n" (block "AAA") "\n(:step :op \"write\" :file \"a.txt\" :content :raw)\n"))
        twoSlots (r/bindRawBlocks (str (block "OOO") "(:step :op \"edit\" :file \"a.txt\" :old :raw :new :raw)\n"))
        twoBlocks (r/bindRawBlocks (str (block "AAA") "(:step :op \"write\" :file \"a.txt\" :content :raw)\n" (block "BBB")))
        inForm (r/bindRawBlocks (str "(:step :op \"write\" :file \"a.txt\"\n" (block "AAA") " :content :raw)\n"))]
    (do
      (assert (and (= foreign.count 0) (= (listLength foreign.missing) 1)) (str "a write whose only :raw is on :contents refuses the whole reply: " foreign.text))
      (assert (and (= foreignBody.count 0) (not (listEmpty? foreignBody.missing))) "a write whose only :raw is on :body refuses the whole reply")
      (assert (and (= swapped.count 2) (and (stringContains? swapped.text ":new \"NNN") (stringContains? swapped.text ":old \"OOO"))) (str "an edit sent :new :raw :old :raw binds its two tail blocks in that order: " swapped.text))
      (assert (and (= prose.count 0) (not (listEmpty? prose.missing))) (str "prose between two tail blocks refuses the reply: " prose.text))
      (assert (and (= caption.count 2) (and (stringContains? caption.text ":old \"OOO") (stringContains? caption.text ":new \"NNN"))) (str "blank lines and a caption ending in a colon between tail blocks still bind: " caption.text))
      (assert (and (= before.count 1) (stringContains? before.text ":content \"AAA")) (str "the only block of the reply binds to the only :raw slot even before its step: " before.text))
      (assert (and (= twoSlots.count 0) (not (listEmpty? twoSlots.missing))) "one block and two :raw slots refuse the reply")
      (assert (and (= twoBlocks.count 0) (not (listEmpty? twoBlocks.missing))) "two blocks and one :raw slot refuse the reply")
      (assert (and (= inForm.count 0) (not (listEmpty? inForm.missing))) (str "a single block inside the step form before its slot is no exception: " inForm.text))
      true))
