(module asl-gates/tests/vcsDirectAuditTest
  :x [runTests]
  :i [(asl-gates/vcsDirectAudit :a va) (asl-tools/fleet/run :a fr)])

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

fn hdr -> String
  "(module m\n  :x [f]\n  :i [])\n\n"

fn srcBody body: String -> String
  (str (hdr) "fn ! f! d: String -> Bool\n  " body "\n")

; (:m :ref VCS-DIRECT-GIT-AUDIT-FIX :do "helpers by data: a fn that prepends git to a parameter is a helper wherever it is named, a qualified call reaches a helper in another file, and a fn passing a parameter on to a helper is one too")
fn testHelpersByData -> Bool
  (let [(bench (str (hdr) "fn ! " (g) " work: String args: (List String) -> Bool\n  (ok? (run (cons \"" (g) "\" args)))\n\nfn ! f! -> Bool\n  (" (g) " \".\" (list \"commit\" \"-m\" \"x\"))\n\nfn ! k! w: String -> Bool\n  (" (g) " w (list \"add\" \"-A\"))\n"))
        (lib (str (hdr) "fn ! sh dir: String args: (List String) -> Bool\n  (ok? (run (listAppend (list \"" (g) "\" \"-c\" \"x=y\") args)))\n\nfn ! wrap d: String args: (List String) -> Bool\n  (sh d args)\n\nfn ! p! d: String -> Bool\n  (wrap d (list \"push\"))\n\nfn ! top d: String -> Bool\n  (sh d)\n"))
        (user (srcBody "(a/sh d (list \"add\" \"-A\"))"))
        (other (srcBody "(b/sh d (list \"status\"))"))]
    (do (assert (= (keysOf (list (pairOf "tools/b.asl" bench))) (list "tools/b.asl#f!|git commit" "tools/b.asl#k!|git add")) (str "a fn named without a bang that prepends git to its parameter is a helper: " (stringJoin (keysOf (list (pairOf "tools/b.asl" bench))) " ")))
        (assert (= (keysOf (list (pairOf "t/a.asl" lib) (pairOf "t/u.asl" user))) (list "t/a.asl#p!|git push" "t/u.asl#f!|git add")) (str "a qualified call reaches a helper of another file and a pass-through fn is a helper: " (stringJoin (keysOf (list (pairOf "t/a.asl" lib) (pairOf "t/u.asl" user))) " ")))
        (assert (= (keysOf (list (pairOf "t/a.asl" lib) (pairOf "t/o.asl" other))) (list "t/a.asl#p!|git push")) "a helper call with a verb outside the covered set is not a site, and a call with one value does not make its fn a helper")
        (assert (= (keysOf (list (pairOf "t/l.asl" (srcBody (str "(ok? (run (listAppend (list \"" (g) "\") (list \"commit\" \"-m\" \"x\"))))"))))) (list "t/l.asl#f!|git commit")) "a verb in the list appended to a git list is a site")
        true))

