(module asl-tools/coord/tests/docAutodropTest
  :x [runTests]
  :i [(asl-tools/coord/conductor :a cd) (asl-gates/docLedger :a dl) (asl-tools/fleet/run :a fr) (asl-tools/coord/store :a st) (asl-tools/coord/tests/fixtures/pipeFix :a pf)])

; (:m :ref DOC-RULE-AUTODROP :do "docAutodropAt! on a fixture branch: of one allowed row (an export another package uses, one sentence on why) and two refused ones (a name echo, a row on a symbol the module does not export) only the allowed row stays, there is exactly one commit with the one-line ASN message, and the dl ledger check finds nothing on the result; a branch with only the allowed row gets no commit and returns 0")
fn sh c: String -> String
  (pf/sh c)

fn ! g dir: String words: String -> fr/Done
  (cd/gitOut dir (stringSplit words " "))

fn trieSrc -> String
  "(module asl-utils/trie\n  :x [empty full]\n  :i [])\n\nfn empty -> Int64\n  1\n\nfn full -> Int64\n  2\n\nfn hidden -> Int64\n  3\n"

fn useSrc -> String
  "(module asl-tools/coord/useTrie\n  :x [useAll]\n  :i [(asl-utils/trie :a t)])\n\nfn useAll -> Int64\n  (+ (t/empty) (t/full))\n"

fn okRow -> String
  "(:doc :symbol \"asl/packages/asl-utils/src/trie.asl#empty\" :text \"Shared by the router and the cache so both see one empty value\")\n"

fn echoRow -> String
  "(:doc :symbol \"asl/packages/asl-utils/src/trie.asl#full\" :text \"Returns the full value\")\n"

fn hiddenRow -> String
  "(:doc :symbol \"asl/packages/asl-utils/src/trie.asl#hidden\" :text \"Kept so the old wire readers still find a third value\")\n"

fn ledgerPath -> String
  "asl/packages/asl-utils/doc.asn"

fn ! repoOf! root: String -> String
  (let [(repo (str root "/repo"))
        (w (sh (str "mkdir -p " repo "/asl/packages/asl-utils/src " repo "/asl/tools/coord " repo "/bin " root "/worktrees && echo initOk")))
        (_ (g repo "init -q -b main"))
        (_ (fileWrite (str repo "/bin/asl") "#!/bin/sh\nexit 0\n"))
        (_ (sh (str "chmod +x " repo "/bin/asl")))
        (_ (fileWrite (str repo "/asl/packages/asl-utils/src/trie.asl") (trieSrc)))
        (_ (fileWrite (str repo "/asl/tools/coord/useTrie.asl") (useSrc)))
        (_ (fileWrite (str repo "/" (ledgerPath)) ""))
        (a (g repo "add -A"))
        (made (g repo "-c user.email=t@example.invalid -c user.name=t commit -qm c0"))]
    (if (and (stringContains? w "initOk") (and (= a.exit 0) (= made.exit 0))) repo ""))

fn ! unitRows! root: String id: String rows: String -> String
  (let [(wt (str root "/worktrees/asex-" id))
        (made (g (str root "/repo") (str "worktree add -q -b sh/" id " " wt " main")))
        (_ (fileWrite (str wt "/" (ledgerPath)) rows))
        (a (g wt "add -A"))
        (c (g wt "-c user.email=t@example.invalid -c user.name=t commit -qm unit"))]
    (if (and (= made.exit 0) (and (= a.exit 0) (= c.exit 0))) wt ""))

fn ! count! wt: String -> Int64
  (optionOr (stringToInt64 (stringTrim (g wt "rev-list --count main..HEAD").out)) 0)

fn ! lastMsg! wt: String -> String
  (stringTrim (g wt "log -1 --format=%s").out)

fn ! treeFindings! wt: String -> Int64
  (listLength (dl/treeFindings! wt))

fn ! countDocs! wt: String -> Int64
  (listLength (filter (fn [(l String)] -> Bool (stringContains? l "(:c :a docs :do")) (stringLines (g wt "log --format=%s main..HEAD").out)))

fn ! journal! dir: String -> String
  (resultOr (fileReadString (cd/journalPath dir)) "")

fn ! ctxFor! dir: String -> cd/Ctx
  (cd/Ctx :dir dir :holder "docAutodropTest" :ttlMs 600000 :maxWait 5 :maxSame 3 :stageSec 30 :maxDesc 50
          :launch (fn [(stage String) (u st/Task) (c cd/CUnit)] -> (List String) (list "/usr/bin/true"))
          :pace (cd/fixedPace 4 4))

fn unitOf id: String -> st/Task
  (st/Task :id id :owns (list "asl/packages/asl-utils/doc.asn") :reads (list) :gate "true" :channel "free" :model "" :base "main" :after (list) :st "queued" :epoch 0 :receipt "")

fn cuAt id: String stateName: String wt: String -> cd/CUnit
  (cd/CUnit :id id :st stateName :lane "free" :fails 0 :sig "" :waited 0 :parked 0 :epoch 0 :branch (str "sh/" id) :wt wt :model "m" :tokens 0 :costMicro 0 :esc 0 :launched 0 :await "")

