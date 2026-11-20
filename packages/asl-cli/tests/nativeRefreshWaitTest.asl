(module asl-cli/nativeRefreshWaitTest :x [runTests] :i [(asl-tools/fleet/run :a run) (asl/packages/asl-cli/src/nativeCli :a nc)])

; (:m :ref AGENTEFF-03 :do "each case removes its scratch root before its first assert, so a red run leaves at most one empty directory")
; (:m :ref AGENTEFF-03 :do "a read-class argv never waits for a rebuild. Part one asserts the ASL class (readOnly?, the write family only while no toolchain root moved). Part two runs each launcher (bin/asl, asl/bin/asl) copied into a scratch root with two fake pinned CLIs (sh scripts that print served old or served new) and a fake builder that logs its argv, blocks until a release file exists (at most 60 s) and then renames the head: an edit outside the deps list serves with no notice and no builder call; an edit inside serves every read from the old CLI with the notice while the builder is still blocked, starts one background rebuild for all of them, and a test, a --fresh read and a read carrying a foreign form or key are not served; after the release the head names the new CLI; a live owner starts no second rebuild, a dead one is replaced, a failed rebuild is not retried until a source moves. Children are bounded by fleet/run, the detached builder by its own loop, the scratch dir is removed")
fn ! put! path: String text: String -> Bool
  (ok? (fileWrite path text))

fn ! exe! path: String text: String -> Bool
  (and (put! path text) (ok? (fileChmod path 493)))

fn ! slurp path: String -> String
  (resultOr (fileReadString path) "")

fn ! more! path: String -> Bool
  (do (sleepMs 1100) (ok? (fileAppend path "x\n")))

fn headOf cache: String r: String -> String
  (str cache "/head" (stringReplace r "/" "_"))

fn bgOf cache: String r: String -> String
  (str cache "/bg" (stringReplace r "/" "_"))

fn builderText r: String cache: String -> String
  (str "#!/bin/sh\necho \"$*\" >> '" r "/builder.log'\n[ \"$1\" != guard ] || exit 0\n"
       "case \" $* \" in *\" --fresh version \"*|*\" --if-cold \"*) ;; *) echo '(:asl :status :failed :error ERR_NATIVE_STALE :message \"fixture: a foreground refresh\")'; exit 2 ;; esac\n"
       "n=0; while [ ! -e '" r "/release' ]; do n=$((n + 1)); [ $n -le 300 ] || exit 75; sleep 0.2; done\n"
       "[ ! -e '" r "/fail' ] || exit 3\n"
       "printf '%s\\n' '" cache "/cli-new' > '" (headOf cache r) ".part' && mv -f '" (headOf cache r) ".part' '" (headOf cache r) "'\n")

; (:m :ref AGENTEFF-03 :do "asl/bin/asl bounds its whole rebuild by ASL_NATIVE_BUILD_WAIT and the background rebuild inherits the row of the read that started it: reads get 120 s, the argvs that must wait get 1 s so they give up behind the blocked rebuild")
fn ! envFor cache: String waitS: String -> (List String)
  (listAppend (list (str "ASL_NATIVE_CLI_CACHE=" cache) (str "ASL_NATIVE_BUILD_WAIT=" waitS))
    (filter (fn [(row String)] -> Bool (not (or (stringStartsWith? row "ASL_NATIVE_BUILD_WAIT=") (or (stringStartsWith? row "ASL_NATIVE_CLI_CACHE=") (or (stringStartsWith? row "ASL_ROOT=") (stringStartsWith? row "ASL_PRELUDE="))))))
            (run/childEnv (list))))

fn ! call! r: String launcher: String cache: String args: (List String) -> run/Done
  (run/runOneLimited (run/job (cons (str r "/" launcher) args) r (envFor cache "120")) (run/limits 60 16))

fn ! callShort! r: String launcher: String cache: String args: (List String) -> run/Done
  (run/runOneLimited (run/job (cons (str r "/" launcher) args) r (envFor cache "1")) (run/limits 60 16))

fn ! builds r: String -> Int64
  (listLength (filter (fn [(l String)] -> Bool (or (stringContains? l "--fresh version") (stringContains? l "--if-cold"))) (stringLines (slurp (str r "/builder.log")))))

fn ! settled! path: String tries: Int64 -> Bool
  (cond
    ((not (fileExists? path)) true)
    ((<= tries 0) false)
    (else (do (sleepMs 200) (settled! path (- tries 1)))))

