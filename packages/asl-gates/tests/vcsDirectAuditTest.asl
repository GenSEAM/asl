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
        (cleanExit (va/main (list "--root" root "--no-cache")))
        (allow1 (str allow0 (allowRow "tests/c.asl#f!" "add")))
        (fixtured (and (put! root "tests/c.asl" (srcList "add")) (and (put! root ".asl/mem/vcsDirectAllow.asn" allow1) (stage! root))))
        (fixtureExit (va/main (list "--root" root "--no-cache")))
        (fixtureReceipt (receiptOr (va/auditWith! root (str root "/.asl/mem/vcsDirectAllow.asn") "" "off")))
        (grownStaged (and (put! root "t/b.asl" (srcList "commit")) (and (put! root ".asl/mem/vcsDirectAllow.asn" (str allow1 (allowRow "t/b.asl#f!" "commit"))) (stage! root))))
        (grownExit (va/main (list "--root" root "--no-cache")))
        (grownBaseExit (va/main (list "--root" root "--base" "HEAD" "--no-cache")))
        (grownReceipt (receiptOr (va/auditWith! root (str root "/.asl/mem/vcsDirectAllow.asn") "" "off")))
        (badBaseExit (va/main (list "--root" root "--base" "noSuchRef" "--no-cache")))
        (_ (pathRemove (str root "/t/a.asl")))
        (unreadableExit (va/main (list "--root" root "--no-cache")))
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
    (do (assert (= (one (str "env -u GIT_DIR " (g) " " (vb "com" "mit") " -m x")) (list "t/q.asl#f!|git commit")) "the unset option and its name are skipped before the command")
        (assert (= (one (str "env -i " (g) " " (vb "ad" "d") " -A")) (list "t/q.asl#f!|git add")) "the ignore-environment option is skipped before the command")
        (assert (= (one (str "env -u A -u B " (g) " push")) (list "t/q.asl#f!|git push")) "two unset options are skipped")
        (assert (= (one (str "env --unset GIT_DIR " (g) " reset --hard")) (list "t/q.asl#f!|git reset")) "the long unset option and its name are skipped")
        (assert (= (one (str "env -uGIT_DIR " (g) " checkout x")) (list "t/q.asl#f!|git checkout")) "the joined unset option is skipped")
        (assert (= (one (str "env -C /d A=1 " (g) " " (vb "com" "mit") " -m x")) (list "t/q.asl#f!|git commit")) "the chdir option with its dir and an assignment are skipped")
        (assert (= (one (str "echo env -u A " (g) " " (vb "ad" "d"))) (list)) "the prefix word after another command is not a command start")
        (assert (= (one "env -u GIT_DIR ls") (list)) "prefix options before another command are no site")
        true))

fn cacheFiles -> (List (Pair String String))
  (list (pairOf "t/a.asl" (srcList "commit")) (pairOf "t/b.asl" (srcShell (str (g) " push"))) (pairOf "t/c.asl" "(module t/c\n  :x [f]\n  :i [])\n\nfn f -> Int64\n  1\n"))

fn siteKeys sites: (List va/Site) -> (List String)
  (map va/siteKey sites)

; (:m :ref VCS-AUDIT-SPEED :do "the per-file cache: any cache content yields the sites of the plain scan; a row in the cache is used a changed file or a changed helper set misses; a malformed cache line is dropped")
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
        (assert (= (mapSize (va/parseCache "garbage line without tab\n\tno key\nk\trow\t.\nk2\trow2\n")) 1) "malformed and unterminated cache lines are dropped, a row ends with the end mark")
        true))

; (:m :ref VCS-AUDIT-LOWS-F1 :do "a temp repo on main with t/a.asl holding one allowlisted push site, committed; true when every step worked")
fn ! repoWith! root: String -> Bool
  (let [(made (and (ok? (dirCreate root)) (and (ok? (dirCreate (str root "/.asl"))) (and (ok? (dirCreate (str root "/.asl/mem"))) (ok? (dirCreate (str root "/t")))))))]
    (and made (and (vcs! root (list "init" "-q" "-b" "main"))
               (and (put! root "t/a.asl" (srcList "push")) (and (put! root ".asl/mem/vcsDirectAllow.asn" (str "(:vcsDirectAllow :v 1)\n" (allowRow "t/a.asl#f!" "push")))
                 (and (stage! root) (vcs! root (list "-c" "user.name=t" "-c" "user.email=t@t" "-c" "commit.gpgsign=false" "commit" "-q" "-m" "base"))))))))

