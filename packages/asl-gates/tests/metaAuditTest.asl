(module asl-gates/tests/metaAuditTest
  :x [testSpec! testClean! testDanglingRef! testUnknownTag! testGate! testWhy! testNoDefinition! testKeys! testCounting! testGrowth! testRealTree! testMain! testSeedCaseTokens! runTests]
  :i [(asl-gates/metaAudit :a meta)])

fn fixtureDir -> String
  "asl/packages/asl-gates/tests/fixtures/meta"

fn fixture name: String -> String
  (str (fixtureDir) "/" name)

fn loadRealSpec! -> meta/MetaSpec
  (mt (fileRead "asl/grammar/meta.asn")
    ((err _) (do (assert false "asl/grammar/meta.asn reads") (meta/MetaSpec :keys (list) :tags (list) :effects (list) :whyWords 0 :pragmas (list))))
    ((ok text)
      (mt (meta/loadSpec text)
        ((err e) (do (assert false (str "meta.asn loads: " e)) (meta/MetaSpec :keys (list) :tags (list) :effects (list) :whyWords 0 :pragmas (list))))
        ((ok spec) spec))))

fn fixtureCtx! -> meta/Ctx
  (meta/Ctx :root (fixtureDir) :spec (loadRealSpec!)
            :rules "(:rules (:rule :id gates :do \"x\") (:rule :id names :do \"y\"))"
            :principles "(:principlesLedger (:principle :id \"MeasureTheThingNotItsProxy\"))"
            :decisions "(:decisionsRegistry :entries [(:adr :id \"D7\")])"
            :decisionFiles (list "D140DialectSettlement.asn" "decisions.asn")
            :tests (list (fixture "silentTest.sh.txt") "asl/packages/asl-gates/tests/metaAuditTest.asl")
            :tracked (list))

fn scanFixture! name: String lang: String -> meta/FileScan
  (let [(path (fixture name))]
    (mt (fileRead path)
      ((err _) (do (assert false (str path " reads")) (meta/FileScan :path path :plain -1 :metas -1 :violations (list))))
      ((ok text) (meta/scanText! (fixtureCtx!) path lang text))))

fn kinds fs: meta/FileScan -> (List String)
  (map (fn [(v meta/Violation)] -> String v.kind) fs.violations)

fn lines fs: meta/FileScan -> (List Int64)
  (map (fn [(v meta/Violation)] -> Int64 v.line) fs.violations)

fn testSpec! -> Bool
  (let [(spec (loadRealSpec!))]
    (do
      (assert (= spec.keys (list "ref" "gate" "tags" "effect" "adopted" "why")) "closed key set from meta.asn")
      (assert (= spec.effects (list "pure" "io" "net" "proc")) "effects from meta.asn")
      (assert (= spec.whyWords 8) "why ceiling from meta.asn")
      (assert (listContains? spec.tags "leon") "tag vocabulary has leon")
      (assert (err? (meta/loadSpec "(:meta :keys ())")) "a spec with no keys is rejected")
      true))

fn testClean! -> Bool
  (let [(fs (scanFixture! "clean.py.txt" "python"))]
    (do
      (assert (= (kinds fs) (list)) (str "clean fixture has no violations, got " (stringJoin (kinds fs) " ")))
      (assert (= fs.metas 2) "clean fixture has two (:m) forms")
      (assert (= fs.plain 0) "shebang, pragma and (:m) lines are not plain")
      true))

fn testDanglingRef! -> Bool
  (let [(fs (scanFixture! "danglingRef.py.txt" "python"))]
    (do
      (assert (= (kinds fs) (list "refUnresolved" "refUnresolved" "refUnresolved")) "decision, ledger and rule refs that do not resolve are flagged")
      (assert (= (lines fs) (list 1 4 7)) "each on the line of its form")
      true))

