(module asl/agentLoop/tests/metricsTest
  :x [runTests]
  :i [(asl/agentLoop/metrics :a m) (asl/agentLoop/core :a c)])


fn fixtureNames -> (List String)
  (list "0c7910c37e984c14.journal"
        "0d849ddd24e64a59.journal"
        "1a4ee5dab7014e08.journal"
        "1b869ca52650466a.journal"
        "2f4ebb27296640bd.journal"
        "30389c3272b84ad7.journal"
        "3fac71a07f4d4d74.journal"
        "52cf2284e8b842eb.journal"
        "5f64724416a94005.journal"
        "62654a3f67a945b3.journal"
        "64a7d742bd1e46be.journal"
        "686d69041c1042eb.journal"
        "f9d441c14c8144d6.journal")


fn fixturePaths -> (List String)
  (let [base "tests/acceptance/agentLoop/fixtures/editMetrics/"]
    (map (fn [name] (str base name)) (fixtureNames)))


fn findJournalSummary list: (List m/JournalEditSummary) name: String -> (Option m/JournalEditSummary)
  (cond
    ((listEmpty? list) (none))
    ((= (c/firstOf list).journal name) (some (c/firstOf list)))
    (else (findJournalSummary (c/restOf list) name)))


fn testClassifyDefects -> Bool
  (do
    (assert (= (m/classifyDefect "(:intent :deliver patch :why \"t\"))" false) "unbalanced") "defect unbalanced")
    (assert (= (m/classifyDefect "(:intent :deliver patch :why \"say \"x\"\")" false) "quote") "defect quote")
    (assert (= (m/classifyDefect "```asn\n(:intent :deliver patch :why \"t\")\n```" false) "prose") "defect prose")
    (assert (= (m/classifyDefect "(:step :op \"read\" :file \"foo.py\" :sta" false) "truncated") "defect truncated")
    (assert (= (m/classifyDefect "(:step :op \"frobnicate\" :file \"a.py\")" false) "unknownOp") "defect unknownOp")
    (assert (= (m/classifyDefect "(:step :op \"write\" :file \"a.py\" :content :raw)\n```python\nprint(1)\n" false) "raw") "defect raw")
    (assert (= (m/classifyDefect "(:done)" false) "other") "defect other")
    (assert (= (m/classifyDefect "(:intent (:step :op \"read\")" true) "truncated") "defect cut truncated")
    (assert (= (m/classifyDefect "(:unregisteredHead)" false) "unknownOp") "defect unknown head")
    (assert (= (m/classifyDefect "(bareHead)" false) "unknownOp") "defect non-keyword head")
    true)


fn testParseDefectsParity! -> Bool
  (let [paths (fixturePaths)
        res (m/analyzeDefects (map (fn [p] (pair p (resultOr (fileReadString p) ""))) paths) 0)]
    (do
      (assert (= res.runs 13) "parseDefects runs 13")
      (assert (= res.turns 114) "parseDefects turns 114")
      (assert (= res.defects 12) "parseDefects defects 12")
      (assert (= (listLength res.byCause) 4) "parseDefects causes 4")
      (let [c0 (c/firstOf res.byCause)
            rest0 (c/restOf res.byCause)
            c1 (c/firstOf rest0)
            rest1 (c/restOf rest0)
            c2 (c/firstOf rest1)
            rest2 (c/restOf rest1)
            c3 (c/firstOf rest2)]
        (do
          (assert (= c0.cause "truncated") "cause 0 truncated")
          (assert (= c0.count 6) "cause 0 count 6")
          (assert (= c1.cause "prose") "cause 1 prose")
          (assert (= c1.count 3) "cause 1 count 3")
          (assert (= c2.cause "quote") "cause 2 quote")
          (assert (= c2.count 2) "cause 2 count 2")
          (assert (= c3.cause "unbalanced") "cause 3 unbalanced")
          (assert (= c3.count 1) "cause 3 count 1")
          (let [formatted (m/formatParseDefects res)]
            (do
              (assert (stringStartsWith? formatted "(:parseDefects :runs 13 :turns 114 :defects 12 :byCause (") "format starts")
              (assert (stringContains? formatted "(:cause truncated :n 6") "format truncated")
              (assert (stringContains? formatted "(:cause prose :n 3") "format prose")
              (assert (stringContains? formatted "(:cause quote :n 2") "format quote")
              (assert (stringContains? formatted "(:cause unbalanced :n 1") "format unbalanced")
              (let [resUnreadable (m/ParseDefectsResult :runs 2 :turns 10 :defects 1 :byCause (list) :unreadable 3)
                    formattedUnreadable (m/formatParseDefects resUnreadable)]
                (assert (= formattedUnreadable "(:parseDefects :runs 2 :turns 10 :defects 1 :byCause () :unreadable 3)") "format with unreadable"))
              true))))))


