(module asl-cli/nativeRefresh
  :x [refresh! guard! under? rebuildAllowed? refusalReceipt suspect? staleFail]
  :i [(asl/packages/asl-cli/src/nativeCli :a nc)])

; (:m :ref BIN-ASL-ASL :do "the slow half of bin/asl, moved out of the shell: a native CLI whose deps list names a source that is missing or newer than the head is suspect and never runs before this refresh has taken the shared build lock (lock/pid, created exclusively, dead holders cleared), verified the binary byte for byte or rebuilt it through the builder closure, rewritten the head and checked the sources did not move again; a failure is one ERR_NATIVE_STALE line on stdout and exit 2, progress goes to stderr")
fn ! mtime path: String -> Int64
  (match (fileStat path) ((ok st) st.mtimeNs) ((err _) 0))

fn ! depSuspect? root: String stamp: Int64 deps: (List String) n: Int64 -> Bool
  (match (listHead deps)
    ((none) (= n 0))
    ((some p) (cond
      ((stringEmpty? p) (depSuspect? root stamp (optionOr (listTail deps) (list)) n))
      ((not (fileExists? (str root "/" p))) true)
      ((> (mtime (str root "/" p)) stamp) true)
      (else (depSuspect? root stamp (optionOr (listTail deps) (list)) (+ n 1))))))

fn ! suspect? root: String dir: String stampPath: String -> Bool
  (match (fileReadString (str dir "/deps"))
    ((err _) true)
    ((ok text) (depSuspect? root (mtime stampPath) (stringLines text) 0)))

fn ! staleFail cache: String dir: String why: String -> Int64
  (do (println (str "(:asl :status :failed :error ERR_NATIVE_STALE :message \"the native CLI " dir " predates its sources and " why "; see " cache "/build.log\")"))
      2)

fn ! headDir cache: String root: String -> String
  (stringTrim (resultOr (fileReadString (nc/headPath cache root)) ""))

fn ! envInt name: String fallback: Int64 -> Int64
  (optionOr (stringToInt64 (optionOr (envGet name) "")) fallback)

fn ! heldPid lock: String -> String
  (stringTrim (resultOr (fileReadString (str lock "/pid")) ""))

fn ! sinceS beganNs: Int64 -> Int64
  (/ (- (monotonicNs) beganNs) 1000000000)

; (:m :ref BIN-ASL-ASL :do "lock/pid is created exclusively; an empty pid file counts a try and is dropped after five, a dead holder is dropped at once")
fn ! acquire! lock: String beganNs: Int64 deadlineNs: Int64 nextReportNs: Int64 tries: Int64 waitS: Int64 reportS: Int64 -> (Result Int64 String)
  (if (ok? (fileCreateExclusive (str lock "/pid") (str (stringFromInt64 (procSelf)) "\n")))
    (ok (sinceS beganNs))
    (let [held (heldPid lock)
          heldN (optionOr (stringToInt64 held) 0)
          emptyHeld (stringEmpty? held)
          tries2 (if emptyHeld (+ tries 1) tries)
          _drop (if (or (and emptyHeld (> tries2 5)) (and (not emptyHeld) (not (nc/alive? heldN)))) (ok? (pathRemove (str lock "/pid"))) false)]
      (if (>= (monotonicNs) deadlineNs)
        (err (str "the build lock stayed held by pid " (if emptyHeld "unknown" held) " for " (stringFromInt64 (sinceS beganNs)) "s, past the budget ASL_NATIVE_BUILD_WAIT=" (stringFromInt64 waitS) "s"))
        (let [report (>= (monotonicNs) nextReportNs)
              _say (if report (do (eprintln (str "(:wait :nativeCli :lockPid " (if emptyHeld "unknown" held) " :elapsedS " (stringFromInt64 (sinceS beganNs)) " :budgetS " (stringFromInt64 waitS) ")")) true) false)
              _sleep (sleepMs 1000)
              _mk (dirCreate lock)]
          (acquire! lock beganNs deadlineNs (if report (+ (monotonicNs) (* reportS 1000000000)) nextReportNs) tries2 waitS reportS)))))

fn ! installHead! cache: String root: String dir: String -> Bool
  (let [head (nc/headPath cache root)
        part (str head ".part." (stringFromInt64 (procSelf)))]
    (and (ok? (fileWrite part (str dir "\n"))) (ok? (pathRename part head))))

