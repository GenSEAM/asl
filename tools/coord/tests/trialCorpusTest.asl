(module asl/tools/coord/tests/trialCorpusTest
  :x [runTests]
  :i [(asl-gates/dyck :a dk) (asl-tools/fleet/run :a fr)])

; (:m :ref TRIAL-CORPUS :do "every trial corpus row parses and has its fields, new-module owns are absent on base, the T5 and T6 branch patches apply on base, and the T4 seed applies with kitTest green and the joinPath probe red; the seed checks run in a git archive of base, so the working tree is never touched")

fn cutOf s: String a: Int64 b: Int64 -> String
  (optionOr (stringSlice s a b) "")

fn ! sh dir: String argv: (List String) -> fr/Done
  (fr/runOneLimited (fr/job argv dir (fr/childEnv (list))) (fr/limits 900 128))

fn ! shAsl dir: String argv: (List String) -> fr/Done
  (fr/runOneLimited (fr/job argv dir (fr/childEnv (list "ASL_ROOT=" "ASL_PRELUDE="))) (fr/limits 900 128))

fn ! scratch -> String
  (str (optionOr (envGet "TMPDIR") "/tmp") "/trialCorpusTest-" (stringFromInt64 (procSelf)))

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

fn archive root: String base: String dir: String -> Bool
  (= (sh root (list "sh" "-c" (str "rm -rf " dir " && git clone -q --no-checkout " root " " dir " && git -C " dir " checkout -q " base))).exit 0)

fn patchApplies? dir: String seed: String -> Bool
  (= (sh dir (list "git" "apply" "--check" seed)).exit 0)

fn ! runTests -> Bool
  (let [(root (resultOr (realPath ".") "."))
        (text (resultOr (fileReadString (str root "/asl/tools/coord/trial/corpus.asn")) ""))
        (base (stringReplace (after text ":base") "\"" ""))
        (chunks (listDrop (stringSplit text "(:task ") 1))
        (seedDir (str root "/asl/tools/coord/trial/seeds"))
        (dir (scratch))
        (absent (newOwnsAbsent? root base chunks))
        (ext (archive root base dir))
        (t5 (patchApplies? dir (str seedDir "/humanBytesWrongBase.patch")))
        (t6 (patchApplies? dir (str seedDir "/unionFindConstAssert.patch")))
        (t4 (patchApplies? dir (str seedDir "/kitJoinPathFix.patch")))
        (t4Applied (= (sh dir (list "git" "apply" (str seedDir "/kitJoinPathFix.patch"))).exit 0))
        (kitRc (if t4Applied (shAsl dir (list (str dir "/bin/asl") "test" "asl/packages/asl-utils/tests/kitTest.asl")) (sh dir (list "false"))))
        (probeCopy (sh dir (list "cp" (str seedDir "/kitJoinPathProbe.asl.seed") (str dir "/asl/packages/asl-utils/tests/kitJoinPathProbe.asl"))))
        (probeRc (if t4Applied (shAsl dir (list (str dir "/bin/asl") "test" "asl/packages/asl-utils/tests/kitJoinPathProbe.asl")) (sh dir (list "false"))))
        (cleaned (sh root (list "rm" "-rf" dir)))]
    (do (assert (none? (dk/checkString text false)) "every row is balanced ASN")
        (assert (= (listLength chunks) 6) (str "six task rows: " (stringFromInt64 (listLength chunks))))
        (assert (listAll? rowOk chunks) "every row has an id, kind, known outcome, owns and a gate")
        (assert absent "new-module owns are absent on base")
        (assert ext "the base archive extracts")
        (assert t5 "the T5 branch patch applies on base")
        (assert t6 "the T6 branch patch applies on base")
        (assert t4 "the T4 seed applies on base")
        (assert (= kitRc.exit 0) "kitTest stays green on the T4 seed")
        (assert (not (= probeRc.exit 0)) "the joinPath probe is red on the T4 seed")
        (assert (= cleaned.exit 0) "the archive scratch directory was removed")
        true))