fn passRes -> cd/Res
  (cd/Res :tiers "" :ok 0 :wt "" :branch "" :model "m" :tokens 0 :costMicro 0 :claimedGreen 0 :sig "" :ms 0 :exit 0 :asserts 0 :verdict "pass")

fn manyRows -> String
  (str (okRow) (echoRow) (hiddenRow) "(:doc :bogus 1)\n" "(:doc :symbol \"asl/packages/asl-utils/src/trie.asl#empty\" :text \"Returns the empty value\")\n")

fn ! runTests -> Bool
  (let [(root (pf/scratch "dadrop" "x"))
        (_ (pf/cleanup root))
        (repo (repoOf! root))
        (_ (fileWrite (str root "/repo.path") repo))
        (wtM (unitRows! root "M" (manyRows)))
        (wtC (unitRows! root "C" (okRow)))
        (wtR (unitRows! root "R" (manyRows)))
        (wtG (unitRows! root "G" (manyRows)))
        (before (treeFindings! wtM))
        (beforeC (count! wtM))
        (labelsM (cd/docAutodropAt! wtM "main" repo "M"))
        (afterM (treeFindings! wtM))
        (text (resultOr (fileReadString (str wtM "/" (ledgerPath))) ""))
        (labelsC (cd/docAutodropAt! wtC "main" repo "C"))
        (ctx (ctxFor! root))
        (_ (cd/finish! ctx (unitOf "R") (cuAt "R" "reviewing" wtR) (passRes)))
        (jR (journal! root))
        (graded (resultOr (fileReadString (str wtR "/.asl/mem/grades.asn")) ""))
        (headR (stringTrim (g wtR "rev-parse HEAD~1").out))
        (_ (cd/writeCUnit! root (cuAt "R" "merged" wtR)))
        (_ (cd/launch! ctx (unitOf "G") (cuAt "G" "merging" wtG)))
        (jG1 (journal! root))
        (docsG1 (countDocs! wtG))
        (graded1 (resultOr (fileReadString (str wtG "/.asl/mem/grades.asn")) ""))
        (_ (cd/launch! ctx (unitOf "G") (cuAt "G" "merging" wtG)))
        (jG2 (journal! root))
        (res (do (assert (not (stringEmpty? repo)) "fixture repo exists")
                 (assert (and (not (stringEmpty? wtM)) (and (not (stringEmpty? wtC)) (and (not (stringEmpty? wtR)) (not (stringEmpty? wtG))))) "the unit worktrees exist")
                 (assert (> before 0) "before: the branch with refused rows fails the tree check")
                 (assert (= (listLength labelsM) 4) (str "four rows dropped: echo, non-exported, unparsed, and the echo row of an allowed symbol: " (stringJoin labelsM ",")))
                 (assert (and (stringContains? text "Shared by the router") (and (not (stringContains? text "#full")) (and (not (stringContains? text "#hidden")) (and (not (stringContains? text "bogus")) (not (stringContains? text "Returns the empty value")))))) (str "only the allowed row remains, a row of the same symbol with another text goes: " text))
                 (assert (= (count! wtM) (+ beforeC 1)) "exactly one commit made")
                 (assert (= (lastMsg! wtM) "(:c :a docs :do \"drop 4 doc rows rule C refuses\" :autodrop 4 :ev (M))") (str "one-line ASN message: " (lastMsg! wtM)))
                 (assert (= afterM 0) (str "docLedger finds nothing on the result: " (stringFromInt64 afterM)))
                 (assert (listEmpty? labelsC) "a branch with no refused rows drops nothing")
                 (assert (= (count! wtC) 1) "and makes no commit")
                 (assert (and (stringContains? jR "(:docAutodrop :unit \"R\" :rows 4 :syms (") (stringContains? jR "trie.asl#full")) (str "the review pass journals the drop with the symbols: " jR))
                 (assert (= (listLength (stringSplit jR "(:gradeLanded :unit \"R\"")) 2) (str "the review pass drops before grading, so the grade lands once: " jR))
                 (assert (and (= (countDocs! wtR) 1) (stringContains? graded (str ":sha \"" (stringTrim (g wtR "rev-parse HEAD~1").out) "\""))) (str "the review pass drops before it grades: one docs commit, the grade row names the head after it: " graded))
                 (assert (and (stringContains? jG1 "(:docAutodrop :unit \"G\" :rows 4") (= docsG1 1)) (str "a unit already merging is dropped at the start of its merge stage: " jG1))
                 (assert (stringContains? graded1 (str ":sha \"" (stringTrim (g wtG "rev-parse HEAD~1").out) "\"")) (str "and graded again so the sha is the new head: " graded1))
                 (assert (= (listLength (stringSplit jG2 "(:docAutodrop :unit \"G\"")) (listLength (stringSplit jG1 "(:docAutodrop :unit \"G\""))) "a second launch on the same head drops nothing again")
                 true))
        (_ (pf/cleanup root))]
    res)
