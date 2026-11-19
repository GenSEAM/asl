(module asl-tools/coord/tests/docRowsMergeTest :x [runTests] :i [(asl-tools/fleet/run :a fr) (tools/fleet/train :a tr)])

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

fn ! put! dir: String text: String -> Bool
  (ok? (fileWrite (str dir "/" (docPath)) text))

fn ! sh! argv: (List String) -> Bool
  (= (fr/runOneLimited (fr/job argv (root) (fr/childEnv (list))) (fr/limits 60 0)).exit 0)

fn ! branch! dir: String name: String text: String -> Bool
  (and (ok! dir (list "checkout" "-q" "-b" name "main"))
    (and (put! dir text)
      (and (ok! dir (list "commit" "-q" "-am" name)) (ok! dir (list "checkout" "-q" "main")))))

fn ! build! dir: String -> Bool
  (and (sh! (list "rm" "-rf" dir))
    (and (sh! (list "mkdir" "-p" (str dir "/asl/packages/pk")))
      (and (ok! dir (list "init" "-q" "-b" "main"))
        (and (ok? (fileWrite (str dir "/.gitattributes") "doc.asn merge=asnRows\n"))
          (and (put! dir (docRow "old" "returns one"))
            (and (ok! dir (list "add" "-A"))
              (and (ok! dir (list "commit" "-q" "-m" "base"))
                (and (branch! dir "unitA" (str (docRow "old" "returns one") (docRow "alpha" "returns a")))
                  (and (branch! dir "unitB" (str (docRow "old" "returns one") (docRow "beta" "returns b")))
                    (and (branch! dir "unitC" (str (docRow "old" "returns one") (docRow "alpha" "returns c")))))))))))))

fn ! sha! dir: String name: String -> String
  (stringTrim (git! dir (list "rev-parse" name)).out)

fn ! runTests -> Bool
  (let [(d (repo ""))
        (ready (build! d))
        (noDriver (stringEmpty? (stringTrim (git! d (list "config" "--get" "merge.asnRows.driver")).out)))
        (both (tr/mergeAll! d (root) 1800 (list (pair "unitA" (sha! d "unitA")) (pair "unitB" (sha! d "unitB"))) (list)))
        (text (resultOr (fileReadString (str d "/" (docPath))) ""))
        (d2 (repo "-c"))
        (ready2 (build! d2))
        (clash (tr/mergeAll! d2 (root) 1800 (list (pair "unitA" (sha! d2 "unitA")) (pair "unitC" (sha! d2 "unitC"))) (list)))
        (_ (sh! (list "rm" "-rf" d d2)))]
    (do
      (assert (and ready noDriver) "scratch repo with doc.asn marked merge=asnRows and no configured driver")
      (assert (ok? both) (str "two units of one package add different contract rows: the train merges both with no conflict: " (match both ((err e) e) ((ok _) "ok"))))
      (assert (and (stringContains? text "#alpha") (and (stringContains? text "#beta") (stringContains? text "#old"))) (str "every row is kept: " text))
      (assert (not (or (stringContains? text "<<<<<<<") (stringContains? text ">>>>>>>"))) "no conflict marker in doc.asn")
      (assert (and ready2 (err? clash)) "two units documenting the same symbol differently still conflict")
      (assert (match clash ((err e) (and (stringContains? e ":conflict") (stringContains? e "doc.asn"))) ((ok _) false)) (str "the conflict names the file: " (match clash ((err e) e) ((ok _) "ok"))))
      true))