fn testEditMetricsParity! -> Bool
  (let [paths (fixturePaths)
        res (mt (m/analyzeJournals! paths) ((ok value) value) ((err _) (m/analyzeEditJournals (list))))
        fbk res.failuresByKind]
    (do
      (assert (= res.totalJournalsScanned 13) "total_journals_scanned")
      (assert (= res.aslAsnJournalsCount 8) "asl_asn_journals_count")
      (assert (= res.totalSequences 12) "total_sequences")
      (assert (= res.acceptedSequences 8) "accepted_sequences")
      (assert (= res.firstPassSequences 5) "first_pass_sequences")
      
      (let [j0c (optionOr (findJournalSummary res.byJournal "0c7910c37e984c14.journal") (m/JournalEditSummary :journal "" :totalSequences 0 :acceptedSequences 0 :firstPassSequences 0 :sequences (list)))
            j1a (optionOr (findJournalSummary res.byJournal "1a4ee5dab7014e08.journal") (m/JournalEditSummary :journal "" :totalSequences 0 :acceptedSequences 0 :firstPassSequences 0 :sequences (list)))
            j1b (optionOr (findJournalSummary res.byJournal "1b869ca52650466a.journal") (m/JournalEditSummary :journal "" :totalSequences 0 :acceptedSequences 0 :firstPassSequences 0 :sequences (list)))
            j2f (optionOr (findJournalSummary res.byJournal "2f4ebb27296640bd.journal") (m/JournalEditSummary :journal "" :totalSequences 0 :acceptedSequences 0 :firstPassSequences 0 :sequences (list)))]
        (do
          (assert (= (listLength j0c.sequences) 4) "0c seqs == 4")
          (assert (= (listLength j1a.sequences) 1) "1a seqs == 1")
          (assert (= (listLength j1b.sequences) 1) "1b seqs == 1")
          (assert (= (listLength j2f.sequences) 1) "2f seqs == 1")))

      (assert (= res.totalFailures 22) (str "total_failures: got " (stringFromInt64 res.totalFailures) " syn=" (stringFromInt64 res.syntaxFailures) " sem=" (stringFromInt64 res.semanticFailures) " gate=" (stringFromInt64 res.gateFailures)))
      (assert (= res.syntaxFailures 13) "syntax_failures")
      (assert (= res.semanticFailures 3) "semantic_failures")
      (assert (= res.gateFailures 6) "gate_failures")
      
      (assert (= fbk.syntaxUnbalanced 3) "syntax_unbalanced")
      (assert (= fbk.syntaxParseDefect 10) "syntax_parse_defect")
      (assert (= fbk.syntaxCheckFailed 0) "syntax_check_failed")
      (assert (= fbk.semanticNoMatch 0) "semantic_no_match")
      (assert (= fbk.semanticOwns 0) "semantic_owns")
      (assert (= fbk.semanticRaw 1) "semantic_raw")
      (assert (= fbk.semanticOther 2) "semantic_other")
      (assert (= fbk.gateFailure 6) "gate_failure")
      
      (assert (= res.totalAttempts 30) "total_attempts")
      (assert (= res.acceptedAttempts 8) "accepted_attempts")
      (assert (= res.failedAttempts 22) "failed_attempts")
      
      (let [j0cOpt (findJournalSummary res.byJournal "0c7910c37e984c14.journal")]
        (do
          (assert (some? j0cOpt) "0c summary found")
          (mt j0cOpt
            ((some j0c)
              (do
                (assert (= j0c.totalSequences 4) "D3 total_sequences == 4")
                (assert (= j0c.acceptedSequences 2) "D3 accepted_sequences == 2")
                (assert (= j0c.firstPassSequences 0) "D3 first_pass_sequences == 0")
                true))
            ((none) false))))
      
      (let [j1aOpt (findJournalSummary res.byJournal "1a4ee5dab7014e08.journal")]
        (do
          (assert (some? j1aOpt) "1a summary found")
          (mt j1aOpt
            ((some j1a)
              (do
                (assert (= j1a.totalSequences 1) "D4 total_sequences == 1")
                (assert (= j1a.acceptedSequences 0) "D4 accepted_sequences == 0")
                (let [seqs (filter (fn [s] (stringEndsWith? s.file "types.asl")) j1a.sequences)]
                  (do
                    (assert (= (listLength seqs) 1) "types.asl seq found")
                    (assert (= (c/firstOf seqs).retries 10) "D4 types.asl retries == 10")
                    true))))
            ((none) false))))
      
      (let [j2fOpt (findJournalSummary res.byJournal "2f4ebb27296640bd.journal")]
        (do
          (assert (some? j2fOpt) "2f summary found")
          (mt j2fOpt
            ((some j2f)
              (do
                (assert (= j2f.totalSequences 1) "D5 total_sequences == 1")
                (let [s0 (c/firstOf j2f.sequences)]
                  (do
                    (assert (stringEndsWith? s0.file "layoutCorpusLib.asl") "D5 file layoutCorpusLib.asl")
                    (assert (= s0.retries 3) "D5 retries == 3")
                    true))))
            ((none) false))))
      
      (let [metricStr (m/formatEditMetric res "2026-09-26" "tests/acceptance/agentLoop/fixtures/editMetrics")]
        (do
          (assert (= metricStr "(:metric editFirstPass\n  :pipeline :baseline :stage \"before G3\" :date \"2026-09-26\"\n  :scope \".asl/.asn\" :journalsScanned 13 :journalsWithEdits 8\n  :journalsDir \"tests/acceptance/agentLoop/fixtures/editMetrics\"\n  :method \"Leon journals in tests/acceptance/agentLoop/fixtures/editMetrics per edit sequence of .asl/.asn files\"\n  :editFirstPassRate \"41.7%\" :acceptedFirstPass 5 :totalEdits 12\n  :retriesPerAccepted 0.75 :tokensPerAccepted 48552\n  :failureShare (:syntax \"59.1%\" :semantic \"13.6%\" :gate \"27.3%\")\n  :syntaxBreakdown (:unbalanced 3 :parseDefect 10 :checkFailed 0)\n  :attemptCounts (:attempts 30 :accepted 8 :failed 22))") "format full edit metric")
          true))))