fn testUnknownTag! -> Bool
  (let [(fs (scanFixture! "unknownTag.sh.txt" "shell"))]
    (do
      (assert (= (kinds fs) (list "tagUnknown")) "a tag outside the vocabulary is flagged")
      (assert (= (optionOr (listHead fs.violations) (meta/Violation :file "" :line 0 :kind "" :ev "")).ev "notAWord") "only the unknown word, leon is known")
      true))

fn testGate! -> Bool
  (let [(fs (scanFixture! "missingGate.asl.txt" "asl"))]
    (do
      (assert (= (kinds fs) (list "gateMissing" "gateSilent")) "a gate with no test file and a test that never names the symbol are flagged")
      (assert (= (lines fs) (list 1 5)) "gate violations sit on the form line")
      true))

fn testWhy! -> Bool
  (let [(fs (scanFixture! "longWhy.py.txt" "python"))]
    (do
      (assert (= (kinds fs) (list "whyTooLong")) "nine words are flagged, eight pass")
      (assert (= (lines fs) (list 1)) "the nine-word form")
      true))

fn testNoDefinition! -> Bool
  (let [(fs (scanFixture! "noDefinition.py.txt" "python"))]
    (do
      (assert (= (kinds fs) (list "definitionMissing" "definitionMissing" "definitionMissing")) "blank line, statement and end of file after (:m) are flagged")
      (assert (= (lines fs) (list 1 5 7)) "each on its form line")
      true))

fn scanInline! lang: String text: String -> (List String)
  (map (fn [(v meta/Violation)] -> String v.kind) (meta/scanText! (fixtureCtx!) "inline" lang text).violations)

fn testKeys! -> Bool
  (do
    (assert (= (scanInline! "python" "# (:m :owner leon)\ndef f():\n    pass\n") (list "keyUnknown")) "a key outside the closed set")
    (assert (= (scanInline! "python" "# (:m :ref gates :ref names)\ndef f():\n    pass\n") (list "keyRepeated")) "one form per key")
    (assert (= (scanInline! "python" "# (:m :effect disk)\ndef f():\n    pass\n") (list "effectUnknown")) "effect outside pure io net proc")
    (assert (= (scanInline! "python" "# (:m :adopted NoSuchPrinciple)\ndef f():\n    pass\n") (list "adoptedUnknown")) "adopted id absent from principles")
    (assert (= (scanInline! "python" "# (:m :why unquoted)\ndef f():\n    pass\n") (list "whyNotString")) "why must be a string")
    (assert (= (scanInline! "python" "# (:m :tags leon)\ndef f():\n    pass\n") (list "tagsNotList")) "tags must be a list")
    (assert (= (scanInline! "python" "# (:m)\ndef f():\n    pass\n") (list "formEmpty")) "an empty form")
    (assert (= (scanInline! "python" "# (:m :ref gates\ndef f():\n    pass\n") (list "formUnreadable")) "an unbalanced form")
    (assert (= (scanInline! "python" "# (:m :ref D7)\nLIMIT = 3\n") (list)) "a decision id in decisions.asn and an assignment definition")
    (assert (= (scanInline! "python" "# (:m :ref D140)\nclass C:\n    pass\n") (list)) "a decision id named by a D<n> file")
    (assert (= (scanInline! "shell" "# (:m :ref gates)\nLIMIT=3\n") (list)) "a shell assignment is a definition")
    (assert (= (scanInline! "shell" "# (:m :ref gates)\necho hi\n") (list "definitionMissing")) "a shell command is not")
    (assert (= (scanInline! "asl" "; (:m :ref gates)\nfn f -> Int64\n  1\n") (list)) "an asl fn is a definition")
    true)

fn plainOf! lang: String text: String -> Int64
  (meta/scanText! (fixtureCtx!) "inline" lang text).plain

