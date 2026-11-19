(module aslAgent/tests/rawAdjacentTest
  :x [runTests]
  :i [(aslAgent/main :a m) (aslAgent/reply :a r) (aslAgent/turn :a tr) (aslAgent/core :a c) (aslHarness/tests/agentLoopRecorderKit :a rk) (aslAgent/tests/gitInitKit :a gk)])

; (:m :ref AGENT-AUDIT-FIX :do "audit 2026-11-19 of the single-block exception: a quoted gate output, a block quoted between other steps and a block standing before another write were written into the one :raw write; the exception now needs the block adjacent before the slot's form and the receipt names it, and an :error code inside a fenced block is no echo")
fn q -> String
  "```"

fn block body: String -> String
  (str (q) "\n" body "\n" (q) "\n")

fn rawWrite file: String -> String
  (str "(:step :op \"write\" :file \"" file "\" :content :raw)")

fn refused? b: r/RawBind -> Bool
  (and (= b.count 0) (not (listEmpty? b.missing)))

fn mark -> String
  ":rawPlace \"adjacent\""

schema Run
  (:f seeded Bool)
  (:f journal String)
  (:f file String)

fn ! run! id: String reply: String -> Run
  (let [(root (rk/freshRecorderRoot! id))
        (seeded (and (ok? (fileWrite (str root "/subject.txt") "seed\n")) (gk/initGitRepo! root id "raw-adjacent@example.invalid")))
        (fixtureDir (str root "/tests/fixtures/agentLoop/mvp"))
        (_ (dirCreate fixtureDir))
        (turns (str "    (:turn :num 1 :reply \"" (c/escapeAsn reply) "\")\n    (:turn :num 2 :reply \"(:done)\")\n"))
        (_ (fileWrite (str fixtureDir "/" id ".asn") (str "(:script :id \"" id "\" :mode :scout\n  :turns (\n" turns "  )\n)\n")))
        (form (str "(:agent :task \"write hint.txt\" :backend \"script/" id "\" :root \"" (c/escapeAsn root)
                   "\" :mode \"scout\" :owns (\"subject.txt\" \"hint.txt\") :budget 4 :contextTokens 8000)"))
        (_ (m/main (list form)))
        (journalDir (str root "/.asl/run/agentLoop"))
        (name (optionOr (listHead (filter (fn [n] (stringEndsWith? n ".journal")) (resultOr (dirList journalDir) (list)))) ""))
        (journal (resultOr (fileReadString (str journalDir "/" name)) ""))
        (file (resultOr (fileReadString (str root "/hint.txt")) ""))
        (_ (pathRemove root))]
    (Run :seeded seeded :journal journal :file file))

fn obs journal: String -> String
  (optionOr (listHead (filter (fn [l] (stringStartsWith? l "(:turn 1 :observation \"")) (stringSplit journal "\n"))) "")

fn ! runTests -> Bool
  (let [gate (r/bindRawBlocks (str "The gate printed:\n" (block "1 assertion(s) executed (0 passed)") "\nNow I write the file.\n" (rawWrite "a.txt") "\n"))
        quote (r/bindRawBlocks (str "(:step :op \"read\" :file \"b.txt\")\n" (block "QQQ") "(:step :op \"run\" :cmd \"ls\")\n" (rawWrite "a.txt") "\n"))
        twoWrites (r/bindRawBlocks (str (block "BBB") "(:step :op \"write\" :file \"a.txt\" :content \"x\")\n" (rawWrite "b.txt") "\n"))
        twoInTxn (r/bindRawBlocks (str (block "BBB") "(:txn :owns (\"a.txt\" \"b.txt\")\n  (:step :op \"write\" :file \"a.txt\" :content \"x\")\n  " (rawWrite "b.txt") ")\n"))
        farAfter (r/bindRawBlocks (str (rawWrite "a.txt") "\n(:step :op \"run\" :cmd \"ls\")\n" (block "LLL")))
        adjBefore (r/bindRawBlocks (str (block "AAA") "\n\n" (rawWrite "a.txt") "\n"))
        adjAfter (r/bindRawBlocks (str (rawWrite "a.txt") "\n\n" (block "AAA")))
        txnBefore (r/bindRawBlocks (str (block "AAA") "(:txn :owns (\"a.txt\")\n  " (rawWrite "a.txt") ")\n"))
        inBlock (tr/turnReply (str (rawWrite "a.txt") "\n" (block "(:receipt :status :rejected :error \"ERR_FOO\")") (block "BBB")) none)
        echoAfter (tr/turnReply (str (block "(:receipt :status :rejected :error \"ERR_FOO\")") (block "BBB") "(:step :op \"write\" :file \"a.txt\" :content :raw :error \"ERR_RAW_MISSING\")\n") none)
        before (run! "adjBefore" (str (block "hello raw") "\n" (rawWrite "hint.txt")))
        after (run! "adjAfter" (str (rawWrite "hint.txt") "\n" (block "hello raw")))
        txn (run! "adjTxn" (str (block "hello txn") "(:txn :owns (\"hint.txt\")\n  " (rawWrite "hint.txt") ")"))]
    (do
      (assert (refused? gate) (str "a quoted gate output with prose between it and the write is not the write's text: " gate.text))
      (assert (refused? quote) (str "a block quoted after a read, with a run before the write, is not the write's text: " quote.text))
      (assert (refused? twoWrites) (str "a block before the first of two writes does not go to the second: " twoWrites.text))
      (assert (refused? twoInTxn) (str "a block before a txn does not go to its second step: " twoInTxn.text))
      (assert (refused? farAfter) (str "a block after another step is not the earlier write's text: " farAfter.text))
      (assert (and (= adjBefore.count 1) (stringContains? adjBefore.text ":content \"AAA")) (str "a block adjacent before the form binds: " adjBefore.text))
      (assert (stringContains? adjBefore.text (mark)) (str "the form bound from before is tagged: " adjBefore.text))
      (assert (and (= adjAfter.count 1) (stringContains? adjAfter.text ":content \"AAA")) (str "a block adjacent after the form binds: " adjAfter.text))
      (assert (not (stringContains? adjAfter.text ":rawPlace")) (str "the regular place carries no tag: " adjAfter.text))
      (assert (and (= txnBefore.count 1) (stringEndsWith? (stringTrim txnBefore.text) (str " " (mark) ")"))) (str "a block adjacent before a txn binds to its first step and tags the txn: " txnBefore.text))
      (assert (and (= inBlock.rawBlocks 0) (not (stringContains? inBlock.text ":error"))) (str "an :error code inside a fenced block is no echo: " inBlock.text))
      (assert (stringContains? echoAfter.text ":error \"ERR_RAW_MISSING\"") (str "the echo outside the blocks is the one kept: " echoAfter.text))
      (assert (and before.seeded (and after.seeded txn.seeded)) "the fixture repos are seeded")
      (assert (= before.file "hello raw\n") (str "the adjacent block before the step is written: " before.file))
      (assert (stringContains? (obs before.journal) "(:raw adjacent)") (str "its receipt says the block came from before the form: " (obs before.journal)))
      (assert (= after.file "hello raw\n") (str "the block after the step is written: " after.file))
      (assert (and (not (stringEmpty? (obs after.journal))) (not (stringContains? (obs after.journal) "raw adjacent"))) (str "the regular place has no repaired mark: " (obs after.journal)))
      (assert (= txn.file "hello txn\n") (str "the adjacent block before the txn is written: " txn.file))
      (assert (stringContains? (obs txn.journal) "(:raw adjacent)") (str "the txn receipt carries the mark: " (obs txn.journal)))
      true))
