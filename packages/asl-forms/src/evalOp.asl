(module asl-forms/evalOp :x [evalStep! nativeEntry!]
  :i [(asl-forms/kernel :a k) (asl-proc/coreProcess :a cp) (tools/nativeTest :a nt)])

fn outputLine id: Int64 status: String fields: String -> String
  (str "(:eval :id " (stringFromInt64 id) " :status :" status fields ")")

fn quoted s: String -> String
  (str "\"" (k/escapeAsnVal s) "\"")

fn ! runRoot root: String -> String
  (let [(scriptDir (k/toolEnv! "SCRIPT_DIR"))]
    (if (stringEndsWith? scriptDir "/bin") (k/dirName scriptDir) root))

fn evalSource code: String -> String
  (str "(module nativeEval :x [main] :i [])\n\nfn ! main -> (Result Int64 String)\n  (do (println " code ")\n      (ok 0))\n")

fn ! cacheDir! workspace: String kw: (Map String String) -> String
  (let [(given (k/kwOr kw "nativeTestCache" ""))
        (env (optionOr (envGet "ASL_NATIVE_TEST_CACHE") ""))]
    (cond
      ((not (stringEmpty? given)) given)
      ((not (stringEmpty? env)) env)
      (else (str workspace "/.asl/cache/nativeTest"))))

fn ! runBinary! id: Int64 bin: String workspace: String timeout: Int64 -> (Pair String Int64)
  (mt (cp/exec! (cp/withTimeout (cp/withCwd (cp/cmd bin (list)) workspace) timeout))
    ((err failure) (mt failure
      ((cp/timeout ms) (pair (outputLine id "error" (str " :error :ERR_TIMEOUT :timeoutMs " (stringFromInt64 ms))) 0))
      (_ (pair (outputLine id "error" " :error :ERR_PROCESS") 1))))
    ((ok out)
      (if (= out.exitCode 0)
        (pair (outputLine id "ok" (str " :value " (quoted (stringTrim out.stdout)) " :stdout " (quoted out.stdout) " :exit 0")) 0)
        (pair (outputLine id "error" (str " :error :ERR_EVAL :stdout " (quoted out.stdout) " :stderr " (quoted out.stderr) " :exit " (stringFromInt64 out.exitCode))) 0))))

fn ! written! path: String src: String -> String
  (mt (dirCreate (k/dirName path))
    ((err e) e)
    ((ok _) (mt (fileWrite path src) ((err e) e) ((ok _) ""))))

fn absolute workspace: String path: String -> String
  (if (stringStartsWith? path "/") path (k/joinPath workspace path))

fn sourcePath workspace: String kind: String src: String -> String
  (str workspace "/.asl/cache/nativeTest/" kind "/" (nt/slotKey kind src) ".asl")

fn ! built! workspace: String cDir: String path: String -> (Result String String)
  (let [(b (nt/prepareIn cDir path (nt/fingerprint) "eval"))]
    (mt b.binary ((some bin) (ok (absolute workspace bin))) ((none) (err b.reason))))

fn ! compileAndRun! id: Int64 workspace: String cDir: String code: String timeout: Int64 -> (Pair String Int64)
  (let [(src (evalSource code))
        (path (sourcePath workspace "evals" src))
        (made (written! path src))]
    (if (not (stringEmpty? made))
      (pair (outputLine id "error" (str " :error :ERR_TEMP :message " (quoted (str path " " made)))) 1)
      (mt (built! workspace cDir path)
        ((err reason) (pair (outputLine id "error" (str " :error :ERR_EVAL :stderr " (quoted reason) " :exit 1")) 1))
        ((ok bin) (runBinary! id bin workspace timeout)))))

fn ! evalStep! root: String id: Int64 kw: (Map String String) args: (List String) -> (Pair String Int64)
  (let [(workspace (runRoot root))
        (code (k/kwOr kw "code" (optionOr (listHead args) "")))
        (timeout (optionOr (stringToInt64 (k/kwOr kw "timeoutMs" "5000")) 5000))]
    (cond
      ((stringEmpty? code) (pair (outputLine id "error" " :error :ERR_MISSING_ARG :message \"missing :code\"") 1))
      ((or (< timeout 1) (> timeout 120000)) (pair (outputLine id "error" " :error :ERR_BAD_TIMEOUT :message \"timeoutMs must be 1..120000\"") 1))
      (else (compileAndRun! id workspace (cacheDir! workspace kw) code timeout))))

fn entrySource importPath: String intMain: Bool -> String
  (str "(module nativeEval :x [main] :i [(" importPath " :a entry)])\n\nfn ! main args: (List String) -> (Result Int64 String)\n  "
       (if intMain "(ok (entry/main args))" "(entry/main args)") "\n")

fn ! nativeEntry! workspace: String importPath: String intMain: Bool -> (Result String String)
  (let [(src (entrySource importPath intMain))
        (path (sourcePath workspace "runs" src))
        (made (written! path src))]
    (if (not (stringEmpty? made))
      (err (str "cannot write " path ": " made))
      (mt (built! workspace (cacheDir! workspace (mapEmpty)) path)
        ((ok bin) (ok bin))
        ((err reason) (err (str importPath " does not build natively: " reason))))))