fn testCounting! -> Bool
  (do
    (assert (= (plainOf! "python" "#!/usr/bin/env python\n# a note\nx = 1  # trailing\n") 1) "shebang skipped, a full comment line counted, a trailing comment not")
    (assert (= (plainOf! "python" "def f():\n    \"\"\"one\n    two\n    \"\"\"\n") 3) "every docstring line is plain")
    (assert (= (plainOf! "python" "S = \"\"\"\n# inside a string\n\"\"\"\n") 0) "a hash inside a triple-quoted value is not a comment")
    (assert (= (plainOf! "shell" "# shellcheck disable=SC2034\n# note\n") 1) "a shellcheck pragma is not plain")
    (assert (= (plainOf! "asl" ";; a note\n; another\n") 2) "asl comment lines")
    true)

fn testGrowth! -> Bool
  (let [(rows (mt (fileRead (fixture "baseline.asn"))
                ((ok t) (resultOr (meta/parseBaseline t) (list)))
                ((err _) (list))))
        (grownScan (scanFixture! "growth.py.txt" "python"))
        (grown (meta/tally rows (list grownScan) (list)))
        (clean (meta/tally rows (list (scanFixture! "clean.py.txt" "python")) (list)))
        (fresh (meta/tally (list) (list grownScan) (list)))]
    (do
      (assert (= (listLength rows) 2) "baseline rows read")
      (assert (= (map (fn [(v meta/Violation)] -> String (str v.kind " " v.ev)) grown.violations) (list "plainGrowth 3 over 2")) "plain lines above the row are flagged")
      (assert (= grown.baselinePlain 2) "baseline plain summed over scanned files")
      (assert (= clean.violations (list)) "a file under its row passes")
      (assert (= clean.lowerable 1) "and its row is reported lowerable")
      (assert (= (map (fn [(v meta/Violation)] -> String v.ev) fresh.violations) (list "3 over none")) "plain lines with no row are growth")
      (assert (stringContains? (meta/baselineText grown "2026-09-25") "(:file :path \"asl/packages/asl-gates/tests/fixtures/meta/growth.py.txt\" :plain 3)") "seed writes the measured row")
      true))

fn testRealTree! -> Bool
  (let [(spec (loadRealSpec!))
        (ctx (meta/loadCtx! "." spec (list)))
        (fs (meta/scanText! ctx "real.py" "python" "# (:m :ref D140 :gate metaAuditTest :adopted MeasureTheThingNotItsProxy)\ndef cleanFixtureSymbol():\n    pass\n# (:m :ref D99999)\ndef other():\n    pass\n# (:m :ref gates)\ndef third():\n    pass\n"))]
    (do
      (assert (listContains? ctx.tests "asl/packages/asl-gates/tests/metaAuditTest.asl") "package tests are indexed")
      (assert (= (map (fn [(v meta/Violation)] -> String (str v.kind " " v.ev)) fs.violations) (list "refUnresolved D99999")) "real decisions, rules, principles and tests resolve; a missing decision does not")
      true))

fn copyTo! src: String dst: String -> Bool
  (mt (fileRead src)
    ((err _) false)
    ((ok t) (ok? (fileWrite dst t))))

fn testMain! -> Bool
  (let [(made (processRun "mktemp -d"))
        (dir (stringTrim made.stdout))
        (cleanPy (str dir "/clean.py"))
        (dirtyPy (str dir "/dirty.py"))
        (base (fixture "baseline.asn"))]
    (do
      (assert (= made.exitCode 0) "a private fixture directory is made")
      (assert (copyTo! (fixture "clean.py.txt") cleanPy) "clean copy written")
      (assert (copyTo! (fixture "danglingRef.py.txt") dirtyPy) "dirty copy written")
      (assert (= (meta/main (list "--baseline" base cleanPy)) (ok 0)) "main exits 0 on the clean fixture")
      (assert (= (meta/main (list "--baseline" base dirtyPy)) (ok 1)) "main exits 1 on a violation")
      (assert (= (meta/main (list "--baseline" base "--bogus" "x")) (ok 64)) "main exits 64 on a bad option")
      (assert (= (processRun (str "rm -rf '" dir "'")).exitCode 0) "the fixture directory is removed")
      true))