fn served? d: run/Done which: String -> Bool
  (and (= d.exit 0) (stringContains? d.out (str "served " which " ")))

fn noticed? d: run/Done word: String -> Bool
  (stringContains? d.out (str "(:cli stale :serving old :rebuilding " word ")"))

fn noticedNew? d: run/Done word: String -> Bool
  (stringContains? d.out (str "(:cli stale :serving new :rebuilding " word ")"))

fn readArgs -> (List String)
  (list "(:read :file \"a.asl\" :symbol main)" "(:query :text \"x\" :in \"asl\")" "(:observe :dim status)" "(:tree :path \".\" :depth 1)" "(:help :op read)" "(:tools)"
        "(:intel :outline :file \"a.asl\")" "(:intel :op outline :file \"a.asl\")" "(:mem :op list)" "(:mem :op get :file \"plan.asn\" :id A-1)" "(:mem :op query :text \"x\")"
        "(:read :file \"a.asl\") (:tree)")

fn waitArgs -> (List (List String))
  (list (list "test" "x.asl") (list "check" "x.asl") (list "audit" "gates") (list "--fresh" "(:tree)") (list "(:read :file \"a.asl\") (:run :cmd \"x\")")
        (list "(:read :file \"a.asl\" :gates (\"x\"))") (list "(:mem :op put :row \"(:u)\")") (list "(:mem :op get :id A :op put)") (list "(:intel :op sweep)") (list "(:test :file \"x.asl\")")
        (list "(:tree)" "check"))

fn ! shapes -> Bool
  (do (assert (listAll? (fn [(a String)] -> Bool (nc/readOnly? (list a))) (readArgs)) "every sample read argv is read class in ASL")
      (assert (and (nc/readOnly? (list "help")) (nc/readOnly? (list "--version")) (nc/readOnly? (list "intel" "outline" "a.asl"))) "the bare help, version and intel outline verbs are read class")
      (assert (not (listAny? (fn [(c (List String))] -> Bool (nc/readOnly? c)) (waitArgs))) "no test, check, audit, fresh, foreign-form or foreign-key argv is read class in ASL")
      (assert (not (nc/readOnly? (list "(:edit :file \"a\" :old \"b\" :new \"c\")"))) "an edit is not read class")
      (assert (nc/formsOnly? (list "(:edit :file \"a\" :old \"b\" :new \"c\") (:flush)")) "an edit stays in the forms family")
      (assert (not (nc/readOnly? (list "version" "x"))) "a verb with a trailing argument is not read class")
      (assert (not (nc/readOnly? (list))) "an empty argv is not read class")
      (assert (nc/readOnly? (list "(:mem :op get :id A) (:mem :op get :id B)")) "two forms each carry their own :op")
      true)

fn ! toolchain base: String -> Bool
  (let [(root (str base "/tc/root"))
        (dir (str base "/tc/cli"))
        (made (listAll? (fn [(d String)] -> Bool (ok? (dirCreate d)))
                (list (str base "/tc") root dir (str root "/asl") (str root "/asl/packages") (str root "/asl/packages/asl-parser") (str root "/asl/packages/asl-parser/src")
                      (str root "/asl/packages/asl-html") (str root "/asl/packages/asl-html/src")
                      (str dir "/src") (str dir "/src/asl") (str dir "/src/asl/packages") (str dir "/src/asl/packages/asl-parser") (str dir "/src/asl/packages/asl-parser/src")
                      (str dir "/src/asl/packages/asl-html") (str dir "/src/asl/packages/asl-html/src"))))
        (p "asl/packages/asl-parser/src/p.asl")
        (h "asl/packages/asl-html/src/h.asl")
        (wrote (and (put! (str root "/" p) "a\n") (put! (str dir "/src/" p) "a\n") (put! (str root "/" h) "a\n") (put! (str dir "/src/" h) "a\n") (put! (str dir "/deps") (str p "\n" h "\n"))))
        (same (nc/toolchainMoved? root dir))
        (outside (and (put! (str root "/" h) "b\n") (nc/toolchainMoved? root dir)))
        (inside (and (put! (str root "/" p) "b\n") (nc/toolchainMoved? root dir)))
        (noDeps (and (ok? (pathRemove (str dir "/deps"))) (nc/toolchainMoved? root dir)))
        (cleaned (pathRemove (str base "/tc")))]
    (do (assert (and made wrote) "the toolchain fixture was made")
        (assert (not same) "unchanged sources: no toolchain root moved")
        (assert (not outside) "a moved source outside the toolchain roots does not count")
        (assert inside "a moved parser source counts, so the write family waits")
        (assert noDeps "a missing deps list counts as moved")
        (assert (ok? cleaned) "the toolchain fixture was removed")
        true))

