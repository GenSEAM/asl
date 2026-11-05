(module asl/tools/coord/tests/trialCorpusTest
  :x [runTests]
  :i [(asl-gates/dyck :a dk) (asl-tools/fleet/run :a fr)])

; (:m :ref TRIAL-CORPUS :do "every trial corpus row parses and has its fields; each row's gate file is absent on base unless the row is seeded; new-module owns are absent on base; in one clone at base, the T4 regression is red on the seed and green after the reference fix with kitTest green, each seeded branch's gate runs green with executed asserts, and each seed's probe shows the seed is wrong; a broken unionFind passes the T6 seed gate and fails its probe")

fn ! sh dir: String argv: (List String) -> fr/Done
  (fr/runOneLimited (fr/job argv dir (fr/childEnv (list "ASL_ROOT=" "ASL_PRELUDE="))) (fr/limits 900 128))

fn ! scratch -> String
  (str (optionOr (envGet "TMPDIR") "/tmp") "/trialCorpusTest-" (stringFromInt64 (procSelf)))

fn cutOf s: String a: Int64 b: Int64 -> String
  (optionOr (stringSlice s a b) "")

fn after row: String key: String -> String
  (match (stringIndexOf row key)
    ((none) "")
    ((some i) (optionOr (listHead (stringSplit (stringTrim (cutOf row (+ i (stringLength key)) (stringLength row))) " ")) "")))

fn idOf row: String -> String
  (optionOr (listHead (stringSplit (stringTrim row) " ")) "")

fn ownsOf row: String -> (List String)
  (match (stringIndexOf row ":owns (")
    ((none) (list))
    ((some i) (let [(rest (cutOf row (+ i 7) (stringLength row)))
                    (inner (match (stringIndexOf rest ")") ((some j) (cutOf rest 0 j)) ((none) rest)))]
                (filter (fn [(s String)] -> Bool (stringContains? s "/")) (stringSplit inner "\"")))))

fn gateOf row: String -> String
  (match (stringIndexOf row ":gate \"")
    ((none) "")
    ((some i) (let [(rest (cutOf row (+ i 7) (stringLength row)))
                    (inner (match (stringIndexOf rest "\"") ((some j) (cutOf rest 0 j)) ((none) rest)))]
                (optionOr (listLast (stringSplit inner " ")) ""))))

fn seeded? row: String -> Bool
  (stringContains? row ":skipWrite true")

fn rowOk row: String -> Bool
  (and (not (stringEmpty? (idOf row)))
       (and (not (stringEmpty? (after row ":kind")))
            (and (not (stringEmpty? (after row ":known")))
                 (and (not (listEmpty? (ownsOf row)))
                      (stringContains? row ":gate \"")))))

fn absentOnBase? root: String base: String path: String -> Bool
  (not (= (sh root (list "git" "cat-file" "-e" (str base ":" path))).exit 0))

fn newOwnsAbsent? root: String base: String chunks: (List String) -> Bool
  (listAll? (fn [(row String)] -> Bool
              (or (not (= (after row ":kind") "newModule"))
                  (listAll? (fn [(p String)] -> Bool (absentOnBase? root base p)) (ownsOf row))))
            chunks)

fn gatesAbsent? root: String base: String chunks: (List String) -> Bool
  (listAll? (fn [(row String)] -> Bool
              (or (seeded? row) (absentOnBase? root base (gateOf row))))
            chunks)

fn ranOk? d: fr/Done -> Bool
  (and (= d.exit 0)
       (and (stringContains? d.out "assertion(s) executed (") (not (stringContains? d.out " 0 assertion(s) executed"))))

fn redOk? d: fr/Done -> Bool
  (and (not (= d.exit 0)) (stringContains? d.out "ERR_ASSERT"))

fn ! cloneAt root: String base: String dir: String -> fr/Done
  (sh root (list "sh" "-c" (str "rm -rf " dir " && git clone -q --shared --no-checkout " root " " dir " && git -C " dir " checkout -q " base)))

fn ! applySeed dir: String seed: String -> Bool
  (= (sh dir (list "git" "apply" seed)).exit 0)

fn ! putIn dir: String src: String dst: String -> Bool
  (= (sh dir (list "cp" src (str dir "/" dst))).exit 0)

fn ! testIn dir: String rel: String -> fr/Done
  (sh dir (list (str dir "/bin/asl") "test" rel))

fn ! resetIn dir: String -> Bool
  (= (sh dir (list "sh" "-c" "git checkout -q -- . && git clean -fdq")).exit 0)