; (:m :ref VCS-DIRECT-GIT-AUDIT-FIX :do "escapes are decoded before shell strings split; || | & and subshell parens split too; the value of -C or -c is never the verb")
fn testShellShapes -> Bool
  (let [(one (fn [(body String)] -> (List String) (keysOf (list (pairOf "t/q.asl" (srcShell body))))))]
    (do (assert (= (one (str "cd x\\n" (g) " add -A")) (list "t/q.asl#f!|git add")) "an escaped newline before git splits the string")
        (assert (= (one (str "x | " (g) " add -A")) (list "t/q.asl#f!|git add")) "a pipe before git splits the string")
        (assert (= (one (str "a || " (g) " reset --hard")) (list "t/q.asl#f!|git reset")) "|| before git splits the string")
        (assert (= (one (str "(cd x && " (g) " add -A)")) (list "t/q.asl#f!|git add")) "git inside a subshell is a site")
        (assert (= (one (str "echo \\\"" (g) " commit\\\" is a word")) (list)) "an escaped quote does not start a segment")
        (assert (= (one (str "if [ -e x ]; then " (g) " -C $w checkout -q --detach y; fi")) (list "t/q.asl#f!|git checkout")) "git after then is a site")
        (assert (= (one (str "[ -d x ] || mkdir x; else " (g) " -C $d update-ref refs/heads/dev y")) (list "t/q.asl#f!|git update-ref")) "git after else is a site")
        (assert (= (one (str "while true; do " (g) " commit -m x; done")) (list "t/q.asl#f!|git commit")) "git after do is a site")
        (assert (= (one (str "! " (g) " checkout x")) (list "t/q.asl#f!|git checkout")) "git after ! is a site")
        (assert (= (one (str "GIT_INDEX_FILE=i " (g) " add -A")) (list "t/q.asl#f!|git add")) "git after a VAR=x assignment is a site")
        (assert (= (one (str "x=$(" (g) " reset --hard)")) (list "t/q.asl#f!|git reset")) "git inside $( is a site")
        (assert (= (one (str "echo `" (g) " push`")) (list "t/q.asl#f!|git push")) "git inside backquotes is a site")
        (assert (= (one (str "echo then " (g) " add -A")) (list)) "a keyword word after another command is not a command start")
        (assert (= (one (str "/usr/bin/" (g) " commit -m x")) (list "t/q.asl#f!|git commit")) "an absolute-path git in a shell string is a site")
        (assert (= (keysOf (list (pairOf "t/c.asl" (srcBody (str "(ok? (run (list \"/usr/bin/" (g) "\" \"add\" \"-A\")))"))))) (list "t/c.asl#f!|git add")) "an absolute-path git argv is a site")
        (assert (= (one (str "/opt/my" (g) " add -A; " (g) "x commit")) (list)) "a command word that only contains git is not git")
        (assert (= (one (str "env A=1 " (g) " add -A")) (list "t/q.asl#f!|git add")) "git after env is a site")
        (assert (= (one (str "exec " (g) " push")) (list "t/q.asl#f!|git push")) "git after exec is a site")
        (assert (= (one (str "command " (g) " reset --hard")) (list "t/q.asl#f!|git reset")) "git after command is a site")
        (assert (= (one (str "nohup " (g) " commit -m x")) (list "t/q.asl#f!|git commit")) "git after nohup is a site")
        (assert (= (one (str "xargs " (g) " add")) (list "t/q.asl#f!|git add")) "git after xargs is a site")
        (assert (= (one (str "sudo " (g) " checkout x")) (list "t/q.asl#f!|git checkout")) "git after sudo is a site")
        (assert (= (one (str "eval " (g) " update-ref refs/x y")) (list "t/q.asl#f!|git update-ref")) "git after eval is a site")
        (assert (= (one (str "echo env " (g) " add")) (list)) "a prefix word after another command is not a command start")
        (assert (= (keysOf (list (pairOf "t/c.asl" (srcBody (str "(ok? (run (list \"" (g) "\" \"-C\" \"/d\" \"commit\" \"-m\" \"x\")))"))))) (list "t/c.asl#f!|git commit")) "a literal -C value is not the verb")
        (assert (= (keysOf (list (pairOf "t/c.asl" (srcBody (str "(ok? (runShell (str \"" (g) " -C \" d \" -c k=v commit -m x\")))"))))) (list "t/c.asl#f!|git commit")) "a git string built with str and a -C value from a parameter is a site")
        true))

; (:m :ref VCS-DIRECT-GIT-AUDIT-FIX :do "every occurrence counts: a second site with the same symbol and verb is new against a one-row allowlist and allowed by :n 2")
fn testCounts -> Bool
  (let [(files (list (pairOf "t/n.asl" (srcBody (str "(do (run (list \"" (g) "\" \"commit\" \"-m\" \"a\")) (ok? (run (list \"" (g) "\" \"commit\" \"-m\" \"b\"))))")))))
        (key "t/n.asl#f!|git commit")
        (two (va/parseAllow (str "(:vcsDirectAllow :v 1)\n(:site \"t/n.asl#f!\" :argv \"" (g) " commit\" :n 2 :why \"w\")\n")))]
    (do (assert (= (keysOf files) (list key key)) "two sites with one symbol and verb are two keys")
        (assert (= (newOf files (list key)) (list key)) "the second occurrence is new against a one-row allowlist")
        (assert (= two (list key key)) "a row with :n 2 parses to the key twice")
        (assert (and (= (newOf files two) (list)) (= (staleOf files two) (list))) "an :n 2 row allows both and is not stale")
        (assert (= (staleOf (list (pairOf "t/n.asl" (srcBody (str "(ok? (run (list \"" (g) "\" \"commit\")))")))) two) (list key)) "one of two sites removed leaves the row stale by one")
        true))