; (:m :ref WT-MAIN-HOME-REBUILD :do "a rebuild starts only in the caller's own tree: ASL_NATIVE_CLI_CACHE names the pin store explicitly, or the tree lives under the caller's HOME (so the pin path resolves under it), or the caller's cwd is inside the tree; otherwise (bin/asl run with HOME overridden against another user's or another agent's worktree) the answer is one (:err :code rebuildRefused :tree :home) receipt and exit 2, nothing is built")
fn under? path: String dir: String -> Bool
  (and (not (stringEmpty? dir)) (or (= path dir) (stringStartsWith? path (str dir "/"))))

fn rebuildAllowed? root: String home: String cwd: String explicitCache: Bool -> Bool
  (or explicitCache (or (under? root home) (under? cwd root)))

fn refusalReceipt root: String home: String -> String
  (str "(:err :code rebuildRefused :tree \"" (stringReplace root "\"" "\\\"") "\" :home \"" (stringReplace home "\"" "\\\"") "\")")

fn ! guard! root: String cache: String -> Int64
  (let [(rootReal (resultOr (realPath root) root))
        (home (optionOr (envGet "HOME") ""))
        (homeReal (if (stringEmpty? home) "" (resultOr (realPath home) home)))
        (cwdReal (resultOr (realPath ".") "."))
        (explicit (not (stringEmpty? (optionOr (envGet "ASL_NATIVE_CLI_CACHE") ""))))]
    (if (rebuildAllowed? rootReal homeReal cwdReal explicit)
      0
      (do (println (refusalReceipt rootReal homeReal)) 2)))

; (:m :ref BIN-ASL-ASL :do "build is the in-process verify-or-rebuild of the builder (exit code); the caller holds no lock")
fn ! refreshBody! root: String cache: String cmd: (List String) build: (fn [String String] -> Int64) -> Int64
  (if (or (nc/pinned? root (headDir cache root) (nc/headPath cache root) cmd) (nc/relayPinned? root (headDir cache root) (nc/headPath cache root) cmd))
    (do (eprintln "asl: native CLI pinned: kept for this command") 0)
  (let [head (nc/headPath cache root)
        dir0 (headDir cache root)
        waitS (envInt "ASL_NATIVE_BUILD_WAIT" 3600)
        reportS (envInt "ASL_NATIVE_WAIT_REPORT_S" 30)
        beganNs (monotonicNs)
        lock (str cache "/lock")
        _say (eprintln (str "asl: native CLI " dir0 " predates its sources; verifying or rebuilding it (waiting up to ASL_NATIVE_BUILD_WAIT=" (stringFromInt64 waitS) "s)"))
        made (dirCreate lock)]
    (if (not (ok? made))
      (staleFail cache dir0 (str "cannot create " lock))
      (match (acquire! lock beganNs (+ beganNs (* waitS 1000000000)) (+ beganNs (* reportS 1000000000)) 0 waitS reportS)
        ((err why) (staleFail cache dir0 why))
        ((ok waited)
          (let [_got (if (> waited 0) (do (eprintln (str "(:wait :nativeCli :ms " (stringFromInt64 (* waited 1000)) " :lock got)")) true) false)
                dir1 (headDir cache root)]
            (if (and (fileExists? (str dir1 "/bin")) (not (suspect? root dir1 head)))
              (do (pathRemove lock) 0)
              (let [rc (build root cache)]
                (if (!= rc 0)
                  (do (pathRemove lock) (staleFail cache dir1 (str "its rebuild exited " (stringFromInt64 rc))))
                  (let [dir2 (headDir cache root)]
                    (cond
                      ((not (fileExists? (str dir2 "/bin"))) (do (pathRemove lock) (staleFail cache dir2 (str "the rebuild left no head at " head))))
                      ((not (installHead! cache root dir2)) (do (pathRemove lock) (staleFail cache dir2 (str "cannot rewrite " head))))
                      ((suspect? root dir2 head) (do (pathRemove lock) (staleFail cache dir2 "its sources moved again during the rebuild")))
                      (else (do (pathRemove lock) 0)))))))))))))
fn ! refresh! root: String cache: String cmd: (List String) build: (fn [String String] -> Int64) -> Int64
  (let [(head (nc/headPath cache root))
        (pinned (or (nc/pinned? root (headDir cache root) head cmd) (nc/relayPinned? root (headDir cache root) head cmd)))
        (refused (if pinned 0 (guard! root cache)))]
    (if (!= refused 0) refused (refreshBody! root cache cmd build)))

