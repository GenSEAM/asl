(module aslAgent/tests/editBySymbolLoopTest
  :x [runTests]
  :i [(aslAgent/main :a m) (aslAgent/reply :a r) (aslAgent/core :a c) (aslHarness/tests/agentLoopRecorderKit :a rk) (aslAgent/tests/gitInitKit :a gk)])

; (:m :ref EDIT-BY-SYMBOL :do "a full scripted Leon loop: a replaceDef step whose body is a :raw fenced block changes one definition of a 300-line module byte for byte; a whole write of a long existing file is refused and leaves it; a long file the session created itself can be written whole a second time")
fn q -> String
  "```"

fn block body: String -> String
  (str (q) "\n" body "\n" (q) "\n")

fn mid i: Int64 -> String
  (str "fn mid" (stringFromInt64 i) " x: Int64 -> Int64\n  (+ x " (stringFromInt64 i) ")\n\n")

fn baseText -> String
  (str "(module fixture/big\n  :x [alpha omega])\n\n"
    "fn alpha -> Int64\n  (+ 1 2)\n\n"
    (stringJoin (map mid (range 0 90)) "")
    "fn omega -> Int64\n  (- 9 1)\n")

fn lines n: Int64 -> String
  (stringJoin (map (fn [i] (str "line " (stringFromInt64 i) "\n")) (range 0 n)) "")

fn ! run! id: String seeds: (List (Pair String String)) replies: (List String) -> (Pair String String)
  (let [root (rk/freshRecorderRoot! id)
        seeded (fold (fn [acc p] (and acc (ok? (fileWrite (str root "/" (pairFirst p)) (pairSecond p))))) true seeds)
        inited (gk/initGitRepoWith! root id "editBySymbol@example.invalid" (map pairFirst seeds))
        fixtureDir (str root "/tests/fixtures/agentLoop/mvp")
        _ (dirCreate fixtureDir)
        turns (stringJoin (map (fn [p] (str "    (:turn :num " (stringFromInt64 (+ (pairFirst p) 1)) " :reply \"" (c/escapeAsn (pairSecond p)) "\")\n")) (enumerate (listAppend replies (list "(:done)")))) "")
        _ (fileWrite (str fixtureDir "/" id ".asn") (str "(:script :id \"" id "\" :mode :scout\n  :turns (\n" turns "  )\n)\n"))
        form (str "(:agent :task \"change big.asl\" :backend \"script/" id "\" :root \"" (c/escapeAsn root)
                   "\" :mode \"scout\" :owns (\"big.asl\" \"made.txt\" \"long.txt\") :budget 6 :contextTokens 8000)")
        _ (m/main (list form))
        journalDir (str root "/.asl/run/agentLoop")
        listing (resultOr (dirList journalDir) (list))
        jname (optionOr (listHead (filter (fn [n] (stringEndsWith? n ".journal")) listing)) "")
        pname (optionOr (listHead (filter (fn [n] (stringEndsWith? n ".patch")) listing)) "")
        journal (resultOr (fileReadString (str journalDir "/" jname)) "")
        patch (if (stringEmpty? pname) "<no patch>" (resultOr (fileReadString (str journalDir "/" pname)) "<unreadable>"))
        _ (pathRemove root)]
    (pair journal (if (and seeded inited) patch "SEED-FAILED")))

fn changedLines patch: String -> (List String)
  (filter (fn [l] (and (or (stringStartsWith? l "+") (stringStartsWith? l "-")) (and (not (stringStartsWith? l "+++")) (not (stringStartsWith? l "---"))))) (stringSplit patch "\n"))

fn clip s: String -> String
  (c/sliceOf s 0 (min 1500 (stringLength s)))

fn ops journal: String -> String
  (clip (stringJoin (filter (fn [l] (or (stringStartsWith? l "(:op ") (stringContains? l ":observation"))) (stringSplit journal "\n")) "\n"))

fn ! runTests -> Bool
  (let [base (baseText)
        rd (str "(:step :op \"replaceDef\" :file \"big.asl\" :symbol \"alpha\" :content :raw)\n" (block "fn alpha -> Int64\n  (+ 10 20)"))
        pureRd (r/bindRawBlocks rd)
        landed (run! "editSymLoopRd" (list (pair "big.asl" base)) (list rd))
        refused (run! "editSymLoopLong" (list (pair "long.txt" (lines 100))) (list (str "(:step :op \"write\" :file \"long.txt\" :content :raw)\n" (block "short"))))
        twice (run! "editSymLoopTwice" (list (pair "big.asl" base)) (list (str "(:step :op \"write\" :file \"made.txt\" :content :raw)\n" (block (lines 100)) "(:step :op \"write\" :file \"made.txt\" :content :raw)\n" (block (str (lines 100) "more\n")))))]
    (do
      (assert (> pureRd.count 0) (str "replaceDef :content :raw binds its fenced block, count " (stringFromInt64 pureRd.count)))
      (assert (stringContains? (pairFirst landed) "\"replaceDef\" :file \"big.asl\" :at \"#alpha\" :status ok") (str "the loop runs replaceDef ok: " (ops (pairFirst landed))))
      (assert (= (changedLines (pairSecond landed)) (list "-  (+ 1 2)" "+  (+ 10 20)")) (str "the loop's patch changes exactly the one definition body and no other byte: " (clip (pairSecond landed))))
      (assert (stringContains? (pairFirst refused) "ERR_WRITE_WHOLE_FILE") (str "a whole write of a long existing file is refused: " (ops (pairFirst refused))))
      (assert (listEmpty? (changedLines (pairSecond refused))) (str "the refused write leaves the file unchanged: " (clip (pairSecond refused))))
      (assert (and (not (stringContains? (pairFirst twice) "ERR_WRITE_WHOLE_FILE")) (stringContains? (pairSecond twice) "+more")) (str "a long file the session created is written whole a second time: " (ops (pairFirst twice))))
      true))