fn ! stripMs r: String -> String
  (optionOr (listHead (stringSplit r " :ms ")) r)

; (:m :ref VCS-AUDIT-SPEED :do "the cache is a file in the given store dir, never in the tree: the second audit reuses it and its receipt equals the first apart from :ms; an unwritable store is named in the receipt")
fn ! testCacheFile -> Bool
  (let [(root (str "/tmp/vcsDirectAuditCache-" (stringFromInt64 (procSelf))))
        (store (str root "-store"))
        (_ (pathRemove root))
        (_ (pathRemove store))
        (based (repoWith! root))
        (allow (str root "/.asl/mem/vcsDirectAllow.asn"))
        (r1 (receiptOr (va/auditWith! root allow "" store)))
        (text1 (resultOr (fileReadString (str store "/vcsDirectAudit.v1")) ""))
        (r2 (receiptOr (va/auditWith! root allow "" store)))
        (text2 (resultOr (fileReadString (str store "/vcsDirectAudit.v1")) ""))
        (inTree (fileExists? (str root "/.asl/cache")))
        (blocker (str root "-blocker"))
        (_ (fileWrite blocker "a file where the store dir should be"))
        (r3 (receiptOr (va/auditWith! root allow "" (str blocker "/sub"))))
        (_ (pathRemove blocker))
        (_ (pathRemove store))
        (_ (pathRemove root))]
    (do (assert based "temp repo built")
        (assert (stringStartsWith? r1 "(:vcsDirectAudit :v 1 :status :ok ") (str "the first audit is ok: " r1))
        (assert (not (stringEmpty? text1)) "the first audit wrote the cache file into the store")
        (assert (not inTree) "and nothing under .asl/cache in the tree")
        (assert (= (stripMs r1) (stripMs r2)) "the second receipt equals the first apart from :ms")
        (assert (= text1 text2) "the second audit left the cache file unchanged")
        (assert (stringContains? r3 ":cache \"cache dir: ") (str "a store that cannot be written is named in the receipt: " r3))
        true))

fn emptySites row: String -> String
  (let [(parts (stringSplit row "\t"))]
    (str (optionOr (listGet parts 0) "") "\t"))

; (:m :ref VCS-AUDIT-LOWS-F1 :do "forged rows hide a site only while the cache is read: with sites emptied in the store, the store audit reports no new site, the --no-cache audit still names it; a tracked path under .asl/cache is refused; the default store is outside the tree and off is no store")
fn ! testForgery -> Bool
  (let [(root (str "/tmp/vcsDirectAuditForge-" (stringFromInt64 (procSelf))))
        (store (str root "-store"))
        (_ (pathRemove root))
        (_ (pathRemove store))
        (based (repoWith! root))
        (allow (str root "/.asl/mem/vcsDirectAllow.asn"))
        (newSite (and (put! root "t/b.asl" (srcList "commit")) (stage! root)))
        (honest (receiptOr (va/auditWith! root allow "" store)))
        (rows (va/parseCache (resultOr (fileReadString (str store "/vcsDirectAudit.v1")) "")))
        (forged (stringJoin (map (fn [(k String)] -> String (str k "\t" (emptySites (optionOr (mapGet rows k) "")) (va/rowEnd))) (mapKeys rows)) "\n"))
        (_ (fileWrite (str store "/vcsDirectAudit.v1") forged))
        (hidden (receiptOr (va/auditWith! root allow "" store)))
        (off (receiptOr (va/auditWith! root allow "" "off")))
        (viaMain (va/main (list "--root" root "--no-cache")))
        (dirDefault (resultOr (va/cacheDirFor! root "") ""))
        (dirOff (resultOr (va/cacheDirFor! root "off") "x"))
        (trackedStaged (and (ok? (dirCreate (str root "/.asl/cache"))) (and (put! root ".asl/cache/vcsDirectAudit.v1" "row") (vcs! root (list "add" "-f" ".asl/cache/vcsDirectAudit.v1")))))
        (tracked (receiptOr (va/auditWith! root allow "" "off")))
        (_ (pathRemove store))
        (_ (pathRemove root))]
    (do (assert (and based newSite) "temp repo with an unallowed site built")
        (assert (stringContains? honest ":new (\"t/b.asl#f!|git commit\")") (str "the honest audit names the new site: " honest))
        (assert (stringContains? hidden ":new (\"t/b.asl#f!|git commit\")") (str "unkeyed forged rows in the store are rescanned, the store audit still names the site: " hidden))
        (assert (stringContains? off ":new (\"t/b.asl#f!|git commit\")") (str "the --no-cache audit still names the site: " off))
        (assert (= viaMain (ok 1)) "and the command line flag --no-cache exits 1")
        (assert (and (stringStartsWith? dirDefault (resultOr (va/storeRoot) "unset")) (not (stringStartsWith? dirDefault root))) (str "the default store is outside the tree: " dirDefault))
        (assert (stringEmpty? dirOff) "mode off has no store dir")
        (assert (and (= (va/cap (list "--no-cache")) "off") (= (va/cap (list "--cache-dir" "d")) "d") (= (va/cap (list)) "")) "the command line picks off, a dir or the runner store")
        (assert (and trackedStaged (stringContains? tracked "ERR_VCS_CACHE_TRACKED")) (str "a tracked path under .asl/cache is refused: " tracked))
        true))

