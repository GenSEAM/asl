(module asl-cli/system
  :x [Context Captured context! childEnv! execv! run! runWith! runMerged! capture! captureWith! findCommand! onPath! executable? isFile? isDir? trimLeft stripTrailingNewlines hostAbsent say! sayErr! parentOf baseName]
  :i [])

(schema Context
  (:f root String)
  (:f scriptDir String)
  (:f argv0 String)
  (:f hostBin String))

(schema Captured
  (:f exitCode Int64)
  (:f stdout String)
  (:f stderr String))

(schema Relay
  (:f outOpen Bool)
  (:f errOpen Bool)
  (:f code (Option Int64))
  (:f out String)
  (:f errText String))

fn say! text: String -> Bool
  (do (println text) true)

fn sayErr! text: String -> Bool
  (do (eprintln text) true)

fn envOr! name: String -> String
  (optionOr (envGet name) "")

fn ! pathPresence! path: String -> (Result Bool String)
  (mt (fileStat path)
    ((ok _) (ok true))
    ((err e) (if (stringStartsWith? e "notFound") (ok false) (err e))))

fn ! realOrSelf! path: String -> (Result String String)
  (mt (realPath path)
    ((ok r) (ok r))
    ((err e) (if (stringStartsWith? e "notFound") (ok path) (err e))))

fn ! rootMarkers! dir: String -> (Result Bool String)
  (let [(gitR (pathPresence! (str dir "/.git")))]
    (mt gitR
      ((err e) (err e))
      ((ok hasGit) (ok (and hasGit (isFile? (str dir "/asl/grammar/rules.asn")))))))

fn ! walkToRoot! dir: String -> (Result (Option String) String)
  (if (stringEmpty? dir)
    (ok (none))
    (let [(markersR (rootMarkers! dir))]
      (mt markersR
        ((err e) (err e))
        ((ok hasMarkers)
          (if hasMarkers
            (ok (some dir))
            (let [(parent (parentOf dir))]
              (if (= parent dir) (ok (none)) (walkToRoot! parent))))))))

fn ! exeCandidates! -> (List String)
  (let [(fromSelf (mt (procExePath) ((ok p) (list p)) ((err _) (list))))
        (a (envOr! "ASL_CLI_ARGV0"))
        (fromArgv0 (if (stringEmpty? a) (list) (list a)))
        (fromPath (mt (onPath! "asl-host") ((some p) (list p)) ((none) (list))))]
    (listAppend fromSelf (listAppend fromArgv0 fromPath)))

fn ! tryCandidates! cands: (List String) lastErr: String -> (Result (Option String) String)
  (mt (listHead cands)
    ((none) (if (stringEmpty? lastErr) (ok (none)) (err lastErr)))
    ((some c)
      (let [(rest (optionOr (listTail cands) (list)))
            (realR (realOrSelf! c))]
        (mt realR
          ((err e) (tryCandidates! rest e))
          ((ok real)
            (let [(walkR (walkToRoot! (parentOf real)))]
              (mt walkR
                ((err e) (tryCandidates! rest e))
                ((ok found)
                  (mt found
                    ((some r) (ok (some r)))
                    ((none) (tryCandidates! rest lastErr)))))))))))

fn ! discoverRoot! -> (Result (Option String) String)
  (let [(cwdR (realOrSelf! "."))]
    (mt cwdR
      ((err e) (err e))
      ((ok cwd)
        (let [(byCwdR (walkToRoot! cwd))]
          (mt byCwdR
            ((err e) (err e))
            ((ok found)
              (mt found
                ((some r) (ok (some r)))
                ((none) (tryCandidates! (exeCandidates!) "")))))))))

fn ! giveUpMessage! -> String
  (let [(cwd (resultOr (realPath ".") "."))
        (cands (exeCandidates!))
        (exeNote (if (listEmpty? cands)
                   "no exe candidate was available (checked the running exe, ASL_CLI_ARGV0, PATH)"
                   (str "exe candidates [" (stringJoin cands ", ") "] (from the running exe, ASL_CLI_ARGV0, PATH) climbed to no workspace root either")))]
    (str "ASL_CLI_ROOT is unset and discovery failed: cwd walk from " cwd
         " found no directory holding .git and asl/grammar/rules.asn; " exeNote
         "; run the asl command through bin/asl"))

