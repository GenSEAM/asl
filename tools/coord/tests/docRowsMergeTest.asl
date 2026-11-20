(module asl-tools/coord/tests/docRowsMergeTest :x [runTests] :i [(asl-tools/fleet/run :a fr) (tools/fleet/train :a tr) (asl-tools/coord/conductor :a cd) (asl-tools/coord/store :a st)])

; (:m :ref COND-OWNS-DOC :do "units of one package each append their own contract rows to its doc.asn (merge=asnRows in .gitattributes, as the repository has it): in a scratch repo with no merge.asnRows.driver configured, the train merges both branches with no conflict and keeps every row; two branches that give the same symbol different text still conflict and name the file")
fn ! root -> String
  (resultOr (realPath ".") ".")

fn ! repo suffix: String -> String
  (str (optionOr (envGet "TMPDIR") "/tmp") "/docRowsMergeTest-" (procSelf) suffix)

fn ! git! dir: String args: (List String) -> fr/Done
  (fr/runOneLimited (fr/job (cons "git" args) dir (fr/childEnv (list "GIT_AUTHOR_NAME=t" "GIT_AUTHOR_EMAIL=t@localhost" "GIT_COMMITTER_NAME=t" "GIT_COMMITTER_EMAIL=t@localhost"))) (fr/limits 120 0))

fn ! ok! dir: String args: (List String) -> Bool
  (= (git! dir args).exit 0)

fn docPath -> String
  "asl/packages/pk/doc.asn"

fn docRow sym: String text: String -> String
  (str "(:doc :symbol \"asl/packages/pk/src/a.asl#" sym "\" :text \"" text "\")\n")

fn srcOf name: String -> String
  (str "asl/packages/pk/src/" name ".txt")

fn ! put! dir: String text: String -> Bool
  (ok? (fileWrite (str dir "/" (docPath)) text))

fn ! sh! argv: (List String) -> Bool
  (= (fr/runOneLimited (fr/job argv (root) (fr/childEnv (list))) (fr/limits 60 0)).exit 0)

fn ! branch! dir: String name: String src: String text: String -> Bool
  (and (ok! dir (list "checkout" "-q" "-b" name "main"))
    (and (and (put! dir text) (or (stringEmpty? src) (ok? (fileWrite (str dir "/" src) (str name "\n")))))
      (and (ok! dir (list "commit" "-q" "-am" name)) (ok! dir (list "checkout" "-q" "main")))))

fn ! build! dir: String -> Bool
  (and (sh! (list "rm" "-rf" dir))
    (and (sh! (list "mkdir" "-p" (str dir "/asl/packages/pk/src")))
      (and (ok! dir (list "init" "-q" "-b" "main"))
        (and (ok? (fileWrite (str dir "/.gitattributes") "doc.asn merge=asnRows\n"))
          (and (and (put! dir (docRow "old" "returns one")) (and (ok? (fileWrite (str dir "/" (srcOf "a")) "base\n")) (ok? (fileWrite (str dir "/" (srcOf "b")) "base\n"))))
            (and (ok! dir (list "add" "-A"))
              (and (ok! dir (list "commit" "-q" "-m" "base"))
                (and (branch! dir "unitA" "" (str (docRow "old" "returns one") (docRow "alpha" "returns a")))
                  (and (branch! dir "unitB" "" (str (docRow "old" "returns one") (docRow "beta" "returns b")))
                    (and (branch! dir "unitC" "" (str (docRow "old" "returns one") (docRow "alpha" "returns c")))
                      (and (branch! dir "sh/P" (srcOf "a") (str (docRow "old" "returns one") (docRow "p" "returns p")))
                        (and (branch! dir "sh/Q" (srcOf "b") (str (docRow "old" "returns one") (docRow "q" "returns q")))
                          (branch! dir "sh/R" (srcOf "a") (str (docRow "old" "returns one") (docRow "r" "returns r")))))))))))))))

fn ! sha! dir: String name: String -> String
  (stringTrim (git! dir (list "rev-parse" name)).out)

; (:m :ref COND-OWNS-DOC-SERIALISES :do "units of one package ride one train: P, Q and R are merging units on branches that each changed their own src file and appended their own row to the package doc.asn (R changed P's src file); with (:train :batch 3) the conductor's batch plan for the leader P takes Q, whose only file shared with P is the doc.asn, and leaves R out; the train then merges exactly that batch with both rows and both src changes kept")
fn ! unit! store: String id: String src: String -> st/Task
  (let [(u (st/Task :id id :owns (list src) :reads (list) :gate "true" :channel "free" :model "" :base "main" :after (list) :st "queued" :epoch 0 :receipt ""))
        (_ (st/put! store u))
        (_ (cd/writeCUnit! store (cd/CUnit :id id :st "merging" :lane "free" :fails 0 :sig "" :waited 0 :parked 0 :epoch 0 :branch (str "sh/" id) :wt "" :model "" :tokens 0 :costMicro 0 :esc 0 :launched 0 :await "")))]
    u)

fn ! cuOf store: String id: String -> cd/CUnit
  (optionOr (listFind (fn [(c cd/CUnit)] -> Bool (= c.id id)) (cd/readCUnits! store)) (cd/CUnit :id id :st "gone" :lane "free" :fails 0 :sig "" :waited 0 :parked 0 :epoch 0 :branch "" :wt "" :model "" :tokens 0 :costMicro 0 :esc 0 :launched 0 :await ""))

