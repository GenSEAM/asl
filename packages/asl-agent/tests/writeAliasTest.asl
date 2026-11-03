(module aslAgent/tests/writeAliasTest
  :x [runTests]
  :i [(aslHarness/tests/agentLoopRecorderKit :a rk) (aslAgent/tests/gitInitKit :a gk)])

; (:m :ref LEON-WRITE-ALIAS :do "the shorthands (:write PATH CONTENT), (:write PATH :content C), (:write :file F :content C) and (:edit PATH OLD NEW) land the same on-disk edit as the canonical (:step :op ...), and the receipt names the canonical form")

fn readFile root: String name: String -> String
  (resultOr (fileReadString (str root "/" name)) "")

fn runShape! tag: String replies: (List String) -> (Pair String String)
  (let [root (rk/freshRecorderRoot! (str "writeAlias" tag))
        ready (and (ok? (fileWrite (str root "/subject.txt") "before\n"))
                (gk/initGitRepo! root "writeAliasTest" "write-alias-test@example.invalid"))
        run (rk/runRecordedAgentLoopWithReplies! root (str "writeAlias" tag) replies (list)
              "Create hello.txt containing exactly the word hello, then finish." 3 8000)
        out (pair (readFile root "hello.txt") run.journal)
        cleaned (ok? (pathRemove root))]
    (if (and ready cleaned) out (pair "FIXTURE-FAILED" "")))

fn runTests -> Bool
  (let [step (runShape! "Step" (list "(:step :op \"write\" :file \"hello.txt\" :content \"hello\")" "(:done)"))
        pos (runShape! "Pos" (list "(:write \"hello.txt\" \"hello\")" "(:done)"))
        mixed (runShape! "Mixed" (list "(:write \"hello.txt\" :content \"hello\")" "(:done)"))
        keyed (runShape! "Keyed" (list "(:write :file \"hello.txt\" :content \"hello\")" "(:done)"))
        edit (runShape! "Edit" (list "(:write \"hello.txt\" \"hello\")\n(:edit \"hello.txt\" \"hello\" \"hello\")" "(:done)"))]
    (do
      (assert (= (pairFirst step) "hello") "canonical step form writes the file")
      (assert (= (pairFirst pos) "hello") "positional (:write PATH CONTENT) writes the same file")
      (assert (= (pairFirst mixed) "hello") "(:write PATH :content C) writes the same file")
      (assert (= (pairFirst keyed) "hello") "(:write :file F :content C) writes the same file")
      (assert (= (pairFirst edit) "hello") "positional (:edit PATH OLD NEW) applies after a positional write")
      (assert (not (stringContains? (pairSecond pos) "write needs :file")) "the positional shape is not rejected ERR_MISSING_ARG")
      (assert (stringContains? (pairSecond pos) ":canonical ") "the receipt shows the canonical step form")
      (assert (stringContains? (pairSecond pos) "Reply with ASN forms only; the next form is a (:step") "every user turn ends with one imperative line naming the next form")
      (assert (not (stringContains? (pairSecond step) ":canonical")) "a canonical step receipt carries no alias note")
      true))