fn ! launcherCase root: String base: String launcher: String -> Bool
  (let [(r0 (str base "/" (stringReplace launcher "/" "-")))
        (made0 (ok? (dirCreate r0)))
        (r (resultOr (realPath r0) r0))
        (cache (str r "/cache"))
        (head (headOf cache r))
        (bg (bgOf cache r))
        (made (listAll? (fn [(d String)] -> Bool (ok? (dirCreate d)))
                (list (str r "/bin") (str r "/asl") (str r "/asl/bin") (str r "/asl/host") (str r "/asl/host/out") (str r "/asl/host/out/aslNativeBuild-fresh")
                      (str r "/src") (str r "/tests") cache (str cache "/cli-old") (str cache "/cli-new"))))
        (wrote (and (exe! (str r "/" launcher) (slurp (str root "/" launcher)))
                    (put! (str r "/.asl.config.asn") "(:workspace :nativeCli (\n  :formsPin true\n))\n")
                    (put! (str r "/src/in.asl") "a\n") (put! (str r "/tests/out.asl") "a\n")
                    (exe! (str cache "/cli-old/bin") "#!/bin/sh\necho \"served old $*\"\n") (put! (str cache "/cli-old/deps") "src/in.asl\n")
                    (exe! (str cache "/cli-new/bin") "#!/bin/sh\necho \"served new $*\"\n") (put! (str cache "/cli-new/deps") "src/in.asl\n")
                    (put! (str r "/asl/host/out/aslNativeBuild-fresh/deps") "src/in.asl\n")
                    (exe! (str r "/asl/host/out/aslNativeBuild") (builderText r cache))
                    (exe! (str r "/asl/host/build.sh") "exit 0\n")
                    (put! head (str cache "/cli-old\n"))))
        (movedOut (more! (str r "/tests/out.asl")))
        (outside (call! r launcher cache (list "(:read :file \"x\")")))
        (logOutside (slurp (str r "/builder.log")))
        (movedIn (ok? (fileAppend (str r "/src/in.asl") "x\n")))
        (reads (map (fn [(a String)] -> run/Done (call! r launcher cache (list a))) (readArgs)))
        (verbs (list (call! r launcher cache (list "version")) (call! r launcher cache (list "intel" "outline" "a.asl"))))
        (buildsHeld (builds r))
        (ownerHeld (stringTrim (slurp bg)))
        (ownerLive (run/runOneLimited (run/job (list "/bin/sh" "-c" "kill -0 \"$1\"" "sh" ownerHeld) r (envFor cache "1")) (run/limits 10 4)))
        (waits (map (fn [(c (List String))] -> run/Done (callShort! r launcher cache c)) (waitArgs)))
        (headHeld (stringTrim (slurp head)))
        (released (put! (str r "/release") "go\n"))
        (done1 (settled! bg 200))
        (after (call! r launcher cache (list "(:tree)")))
        (headAfter (stringTrim (slurp head)))
        (buildsAfter (builds r))
        (stale2 (more! (str r "/src/in.asl")))
        (livePid (put! bg (str (stringFromInt64 (procSelf)) "\n")))
        (live (call! r launcher cache (list "(:tree)")))
        (buildsLive (builds r))
        (deadPid (put! bg "99999999\n"))
        (dead (call! r launcher cache (list "(:tree)")))
        (done2 (settled! bg 200))
        (buildsDead (builds r))
        (stale3 (and (more! (str r "/src/in.asl")) (put! (str r "/fail") "x\n")))
        (failing (call! r launcher cache (list "(:tree)")))
        (done3 (settled! bg 200))
        (failedMark (fileExists? (str bg ".failed")))
        (again (call! r launcher cache (list "(:tree)")))
        (buildsFailed (builds r))
        (stale4 (and (ok? (pathRemove (str r "/fail"))) (more! (str r "/src/in.asl"))))
        (retried (call! r launcher cache (list "(:tree)")))
        (done4 (settled! bg 200))
        (buildsRetried (builds r))
        (failedGone (not (fileExists? (str bg ".failed"))))
        (logAll (slurp (str r "/builder.log")))
        (cleaned (pathRemove r0))
        (tag (str launcher ": "))]
    (do (assert (and made0 made wrote) (str tag "the scratch root, its fake CLIs and its fake builder were made"))
        (assert (and movedOut (= (stringTrim outside.out) "served old (:read :file \"x\")") (= outside.exit 0)) (str tag "an edit outside the deps list serves with no notice: " outside.out))
        (assert (stringEmpty? logOutside) (str tag "an edit outside the deps list calls no builder: " logOutside))
        (assert movedIn (str tag "a source the CLI was built from moved"))
        (assert (listAll? (fn [(d run/Done)] -> Bool (and (served? d "old") (noticed? d "true"))) reads)
                (str tag "every read-class form is served by the pinned CLI with the notice while the rebuild is blocked: " (stringJoin (map (fn [(d run/Done)] -> String d.out) reads) " | ")))
        (assert (listAll? (fn [(d run/Done)] -> Bool (and (served? d "old") (noticed? d "true"))) verbs) (str tag "version and intel outline are served the same way"))
        (assert (= buildsHeld 1) (str tag "all of them started one background rebuild: " (stringFromInt64 buildsHeld) " in " logAll))
        (assert (and (not (stringEmpty? ownerHeld)) (= ownerLive.exit 0)) (str tag "the single-flight file names the live rebuild: " ownerHeld))
        (assert (listAll? (fn [(d run/Done)] -> Bool (and (!= d.exit 0) (not (stringContains? d.out "served ")))) waits)
                (str tag "a test, check, audit, --fresh, foreign form or foreign key is never served by the stale CLI: " (stringJoin (map (fn [(d run/Done)] -> String (str (stringFromInt64 d.exit) " " d.out)) waits) " | ")))
        (assert (= headHeld (str cache "/cli-old")) (str tag "the head still names the old CLI while the rebuild runs: " headHeld))
        (assert (and released done1) (str tag "the released rebuild finished and dropped its single-flight file"))
        (assert (= (stringTrim after.out) "served new (:tree)") (str tag "after the switch the new CLI answers with no notice: " after.out))
        (assert (and (= headAfter (str cache "/cli-new")) (not (fileExists? (str head ".part")))) (str tag "the head was renamed into place: " headAfter))
        (assert (= buildsAfter 1) (str tag "still one rebuild after the switch: " (stringFromInt64 buildsAfter)))
        (assert (and stale2 livePid (served? live "new") (noticedNew? live "true") (= buildsLive 1)) (str tag "a live single-flight owner starts no second rebuild: " live.out " builds " (stringFromInt64 buildsLive)))
        (assert (and deadPid (served? dead "new") (noticedNew? dead "true") done2 (= buildsDead 2)) (str tag "a dead owner is replaced by exactly one rebuild: " dead.out " builds " (stringFromInt64 buildsDead)))
        (assert (and stale3 (served? failing "new") (noticedNew? failing "true") done3 failedMark) (str tag "a failing rebuild leaves its failed mark: " failing.out))
        (assert (and (served? again "new") (noticedNew? again "failed") (= buildsFailed 3)) (str tag "a failed rebuild is not started again for the same sources: " again.out " builds " (stringFromInt64 buildsFailed)))
        (assert (and (ok? cleaned) (not (fileExists? r0))) (str tag "the scratch root was removed before any verdict"))
        (assert (and stale4 (served? retried "new") (noticedNew? retried "true") done4 (= buildsRetried 4) failedGone) (str tag "a source moved after the failure starts one rebuild and clears the mark: " retried.out " builds " (stringFromInt64 buildsRetried)))
        true))

fn ! runTests -> Bool
  (let [(root (resultOr (realPath ".") "."))
        (base (str root "/.asl/cache/nativeRefreshWait/" (stringFromInt64 (procSelf))))
        (made (and (ok? (dirCreate (str root "/.asl/cache/nativeRefreshWait"))) (ok? (dirCreate base))))
        (ok1 (shapes))
        (ok2 (toolchain base))
        (ok3 (launcherCase root base "bin/asl"))
        (ok4 (launcherCase root base "asl/bin/asl"))
        (cleaned (pathRemove base))]
    (do (assert made "the scratch dir was made")
        (assert (and (ok? cleaned) (not (fileExists? base))) "the scratch dir was removed")
        (and ok1 ok2 ok3 ok4)))
