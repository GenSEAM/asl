(module asl-utils/tests/timeoutTest
  :x [runTests]
  :i [(asl-tools/fleet/run :a fr) (asl-utils/timeout :a t)])

fn ! shimEnv! -> (List String)
  (fr/childEnv (list (str "ASL_PRELUDE=" (resultOr (realPath "asl/prelude/prelude.asl") "asl/prelude/prelude.asl")) (str "ASL_CLI_ROOT=" (resultOr (realPath ".") "."))))

fn ! shim! secs: String argv: (List String) -> fr/ProcOut
  (fr/runGuarded (listAppend (list (fr/nativeCli!) "timeout" secs "--") argv) "." (shimEnv!) (fr/limits 40 64))

fn ! alive? pid: Int64 -> Bool
  (and (> pid 1) (match (procAlive? pid) ((ok b) b) ((err _) false)))

fn pidOf out: String -> Int64
  (optionOr (stringToInt64 (stringTrim (optionOr (listHead (stringSplit out "\n")) ""))) 0)

fn ! cleanup! pid: Int64 -> Bool
  (do (if (alive? pid) (procKill pid "SIGKILL") (ok ())) true)

fn ! testPassThrough -> Bool
  (let [(zero (shim! "10" (list "/bin/sh" "-c" "exit 0")))
        (three (shim! "10" (list "/bin/sh" "-c" "echo out; echo err >&2; exit 3")))
        (lit (shim! "10" (list "/bin/sh" "-c" "printf %s \"$1\"" "x" "a b;c $HOME")))]
    (do (assert (= zero.exitCode 0) (str "exit 0 passes through: " zero.exitCode " " zero.stderr))
        (assert (= three.exitCode 3) (str "exit 3 passes through: " three.exitCode " " three.stderr))
        (assert (stringContains? three.stdout "out") (str "child stdout is forwarded: " three.stdout))
        (assert (stringContains? three.stderr "err") (str "child stderr is forwarded: " three.stderr))
        (assert (= lit.stdout "a b;c $HOME") (str "an argv with spaces, a semicolon and a dollar reaches the child literally: " lit.stdout))
        true))

fn ! testSignalled -> Bool
  (let [(r (shim! "10" (list "/bin/sh" "-c" "kill -9 $$")))]
    (do (assert (= r.exitCode 137) (str "a child killed by SIGKILL exits 128+9: " r.exitCode))
        true))

fn ! testExpiry -> Bool
  (let [(t0 (monotonicNs))
        (r (shim! "1" (list "/bin/sh" "-c" "sleep 60 & echo $!; wait")))
        (ms (/ (- (monotonicNs) t0) 1000000))
        (gc (pidOf r.stdout))
        (_ (sleepMs 200))
        (left (alive? gc))
        (_ (cleanup! gc))]
    (do (assert (= r.exitCode 124) (str "expiry exits 124: " r.exitCode " " r.stderr))
        (assert (> gc 1) (str "the grandchild pid was reported: " r.stdout))
        (refute left (str "the grandchild " gc " did not survive the expiry"))
        (assert (< ms 20000) (str "the shim returned long before the sleeper would have: " ms " ms"))
        true))

fn pidsOf out: String -> (List Int64)
  (filter (fn [(n Int64)] -> Bool (> n 1)) (map (fn [(w String)] -> Int64 (optionOr (stringToInt64 w) 0)) (stringSplit (stringTrim out) " ")))

fn ! markerCount! marker: String -> Int64
  (listLength (filter (fn [(l String)] -> Bool (stringContains? l marker)) (stringLines (resultOr (fr/shellOut "ps -A -o pid= -o command=" 10000) ""))))

fn ! killMarker! marker: String -> Bool
  (do (fr/shellOut (str "pkill -9 -f '" marker "'") 10000) true)

fn ! cliSh! script: String shell: String -> fr/ProcOut
  (fr/runGuarded (list shell "-c" script (fr/nativeCli!)) "." (shimEnv!) (fr/limits 40 64))

