(module asl-forms/evalOp :x [evalStep! warmNativeSelf!]
  :i [(asl-forms/kernel :a k) (asl-proc/coreProcess :a cp)])

fn outputLine id: Int64 status: String fields: String -> String
  (str "(:eval :id " (stringFromInt64 id) " :status :" status fields ")")

fn quoted s: String -> String
  (str "\"" (k/escapeAsnVal s) "\"")

fn ! cleanupError removed: (Result Unit String) -> (Option String)
  (mt removed ((err e) (some e)) ((ok _) (none)))

fn ! runRoot root: String -> String
  (let [(scriptDir (k/toolEnv! "SCRIPT_DIR"))]
    (if (stringEndsWith? scriptDir "/bin") (k/dirName scriptDir) root))

fn ! warmNativeSelf! root: String -> (Pair String Int64)
  (let [(workspace (runRoot root))
        (tmp (str workspace "/aslWarmTmp-" (stringFromInt64 (procSelf)) "_" (stringFromInt64 (nowNs))))
        (path (str tmp "/warm.asl"))
        (source "(module ws/warmTmp :x [main])\nfn ! main args: (List String) -> (Result Unit IoError)\n  (ok ())\n")
        (host (str workspace "/asl/host/out/asl-host"))
        (native (str workspace "/tools/nativeTest.asl"))]
    (mt (dirCreate tmp)
      ((err e) (pair (str "warm: cannot create tmp: " e) 1))
      ((ok _)
        (mt (fileWrite path source)
          ((err e)
            (let [(cleanup (cleanupError (pathRemove tmp)))]
              (mt cleanup
                ((some failure) (pair (str "warm: cleanup failed: " failure) 1))
                ((none) (pair (str "warm: cannot write: " e) 1)))))
          ((ok _)
            (let [(cmd (cp/withEnv (cp/withTimeout (cp/withCwd (cp/cmd host (list "run" native "prepare" path)) workspace) 1860000) "ASL_NATIVE_SELF_WAIT" "1"))
                  (built (cp/exec! cmd))
                  (removed (cleanupError (pathRemove tmp)))]
              (mt removed
                ((some failure) (pair (str "warm: cleanup failed: " failure) 1))
                ((none)
                  (mt built
                    ((err _) (pair "warm: ERR_PROCESS" 1))
                    ((ok out) (pair out.stdout out.exitCode)))))))))))

fn evalStep! root: String id: Int64 kw: (Map String String) args: (List String) -> (Pair String Int64)
  (let [(workspace (runRoot root))
        (code (k/kwOr kw "code" (optionOr (listHead args) "")))
        (timeout (optionOr (stringToInt64 (k/kwOr kw "timeoutMs" "5000")) 5000))
        (tmp (str workspace "/aslEvalTmp-" (stringFromInt64 (procSelf)) "_" (stringFromInt64 (nowNs))))
        (path (str tmp "/eval.asl"))
        (source (str "(module ws/evalTmp :x [main])\nfn ! main args: (List String) -> (Result Unit IoError)\n  (do (println " code ") (ok ()))\n"))
        (host (str workspace "/asl/host/out/asl-host"))
        (native (str workspace "/tools/nativeTest.asl"))]
    (cond
      ((stringEmpty? code) (pair (outputLine id "error" " :error :ERR_MISSING_ARG :message \"missing :code\"") 1))
      ((or (< timeout 1) (> timeout 120000)) (pair (outputLine id "error" " :error :ERR_BAD_TIMEOUT :message \"timeoutMs must be 1..120000\"") 1))
      (else
        (mt (dirCreate tmp)
          ((err e) (pair (outputLine id "error" (str " :error :ERR_TEMP :message " (quoted (str root " " e)))) 1))
          ((ok _)
            (mt (fileWrite path source)
              ((err e)
                (let [(cleanup (cleanupError (pathRemove tmp)))]
                  (mt cleanup
                    ((some failure) (pair (outputLine id "error" (str " :error :ERR_TEMP_CLEANUP :message " (quoted failure))) 1))
                    ((none) (pair (outputLine id "error" (str " :error :ERR_TEMP :message " (quoted e))) 1)))))
              ((ok _)
                (let [(prepareCmd (cp/withTimeout (cp/withCwd (cp/cmd host (list "run" native "prepare" path)) workspace) 120000))
                      (cache (k/kwOr kw "nativeTestCache" ""))
                      (clang (k/kwOr kw "nativeTestClang" ""))
                      (configured (if (stringEmpty? cache) prepareCmd (cp/withEnv prepareCmd "ASL_NATIVE_TEST_CACHE" cache)))
                      (configured (if (stringEmpty? clang) configured (cp/withEnv configured "CLANG" clang)))
                      (build (cp/exec! configured))
                      (removed (cleanupError (pathRemove tmp)))]
                  (mt removed
                    ((some failure) (pair (outputLine id "error" (str " :error :ERR_TEMP_CLEANUP :message " (quoted failure))) 1))
                    ((none)
                    (mt build
                      ((err _) (pair (outputLine id "error" " :error :ERR_PROCESS") 0))
                      ((ok prepared)
                        (if (!= prepared.exitCode 0)
                          (pair (outputLine id "error" (str " :error :ERR_EVAL :stderr " (quoted prepared.stderr) " :exit " (stringFromInt64 prepared.exitCode))) 0)
                          (let [(cmd (cp/withTimeout (cp/withCwd (cp/cmd (stringTrim prepared.stdout) (list)) workspace) timeout))
                                (ran (cp/exec! cmd))]
                            (mt ran
                              ((err failure) (mt failure
                                ((cp/timeout ms) (pair (outputLine id "error" (str " :error :ERR_TIMEOUT :timeoutMs " (stringFromInt64 ms))) 0))
                                ((cp/notFound _) (pair (outputLine id "error" " :error :ERR_PROCESS") 0))
                                ((cp/permissionDenied _) (pair (outputLine id "error" " :error :ERR_PROCESS") 0))
                                ((cp/executionFailed _ _) (pair (outputLine id "error" " :error :ERR_PROCESS") 0))))
                              ((ok out)
                                (if (= out.exitCode 0)
                                  (pair (outputLine id "ok" (str " :value " (quoted (stringTrim out.stdout)) " :stdout " (quoted out.stdout) " :exit " (stringFromInt64 out.exitCode))) 0)
                                  (pair (outputLine id "error" (str " :error :ERR_EVAL :stdout " (quoted out.stdout) " :stderr " (quoted out.stderr) " :exit " (stringFromInt64 out.exitCode))) 0))))))))))))))))))