fn ! runTests -> Bool
  (let [(root (resultOr (realPath ".") "."))
        (text (resultOr (fileReadString (str root "/asl/tools/coord/trial/corpus.asn")) ""))
        (base (stringReplace (after text ":base") "\"" ""))
        (chunks (listDrop (stringSplit text "(:task ") 1))
        (seeds (str root "/asl/tools/coord/trial/seeds"))
        (dir (scratch))
        (absent (newOwnsAbsent? root base chunks))
        (gates (gatesAbsent? root base chunks))
        (cloned (cloneAt root base dir))
        (t5Patch (applySeed dir (str seeds "/humanBytesWrongBase.patch")))
        (t5Gate (testIn dir "asl/packages/asl-utils/tests/humanBytesTest.asl"))
        (t5ProbeCopy (putIn dir (str seeds "/humanBytesProbe.asl.seed") "asl/packages/asl-utils/tests/humanBytesProbe.asl"))
        (t5Probe (testIn dir "asl/packages/asl-utils/tests/humanBytesProbe.asl"))
        (r1 (resetIn dir))
        (t4Patch (applySeed dir (str seeds "/kitJoinPathFix.patch")))
        (t4Copy (putIn dir (str seeds "/joinPathTest.asl.seed") "asl/packages/asl-utils/tests/joinPathTest.asl"))
        (t4Red (testIn dir "asl/packages/asl-utils/tests/joinPathTest.asl"))
        (t4Ref (applySeed dir (str seeds "/kitJoinPathReference.patch")))
        (t4Green (testIn dir "asl/packages/asl-utils/tests/joinPathTest.asl"))
        (t4Kit (testIn dir "asl/packages/asl-utils/tests/kitTest.asl"))
        (r2 (resetIn dir))
        (t6Patch (applySeed dir (str seeds "/unionFindConstAssert.patch")))
        (t6Gate (testIn dir "asl/packages/asl-utils/tests/unionFindTest.asl"))
        (t6ProbeCopy (putIn dir (str seeds "/unionFindProbe.asl.seed") "asl/packages/asl-utils/tests/unionFindProbe.asl"))
        (t6Probe (testIn dir "asl/packages/asl-utils/tests/unionFindProbe.asl"))
        (t6Mut (sh dir (list "perl" "-pi" "-e" "s/\\(mapSet parent ra rb\\)/parent/" "asl/packages/asl-utils/src/unionFind.asl")))
        (t6MutGate (testIn dir "asl/packages/asl-utils/tests/unionFindTest.asl"))
        (t6MutProbe (testIn dir "asl/packages/asl-utils/tests/unionFindProbe.asl"))
        (r3 (resetIn dir))
        (cleaned (sh root (list "rm" "-rf" dir)))]
    (do (assert (none? (dk/checkString text false)) "every row is balanced ASN")
        (assert (= (listLength chunks) 6) (str "six task rows: " (stringFromInt64 (listLength chunks))))
        (assert (listAll? rowOk chunks) "every row has an id, kind, known outcome, owns and a gate")
        (assert absent "new-module owns are absent on base")
        (assert gates "every unseeded row's gate file is absent on base, so its gate is red before")
        (assert (= cloned.exit 0) "the clone at base was made")
        (assert t5Patch "the T5 branch patch applies on base")
        (assert (ranOk? t5Gate) "the T5 seed gate is green with executed asserts")
        (assert (and t5ProbeCopy (redOk? t5Probe)) "the T5 probe fails on the seed: the seed is wrong")
        (assert r1 "the clone was reset after T5")
        (assert t4Patch "the T4 seed applies on base")
        (assert (and t4Copy (redOk? t4Red)) "the T4 regression is red on the seed")
        (assert t4Ref "the T4 reference fix applies on the seed")
        (assert (ranOk? t4Green) "the T4 regression is green after the reference fix")
        (assert (= t4Kit.exit 0) "kitTest stays green after the reference fix")
        (assert r2 "the clone was reset after T4")
        (assert t6Patch "the T6 branch patch applies on base")
        (assert (ranOk? t6Gate) "the T6 seed gate is green with executed asserts")
        (assert (and t6ProbeCopy (= t6Probe.exit 0)) "the unionFind probe passes on the real module")
        (assert (= t6Mut.exit 0) "the no-op union mutant was applied")
        (assert (ranOk? t6MutGate) "the T6 seed gate stays green with a no-op union: the test is vacuous")
        (assert (redOk? t6MutProbe) "the unionFind probe fails with a no-op union")
        (assert (= cleaned.exit 0) "the scratch clone was removed")
        true))
