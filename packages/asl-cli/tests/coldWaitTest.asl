(module asl-cli/tests/coldWaitTest
  :x [runTests]
  :i [(asl/packages/asl-cli/src/system :a sys) (asl-tools/fleet/run :a fr)])

; (:m :ref COLDSTART-WAIT-LIVE-HOLDER :do "gate for asl/host/build.sh --cold (a pid with another recorded start time and a SIGKILLed real holder read as gone; a real holder whose progress dirs stay still stops itself with exit 75 and releases the lock): a fake holder of CACHE/build.lockd that is alive and keeps writing files under its out dir past the waiter's window does not make the waiter give up, and the waiter takes the lock once the holder ends; an alive holder that writes nothing makes it give up after the window with the lock left alone; a dead holder is taken over at once. Every holder is a fr/spawnSep child in its own group, killed and reaped at the end; the waiter runs as fr/runGuarded of build.sh --cold-probe, which takes the lock and exits without building")

fn ! removeAll! path: String -> (Result Unit String)
  (if (sys/isFile? path) (pathRemove path)
    (do (map (fn [(n String)] -> (Result Unit String) (removeAll! (str path "/" n))) (resultOr (dirList path) (list)))
        (pathRemove path)))

fn ! holderLockAt! cache: String pid: Int64 out: String start: String -> Bool
  (and (ok? (dirCreate (str cache "/build.lockd")))
       (ok? (fileWrite (str cache "/build.lockd/holder") (str pid "\n" out "\n" start "\n"))))

fn ! holderLock! cache: String pid: Int64 out: String -> Bool
  (holderLockAt! cache pid out "")

fn ! holderLines! cache: String t0: Int64 -> Int64
  (let [(n (listLength (filter (fn [(l String)] -> Bool (not (stringEmpty? l))) (stringLines (resultOr (fileReadString (str cache "/build.lockd/holder")) "")))))]
    (if (or (>= n 4) (> (/ (- (monotonicNs) t0) 1000000) 15000)) n (do (sleepMs 100) (holderLines! cache t0))))

; (:m :do "the mutant gate points COLD_WAIT_BUILD_SH at a mu/mutantRun! copy's build.sh, so the tree under test is never edited")
fn ! buildSh! -> String
  (optionOr (envGet "COLD_WAIT_BUILD_SH") "asl/host/build.sh")

fn ! probe! cache: String window: String -> fr/ProcOut
  (fr/runGuarded (list "/bin/sh" (buildSh!) "--cold-probe" cache window) "." (fr/childEnv (list)) (fr/limits 60 16))

fn ! stopHolder! pid: Int64 -> Bool
  (do (procKill (- 0 pid) "SIGKILL") (procWaitPid pid false) true)

fn ! fresh! tag: String -> String
  (let [(root (resultOr (realPath ".") "."))
        (cache (str root "/.asl/cache/coldWaitTest." (procSelf) "." tag))
        (_ (dirCreate (str root "/.asl/cache")))
        (_ (dirCreate cache))
        (_ (dirCreate (str cache "/out")))]
    cache)

fn ! testProgressingHolder -> Bool
  (let [(cache (fresh! "progress"))
        (out (str cache "/out"))]
    (match (fr/spawnSep (list "/bin/sh" "-c" "i=0; while [ $i -lt 7 ]; do : > \"$0/p$i\"; sleep 1; i=$((i+1)); done" out) "." (fr/childEnv (list)))
      ((err d) (do (assert false (str "holder spawn failed: " d.stderr)) false))
      ((ok h)
        (let [(_ (fdClose h.outFd))
              (_ (fdClose h.errFd))
              (locked (holderLock! cache h.pid out))
              (r (probe! cache "3"))
              (written (listLength (resultOr (dirList out) (list))))
              (_ (stopHolder! h.pid))
              (released (not (fileExists? (str cache "/build.lockd"))))
              (gone (removeAll! cache))]
          (do (assert locked "fixture: the holder's lock is written")
              (assert (stringContains? r.stdout "(:coldLock :got") (str "a waiter behind an alive holder that keeps writing past the window gets the lock once the holder ends: " r.exitCode " " r.stderr))
              (assert (> written 3) (str "the holder wrote files for longer than the 3 s window: " written))
              (assert released "the waiter releases the lock when it exits")
              (assert (ok? gone) "the fixture dir is removed")
              true)))))

fn ! testStalledHolder -> Bool
  (let [(cache (fresh! "stall"))]
    (match (fr/spawnSep (list "/bin/sh" "-c" "exec sleep 37") "." (fr/childEnv (list)))
      ((err d) (do (assert false (str "holder spawn failed: " d.stderr)) false))
      ((ok h)
        (let [(_ (fdClose h.outFd))
              (_ (fdClose h.errFd))
              (locked (holderLock! cache h.pid (str cache "/out")))
              (r (probe! cache "2"))
              (kept (resultOr (fileReadString (str cache "/build.lockd/holder")) ""))
              (_ (stopHolder! h.pid))
              (gone (removeAll! cache))]
          (do (assert locked "fixture: the holder's lock is written")
              (assert (= r.exitCode 1) (str "a waiter behind an alive holder that writes nothing gives up: " r.exitCode " " r.stdout))
              (assert (stringContains? r.stderr "made no progress") (str "and says why: " r.stderr))
              (assert (stringStartsWith? kept (str h.pid "\n")) (str "the live holder's lock is left alone: " kept))
              (assert (ok? gone) "the fixture dir is removed")
              true)))))