fn ! testBatch -> Bool
  (let [(d (repo "-u"))
        (store (repo "-store"))
        (ready (and (build! d) (sh! (list "mkdir" "-p" store))))
        (_ (fileWrite (cd/repoPath store) d))
        (_ (fileWrite (str store "/ladder.asn") "(:train :batch 3)\n"))
        (p (unit! store "P" (srcOf "a")))
        (_ (unit! store "Q" (srcOf "b")))
        (_ (unit! store "R" (srcOf "a")))
        (ctx (cd/Ctx :dir store :holder "docRowsMergeTest" :ttlMs 600000 :maxWait 0 :maxSame 3 :stageSec 60 :maxDesc 50
                     :launch (fn [(stage String) (u st/Task) (c cd/CUnit)] -> (List String) (list "/usr/bin/true")) :pace (cd/fixedPace 8 8)))
        (picked (cd/batchPlan! ctx p (cuOf store "P")))
        (members (map (fn [(id String)] -> (Pair String String) (pair (str "sh/" id) (sha! d (str "sh/" id)))) (cons "P" picked)))
        (merged (tr/mergeAll! d (root) 1800 members (list)))
        (text (resultOr (fileReadString (str d "/" (docPath))) ""))
        (a (resultOr (fileReadString (str d "/" (srcOf "a"))) ""))
        (b (resultOr (fileReadString (str d "/" (srcOf "b"))) ""))
        (_ (sh! (list "rm" "-rf" d store)))]
    (do
      (assert ready "scratch repo with three unit branches of one package and a store")
      (assert (= picked (list "Q")) (str "the batch of P takes Q, which shares only the package doc.asn, and not R, which changed P's src file: " (stringJoin picked ",")))
      (assert (ok? merged) (str "the train merges the batch: " (match merged ((err e) e) ((ok _) "ok"))))
      (assert (and (stringContains? text "#p\"") (and (stringContains? text "#q\"") (stringContains? text "#old\""))) (str "the rows of both units and the base row are in doc.asn: " text))
      (assert (not (stringContains? text "#r\"")) "the unit left out of the batch is not merged")
      (assert (and (= a "sh/P\n") (= b "sh/Q\n")) (str "both src changes landed: " a b))
      (assert (cd/mergeShared? "asl/packages/pk/doc.asn") "a package doc.asn is shared between batch members")
      (assert (and (cd/mergeShared? "asl/packages/asl-know/cards/pk.asn") (cd/mergeShared? "asl/packages/asl-know/missing.asn")) "the generated card and missing.asn are shared")
      (assert (not (or (cd/mergeShared? (srcOf "a")) (or (cd/mergeShared? "asl/doc.asn") (or (cd/mergeShared? "asl/packages/pk/tests/doc.asn") (cd/mergeShared? "asl/packages/asl-know/src/know.asl"))))) "a src file, a doc.asn that is no package contract and the generator source still keep units apart")
      (assert (= (cd/batchPick 3 (list "asl/packages/pk/doc.asn" "x.txt") (list (pair "B" (some (list "asl/packages/pk/doc.asn" "asl/packages/asl-know/cards/pk.asn" "y.txt"))) (pair "C" (some (list "asl/packages/pk/doc.asn" "y.txt"))))) (list "B")) "shared files never exclude, the plain file two candidates share still does")
      true))

fn ! runTests -> Bool
  (let [(batch (testBatch))
        (d (repo ""))
        (ready (build! d))
        (noDriver (stringEmpty? (stringTrim (git! d (list "config" "--get" "merge.asnRows.driver")).out)))
        (both (tr/mergeAll! d (root) 1800 (list (pair "unitA" (sha! d "unitA")) (pair "unitB" (sha! d "unitB"))) (list)))
        (text (resultOr (fileReadString (str d "/" (docPath))) ""))
        (d2 (repo "-c"))
        (ready2 (build! d2))
        (clash (tr/mergeAll! d2 (root) 1800 (list (pair "unitA" (sha! d2 "unitA")) (pair "unitC" (sha! d2 "unitC"))) (list)))
        (_ (sh! (list "rm" "-rf" d d2)))]
    (do
      (assert batch "units of one package ride one train")
      (assert (and ready noDriver) "scratch repo with doc.asn marked merge=asnRows and no configured driver")
      (assert (ok? both) (str "two units of one package add different contract rows: the train merges both with no conflict: " (match both ((err e) e) ((ok _) "ok"))))
      (assert (and (stringContains? text "#alpha") (and (stringContains? text "#beta") (stringContains? text "#old"))) (str "every row is kept: " text))
      (assert (not (or (stringContains? text "<<<<<<<") (stringContains? text ">>>>>>>"))) "no conflict marker in doc.asn")
      (assert (and ready2 (err? clash)) "two units documenting the same symbol differently still conflict")
      (assert (match clash ((err e) (and (stringContains? e ":conflict") (stringContains? e "doc.asn"))) ((ok _) false)) (str "the conflict names the file: " (match clash ((err e) e) ((ok _) "ok"))))
      true))
