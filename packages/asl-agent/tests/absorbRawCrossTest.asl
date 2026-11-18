(module aslAgent/tests/absorbRawCrossTest
  :x [runTests]
  :i [(aslAgent/core :a c) (aslAgent/turn :a tr) (aslAgent/reply :a r)])

; (:m :ref ABSORB-AGENT-K1-K2-K4 :do "node2 2026-11-17 STD-BASE64 turn 1 (journal 1b8e65199170cbef, synKimiK31Pro): a txn of two writes, each :content :raw step followed by its fenced block before the txn's closing paren; stdBase64Turn1.txt is that layout built from the recorded row, and on base 6f6a30785 tr/turnReply turns it byte for byte into stdBase64Turn1.recorded.txt, where src/base64.asl got the test module and the code's parens closed the txn inside the first block; after the fix each write gets its own block")

fn dir -> String
  "asl/packages/asl-agent/tests/fixtures/absorb/"

fn contentAfter text: String file: String -> String
  (let [key (str ":file \"" file "\" :content \"")
        at (stringIndexOf text key)]
    (match at
      ((some i) (c/sliceOf text (+ i (stringLength key)) (min (stringLength text) (+ i (stringLength key) 40))))
      ((none) "?")))

fn ! runTests -> Bool
  (let [raw (resultOr (fileReadString (str (dir) "stdBase64Turn1.txt")) "")
        recorded (resultOr (fileReadString (str (dir) "stdBase64Turn1.recorded.txt")) "")
        t (tr/turnReply raw (some (list)))
        src (contentAfter t.text "asl/packages/asl-text/src/base64.asl")
        test (contentAfter t.text "asl/packages/asl-text/tests/base64Test.asl")
        plain (r/bindRawBlocks "(:txn :owns (\"a.asl\" \"b.asl\")\n  (:step :op \"write\" :file \"a.asl\" :content :raw)\n  (:step :op \"write\" :file \"b.asl\" :content :raw))\n```\nfn a -> Int64\n  (+ 1 (f 2))\n```\n```\nfn b -> Int64\n  2\n```")
        decoy (r/bindRawBlocks "(:txn :owns (\"a.asl\" \"b.asl\")\n  (:step :op \"write\" :file \"a.asl\" :content :raw)\n```\n(:step :op \"write\" :file \"x\" :content :raw))\n```\n  (:step :op \"write\" :file \"b.asl\" :content :raw))\n```\nfn b -> Int64\n  2\n```")]
    (do
      (assert (> (stringLength raw) 7000) "the fixture holds the whole turn")
      (assert (> (stringLength recorded) 8000) "the recorded row is there")
      (assert (stringStartsWith? src "(module asl-text/base64\\n") (str "src/base64.asl gets the base64 module, got " src))
      (assert (stringStartsWith? test "(module asl-text/tests/base64Test\\n") (str "tests/base64Test.asl gets the test module, got " test))
      (assert (not (stringContains? t.text "```")) "no fenced block is left in the reply")
      (assert (listEmpty? t.missingRaw) (str "no raw field is missing: " (stringJoin t.missingRaw ",")))
      (assert (!= t.text recorded) "the reply is no longer the crossed one node2 recorded")
      (assert (and (stringContains? plain.text ":file \"a.asl\" :content \"fn a -> Int64\\n  (+ 1 (f 2))\\n\"") (stringContains? plain.text ":file \"b.asl\" :content \"fn b -> Int64\\n  2\\n\"")) (str "blocks after the txn still bind in order: " plain.text))
      (assert (= plain.count 2) "two blocks bound")
      (assert (and (stringContains? decoy.text ":file \"a.asl\" :content \"(:step :op \\\"write\\\" :file \\\"x\\\" :content :raw))\\n\"") (not (stringContains? decoy.text ":file \"x\" :content \""))) (str "a :raw inside a block's code is text, not a field: " decoy.text))
      (probes)))

fn q -> String
  "```"

fn wrote? b: r/RawBind file: String content: String -> Bool
  (stringContains? b.text (str ":file \"" file "\" :content \"" (c/escapeAsn content) "\""))

fn missed? b: r/RawBind file: String -> Bool
  (listAny? (fn [p] (= (pairSecond p) file)) b.missing)