; (:m :ref VCS-AUDIT-LOWS-F1 :do "the key names the file text, the helper set, whether the path is the vcs layer and the file's own helpers: each part changes the key; an identical text under an excluded path cannot hide the sites of the same text under a normal path")
fn testKeys -> Bool
  (let [(h0 (va/Helpers :local (list) :names (list)))
        (h1 (va/Helpers :local (list "t/a.asl|sh") :names (list "sh")))
        (h2 (va/Helpers :local (list) :names (list "sh")))
        (body (srcList "push"))
        (excl (pairOf "asl/tools/vcs/x.asl" body))
        (norm (pairOf "t/n.asl" body))
        (viaExcludedFirst (siteKeys (pairFirst (va/scanFilesC (mapEmpty) (list excl norm)))))
        (rowsAfter (va/parseCache (va/cacheText (pairSecond (va/scanFilesC (mapEmpty) (list excl))))))
        (viaWarm (siteKeys (pairFirst (va/scanFilesC rowsAfter (list norm)))))]
    (do (assert (not (= (va/viewKey "s" "d" h1 "t/a.asl") (va/viewKey "s" "d" h2 "t/a.asl"))) "the file's own helper names are part of the key")
        (assert (not (= (va/viewKey "s" "d" h0 "t/a.asl") (va/viewKey "s" "e" h0 "t/a.asl"))) "the helper set digest is part of the key")
        (assert (not (= (va/viewKey "s" "d" h0 "t/a.asl") (va/viewKey "t" "d" h0 "t/a.asl"))) "the text is part of the key")
        (assert (not (= (va/viewKey "s" "d" h0 "asl/tools/vcs/x.asl") (va/viewKey "s" "d" h0 "t/a.asl"))) "an excluded path has another key than a normal path with the same text")
        (assert (= viaExcludedFirst (siteKeys (va/scanFiles (list excl norm)))) "the same text under an excluded path first does not hide the normal copy")
        (assert (= viaWarm (list "t/n.asl#f!|git push")) (str "rows written for the excluded copy do not hide the normal copy: " (stringJoin viaWarm ",")))
        true))

fn storeNames -> (List String)
  (listSort (resultOr (dirList (resultOr (va/storeRoot) "")) (list)))

; (:m :ref VCS-AUDIT-LOWS-F2 :do "the store id comes from the git common dir: a repo and a linked worktree of it share one store dir, another repo has another; the audits of temp repos use no cache or a temp dir, so the real store gains at most the id of the real repo")
fn ! testStoreId -> Bool
  (let [(root (str "/tmp/vcsDirectAuditId-" (stringFromInt64 (procSelf))))
        (wt (str root "-wt"))
        (other (str root "-other"))
        (_ (pathRemove wt))
        (_ (pathRemove root))
        (_ (pathRemove other))
        (based (and (repoWith! root) (repoWith! other)))
        (linked (vcs! root (list "worktree" "add" "-q" "-b" "linked" wt "main")))
        (dRoot (resultOr (va/cacheDirFor! root "") "a"))
        (dWt (resultOr (va/cacheDirFor! wt "") "b"))
        (dOther (resultOr (va/cacheDirFor! other "") "c"))
        (_ (vcs! root (list "worktree" "remove" "--force" wt)))
        (_ (pathRemove wt))
        (_ (pathRemove root))
        (_ (pathRemove other))]
    (do (assert (and based linked) "two repos and a linked worktree built")
        (assert (= dRoot dWt) (str "a repo and its linked worktree share the store dir: " dRoot " " dWt))
        (assert (not (= dRoot dOther)) "another repo has another store dir")
        true))