fn ! context! -> (Result Context String)
  (let [(envRoot (envOr! "ASL_CLI_ROOT"))]
    (if (not (stringEmpty? envRoot))
      (ok (contextAt! envRoot))
      (let [(discoveredR (discoverRoot!))]
        (mt discoveredR
          ((err e) (err (str "ASL_CLI_ROOT is unset and discovery failed: " e "; run the asl command through bin/asl")))
          ((ok found)
            (mt found
              ((none) (err (giveUpMessage!)))
              ((some root) (ok (contextAt! root)))))))))

fn ! contextAt! root: String -> Context
  (Context :root root
           :scriptDir (let [(d (envOr! "ASL_CLI_SCRIPT_DIR"))] (if (stringEmpty? d) (str root "/bin") d))
           :argv0 (let [(a (envOr! "ASL_CLI_ARGV0"))] (if (stringEmpty? a) (str root "/bin/asl") a))
           :hostBin (let [(h (envOr! "ASL_CLI_HOST_BIN"))] (if (stringEmpty? h) (str root "/asl/host/out/asl-host") h)))

fn envName entry: String -> String
  (mt (stringIndexOf entry "=") ((some i) (optionOr (stringSlice entry 0 i) entry)) ((none) entry))

fn childEnv! extra: (List String) -> (List String)
  (let [(dropHost (= (envOr! "ASL_CLI_HOST_UNSET") "1"))
        (names (map envName extra))
        (kept (filter (fn [(e String)] -> Bool
                        (let [(n (envName e))]
                          (not (or (stringStartsWith? n "ASL_CLI_") (or (and dropHost (= n "ASL_HOST")) (listContains? names n))))))
                      (envList)))]
    (listAppend kept extra))

fn ! execv! argv: (List String) extra: (List String) -> Int64
  (mt (procExecv argv (some (childEnv! extra)))
    ((ok _) 0)
    ((err e)
      (do (sayErr! (str "asl: cannot exec " (optionOr (listHead argv) "") ": " e))
          (if (= e "notFound") 127 126))))

fn ! readSide! fd: Int64 -> (Result (Option String) String)
  (mt (fdRead fd 65536)
    ((err e) (err (str "read fd " (stringFromInt64 fd) ": " e)))
    ((ok chunk)
      (if (> (stringLength chunk) 0)
        (ok (some chunk))
        (mt (fdClose fd) ((err e) (err (str "close fd " (stringFromInt64 fd) ": " e))) ((ok _) (ok (none)))))))

fn readyFd? ready: (List (Pair Int64 Int64)) fd: Int64 -> Bool
  (listAny? (fn [(p (Pair Int64 Int64))] -> Bool (= (pairFirst p) fd)) ready)

fn exitOf exited: (List (Pair Int64 Int64)) pid: Int64 -> (Option Int64)
  (fold (fn [(acc (Option Int64)) (p (Pair Int64 Int64))] -> (Option Int64) (if (= (pairFirst p) pid) (some (pairSecond p)) acc)) (none) exited)

fn ! emit! chunk: String toErr: Bool mode: Int64 -> (Result Unit String)
  (cond
    ((or (= mode 0) (stringEmpty? chunk)) (ok ()))
    ((and toErr (= mode 1)) (mt (fdWrite 2 chunk) ((err e) (err (str "write stderr: " e))) ((ok n) (if (< n (stringLength chunk)) (emit! (optionOr (stringSlice chunk n (stringLength chunk)) "") true 1) (ok ())))))
    (else (do (print chunk) (ok ()))))

fn ! pump! sp: SpawnedProc st: Relay mode: Int64 -> (Result Relay String)
  (if (and (some? st.code) (and (not st.outOpen) (not st.errOpen)))
    (ok st)
    (let [(fds (listAppend (if st.outOpen (list (pair sp.stdout 1)) (list)) (if st.errOpen (list (pair sp.stderr 1)) (list))))
          (pids (if (none? st.code) (list sp.pid) (list)))]
      (mt (procPoll fds pids -1)
        ((err e) (err (str "procPoll: " e)))
        ((ok ready)
          (let [(outR (if (and st.outOpen (readyFd? (pairFirst ready) sp.stdout)) (readSide! sp.stdout) (ok (some ""))))
                (errR (if (and st.errOpen (readyFd? (pairFirst ready) sp.stderr)) (readSide! sp.stderr) (ok (some ""))))
                (code (if (some? st.code) st.code (exitOf (pairSecond ready) sp.pid)))]
            (mt outR
              ((err e) (err e))
              ((ok o)
                (mt errR
                  ((err e) (err e))
                  ((ok x)
                    (mt (emit! (optionOr o "") false mode)
                      ((err e) (err e))
                      ((ok _)
                        (mt (emit! (optionOr x "") true mode)
                          ((err e) (err e))
                          ((ok _)
                            (pump! sp (Relay :outOpen (and st.outOpen (some? o)) :errOpen (and st.errOpen (some? x)) :code code
                                             :out (if (> mode 0) "" (str st.out (optionOr o ""))) :errText (if (> mode 0) "" (str st.errText (optionOr x ""))))
                                   mode))))))))))))))