fn testUnreadableJournal! -> Bool
  (let [result (m/analyzeJournals! (list "asl/agentLoop/tests/no-such-metrics-journal-LX5"))]
    (mt result
      ((ok _) (do (assert false "unreadable journals must not produce empty metrics") false))
      ((err message) (do (assert (stringContains? message "no-such-metrics-journal-LX5") "read error identifies unreadable path") true))))
    (let [defects (m/analyzeDefectFiles! (list "asl/agentLoop/tests/no-such-metrics-journal-LX5"))]
      (do
        (assert (= defects.unreadable 1) "unreadable defect journals are counted")
        (assert (= (m/formatParseDefects defects) "(:parseDefects :runs 0 :turns 0 :defects 0 :byCause () :unreadable 1)") "unreadable count is serialized")
        true))


fn testFlattenFlushed -> Bool
  (let [recs (list (m/Receipt :op "txn" :file "" :status "ok" :error "" :flushed (list "src/flushed.asl" "notes.txt")))
        flushed (m/flattenFlushed recs)]
    (do (assert (= flushed (list "src/flushed.asl")) "flushed txn receipts retain only ASL/ASN files") true))


fn ! runTests -> Bool
  (do
    (assert (m/isAslOrAsn "src/app.asl") "app.asl is ASL")
    (assert (m/isAslOrAsn "data/rules.asn") "rules.asn is ASN")
    (assert (m/isAslOrAsn "UPPER.ASL") "UPPER.ASL is ASL")
    (assert (not (m/isAslOrAsn "main.py")) "main.py not ASL")
    (assert (not (m/isAslOrAsn "")) "empty string not ASL")
    (assert (testClassifyDefects) "testClassifyDefects passed")
    (assert (testParseDefectsParity!) "testParseDefectsParity passed")
    (assert (testEditMetricsParity!) "testEditMetricsParity passed")
    (assert (testFlattenFlushed) "testFlattenFlushed passed")
    (assert (testUnreadableJournal!) "testUnreadableJournal passed")
    true)