fn ! vcs! root: String args: (List String) -> Bool
  (= (fr/runOneLimited (fr/job (cons (g) args) root (fr/childEnv (list))) (fr/limits 60 8)).exit 0)

fn ! put! root: String path: String text: String -> Bool
  (ok? (fileWrite (str root "/" path) text))

fn allowRow site: String verb: String -> String
  (str "(:site \"" site "\" :argv \"" (g) " " verb "\" :why \"w\")\n")

fn ! stage! root: String -> Bool
  (vcs! root (list "add" "-A"))

fn receiptOr r: (Result String String) -> String
  (match r ((ok s) s) ((err e) (str "error " e)))

; (:m :ref VCS-DIRECT-GIT-AUDIT-FIX :do "the ratchet on a temp repo on main: a product row added since the base is :grown and exits 1 even with its site, a fixture row under tests is reported and exits 0, an unknown --base and an unreadable tracked file exit 2")
fn ! testRatchet -> Bool
  (let [(root (str "/tmp/vcsDirectAuditTest-" (stringFromInt64 (procSelf))))
        (_ (pathRemove root))
        (made (and (ok? (dirCreate root)) (and (ok? (dirCreate (str root "/.asl"))) (and (ok? (dirCreate (str root "/.asl/mem"))) (and (ok? (dirCreate (str root "/t"))) (ok? (dirCreate (str root "/tests"))))))))
        (allow0 (str "(:vcsDirectAllow :v 1)\n" (allowRow "t/a.asl#f!" "push")))
        (based (and made (and (vcs! root (list "init" "-q" "-b" "main"))
                   (and (put! root "t/a.asl" (srcList "push")) (and (put! root ".asl/mem/vcsDirectAllow.asn" allow0)
                     (and (stage! root) (vcs! root (list "-c" "user.name=t" "-c" "user.email=t@t" "-c" "commit.gpgsign=false" "commit" "-q" "-m" "base"))))))))
        (cleanExit (va/main (list "--root" root)))
        (allow1 (str allow0 (allowRow "tests/c.asl#f!" "add")))
        (fixtured (and (put! root "tests/c.asl" (srcList "add")) (and (put! root ".asl/mem/vcsDirectAllow.asn" allow1) (stage! root))))
        (fixtureExit (va/main (list "--root" root)))
        (fixtureReceipt (receiptOr (va/audit! root (str root "/.asl/mem/vcsDirectAllow.asn"))))
        (grownStaged (and (put! root "t/b.asl" (srcList "commit")) (and (put! root ".asl/mem/vcsDirectAllow.asn" (str allow1 (allowRow "t/b.asl#f!" "commit"))) (stage! root))))
        (grownExit (va/main (list "--root" root)))
        (grownBaseExit (va/main (list "--root" root "--base" "HEAD")))
        (grownReceipt (receiptOr (va/audit! root (str root "/.asl/mem/vcsDirectAllow.asn"))))
        (badBaseExit (va/main (list "--root" root "--base" "noSuchRef")))
        (_ (pathRemove (str root "/t/a.asl")))
        (unreadableExit (va/main (list "--root" root)))
        (_ (pathRemove root))]
    (do (assert (and based (= cleanExit (ok 0))) "control: the base tree matches its allowlist and exits 0")
        (assert (and fixtured (= fixtureExit (ok 0))) "a row grown under tests with its site exits 0")
        (assert (and grownStaged (= grownExit (ok 1))) "a new product site with a new allowlist row exits 1 against the merge base with main")
        (assert (= grownBaseExit (ok 1)) "the same with --base HEAD")
        (assert (stringContains? grownReceipt ":grown (\"t/b.asl#f!|git commit\")") (str "the grown row is named: " grownReceipt))
        (assert (and (stringContains? grownReceipt ":base :self ") (stringContains? grownReceipt " :ms ")) (str "on main the default base is HEAD itself and says so, with the run time: " grownReceipt))
        (assert (stringContains? fixtureReceipt ":grownFixtures (\"tests/c.asl#f!|git add\")") (str "the fixture growth is reported: " fixtureReceipt))
        (assert (= badBaseExit (ok 2)) "a base that does not resolve is an error")
        (assert (= unreadableExit (ok 2)) "a tracked file that cannot be read is an error, not an empty file")
        true))