fn ! spawn! argv: (List String) cwd: (Option String) mode: Int64 extra: (List String) -> (Result Relay String)
  (mt (procSpawnv argv cwd (some (childEnv! extra)))
    ((err e) (err (str (optionOr (listHead argv) "") ": " e)))
    ((ok sp)
      (mt (fdClose sp.stdin)
        ((err e) (err (str "close stdin: " e)))
        ((ok _) (pump! sp (Relay :outOpen true :errOpen true :code (none) :out "" :errText "") mode)))))

fn ! run! argv: (List String) -> Int64
  (runWith! argv (list))

fn ! runWith! argv: (List String) extra: (List String) -> Int64
  (mt (spawn! argv (none) 1 extra)
    ((err e) (do (sayErr! (str "asl: cannot run " e)) 127))
    ((ok st) (optionOr st.code 1)))

fn ! runMerged! argv: (List String) -> Int64
  (mt (spawn! argv (none) 2 (list))
    ((err e) (do (sayErr! (str "asl: cannot run " e)) 127))
    ((ok st) (optionOr st.code 1)))

fn ! capture! argv: (List String) cwd: (Option String) -> (Result Captured String)
  (captureWith! argv cwd (list))

fn ! captureWith! argv: (List String) cwd: (Option String) extra: (List String) -> (Result Captured String)
  (mt (spawn! argv cwd 0 extra)
    ((err e) (err e))
    ((ok st) (ok (Captured :exitCode (optionOr st.code 1) :stdout st.out :stderr st.errText))))

fn ! isFile? path: String -> Bool
  (mt (fileStat path) ((ok st) st.isFile) ((err _) false))

fn ! isDir? path: String -> Bool
  (mt (fileStat path) ((ok st) st.isDir) ((err _) false))

fn ! executable? path: String -> Bool
  (mt (fileStat path) ((ok st) (!= (& st.mode 73) 0)) ((err _) false))

fn onPathLoop! name: String dirs: (List String) -> (Option String)
  (mt (listHead dirs)
    ((none) (none))
    ((some d)
      (let [(p (str (if (stringEmpty? d) "." d) "/" name))]
        (if (and (isFile? p) (executable? p)) (some p) (onPathLoop! name (optionOr (listTail dirs) (list)))))))

fn onPath! name: String -> (Option String)
  (onPathLoop! name (stringSplit (envOr! "PATH") ":"))

fn findCommand! ctx: Context name: String -> (Option String)
  (cond
    ((executable? (str ctx.scriptDir "/" name)) (some (str ctx.scriptDir "/" name)))
    ((executable? (str ctx.root "/bin/" name)) (some (str ctx.root "/bin/" name)))
    (else (onPath! name)))

fn spaceByte? b: Int64 -> Bool
  (or (= b 32) (and (>= b 9) (<= b 13)))

fn leadingSpace b: Bytes i: Int64 n: Int64 -> Int64
  (if (and (< i n) (spaceByte? (bytesGet b i))) (leadingSpace b (+ i 1) n) i)

fn trimLeft s: String -> String
  (let [(b (stringToBytes s))]
    (optionOr (stringSlice s (leadingSpace b 0 (bytesLength b)) (stringLength s)) s))

fn stripTrailingNewlines s: String -> String
  (if (stringEndsWith? s "\n") (stripTrailingNewlines (optionOr (stringSlice s 0 (- (stringLength s) 1)) "")) s)

fn hostAbsent cmd: String -> String
  (str "(:" cmd " :status :failed :error ERR_HOST_ABSENT :message \"asl " cmd " needs the stage-0 host at asl/host/out/asl-host; build it with sh asl/host/build.sh or set ASL_HOST\")")

fn parentOf path: String -> String
  (let [(parts (stringSplit path "/"))]
    (stringJoin (listTake parts (- (listLength parts) 1)) "/"))

fn baseName path: String -> String
  (optionOr (listLast (stringSplit path "/")) path)
