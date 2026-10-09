(module asl-cli/tests/asl1CacheLockTest
  :x [runTests main]
  :i [(asl-cli/asl1Cache :a cache) (asl-cli/system :a sys)])

fn ! tempRoot -> String
  (str "/tmp/asl1CacheLockTest_" (stringFromInt64 (monotonicNs)))

fn ! setup path: String -> Bool
  (ok? (dirCreate path))

fn ! resultPath? result: (Result String String) expected: String -> Bool
  (mt result
    ((err _) false)
    ((ok actual) (= actual expected)))

fn ! check condition: Bool message: String -> Bool
  (do (assert condition message) condition)

fn ! testOneBuildAndReuse -> Bool
  (let [(root (tempRoot))
        (dirMade (setup root))
        (lock (str root "/build.lock"))
        (artifact (str root "/artifact"))
        (buildCount (str root "/build-count"))
        (ready (fn [] -> Bool (fileExists? artifact)))
        (builder (fn [] -> (Result String String)
          (mt (fileCreateExclusive buildCount "built")
            ((err e) (err e))
            ((ok _) (mt (fileWrite artifact "the-native-artifact")
              ((err e) (err e))
              ((ok _) (ok artifact)))))))
        (first (cache/singleFlight! lock artifact 100 ready builder))
        (second (cache/singleFlight! lock artifact 100 ready builder))]
    (and dirMade
      (and (check (resultPath? first artifact) "first caller receives built artifact")
        (and (check (resultPath? second artifact) "later caller reuses the same artifact")
          (and (check (stringContains? (resultOr (fileReadString buildCount) "") "built") "injected builder ran exactly once")
            (and (check (stringContains? (resultOr (fileReadString artifact) "") "native-artifact") "artifact content is returned from the cache")
              (check (not (fileExists? lock)) "successful owner removes its exclusive lock file")))))))

fn ! workerBuild! artifact: String buildCount: String -> (Result String String)
  (do
    (sleepMs 250)
    (mt (fileCreateExclusive buildCount "built")
      ((err e) (err e))
      ((ok _) (mt (fileWrite artifact "concurrent-artifact")
        ((err e) (err e))
        ((ok _) (ok artifact))))))

fn ! workerMain! root: String -> (Result Int64 String)
  (let [(lock (str root "/build.lock"))
        (artifact (str root "/artifact"))
        (buildCount (str root "/build-count"))
        (ready (fn [] -> Bool (fileExists? artifact)))
        (builder (fn [] -> (Result String String) (workerBuild! artifact buildCount)))]
    (mt (cache/singleFlight! lock artifact 10000 ready builder)
      ((err e) (err e))
      ((ok sharedArtifact)
        (mt (fileWrite (str root "/child-result") sharedArtifact)
          ((err e) (err e))
          ((ok _) (ok 0))))))

fn ! main -> (Result Int64 String)
  (mt (envGet "ASL1_LOCK_WORKER_ROOT")
    ((some root) (workerMain! root))
    ((none) (err "missing ASL1_LOCK_WORKER_ROOT")))

fn ! testLiveOwnerMetadataIsRespected -> Bool
  (let [(root (tempRoot))
        (lock (str root "/build.lock"))
        (artifact (str root "/artifact"))
        (ready (fn [] -> Bool (fileExists? artifact)))
        (builder (fn [] -> (Result String String) (ok artifact)))]
    (and (setup root)
      (and (ok? (fileWrite lock (str (stringFromInt64 (procSelf)) "\n" (stringFromInt64 (nowNs)) "\n")))
        (check (mt (cache/singleFlight! lock artifact 10 ready builder)
          ((err e) (stringStartsWith? e "ERR_ASL1_CACHE_LOCK_TIMEOUT:"))
          ((ok _) false)) "cache honors live owner metadata without an OS lock"))))

fn ! spawnWorker! host: String root: String -> (Result Int64 String)
  (let [(testPath (str "asl/packages/asl-cli/tests/asl1CacheLockTest.asl"))
        (argv (list "/usr/bin/env" (str "ASL1_LOCK_WORKER_ROOT=" root) host "run" testPath))]
    (mt (procSpawnv argv (none) (none))
      ((err e) (err e))
      ((ok child)
        (mt (fdClose child.stdout)
          ((err e) (err e))
          ((ok _)
            (mt (fdClose child.stderr)
              ((err e) (err e))
                    ((ok _) (ok child.pid))))))))

fn ! waitWorker! pid: Int64 -> Bool
  (mt (procWaitPid pid false)
    ((err _) false)
    ((ok status) (mt status ((none) false) ((some code) (= code 0)))))

fn ! testConcurrentCallersBuildOnce -> Bool
  (let [(root (tempRoot))
        (made (setup root))]
    (if (not made) false
      (mt (sys/context!)
        ((err _) false)
        ((ok ctx)
          (mt (spawnWorker! ctx.hostBin root)
            ((err _) false)
            ((ok childPid)
              (let [(artifactPath (str root "/artifact"))
                    (buildCountPath (str root "/build-count"))
                    (ready (fn [] -> Bool (fileExists? artifactPath)))
                    (builder (fn [] -> (Result String String) (workerBuild! artifactPath buildCountPath)))
                    (parentResult (cache/singleFlight! (str root "/build.lock") artifactPath 10000 ready builder))
                    (childDone (waitWorker! childPid))
                    (childResult (fileReadString (str root "/child-result")))
                    (artifact (resultOr (fileReadString artifactPath) ""))
                    (buildCount (resultOr (fileReadString buildCountPath) ""))]
                (and (check (resultPath? parentResult artifactPath) "first caller receives the shared artifact")
                  (and (check childDone "second concurrent caller completes successfully")
                    (and (check (resultPath? childResult artifactPath) "second caller receives the same artifact path")
                      (and (check (stringContains? artifact "concurrent-artifact") "both callers observe the built artifact")
                        (check (stringContains? buildCount "built") "the injected concurrent build step ran exactly once"))))))))))))

