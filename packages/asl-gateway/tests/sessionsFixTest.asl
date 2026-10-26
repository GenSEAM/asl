(module aslGateway/tests/sessionsFixTest
  :x [runTests]
  :i [(sessions :a s)
      (asl-tools/fleet/run :a fr)])

; (:m :do "GWSESS-FIX1 gates for named sessions: fork args on the first turn of a fork only, a dash prompt follows --, lock tokens and takeover")
fn fakeProgram -> String
  "BEGIN{sd=ARGV[1]; n=ARGC-1; prompt=ARGV[n]; id=\"\"; for(i=2;i<n;i++) if(ARGV[i]==\"--resume\") id=ARGV[i+1]; resumed=(id!=\"\"); if(!resumed){f=sd \"/counter\"; c=0; getline c < f; close(f); c++; print c > f; close(f); id=\"fake-\" c} ctxf=sd \"/ctx-\" id; mem=\"\"; while((getline l < ctxf)>0) mem=mem l \"|\"; close(ctxf); print prompt >> ctxf; close(ctxf); af=sd \"/argv-\" id; print \"TURN resumed=\" resumed >> af; for(i=2;i<=n;i++) print \"ARG<\" ARGV[i] \">\" >> af; close(af); printf \"{\\\"session_id\\\":\\\"%s\\\",\\\"result\\\":\\\"seen=%s now=%s can=%s lst=%s\\\",\\\"usage\\\":{\\\"input_tokens\\\":3,\\\"output_tokens\\\":4}}\\n\", id, mem, prompt, ENVIRON[\"ASLCANARY\"], ENVIRON[\"ASLLISTED\"]; exit 0}"

fn forkVendor sd: String -> s/SessVendor
  (s/SessVendor :name "fake" :bin "/usr/bin/awk" :env (list) :first (list (fakeProgram) sd) :resume (list (fakeProgram) sd "--resume" "{id}")
                :idFrom "session_id" :replyFrom "result" :wrap "" :wrapResume "" :sep "" :modelArgs (list) :fork (list "--fork-session"))

fn plainRow bin: String sep: String -> s/SessVendor
  (s/SessVendor :name "p" :bin bin :env (list) :first (list "-x") :resume (list) :idFrom "" :replyFrom "" :wrap "" :wrapResume "" :sep sep :modelArgs (list) :fork (list))

fn lastTurn text: String -> String
  (optionOr (listLast (stringSplit text "TURN resumed=")) "")

fn ! rd path: String -> String
  (resultOr (fileReadString path) "")

fn testFork -> Bool
  (let [(me (stringFromInt64 (procSelf)))
        (dir (str "/tmp/aslSfFork" me))
        (sd (str dir "/state"))
        (ctx (s/SessCtx :dir (str dir "/sessions") :env (envList) :timeoutSec 20 :ttlSec 0 :ledger "" :vendors (list (forkVendor sd))))
        (_mk (dirCreate sd))
        (start (s/sessStart! ctx "src" "fake" dir (list) "alpha"))
        (fork (s/sessFork! ctx "src" "kid"))
        (badFork (s/sessFork! ctx "src" "b-kid"))
        (kid1 (s/sessSend! ctx "kid" "beta" (list)))
        (argvKid1 (lastTurn (rd (str sd "/argv-fake-1"))))
        (kid2 (s/sessSend! ctx "kid" "gamma" (list)))
        (argvKid2 (lastTurn (rd (str sd "/argv-fake-1"))))
        (src2 (s/sessSend! ctx "src" "delta" (list)))
        (argvSrc (lastTurn (rd (str sd "/argv-fake-1"))))
        (kidRow (rd (s/sessRowPath ctx "kid")))
        (_rm (pathRemove dir))]
    (do (assert (stringContains? start ":status ok") "the source session starts")
        (assert (stringContains? fork ":op fork") "fork copies the row")
        (assert (stringContains? badFork ":code badName") "a fork may not be named into the binding namespace")
        (assert (stringContains? kid1 ":status ok") "the fork's first turn runs")
        (assert (stringContains? argvKid1 "ARG<--fork-session>") "the first turn of a fork runs the vendor's fork args")
        (assert (stringContains? kid2 ":status ok") "the fork's second turn runs")
        (assert (not (stringContains? argvKid2 "--fork-session")) "later turns of the fork do not fork again")
        (assert (stringContains? src2 ":status ok") "the source keeps working")
        (assert (not (stringContains? argvSrc "--fork-session")) "the source never forks")
        (assert (stringContains? kidRow ":fork false") "the fork flag is cleared after the first turn")
        true))

fn testArgv -> Bool
  (let [(plain (plainRow "claude" ""))
        (withSep (plainRow "agy" "-p"))]
    (do (assert (= (s/sessArgv plain "" (list) "hi") (list "claude" "-x" "hi")) "an ordinary prompt follows the head unchanged")
        (assert (= (s/sessArgv plain "" (list) "-v") (list "claude" "-x" "--" "-v")) "a prompt that starts with a dash follows --")
        (assert (= (s/sessArgv withSep "" (list) "-v") (list "agy" "-x" "-p" "-v")) "a row with a :sep uses it")
        true))

fn ! testLock -> Bool
  (let [(me (stringFromInt64 (procSelf)))
        (dir (str "/tmp/aslSfLock" me))
        (ctx (s/SessCtx :dir (str dir "/sessions") :env (envList) :timeoutSec 20 :ttlSec 0 :ledger "" :vendors (list)))
        (t1 (s/sessLockTake! ctx "n"))
        (held (s/sessLockHeld? ctx "n" t1))
        (t2 (s/sessLockTake! ctx "n"))
        (_wrong (s/sessUnlock! ctx "n" "123:456"))
        (stillHeld (s/sessLockHeld? ctx "n" t1))
        (_u (s/sessUnlock! ctx "n" t1))
        (gone (not (s/sessLockHeld? ctx "n" t1)))
        (_stale (pathSymlink "999999:1" (s/sessLockPath ctx "n")))
        (t3 (s/sessLockTake! ctx "n"))
        (heldAfter (s/sessLockHeld? ctx "n" t3))
        (leftovers (filter (fn [(f String)] -> Bool (stringContains? f ".stale-")) (resultOr (dirList (str dir "/sessions")) (list))))
        (_u3 (s/sessUnlock! ctx "n" t3))
        (_rm (pathRemove dir))]
    (do (assert (not (stringEmpty? t1)) "a free lock is taken")
        (assert held "the token proves ownership")
        (assert (stringEmpty? t2) "a lock held by a live owner is busy")
        (assert stillHeld "unlocking with another token leaves the lock alone")
        (assert gone "unlocking with the owner's token releases it")
        (assert (not (stringEmpty? t3)) "a lock whose owner is gone is taken over")
        (assert heldAfter "the takeover token holds the lock")
        (assert (listEmpty? leftovers) "the renamed stale lock is removed")
        true))

fn ! runTests -> Bool
  (do (assert (testFork) "fork")
      (assert (testArgv) "argv")
      (assert (testLock) "lock")
      true)