fn testSeedCaseTokens! -> Bool
  (mt (fileRead "scripts/audit/cases.asn")
    ((err _) false)
    ((ok cases)
      (mt (meta/seedCaseReceipts cases)
        ((err _) false)
        ((ok receipts)
          (and (seedTokensPresent receipts (list "ERR_UNBALANCED" "ERR_WORKSPACE_REMOTE" "ERR_SSOT_DRIFT" "ERR_EMOJI" "ERR_NEW_RED_SUITE" "ERR_DECLARED_GAP" "ERR_VACUOUS_SUITE" "ERR_STALE_KNOWN_RED" "ERR_BASE_UNVERIFIED" "ERR_TREE_DIRTIED" "ERR_TIMEOUT" "ERR_FOREIGN" "ERR_STALE_ALLOWLIST" "ERR_UNGROUNDED" "ERR_MANIFEST" "ERR_GRAMMAR_COUNT" "ERR_C4" "ERR_SKILL" "ERR_INSTALLER_DRIFT" "ERR_TIER_FAILED" "ERR_NOT_COMPUTED" "ERR_PLACEHOLDER_DIGEST" "ERR_UNIMPLEMENTED" ":knownRedDelta (:added" ":confirmation :unverified" ":removed (" ":added ("))
               (and (seedIdsPresent receipts (list "clean" "unbalancedAsn" "gitRemoteConsistency" "gitRemote" "renderedRuleEdit" "renderedSurfaceMissing" "emojiInGrammar" "falseAssertOutsideGates" "unreachedAssert" "zeroAssertSuite" "depDefect" "committedDefectCleanTree" "knownRedNowGreen" "knownRedAdded" "knownRedSwap" "fullGreenForged" "scopeMinimal" "scopeForcedFull" "knownRedWorsened" "treeWrittenBySuite" "timeoutIsRed" "foreignOutsidePackages" "foreignInAllowlistedDir" "machoOutsideAllowlist" "staleAllowlist" "claimMetricMutated" "manifestUnbalanced" "grammarSymbolCount" "c4Overbudget" "skillFrontmatter" "installerDrift" "closureTierRed" "closureNotComputed" "stepPlaceholderDigest" "buildGarbage" "multiCheckSecondBad" "dyckCorpus" "cleanClone"))
                    (and (stringContains? receipts "(:seed :id clean :expect :green")
                         (and (stringContains? receipts "(:seed :id scopeForcedFull :expect :pending")
                              (stringContains? receipts "(:seed :id multiCheckSecondBad :expect :red :token \"ERR_UNBALANCED\"")))))))))

fn seedTokensPresent receipt: String tokens: (List String) -> Bool
  (mt (listHead tokens)
    ((none) true)
    ((some token) (and (stringContains? receipt token) (seedTokensPresent receipt (optionOr (listTail tokens) (list))))))

fn seedIdsPresent receipt: String ids: (List String) -> Bool
  (mt (listHead ids)
    ((none) true)
    ((some id) (and (stringContains? receipt (str ":id " id " ")) (seedIdsPresent receipt (optionOr (listTail ids) (list))))))

fn ! runTests -> Bool
  (do
    (assert (testSpec!) "testSpec!")
    (assert (testClean!) "testClean!")
    (assert (testDanglingRef!) "testDanglingRef!")
    (assert (testUnknownTag!) "testUnknownTag!")
    (assert (testGate!) "testGate!")
    (assert (testWhy!) "testWhy!")
    (assert (testNoDefinition!) "testNoDefinition!")
    (assert (testKeys!) "testKeys!")
    (assert (testCounting!) "testCounting!")
    (assert (testGrowth!) "testGrowth!")
    (assert (testRealTree!) "testRealTree!")
    (assert (testMain!) "testMain!")
    (assert (testSeedCaseTokens!) "testSeedCaseTokens")
    true)