fn ! testDeadHolder -> Bool
  (let [(cache (fresh! "dead"))]
    (match (fr/spawnSep (list "/bin/sh" "-c" "true") "." (fr/childEnv (list)))
      ((err d) (do (assert false (str "holder spawn failed: " d.stderr)) false))
      ((ok h)
        (let [(_ (fdClose h.outFd))
              (_ (fdClose h.errFd))
              (_ (procWaitPid h.pid false))
              (locked (holderLock! cache h.pid (str cache "/out")))
              (r (probe! cache "20"))
              (released (not (fileExists? (str cache "/build.lockd"))))
              (gone (removeAll! cache))]
          (do (assert locked "fixture: the dead holder's lock is written")
              (assert (stringContains? r.stdout "(:coldLock :got") (str "a lock whose holder is gone is taken over: " r.exitCode " " r.stderr))
              (assert released "and released again on exit")
              (assert (ok? gone) "the fixture dir is removed")
              true)))))

fn ! runTests -> Bool
  (do (assert (testProgressingHolder) "an alive, progressing holder is waited on past the window")
      (assert (testStalledHolder) "an alive holder with no progress makes the waiter give up")
      (assert (testDeadHolder) "a gone holder is taken over")
      (assert (testBusyHolder) "an alive holder that only burns CPU is waited on past the window")
      (assert (testReusedPid) "a reused holder pid with another start time is taken over")
      (assert (testKilledHolder) "a SIGKILLed real holder's lock is taken over")
      (assert (testHolderStopsItself) "a holder with no progress stops itself and releases the lock")
      true)

fn ! testBusyHolder -> Bool
  (let [(cache (fresh! "busy"))]
    (match (fr/spawnSep (list "/bin/sh" "-c" "end=$(( $(date +%s) + 8 )); while :; do i=0; while [ $i -lt 20000 ]; do i=$((i+1)); done; [ $(date +%s) -ge $end ] && break; done") "." (fr/childEnv (list)))
      ((err d) (do (assert false (str "holder spawn failed: " d.stderr)) false))
      ((ok h)
        (let [(_ (fdClose h.outFd))
              (_ (fdClose h.errFd))
              (locked (holderLock! cache h.pid (str cache "/out")))
              (r (probe! cache "3"))
              (written (listLength (resultOr (dirList (str cache "/out")) (list))))
              (_ (stopHolder! h.pid))
              (gone (removeAll! cache))]
          (do (assert locked "fixture: the busy holder's lock is written")
              (assert (= written 0) (str "the busy holder writes no file: " written))
              (assert (stringContains? r.stdout "(:coldLock :got") (str "a waiter behind an alive holder whose CPU time grows past the window gets the lock once the holder ends: " r.exitCode " " r.stderr))
              (assert (ok? gone) "the fixture dir is removed")
              true)))))

fn ! testReusedPid -> Bool
  (let [(cache (fresh! "reused"))]
    (match (fr/spawnSep (list "/bin/sh" "-c" "exec sleep 38") "." (fr/childEnv (list)))
      ((err d) (do (assert false (str "stranger spawn failed: " d.stderr)) false))
      ((ok h)
        (let [(_ (fdClose h.outFd))
              (_ (fdClose h.errFd))
              (locked (holderLockAt! cache h.pid (str cache "/out") "Mon Jan  1 00:00:00 2001"))
              (r (probe! cache "20"))
              (_ (stopHolder! h.pid))
              (gone (removeAll! cache))]
          (do (assert locked "fixture: a lock whose recorded start time is not the live pid's")
              (assert (stringContains? r.stdout "(:coldLock :got") (str "a holder pid now held by a process with another start time reads as gone and is taken over: " r.exitCode " " r.stderr))
              (assert (ok? gone) "the fixture dir is removed")
              true)))))

; (:m :do "close the pipes only after the kill: the holder prints (:coldLock :holding) once it holds the lock, and on Darwin a closed read end fails that write and the holder exits, releasing the lock")
fn ! testKilledHolder -> Bool
  (let [(cache (fresh! "killed"))]
    (match (fr/spawnSep (list "/bin/sh" (buildSh!) "--cold-hold" cache "60") "." (fr/childEnv (list)))
      ((err d) (do (assert false (str "holder spawn failed: " d.stderr)) false))
      ((ok h)
        (let [(lines (holderLines! cache (monotonicNs)))
              (_ (stopHolder! h.pid))
              (_ (fdClose h.outFd))
              (_ (fdClose h.errFd))
              (left (fileExists? (str cache "/build.lockd")))
              (r (probe! cache "20"))
              (gone (removeAll! cache))]
          (do (assert (= lines 4) (str "the real holder records pid, out dir, start time and watcher pid: " lines))
              (assert left "a SIGKILLed holder leaves its lock dir behind")
              (assert (stringContains? r.stdout "(:coldLock :got") (str "a waiter takes the lock of a SIGKILLed holder over: " r.exitCode " " r.stderr))
              (assert (ok? gone) "the fixture dir is removed")
              true)))))

fn ! testHolderStopsItself -> Bool
  (let [(cache (fresh! "self"))
        (r (fr/runGuarded (list "/bin/sh" (buildSh!) "--cold-hold" cache "2") "." (fr/childEnv (list)) (fr/limits 60 16)))
        (released (not (fileExists? (str cache "/build.lockd"))))
        (gone (removeAll! cache))]
    (do (assert (stringContains? r.stdout "(:coldLock :holding") (str "the holder took the lock: " r.stdout))
        (assert (= r.exitCode 75) (str "a holder whose out dir makes no progress for the window stops itself with exit 75: " r.exitCode " " r.stderr))
        (assert (stringContains? r.stderr "made no progress") (str "and says why: " r.stderr))
        (assert released "and releases the lock")
        (assert (ok? gone) "the fixture dir is removed")
        true))