fn testRealTree -> Bool
  (match (va/audit! "." ".asl/mem/vcsDirectAllow.asn")
    ((err e) (do (assert false (str "audit failed to run: " e)) false))
    ((ok r) (do (assert (stringStartsWith? r "(:vcsDirectAudit :v 1 :status :ok ") (str "the real tree matches its allowlist exactly: " r))
                (assert (stringContains? r ":new () :stale ()") "no new site and no stale row on the real tree")
                true)))

fn vb a: String b: String -> String
  (str a b)

; (:m :ref VCS-AUDIT-ENV-OPTS :do "env options before the command word are skipped: -u NAME, -i, --unset NAME, -C DIR, -uNAME and NAME=v; a word after another command is not a command start")
fn testEnvOptions -> Bool
  (let [(one (fn [(body String)] -> (List String) (keysOf (list (pairOf "t/q.asl" (srcShell body))))))]
    (do (assert (= (one (str "env -u GIT_DIR " (g) " " (vb "com" "mit") " -m x")) (list "t/q.asl#f!|git commit")) "env -u NAME git commit is a site")
        (assert (= (one (str "env -i " (g) " " (vb "ad" "d") " -A")) (list "t/q.asl#f!|git add")) "env -i git add is a site")
        (assert (= (one (str "env -u A -u B " (g) " push")) (list "t/q.asl#f!|git push")) "two -u options are skipped")
        (assert (= (one (str "env --unset GIT_DIR " (g) " reset --hard")) (list "t/q.asl#f!|git reset")) "--unset NAME is skipped")
        (assert (= (one (str "env -uGIT_DIR " (g) " checkout x")) (list "t/q.asl#f!|git checkout")) "-uNAME is skipped")
        (assert (= (one (str "env -C /d A=1 " (g) " " (vb "com" "mit") " -m x")) (list "t/q.asl#f!|git commit")) "-C DIR and an assignment are skipped")
        (assert (= (one (str "echo env -u A " (g) " " (vb "ad" "d"))) (list)) "env after another command is not a command start")
        (assert (= (one "env -u GIT_DIR ls") (list)) "env options before a non-git command are no site")
        true))

fn cacheFiles -> (List (Pair String String))
  (list (pairOf "t/a.asl" (srcList "commit")) (pairOf "t/b.asl" (srcShell (str (g) " push"))) (pairOf "t/c.asl" "(module t/c\n  :x [f]\n  :i [])\n\nfn f -> Int64\n  1\n"))

fn siteKeys sites: (List va/Site) -> (List String)
  (map va/siteKey sites)