fn rowsOf store: String -> (Map String String)
  (va/parseCache (resultOr (fileReadString (str store "/vcsDirectAudit.v1")) ""))

; (:m :ref VCS-STORE-ATOMIC :do "the store keeps the rows of every root that shares it (two roots, both rows survive); a file torn at any byte is never read as a row with fewer sites, the site is still named; the write leaves no temp file; nothing is read back from a missing mark")
fn ! testStoreAtomic -> Bool
  (let [(store (str "/tmp/vcsDirectAuditAtomic-" (stringFromInt64 (procSelf))))
        (_ (pathRemove store))
        (filesA (list (pairOf "t/a.asl" (srcList "push"))))
        (filesB (list (pairOf "u/b.asl" (srcList "reset"))))
        (a1 (va/scanCached! store filesA))
        (rowsA (rowsOf store))
        (b1 (va/scanCached! store filesB))
        (rowsB (rowsOf store))
        (a2 (va/scanCached! store filesA))
        (names (listSort (resultOr (dirList store) (list))))
        (full (resultOr (fileReadString (str store "/vcsDirectAudit.v1")) ""))
        (plain (siteKeys (va/scanFiles filesA)))
        (cuts (range 0 (stringLength full)))
        (bad (filter (fn [(n Int64)] -> Bool
                       (let [(_ (fileWrite (str store "/vcsDirectAudit.v1") (optionOr (stringSlice full 0 n) "")))
                             (r (va/scanCached! store filesA))]
                         (!= (siteKeys (pairFirst r)) plain)))
                     cuts))
        (_ (pathRemove store))]
    (do (assert (= (mapSize rowsA) 1) "the first root wrote its row")
        (assert (= (mapSize rowsB) 2) "the second root's run kept the first root's row and added its own")
        (assert (= (mapSize (va/parseCache full)) 2) "a third run of the first root evicts nothing")
        (assert (= names (list (va/keyFile) "vcsDirectAudit.v1")) (str "the write leaves no temp file: " (stringJoin names ",")))
        (assert (= (siteKeys (pairFirst a1)) plain) "the audit names the site")
        (assert (= (listLength bad) 0) (str "a file cut at these bytes changed the sites: " (stringJoin (map stringFromInt64 (listTake bad 5)) ",")))
        true))

; (:m :ref VCS-STORE-ATOMIC :do "over the cap the store is replaced by the rows this run used; a rename that fails (the store file is a non-empty directory) reports cache rename and leaves no temp file; a clean run leaves no temp file")
fn ! testStoreCapAndRename -> Bool
  (let [(store (str "/tmp/vcsDirectAuditCap-" (stringFromInt64 (procSelf))))
        (files (list (pairOf "t/a.asl" (srcList "push"))))
        (_ (pathRemove store))
        (_ (dirCreate store))
        (seed (stringJoin (map (fn [(i Int64)] -> String (str "seed" (stringFromInt64 i) "\t\t" (va/rowEnd))) (range 0 (+ (va/cacheCap) 1))) "\n"))
        (_ (fileWrite (str store "/vcsDirectAudit.v1") seed))
        (seeded (mapSize (va/parseCache seed)))
        (r (va/scanCached! store files))
        (after (rowsOf store))
        (clean (listSort (resultOr (dirList store) (list))))
        (_ (pathRemove store))
        (blocked (str store "-blocked"))
        (_ (pathRemove blocked))
        (_ (dirCreate blocked))
        (_ (dirCreate (str blocked "/vcsDirectAudit.v1")))
        (_ (fileWrite (str blocked "/vcsDirectAudit.v1/keep") "x"))
        (rb (va/scanCached! blocked files))
        (left (listSort (resultOr (dirList blocked) (list))))
        (_ (pathRemove blocked))]
    (do (assert (= seeded (+ (va/cacheCap) 1)) "the seeded store holds cap plus one marked rows")
        (assert (= (mapSize after) 1) (str "over the cap only the rows this run used remain: " (stringFromInt64 (mapSize after))))
        (assert (= (pairSecond r) "") "the over-cap run wrote without a note")
        (assert (= clean (list (va/keyFile) "vcsDirectAudit.v1")) (str "a clean run leaves no temp file: " (stringJoin clean ",")))
        (assert (stringStartsWith? (pairSecond rb) "cache rename") (str "a failed rename is reported: " (pairSecond rb)))
        (assert (= left (list (va/keyFile) "vcsDirectAudit.v1")) (str "a failed rename leaves no temp file: " (stringJoin left ",")))
        (assert (= (siteKeys (pairFirst rb)) (siteKeys (va/scanFiles files))) "and the audit still names the site")
        true))

