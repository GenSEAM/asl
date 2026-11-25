(module asl-cli/auditOwnTreeTest :x [runTests] :i [(asl-tools/fleet/run :a run)])

; (:m :ref MERGECHECK-CLI-AUDITS-OWN-TREE :do "the audit verb audits the tree it is pointed at while running this CLI's auditor: a scratch git tree holding an unbalanced asn fails ERR_UNBALANCED by cwd and by --root from elsewhere, and this tree stays green; the CLI is the worktree's own built one, so no CLI is built here")
fn ! sh! cwd: String argv: (List String) -> run/Done
  (run/runOneLimited (run/job argv cwd (run/childEnv (list))) (run/limits 900 64))

fn ! put! path: String text: String -> Bool
  (ok? (fileWrite path text))

fn ! runTests -> Bool
  (let [(root (resultOr (realPath ".") "."))
        (cli (str root "/bin/asl"))
        (t (str root "/.asl/cache/auditOwnTree/" (stringFromInt64 (procSelf))))
        (made (listAll? (fn [(d String)] -> Bool (ok? (dirCreate d))) (list (str root "/.asl/cache") (str root "/.asl/cache/auditOwnTree") t)))
        (wrote (put! (str t "/bad.asn") "(:broken (:a 1)\n"))
        (inited (sh! t (list "git" "init" "-q")))
        (added (sh! t (list "git" "add" "bad.asn")))
        (byCwd (sh! t (list cli "audit" "consistency" "--no-cache")))
        (byRoot (sh! root (list cli "audit" "consistency" "--no-cache" "--root" t)))
        (own (sh! root (list cli "audit" "consistency" "--no-cache")))
        (cleaned (pathRemove t))]
    (do (assert (and made wrote) "scratch tree set up")
      (assert (= byCwd.exit 1) "unbalanced scratch tree by cwd exits 1")
      (assert (stringContains? byCwd.out "ERR_UNBALANCED") "by cwd names ERR_UNBALANCED")
      (assert (= byRoot.exit 1) "unbalanced scratch tree by --root exits 1")
      (assert (stringContains? byRoot.out "ERR_UNBALANCED") "by --root names ERR_UNBALANCED")
      (assert (and (stringContains? own.out ":id syntax :status :passed") (not (stringContains? own.out "ERR_UNBALANCED"))) "the CLI's own balanced tree passes the syntax check") true))