fn ! testKillEscalation -> Bool
  (let [(t0 (monotonicNs))
        (r (shim! "1" (list "/bin/sh" "-c" "trap '' TERM; (trap '' TERM; exec sleep 60) & echo \"$$ $!\"; while :; do sleep 1; done")))
        (ms (/ (- (monotonicNs) t0) 1000000))
        (pids (pidsOf r.stdout))
        (_ (sleepMs 200))
        (left (filter alive? pids))
        (_ (map cleanup! pids))]
    (do (assert (= r.exitCode 124) (str "a child ignoring SIGTERM still exits 124: " r.exitCode " " r.stderr))
        (assert (= (listLength pids) 2) (str "the child and its grandchild pids were reported: " r.stdout))
        (assert (listEmpty? left) (str "the TERM-ignoring child and grandchild are both gone: " left))
        (assert (>= ms 2500) (str "SIGKILL waited out the 2 s grace: " ms " ms"))
        true))

fn ! testRespawner -> Bool
  (let [(r (shim! "1" (list "/bin/sh" "-c" "trap '' TERM; while :; do sleep 7311; done")))
        (_ (sleepMs 300))
        (n (markerCount! "sleep 7311"))
        (_ (killMarker! "sleep 7311"))]
    (do (assert (= r.exitCode 124) (str "a respawning tree exits 124: " r.exitCode " " r.stderr))
        (assert (= n 0) (str "no member of the respawning tree survived: " n))
        true))

fn ! testBrokenPipe -> Bool
  (let [(t0 (monotonicNs))
        (r (cliSh! "\"$0\" timeout 30 -- yes 7312marker | head -c 10 >/dev/null; echo ${PIPESTATUS[0]}" "/bin/bash"))
        (ms (/ (- (monotonicNs) t0) 1000000))
        (_ (sleepMs 200))
        (n (markerCount! "yes 7312marker"))
        (_ (killMarker! "yes 7312marker"))]
    (do (assert (= (stringTrim r.stdout) "141") (str "a closed reader makes the shim exit 141: " r.stdout " " r.stderr))
        (assert (< ms 20000) (str "it did not wait out the 30 s timeout: " ms " ms"))
        (assert (= n 0) (str "the producer was killed: " n))
        true))

fn ! testStdin -> Bool
  (let [(r (cliSh! "printf hello | \"$0\" timeout 5 -- cat" "/bin/sh"))]
    (do (assert (= r.stdout "hello") (str "stdin reaches the child and closes at EOF: " r.stdout " " r.stderr))
        (assert (= r.exitCode 0) (str "cat exits 0 once stdin closes: " r.exitCode))
        true))

; (:m :ref TIMEOUT-WRAPPER-ORPHAN :do "two shims read one stdin pipe that stays open; the first exits after 1 s and clears O_NONBLOCK on the shared description, the second must still exit with its 3 s child instead of blocking in read until its own timeout")
fn ! testSharedStdin -> Bool
  (let [(r (cliSh! "sleep 30.7314 | { \"$0\" timeout 20 -- sleep 1 <&0 & a=$!; s=$(date +%s); \"$0\" timeout 20 -- sleep 3; echo \"$? $(( $(date +%s) - s ))\"; pkill -f 'sleep 30.7314'; wait $a; }" "/bin/bash"))
        (_ (killMarker! "sleep 30.7314"))
        (words (stringSplit (stringTrim r.stdout) " "))
        (secs (optionOr (stringToInt64 (optionOr (listGet words 1) "")) 99))]
    (do (assert (= (optionOr (listHead words) "") "0") (str "the second shim exits 0 with its child: " r.stdout " " r.stderr))
        (assert (< secs 15) (str "it exits when its child exits, not at its 20 s timeout: " secs " s"))
        true))

fn ! testDrain -> Bool
  (let [(r (shim! "10" (list "/bin/sh" "-c" "head -c 60000 /dev/zero | tr '\\0' a")))]
    (do (assert (= (stringLength r.stdout) 60000) (str "everything a fast-exiting child wrote is forwarded: " (stringLength r.stdout)))
        true))