; (:m :ref STOREROOT-NO-HOME :do "without HOME the runner store is refused with a named error and no /tmp path; off and an explicit dir need no HOME; a set HOME gives HOME/.asl/run/vcsDirect")
fn ! testNoHome -> Bool
  (let [(root (str "/tmp/vcsDirectAuditNoHome-" (stringFromInt64 (procSelf))))
        (_ (pathRemove root))
        (based (repoWith! root))
        (unset (va/cacheDirWith! root "" (none)))
        (blank (va/cacheDirWith! root "" (some "  ")))
        (set (va/cacheDirWith! root "" (some "/h")))
        (off (va/cacheDirWith! root "off" (none)))
        (dir (va/cacheDirWith! root "/d" (none)))
        (_ (pathRemove root))]
    (do (assert based "temp repo built")
        (assert (match (va/storeRootFrom (none)) ((err e) (stringStartsWith? e "ERR_VCS_STORE_NO_HOME")) ((ok _) false)) "an unset HOME has no store root")
        (assert (match (va/storeRootFrom (some "")) ((err e) (stringStartsWith? e "ERR_VCS_STORE_NO_HOME")) ((ok _) false)) "an empty HOME has no store root")
        (assert (= (resultOr (va/storeRootFrom (some "/h")) "") "/h/.asl/run/vcsDirect") "a set HOME gives its store root")
        (assert (match unset ((err e) (and (stringStartsWith? e "ERR_VCS_STORE_NO_HOME") (not (stringContains? e "/tmp/.asl")))) ((ok _) false)) (str "the runner store without HOME is refused: " (resultOr unset "refused")))
        (assert (match blank ((err e) (stringStartsWith? e "ERR_VCS_STORE_NO_HOME")) ((ok _) false)) "a blank HOME is refused")
        (assert (match set ((ok d) (stringStartsWith? d "/h/.asl/run/vcsDirect/")) ((err _) false)) (str "a set HOME keeps the store under it: " (resultOr set "error")))
        (assert (and (ok? off) (= (resultOr off "x") "")) "mode off needs no HOME")
        (assert (= (resultOr dir "") "/d") "an explicit cache dir needs no HOME")
        true))

fn dropSites row: String -> String
  (let [(parts (stringSplit row "\t"))]
    (str (optionOr (listGet parts 0) "") "\t\t" (optionOr (listGet parts 2) "")))