fn ! testDeadOwnerTakenOver -> Bool
  (let [(root (tempRoot))
        (dirMade (setup root))
        (lock (str root "/build.lock"))
        (artifact (str root "/artifact"))
        (observed (str root "/owner-during-build"))
        (ready (fn [] -> Bool (fileExists? artifact)))
        (builder (fn [] -> (Result String String)
          (mt (fileReadString lock)
            ((err e) (err e))
            ((ok metadata) (mt (fileWrite observed metadata)
              ((err e) (err e))
              ((ok _) (mt (fileWrite artifact "rebuilt") ((err e) (err e)) ((ok _) (ok artifact))))))))) ]
    (if (not dirMade) false
      (mt (fileWrite lock "2147483647\n1\n")
        ((err _) false)
        ((ok _)
          (let [(alive (procAlive? 2147483647))
                (result (cache/singleFlight! lock artifact 100 ready builder))
                (metadata (resultOr (fileReadString observed) ""))]
            (and (check (mt alive ((err _) false) ((ok isAlive) (not isAlive))) "fixture PID is dead")
              (and (check (resultPath? result artifact) "stale owner lock is taken over")
                (and (check (stringStartsWith? metadata (stringFromInt64 (procSelf))) "takeover records the new owner PID")
                  (check (not (fileExists? lock)) "new owner removes its lock file after the build")))))))))

fn ! testLiveOwnerTimesOut -> Bool
  (let [(root (tempRoot))
        (dirMade (setup root))
        (lock (str root "/build.lock"))
        (artifact (str root "/artifact"))
        (ready (fn [] -> Bool (fileExists? artifact)))
        (builder (fn [] -> (Result String String) (ok artifact)))]
    (if (not dirMade) false
      (mt (fileWrite lock (str (stringFromInt64 (procSelf)) "\n" (stringFromInt64 (nowNs)) "\n"))
        ((err _) false)
        ((ok _)
          (let [(result (cache/singleFlight! lock artifact 10 ready builder))]
            (and (check (mt result ((err e) (stringStartsWith? e "ERR_ASL1_CACHE_LOCK_TIMEOUT:")) ((ok _) false)) "unlocked file owned by a live PID is not taken over")
              (and (check (not (fileExists? artifact)) "live owner prevents the build step")
                (check (stringStartsWith? (resultOr (fileReadString lock) "") (stringFromInt64 (procSelf))) "live owner's metadata is preserved"))))))))

fn ! testNegativeTimeoutIsBounded -> Bool
  (let [(root (tempRoot))
        (dirMade (setup root))
        (lock (str root "/build.lock"))
        (artifact (str root "/artifact"))
        (startedAt (monotonicNs))
        (ready (fn [] -> Bool (>= (- (monotonicNs) startedAt) 50000000)))
        (builder (fn [] -> (Result String String) (ok artifact)))]
    (if (not dirMade) false
      (mt (fileWrite lock (str (stringFromInt64 (procSelf)) "\n" (stringFromInt64 (nowNs)) "\n"))
        ((err _) false)
        ((ok _)
          (check (mt (cache/singleFlight! lock artifact -1 ready builder)
            ((err e) (stringStartsWith? e "ERR_ASL1_CACHE_LOCK_TIMEOUT:"))
            ((ok _) false)) "negative timeout does not wait indefinitely")))))

fn ! testInvalidOwnerMetadataAndLivenessPropagate -> Bool
  (let [(root (tempRoot))
        (dirMade (setup root))
        (readLock (str root "/missing-pid.lock"))
        (malformedLock (str root "/malformed.lock"))
        (invalidPidLock (str root "/invalid-pid.lock"))
        (ready (fn [] -> Bool false))
        (builder (fn [] -> (Result String String) (ok "unexpected")))]
    (if (not dirMade) false
      (and (ok? (dirCreate readLock))
        (and (ok? (fileWrite malformedLock "not-a-pid\n"))
          (and (ok? (fileWrite invalidPidLock "-1\n"))
            (let [(readResult (cache/singleFlight! readLock "unused" 100 ready builder))
                  (malformedResult (cache/singleFlight! malformedLock "unused" 100 ready builder))
                  (invalidPidResult (cache/singleFlight! invalidPidLock "unused" 100 ready builder))]
              (and (check (mt readResult ((err e) (stringStartsWith? e "ERR_ASL1_CACHE_OWNER_METADATA:")) ((ok _) false)) "missing lock owner PID is rejected")
                (and (check (mt malformedResult ((err e) (stringStartsWith? e "ERR_ASL1_CACHE_OWNER_METADATA:")) ((ok _) false)) "malformed lock owner metadata propagates")
                  (check (mt invalidPidResult ((err e) (stringStartsWith? e "ERR_ASL1_CACHE_OWNER_LIVENESS:")) ((ok _) false)) "lock owner liveness errors propagate")))))))))

fn ! runTests -> Bool
  (and (testInvalidOwnerMetadataAndLivenessPropagate) (and (testNegativeTimeoutIsBounded) (and (testLiveOwnerMetadataIsRespected) (and (testLiveOwnerTimesOut) (and (testOneBuildAndReuse) (and (testConcurrentCallersBuildOnce) (testDeadOwnerTakenOver)))))))