fn ! testDrainDirect -> Bool
  (match (fr/spawnSep (list "/bin/sh" "-c" "head -c 60000 /dev/zero | tr '\\0' a") "." (shimEnv!))
    ((err d) (assert false (str "writer spawn: " d.stderr)))
    ((ok w) (let [(a (procWaitPid w.pid false))
                  (text (t/readRest! w.outFd true ""))
                  (b (fdClose w.errFd))]
              (do (assert (= (stringLength text) 60000) (str "reading a pipe after its writer exited yields every byte: " (stringLength text)))
                  true))))


fn ! testSpawnFailure -> Bool
  (let [(r (shim! "5" (list "asl-no-such-command-7313")))]
    (do (assert (= r.exitCode 127) (str "a command that cannot start exits 127: " r.exitCode))
        (assert (stringContains? r.stderr "cannot start") (str "the reason is reported: " r.stderr))
        true))

fn testClosure -> Bool
  (let [(procs (list (fr/Proc :pid 10 :ppid 1 :pgid 10) (fr/Proc :pid 11 :ppid 10 :pgid 10) (fr/Proc :pid 12 :ppid 11 :pgid 10) (fr/Proc :pid 13 :ppid 1 :pgid 13) (fr/Proc :pid 14 :ppid 13 :pgid 10)))
        (tree (t/closure procs (list 10) 14 20))
        (chain (list (fr/Proc :pid 20 :ppid 1 :pgid 20) (fr/Proc :pid 21 :ppid 20 :pgid 20) (fr/Proc :pid 22 :ppid 21 :pgid 20) (fr/Proc :pid 23 :ppid 22 :pgid 20) (fr/Proc :pid 24 :ppid 20 :pgid 20)))
        (above (t/closure chain (list 20 24) 23 20))
        (fromZero (t/closure procs (list 0 1) 14 20))
        (starts (list (pair 10 "Mon Jan  1 00:00:00 2026") (pair 11 "Tue Jan  2 00:00:00 2026")))]
    (do (assert (listContains? tree 12) "a grandchild is reached through its parent")
        (assert (not (listContains? tree 13)) "an unrelated process is not")
        (assert (not (listContains? tree 14)) "the shim's own pid is never a member")
        (assert (listEmpty? (filter (fn [(p Int64)] -> Bool (or (= p 20) (or (= p 21) (or (= p 22) (= p 23))))) above)) (str "a root above the shim never makes the shim, its parent chain or that root a member: " above))
        (assert (listContains? above 24) (str "a pinned pid off the chain stays a member: " above))
        (assert (listEmpty? fromZero) (str "pids 0 and 1 are never seeds: " fromZero))
        (assert (= (t/startOf starts 11) "Tue Jan  2 00:00:00 2026") "a pid maps to its recorded start time")
        (assert (= (t/startOf starts 99) "") "an unknown pid has no start time, so it is never signalled")
        true))


fn ! testUsage -> Bool
  (let [(none (shim! "x" (list "/bin/true")))
        (bare (fr/runGuarded (list (fr/nativeCli!) "timeout" "5") "." (shimEnv!) (fr/limits 40 64)))]
    (do (assert (= none.exitCode 125) (str "a malformed SECS is a usage error: " none.exitCode))
        (assert (= bare.exitCode 125) (str "no command is a usage error: " bare.exitCode))
        true))

fn ! runTests -> Bool
  (do (assert (testPassThrough) "exit codes, streams and a literal argv pass through")
      (assert (testSignalled) "a signalled child maps to 128+signal")
      (assert (testExpiry) "expiry exits 124 and takes the grandchild")
      (assert (testKillEscalation) "a TERM-ignoring tree is killed after the grace")
      (assert (testUsage) "usage errors exit 125")
      (assert (testRespawner) "a respawning tree is stopped by STOP then KILL rounds")
      (assert (testBrokenPipe) "a closed reader ends the shim with 141 and kills the tree")
      (assert (testStdin) "stdin is pumped to the child and closed at EOF")
      (assert (testSharedStdin) "a shim exits with its child when a sibling shim on the same stdin cleared O_NONBLOCK")
      (assert (testDrain) "output written just before exit is not lost")
      (assert (testDrainDirect) "draining a pipe after its writer exited delivers every byte")
      (assert (testSpawnFailure) "an unstartable command exits 127")
      (assert (testClosure) "tree closure and start-time pinning")
      true)