; (:m :ref SCANCACHED-PLANTED :do "the store rows carry a keyed digest: an honest warm run hits its own rows; a row whose sites were emptied with the old digest kept, a row with no digest and a row signed under another key are all misses, the site is still named and the rewrite signs the rows again; the key file is mode 600")
fn ! testPlanted -> Bool
  (let [(store (str "/tmp/vcsDirectAuditPlanted-" (stringFromInt64 (procSelf))))
        (_ (pathRemove store))
        (files (list (pairOf "t/a.asl" (srcList "push"))))
        (plain (siteKeys (va/scanFiles files)))
        (cold (va/scanCached! store files))
        (path (str store "/vcsDirectAudit.v1"))
        (rows (rowsOf store))
        (k (optionOr (listHead (mapKeys rows)) ""))
        (row (optionOr (mapGet rows k) ""))
        (secret (stringTrim (resultOr (fileReadString (str store "/" (va/keyFile))) "")))
        (mode (match (fileStat (str store "/" (va/keyFile))) ((ok st) (& st.mode 511)) ((err _) -1)))
        (warm (va/scanCached! store files))
        (plant (fn [(text String)] -> (List String)
                 (let [(_ (fileWrite path (str k "\t" text (va/rowEnd) "\n")))]
                   (siteKeys (pairFirst (va/scanCached! store files))))))
        (wrongDigest (plant (dropSites row)))
        (resigned (rowsOf store))
        (noDigest (plant "\t"))
        (otherKey (plant (str "\t\t" (va/rowMac (str secret "x") k "\t"))))
        (signedOk (let [(b (stringJoin (listTake (stringSplit row "\t") 2) "\t"))] (= row (str b "\t" (va/rowMac secret k b)))))
        (_ (pathRemove store))]
    (do (assert (= (siteKeys (pairFirst cold)) plain) "the cold run names the site")
        (assert (= (mapSize rows) 1) "the cold run wrote one row")
        (assert signedOk (str "the stored row ends with the keyed digest of its key and body: " row))
        (assert (= mode 384) (str "the key file is mode 600: " (stringFromInt64 mode)))
        (assert (and (= (siteKeys (pairFirst warm)) plain) (= (pairSecond warm) "")) "the warm run hits its own signed row and writes nothing")
        (assert (= wrongDigest plain) (str "a row with its sites emptied and the old digest kept is a miss, the site is named: " (stringJoin wrongDigest ",")))
        (assert (= (optionOr (mapGet resigned k) "") row) "the rescan writes the honest signed row back")
        (assert (= noDigest plain) "a planted row with no digest is a miss")
        (assert (= otherKey plain) "a row signed under another key is a miss")
        true))

; (:m :ref SCANCACHED-PLANTED :do "an existing key is never clobbered: an unusable key file stays as it was, every row is a miss and the site is still named with a cache note, never an error; a usable key another run made is read and used, not replaced; the key never appears in the note")
fn ! testKeyNoClobber -> Bool
  (let [(store (str "/tmp/vcsDirectAuditKey-" (stringFromInt64 (procSelf))))
        (_ (pathRemove store))
        (_ (dirCreate store))
        (keyPath (str store "/" (va/keyFile)))
        (files (list (pairOf "t/a.asl" (srcList "push"))))
        (plain (siteKeys (va/scanFiles files)))
        (_ (fileWrite keyPath "not a key\n"))
        (bad (va/scanCached! store files))
        (badAfter (resultOr (fileReadString keyPath) ""))
        (other (stringJoin (map (fn [(i Int64)] -> String "ab") (range 0 32)) ""))
        (_ (fileWrite keyPath (str other "\n")))
        (_ (pathRemove (str store "/vcsDirectAudit.v1")))
        (good (va/scanCached! store files))
        (goodAfter (stringTrim (resultOr (fileReadString keyPath) "")))
        (rows (rowsOf store))
        (k (optionOr (listHead (mapKeys rows)) ""))
        (row (optionOr (mapGet rows k) ""))
        (body (stringJoin (listTake (stringSplit row "\t") 2) "\t"))
        (_ (pathRemove store))]
    (do (assert (= (siteKeys (pairFirst bad)) plain) "with an unusable key the site is still named")
        (assert (stringStartsWith? (pairSecond bad) "cache key: present but unusable") (str "the unusable key is a cache note, not an error: " (pairSecond bad)))
        (assert (= badAfter "not a key\n") "the unusable key file is not clobbered")
        (assert (= (siteKeys (pairFirst good)) plain) "with another run's key the site is named")
        (assert (= goodAfter other) "a usable existing key is read, not replaced")
        (assert (= row (str body "\t" (va/rowMac other k body))) "the rows are signed with the existing key")
        (assert (not (stringContains? (pairSecond good) other)) "the key is not in the note")
        true))