; (:m :ref VCS-AUDIT-SPEED :do "the per-file cache: any cache content yields the sites of the plain scan; a row in the cache is used (a planted row shows through); a changed file or a changed helper set misses; a malformed cache line is dropped")
fn testCache -> Bool
  (let [(files (cacheFiles))
        (plain (siteKeys (va/scanFiles files)))
        (cold (va/scanFilesC (mapEmpty) files))
        (warmOld (va/parseCache (va/cacheText (pairSecond cold))))
        (warm (va/scanFilesC warmOld files))
        (poisoned (fold (fn [(m (Map String String)) (k String)] -> (Map String String) (mapSet m k "\tpush t/fake")) warmOld (mapKeys warmOld)))
        (shown (siteKeys (pairFirst (va/scanFilesC poisoned files))))
        (edited (list (pairOf "t/a.asl" (srcList "add")) (pairOf "t/b.asl" (srcShell (str (g) " push"))) (pairOf "t/c.asl" "(module t/c\n  :x [f]\n  :i [])\n")))
        (editedWarm (siteKeys (pairFirst (va/scanFilesC warmOld edited))))
        (editedPlain (siteKeys (va/scanFiles edited)))
        (libA (str (hdr) "fn ! sh dir: String args: (List String) -> Bool\n  (ok? (run (listAppend (list \"" (g) "\" \"-c\" \"x=y\") args)))\n"))
        (userB (srcBody "(a/sh d (list \"add\" \"-A\"))"))
        (noLib (list (pairOf "t/a.asl" (srcBody "(ok? (run (list \"echo\")))")) (pairOf "t/u.asl" userB)))
        (withLib (list (pairOf "t/a.asl" libA) (pairOf "t/u.asl" userB)))
        (coldNo (va/scanFilesC (mapEmpty) noLib))
        (helperChanged (siteKeys (pairFirst (va/scanFilesC (va/parseCache (va/cacheText (pairSecond coldNo))) withLib))))]
    (do (assert (= (siteKeys (pairFirst cold)) plain) "a cold cache scan equals the plain scan")
        (assert (= (siteKeys (pairFirst warm)) plain) "a warm cache scan equals the plain scan")
        (assert (> (mapSize (pairSecond warm)) 0) "the used rows are recorded")
        (assert (= (mapSize (pairSecond warm)) (mapSize warmOld)) "a warm run uses exactly the stored rows")
        (assert (not (= shown plain)) "a planted cache row is used instead of a rescan")
        (assert (= editedWarm editedPlain) (str "an edited file misses and the result equals the plain scan: " (stringJoin editedWarm ",")))
        (assert (= helperChanged (siteKeys (va/scanFiles withLib))) (str "a changed helper set misses for the unchanged caller: " (stringJoin helperChanged ",")))
        (assert (= (mapSize (va/parseCache "garbage line without tab\n\tno key\nk\trow\n")) 1) "malformed cache lines are dropped")
        true))

; (:m :ref VCS-AUDIT-SPEED :do "on a temp repo the second audit reuses the cache file and its receipt equals the first one apart from :ms; an unwritable cache dir is named in the receipt, not hidden")
fn ! testCacheFile -> Bool
  (let [(root (str "/tmp/vcsDirectAuditCache-" (stringFromInt64 (procSelf))))
        (_ (pathRemove root))
        (made (and (ok? (dirCreate root)) (and (ok? (dirCreate (str root "/.asl"))) (and (ok? (dirCreate (str root "/.asl/mem"))) (ok? (dirCreate (str root "/t")))))))
        (based (and made (and (vcs! root (list "init" "-q" "-b" "main"))
                   (and (put! root "t/a.asl" (srcList "push")) (and (put! root ".asl/mem/vcsDirectAllow.asn" (str "(:vcsDirectAllow :v 1)\n" (allowRow "t/a.asl#f!" "push")))
                     (and (stage! root) (vcs! root (list "-c" "user.name=t" "-c" "user.email=t@t" "-c" "commit.gpgsign=false" "commit" "-q" "-m" "base"))))))))
        (allow (str root "/.asl/mem/vcsDirectAllow.asn"))
        (strip (fn [(r String)] -> String (optionOr (listHead (stringSplit r " :ms ")) r)))
        (r1 (receiptOr (va/audit! root allow)))
        (cacheText1 (resultOr (fileReadString (str root "/" (va/cacheRel))) ""))
        (r2 (receiptOr (va/audit! root allow)))
        (cacheText2 (resultOr (fileReadString (str root "/" (va/cacheRel))) ""))
        (_ (pathRemove (str root "/.asl/cache")))
        (_ (fileWrite (str root "/.asl/cache") "file where the dir should be"))
        (r3 (receiptOr (va/audit! root allow)))
        (_ (pathRemove root))]
    (do (assert based "temp repo built")
        (assert (stringStartsWith? r1 "(:vcsDirectAudit :v 1 :status :ok ") (str "the first audit is ok: " r1))
        (assert (not (stringEmpty? cacheText1)) "the first audit wrote the cache file")
        (assert (= (strip r1) (strip r2)) "the second receipt equals the first apart from :ms")
        (assert (= cacheText1 cacheText2) "the second audit left the cache file unchanged")
        (assert (stringContains? r3 ":cache \"cache dir: ") (str "a cache that cannot be written is named in the receipt: " r3))
        true))

fn ! runTests -> Bool
  (do (testNewSite) (testAllowed) (testStale) (testPatterns) (testParse) (testHelpersByData) (testShellShapes) (testEnvOptions) (testCache) (testCacheFile) (testCounts) (testRatchet) (testRealTree))