; (:m :ref ABSORB-AGENT-K1-K2-K4 :do "the grader's layouts of 2026-11-18 on add063635: each block binds by place, a layout that does not map one to one binds nothing and names its steps, and a block that holds a nested fence of its own length is never written")
fn ! probes -> Bool
  (let [f (q)
        md (str "# Title\n\n" f "asl\n(fn x)\n" f "\n\ntext\n")
        p1 (r/bindRawBlocks (str "(:txn :owns (\"a.md\" \"b.asl\")\n  (:step :op \"write\" :file \"a.md\" :content :raw)\n" f "\n" md f "\n  (:step :op \"write\" :file \"b.asl\" :content :raw)\n" f "\nfn b -> Int64\n  2\n" f "\n)"))
        p1b (r/bindRawBlocks (str "(:txn :owns (\"a.md\" \"b.asl\")\n  (:step :op \"write\" :file \"a.md\" :content :raw)\n  (:step :op \"write\" :file \"b.asl\" :content :raw))\n" f "\n" md f "\n" f "\nfn b -> Int64\n  2\n" f "\n"))
        p4b (r/bindRawBlocks (str "(:txn :owns (\"a\" \"b\")\n  (:step :op \"write\" :file \"a\" :content :raw)\n  (:step :op \"write\" :file \"b\" :content :raw)\n" f "\nBBB\n" f "\n)\n" f "\nAAA\n" f "\n"))
        p5b (r/bindRawBlocks (str "(:txn :owns (\"a\" \"b\")\n  (:step :op \"write\" :file \"a\" :content :raw)\n" f "\nAAA\n" f "\n" f "\nXXX\n" f "\n  (:step :op \"write\" :file \"b\" :content :raw)\n" f "\nBBB\n" f "\n)"))
        p8b (r/bindRawBlocks (str "(:txn :owns (\"a\" \"b\")\n  (:step :op \"edit\" :file \"a\" :old :raw\n" f "\nOLD\n" f "\n :new :raw\n" f "\nNEW\n" f "\n)\n  (:step :op \"write\" :file \"b\" :content :raw)\n" f "\nBBB\n" f "\n)"))
        p9 (r/bindRawBlocks (str "(:step :op \"write\" :file \"a\" :content :raw)\n(:txn :owns (\"b\")\n  (:step :op \"write\" :file \"b\" :content :raw)\n" f "\nBBB\n" f "\n)"))
        p10 (r/bindRawBlocks (str "(:txn :owns (\"a\" \"b\")\n  (:step :op \"write\" :file \"a\" :content :raw\n" f "\nAAA\n" f "\n)\n  (:step :op \"write\" :file \"b\" :content :raw)\n" f "\nBBB\n" f "\n)"))
        pre (r/bindRawBlocks (str "(:step :op \"write\" :file \"a\"\n" f "\nXXX\n" f "\n :content :raw)"))
        stray (r/bindRawBlocks (str "(:txn :owns (\"a\")\n" f "\nXXX\n" f "\n  (:step :op \"write\" :file \"a\" :content :raw)\n" f "\nAAA\n" f "\n)"))
        whole (tr/turnReply (str "(:step :op \"read\" :file \"x\")\n(:step :op \"write\" :file \"a\" :content :raw)\n(:step :op \"write\" :file \"b\" :content :raw)\n" f "\nBBB\n" f "\n") (some (list)))
        after (r/bindRawBlocks (str "(:txn :owns (\"a\" \"b\")\n  (:step :op \"write\" :file \"a\" :content :raw)\n  (:step :op \"write\" :file \"b\" :content :raw))\n" f "\nAAA\n" f "\n" f "\nBBB\n" f "\n"))]
    (do
      (assert (and (wrote? p10 "a" "AAA\n") (wrote? p10 "b" "BBB\n")) (str "p10: a block inside its own step binds to that step, got " p10.text))
      (assert (and (wrote? p8b "b" "BBB\n") (and (stringContains? p8b.text ":old \"OLD\\n\"") (stringContains? p8b.text ":new \"NEW\\n\""))) (str "p8b: an edit's interleaved blocks bind old to old and new to new, got " p8b.text))
      (assert (and (wrote? p4b "a" "AAA\n") (wrote? p4b "b" "BBB\n")) (str "p4b: a block inside the txn binds to the step it follows and the one after the txn to the step that had none, got " p4b.text))
      (assert (and (missed? p5b "a") (and (not (wrote? p5b "a" "AAA\n")) (not (stringContains? p5b.text ":file \"b\" :content \"")))) (str "p5b: an extra block inside the txn binds nothing and names the steps, got " p5b.text))
      (assert (and (missed? p9 "a") (not (wrote? p9 "b" "BBB\n"))) (str "p9: a write with no block of its own does not take the next form's block, and the reply binds nothing, got " p9.text))
      (assert (and (missed? p1 "a.md") (not (stringContains? p1.text ":file \"a.md\" :content \""))) (str "p1: a block cut at a nested fence of its own length is not written, got " p1.text))
      (assert (and (missed? p1b "a.md") (not (stringContains? p1b.text ":file \"b.asl\" :content \""))) (str "p1b: the same after the txn, and the next file does not get the rest, got " p1b.text))
      (assert (and (missed? pre "a") (not (wrote? pre "a" "XXX\n"))) (str "a block that stands before the field it would fill binds nothing, got " pre.text))
      (assert (and (missed? stray "a") (not (wrote? stray "a" "AAA\n"))) (str "a block inside the txn before any step binds nothing, got " stray.text))
      (assert (and (= (listLength whole.facts.ops) 1) (= (match (listHead whole.facts.ops) ((some op) (match (c/dictGet op "file") ((some (c/kvStr s)) s) (_ "?"))) ((none) "none")) "a")) (str "a reply whose blocks do not bind whole runs none of its steps, only the one unbound write that answers ERR_RAW_MISSING, got " (stringFromInt64 (listLength whole.facts.ops)) " ops, text " whole.text))
      (assert (and (wrote? after "a" "AAA\n") (wrote? after "b" "BBB\n")) (str "blocks after the txn still bind in step order, got " after.text))
      true))