; (:m :ref VCS-STORE-LOWS-G3 :do "the digest binds the row key: a clean file's signed row copied under a dirty file's key is a miss and the dirty site is still named")
fn ! testKeyBound -> Bool
  (let [(store (str "/tmp/vcsDirectAuditBound-" (stringFromInt64 (procSelf))))
        (_ (pathRemove store))
        (dirty (pairOf "t/a.asl" (srcList "push")))
        (clean (pairOf "t/c.asl" "(module t/c\n  :x [f]\n  :i [])\n\nfn f -> Int64\n  1\n"))
        (files (list dirty clean))
        (plain (siteKeys (va/scanFiles files)))
        (cold (va/scanCached! store files))
        (rows (rowsOf store))
        (kDirty (optionOr (listHead (filter (fn [(k String)] -> Bool (stringContains? (optionOr (mapGet rows k) "") "push")) (mapKeys rows))) ""))
        (kClean (optionOr (listHead (filter (fn [(k String)] -> Bool (not (stringContains? (optionOr (mapGet rows k) "") "push"))) (mapKeys rows))) ""))
        (cleanRow (optionOr (mapGet rows kClean) ""))
        (_ (fileWrite (str store "/vcsDirectAudit.v1") (str kDirty "\t" cleanRow (va/rowEnd) "\n" kClean "\t" cleanRow (va/rowEnd) "\n")))
        (swapped (siteKeys (pairFirst (va/scanCached! store files))))
        (_ (pathRemove store))]
    (do (assert (and (= (siteKeys (pairFirst cold)) plain) (= (listLength plain) 1)) (str "the cold run names the one dirty site: " (stringJoin plain ",")))
        (assert (and (not (stringEmpty? kDirty)) (not (stringEmpty? kClean)) (not (= kDirty kClean))) "both files have their own row")
        (assert (= swapped plain) (str "a clean signed row under the dirty key is a miss, the site is named: " (stringJoin swapped ",")))
        true))

; (:m :ref VCS-STORE-LOWS-G7 :do "the rewrite keeps only verified rows: an unsigned row planted under a key no file uses is not signed into the store")
fn ! testPlantedUnused -> Bool
  (let [(store (str "/tmp/vcsDirectAuditUnused-" (stringFromInt64 (procSelf))))
        (_ (pathRemove store))
        (_ (dirCreate store))
        (files (list (pairOf "t/a.asl" (srcList "push"))))
        (_ (fileWrite (str store "/vcsDirectAudit.v1") (str "zzUnusedKey\t\t" (va/rowEnd) "\n")))
        (run (va/scanCached! store files))
        (secret (stringTrim (resultOr (fileReadString (str store "/" (va/keyFile))) "")))
        (rows (rowsOf store))
        (verified (va/verifiedRows secret rows))
        (_ (pathRemove store))]
    (do (assert (= (pairSecond run) "") (str "the run wrote the store: " (pairSecond run)))
        (assert (= (mapSize verified) 1) (str "the rewrite holds one verified row, the scanned file's: " (stringFromInt64 (mapSize verified))))
        (assert (not (some? (mapGet verified "zzUnusedKey"))) "the planted unsigned row is not signed into the store")
        true))

; (:m :ref VCS-STORE-LOWS-G6 :do "each store makes its own random key: two fresh stores get two different well-formed keys")
fn ! testKeysDiffer -> Bool
  (let [(a (str "/tmp/vcsDirectAuditKeyA-" (stringFromInt64 (procSelf))))
        (b (str "/tmp/vcsDirectAuditKeyB-" (stringFromInt64 (procSelf))))
        (_ (pathRemove a))
        (_ (pathRemove b))
        (files (list (pairOf "t/a.asl" (srcList "push"))))
        (_ (va/scanCached! a files))
        (_ (va/scanCached! b files))
        (ka (stringTrim (resultOr (fileReadString (str a "/" (va/keyFile))) "")))
        (kb (stringTrim (resultOr (fileReadString (str b "/" (va/keyFile))) "")))
        (_ (pathRemove a))
        (_ (pathRemove b))]
    (do (assert (and (= (stringLength ka) 64) (= (stringLength kb) 64)) "both stores made a 64-hex key")
        (assert (not (= ka kb)) "two fresh stores get different keys")
        true))

fn ! runTests -> Bool
  (let [(before (storeNames))]
    (do (testNewSite) (testAllowed) (testStale) (testPatterns) (testParse) (testHelpersByData) (testShellShapes) (testEnvOptions) (testCache) (testCacheFile) (testForgery) (testKeys) (testCounts) (testRatchet) (testStoreId) (testStoreAtomic) (testStoreCapAndRename) (testNoHome) (testPlanted) (testKeyNoClobber) (testKeyBound) (testPlantedUnused) (testKeysDiffer) (testRealTree)
        (assert (= (listLength (storeNames)) (listLength before)) (str "the audits of temp repos left the real store unchanged: " (stringFromInt64 (listLength before)) " dirs before, " (stringFromInt64 (listLength (storeNames))) " after"))
        true))
