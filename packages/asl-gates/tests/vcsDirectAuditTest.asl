(module asl-gates/tests/vcsDirectAuditTest
  :x [runTests]
  :i [(asl-gates/vcsDirectAudit :a va)])

; (:m :ref VCS-DIRECT-GIT-AUDIT :do "inputs are in-memory path and text pairs, and the word git is assembled so this file holds no site itself")
fn g -> String
  (str "gi" "t")

fn pairOf path: String text: String -> (Pair String String)
  (pair path text)

fn keysOf files: (List (Pair String String)) -> (List String)
  (map va/siteKey (va/scanFiles files))

fn newOf files: (List (Pair String String)) allow: (List String) -> (List String)
  (va/verdictOf (va/scanFiles files) allow).newSites

fn staleOf files: (List (Pair String String)) allow: (List String) -> (List String)
  (va/verdictOf (va/scanFiles files) allow).stale

fn srcList verb: String -> String
  (str "(module m\n  :x [f]\n  :i [])\n\nfn ! f! dir: String -> Bool\n  (ok? (run (list \"" (g) "\" \"" verb "\" \"-A\")))\n")

fn srcHelper -> String
  (str "(module m\n  :x [f]\n  :i [])\n\nfn ! f! dir: String -> Bool\n  (ok? (" (g) "Run! dir (list \"-C\" dir \"commit\" \"-m\" \"x\")))\n")

fn srcString -> String
  (str "(module m\n  :x [f]\n  :i [])\n\nfn ! f! -> Bool\n  (ok? (runShell \"" (g) " add -A\"))\n")

fn srcShell body: String -> String
  (str "(module m\n  :x [f]\n  :i [])\n\nfn ! f! -> Bool\n  (ok? (runShell \"" body "\"))\n")

fn srcNonVerb -> String
  (str "(module m\n  :x [f]\n  :i [])\n\nfn ! f! -> Bool\n  (ok? (run (list \"" (g) "\" \"status\")))\n")

fn srcComment -> String
  (str "(module m\n  :x [f]\n  :i [])\n\n; (list \"" (g) "\" \"commit\")\nfn f -> String\n  \"talks about " (g) " commit in prose\"\n")

fn testNewSite -> Bool
  (let [(files (list (pairOf "tools/a.asl" (srcList "commit"))))]
    (do (assert (= (keysOf files) (list "tools/a.asl#f!|git commit")) "a literal argv list is a site keyed path#symbol|git verb")
        (assert (= (newOf files (list)) (list "tools/a.asl#f!|git commit")) "a site absent from the allowlist is new, so the audit is red")
        (assert (= (staleOf files (list)) (list)) "no allowlist row, no stale row")
        (assert (= (va/receiptOf (va/verdictOf (va/scanFiles files) (list)) 0) "(:vcsDirectAudit :v 1 :status :violation :sites 1 :allowed 0 :new (\"tools/a.asl#f!|git commit\") :stale ())") "the receipt is one ASN line with status violation")
        true))

fn testAllowed -> Bool
  (let [(files (list (pairOf "tools/a.asl" (srcList "commit"))))
        (allow (list "tools/a.asl#f!|git commit"))]
    (do (assert (= (newOf files allow) (list)) "an allowlisted site is not new")
        (assert (= (staleOf files allow) (list)) "an allowlisted site that still exists is not stale")
        (assert (= (va/receiptOf (va/verdictOf (va/scanFiles files) allow) 1) "(:vcsDirectAudit :v 1 :status :ok :sites 1 :allowed 1 :new () :stale ())") "the receipt is status ok")
        true))

fn testStale -> Bool
  (let [(files (list (pairOf "tools/a.asl" (srcList "commit"))))
        (allow (list "tools/a.asl#f!|git commit" "tools/gone.asl#h!|git add"))]
    (do (assert (= (staleOf files allow) (list "tools/gone.asl#h!|git add")) "an allowlist row with no site is stale")
        (assert (= (newOf files allow) (list)) "a stale row alone adds no new site")
        (assert (= (va/receiptOf (va/verdictOf (va/scanFiles files) allow) 2) "(:vcsDirectAudit :v 1 :status :violation :sites 1 :allowed 2 :new () :stale (\"tools/gone.asl#h!|git add\"))") "a stale row makes the receipt a violation")
        (assert (= (staleOf (list (pairOf "tools/a.asl" "(module m\n  :x []\n  :i [])\n")) allow) allow) "removing the site leaves both rows stale")
        true))

fn testPatterns -> Bool
  (do (assert (= (keysOf (list (pairOf "t/h.asl" (srcHelper)))) (list "t/h.asl#f!|git commit")) "a call of a git-named helper with a verb literal is a site")
      (assert (= (keysOf (list (pairOf "t/s.asl" (srcString)))) (list "t/s.asl#f!|git add")) "a string starting with the git word and a verb is a site")
      (assert (= (keysOf (list (pairOf "t/q.asl" (srcShell (str "cd x && " (g) " add -A"))))) (list "t/q.asl#f!|git add")) "a shell string with git after && is a site")
      (assert (= (keysOf (list (pairOf "t/q.asl" (srcShell (str "cd x; " (g) " reset --hard && " (g) " commit -m y"))))) (list "t/q.asl#f!|git reset" "t/q.asl#f!|git commit")) "every git segment after ; and && is a site")
      (assert (= (keysOf (list (pairOf "t/q.asl" (srcShell (str "echo " (g) " add -A"))))) (list)) "git in the middle of a segment, not at its start, is not a site")
      (assert (= (keysOf (list (pairOf "t/n.asl" (srcNonVerb)))) (list)) "a git status argv is not a covered verb")
      (assert (= (keysOf (list (pairOf "t/c.asl" (srcComment)))) (list)) "comment text and prose strings are not sites")
      (assert (= (keysOf (list (pairOf "asl/tools/vcs/git.asl" (srcList "commit")))) (list)) "the vcs layer itself is excluded")
      (assert (= (keysOf (list (pairOf "asl/tools/vcsOther/x.asl" (srcList "push")))) (list "asl/tools/vcsOther/x.asl#f!|git push")) "only the exact asl/tools/vcs/ directory is excluded")
      (assert (= (listLength (keysOf (list (pairOf "t/a.asl" (srcList "reset")) (pairOf "t/b.asl" (srcList "checkout")) (pairOf "t/c.asl" (srcList "update-ref")) (pairOf "t/d.asl" (srcList "commit-tree")) (pairOf "t/e.asl" (srcList "push"))))) 5) "every covered verb is found")
      true)

fn testParse -> Bool
  (let [(text "(:vcsDirectAllow :v 1)\n(:site \"a.asl#f\" :file \"a.asl\" :symbol \"f\" :argv \"git add\" :why \"w\")\n(:site \"b.asl#h!\" :file \"b.asl\" :symbol \"h!\" :argv \"git push\" :why \"w\")\n")]
    (do (assert (= (va/parseAllow text) (list "a.asl#f|git add" "b.asl#h!|git push")) "allowlist rows parse to site|argv keys in order")
        true))

fn testRealTree -> Bool
  (match (va/audit! "." ".asl/mem/vcsDirectAllow.asn")
    ((err e) (do (assert false (str "audit failed to run: " e)) false))
    ((ok r) (do (assert (stringStartsWith? r "(:vcsDirectAudit :v 1 :status :ok ") (str "the real tree matches its allowlist exactly: " r))
                (assert (stringContains? r ":new () :stale ()") "no new site and no stale row on the real tree")
                true)))

fn ! runTests -> Bool
  (do (testNewSite) (testAllowed) (testStale) (testPatterns) (testParse) (testRealTree))
