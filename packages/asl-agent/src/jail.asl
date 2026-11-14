(module aslAgent/jail
  :x [Jail envKey secretName? passName? scrubEnv cacheNames jailHome jailCacheEnv! cacheSources! seedCaches! childEnv! childEnvIn! jailOf! jailPlan! jailMode lexicalOptIn! jailTool! jailWrap! refusedArgv lexicalJail seatbeltProfile bwrapArgs denialText? sandboxNote absentNote]
  :i [(aslAgent/agentConfig :a ac)])

; (:m :ref LEON-RUN-HOME-JAIL :do "B-02: the lexical guard and the HOME swap are not a boundary. A unit child (run, manage, gate) now gets an allowlisted environment and runs under an OS sandbox: sandbox-exec on macOS, bwrap on Linux, writes only under :root, the jail home and the rebuildable caches, the root's own .git and the real HOME unreadable and unwritable, no network beyond loopback unless the unit declares :net true. Where no sandbox tool applies (none installed, or already inside a sandbox, which cannot nest) the child runs under the lexical guard only and the receipt says :sandbox lexical")
(schema Jail
  (:f mode String)
  (:f tool String)
  (:f root String)
  (:f writes (List String))
  (:f reads (List String))
  (:f lists (List String))
  (:f realHome String)
  (:f net Bool)
  (:f why String :default ""))

fn envKey row: String -> String
  (match (stringIndexOf row "=") ((some i) (optionOr (stringSlice row 0 i) row)) ((none) row))

fn envValue row: String -> String
  (match (stringIndexOf row "=") ((some i) (optionOr (stringSlice row (+ i 1) (stringLength row)) "")) ((none) ""))

fn secretName? name: String -> Bool
  (let [up (stringUpper name)]
    (listAny? (fn [w] (stringContains? up w)) (list "KEY" "TOKEN" "SECRET" "PASSWORD" "PASSWD" "CREDENTIAL" "AUTH" "COOKIE" "SESSION")))

fn cacheNames -> (List String)
  (list "ASL_NATIVE_CLI_CACHE" "ASL_HOST_CACHE_DIR" "ASL_NATIVE_ASL1_CACHE" "ASL_CHECK_CACHE" "ASL_CORPUS_CACHE" "ASL_NATIVE_TEST_CACHE")

; (:m :ref LEON-RUN-HOME-JAIL :do "the names a unit child may inherit: locale, terminal and identity, the fleet tag an outer guard finds its descendants by, and the rebuildable cache directories; everything else of the parent, provider keys and ASL_ settings included, stays behind")
fn plainNames -> (List String)
  (list "PATH" "LANG" "LANGUAGE" "TERM" "TZ" "USER" "LOGNAME" "SHELL" "NO_COLOR" "CI" "ASL_FLEET_TAG" "ASL_NATIVE_BUILD_WAIT")

; (:m :ref FABLE-BLIND-03 :do "the cache variables are not inherited: a unit child gets its own private cache rows from childEnvIn!, so a value the harness was started with never hands the shared cache to the child")
fn passName? name: String -> Bool
  (and (not (secretName? name))
    (or (listContains? (plainNames) name) (stringStartsWith? name "LC_")))

; (:m :ref LEON-RUN-HOME-JAIL :do "own rows are the ones the harness sets for the unit (PWD, HOME, TMPDIR and the like); they pass whatever their name, the inherited rows only by allowlist")
fn scrubEnv inherited: (List String) own: (List String) -> (List String)
  (let [ownKeys (map envKey own)]
    (listAppend (filter (fn [r] (and (passName? (envKey r)) (not (listContains? ownKeys (envKey r))))) inherited) own))

fn ! realOr! p: String -> String
  (resultOr (realPath p) p)

fn ! dir? p: String -> Bool
  (match (fileStat p) ((ok st) st.isDir) ((err _) false))

fn ! file? p: String -> Bool
  (match (fileStat p) ((ok st) st.isFile) ((err _) false))

; (:m :ref LEON-RUN-HOME-JAIL :do "the child of a unit op gets HOME and TMPDIR inside <root>/.asl/run/agentLoop/home, created by childEnv!; the real HOME is never passed")
fn jailHome absRoot: String -> String
  (str absRoot "/.asl/run/agentLoop/home")

; (:m :ref FABLE-BLIND-03 :do "the six cache variables of fleet/run#cacheRows and their place under a HOME. The shared caches of the real HOME hold executables every later asl run on the machine starts unsandboxed, so a unit child never gets them writable: each variable names a private directory under the jail home, and the shared one is at most a read-only source")
fn jailCacheRows -> (List (Pair String String))
  (list (pair "ASL_NATIVE_CLI_CACHE" "/.asl/run/nativeCli") (pair "ASL_HOST_CACHE_DIR" "/.asl/run/hosts")
        (pair "ASL_NATIVE_ASL1_CACHE" "/.asl/run/asl1") (pair "ASL_CHECK_CACHE" "/.asl/cache/check") (pair "ASL_CORPUS_CACHE" "/.asl/run/corpusCache")
        (pair "ASL_NATIVE_TEST_CACHE" "/.asl/run/nativeTest"))

fn rowValue rows: (List String) name: String -> String
  (envValue (optionOr (listHead (filter (fn [r] (= (envKey r) name)) rows)) ""))

; (:m :ref FABLE-BLIND-03 :do "the shared cache directories a unit child may read: per variable the value the harness itself runs with, else the real home's default, each only when it is a directory")
fn ! cacheSources! inherited: (List String) realHome: String -> (List (Pair String String))
  (filter (fn [p] (dir? (pairSecond p)))
    (map (fn [r]
           (let [set (rowValue inherited (pairFirst r))]
             (pair (pairFirst r) (if (stringEmpty? set) (if (stringEmpty? realHome) "" (str realHome (pairSecond r))) set))))
      (jailCacheRows)))

; (:m :ref FABLE-BLIND-03 :do "the private cache rows of a jail home: every variable names <jail home><its default place>, created here; the test compile cache only in a linked worktree, where its default would follow HOME (the main checkout keeps it inside the root).")
fn ! jailCacheEnv! absRoot: String home: String -> (List String)
  (let [linked (file? (str absRoot "/.git"))
        wanted (filter (fn [r] (or (!= (pairFirst r) "ASL_NATIVE_TEST_CACHE") linked)) (jailCacheRows))]
    (map (fn [r] (let [made (dirCreate (str home (pairSecond r)))] (str (pairFirst r) "=" home (pairSecond r)))) wanted))

fn ! waitUntil! pid: Int64 deadline: Int64 -> Bool
  (match (procWaitPid pid true)
    ((err _) false)
    ((ok got)
      (match got
        ((some code) (= code 0))
        ((none)
          (if (>= (monotonicNs) deadline)
            (let [killed (procKill pid "SIGKILL")
                  reaped (procWaitPid pid false)]
              false)
            (do (sleepMs 20) (waitUntil! pid deadline)))))))

; (:m :ref FABLE-BLIND-03 :do "a copy-on-write clone of one directory, bounded at 120 s: cp -c on macOS (clonefile), cp --reflink=always elsewhere; where the file system cannot clone the copy fails and the private cache starts cold, which costs a rebuild and never a shared write. Not yet run on a Linux host")
fn ! cloneDir! src: String dst: String -> Bool
  (let [argv (if (file? "/usr/bin/sandbox-exec")
               (list "/bin/cp" "-cRp" src dst)
               (list "cp" "-Rp" "--reflink=always" src dst))]
    (match (procSpawnv argv (none) (some (list "PATH=/usr/bin:/bin")))
      ((err _) false)
      ((ok sp)
        (let [closedIn (fdClose sp.stdin)
              closedOut (fdClose sp.stdout)
              closedErr (fdClose sp.stderr)]
          (waitUntil! sp.pid (+ (monotonicNs) 120000000000))))))

fn seededNames -> (List String)
  (list "ASL_NATIVE_CLI_CACHE" "ASL_HOST_CACHE_DIR" "ASL_NATIVE_ASL1_CACHE" "ASL_CHECK_CACHE" "ASL_NATIVE_TEST_CACHE")

; (:m :ref FABLE-BLIND-03 :do "a private cache that does not exist yet starts as a clone of its shared source, so the first asl run of a unit is warm; the clone lands under a private name and is renamed into place, a failed clone is removed; the corpus cache is not seeded. Returns the names seeded now")
fn ! seedCaches! home: String sources: (List (Pair String String)) -> (List String)
  (fold (fn [acc r]
          (let [name (pairFirst r)
                dst (str home (pairSecond r))
                src (optionOr (listHead (map pairSecond (filter (fn [s] (= (pairFirst s) name)) sources))) "")]
            (if (or (stringEmpty? src) (or (not (listContains? (seededNames) name)) (ok? (fileStat dst))))
              acc
              (let [tmp (str dst ".seed-" (stringFromInt64 (monotonicNs)))
                    parent (dirCreate (parentOf dst))
                    cloned (and (cloneDir! src tmp) (ok? (pathRename tmp dst)))
                    swept (if cloned true (ok? (pathRemove tmp)))]
                (if cloned (listAppend acc (list name)) acc)))))
    (list) (jailCacheRows))

; (:m :ref LEON-RUN-HOME-JAIL :do "B-02: the child env is an allowlist, not the parent env minus a few names: of the inherited rows only the names passName? knows pass, so provider keys and ASL_ settings never reach a unit child; the rows the harness sets (PWD, HOME, TMPDIR, the private cache directories) are added after, and the names the run hides are dropped last. seed true clones the shared caches into the private ones first; they hold tens of thousands of files inside the root, so <jail home>/.asl then carries a .gitignore of * and the run snapshot (git ls-files of untracked files) never walks them")
fn ! childEnvIn! absRoot: String inherited: (List String) hidden: (List String) realHome: String seed: Bool -> (List String)
  (let [home (jailHome absRoot)
        made (and (ok? (dirCreate home)) (ok? (dirCreate (str home "/tmp"))))
        kept (filter (fn [r] (passName? (envKey r))) inherited)
        seeded (if seed (seedCaches! home (cacheSources! inherited realHome)) (list))
        ignore (str home "/.asl/.gitignore")
        ignored (if (and seed (not (file? ignore))) (and (ok? (dirCreate (str home "/.asl"))) (ok? (fileWrite ignore "*\n"))) true)
        caches (jailCacheEnv! absRoot home)
        own (listAppend caches (list (str "PWD=" absRoot) (str "HOME=" home) (str "TMPDIR=" home "/tmp") "PYTHONDONTWRITEBYTECODE=1"))]
    (filter (fn [r] (not (listContains? hidden (envKey r)))) (scrubEnv kept own)))

; (:m :ref FABLE-BLIND-03 :do "the caches are seeded only for a root that carries its own bin/asl: any other root (a foreign project, a test fixture) never starts the tool from its child and keeps empty private caches")
fn ! childEnv! absRoot: String inherited: (List String) hidden: (List String) -> (List String)
  (childEnvIn! absRoot inherited hidden (optionOr (envGet "HOME") "") (file? (str absRoot "/bin/asl")))

fn under? p: String base: String -> Bool
  (and (not (stringEmpty? base)) (or (= p base) (stringStartsWith? p (str base "/"))))

fn parentOf p: String -> String
  (let [segs (filter (fn [x] (not (stringEmpty? x))) (stringSplit p "/"))]
    (str "/" (stringJoin (listTake segs (max 0 (- (listLength segs) 1))) "/")))

fn ancestorsIn p: String base: String acc: (List String) -> (List String)
  (let [up (parentOf p)]
    (if (or (= up p) (or (= up base) (not (under? up base)))) acc (ancestorsIn up base (cons up acc))))

fn firstLine text: String -> String
  (stringTrim (optionOr (listHead (stringSplit text "\n")) ""))

fn normDots segs: (List String) acc: (List String) -> (List String)
  (if (listEmpty? segs)
    (listReverse acc)
    (let [s (optionOr (listHead segs) "")
          rest (optionOr (listTail segs) (list))]
      (cond
        ((or (= s "") (= s ".")) (normDots rest acc))
        ((= s "..") (normDots rest (optionOr (listTail acc) (list))))
        (else (normDots rest (cons s acc))))))

fn normPath p: String -> String
  (str "/" (stringJoin (normDots (stringSplit p "/") (list)) "/"))

; (:m :ref LEON-RUN-HOME-JAIL :do "a linked worktree's .git is a file naming its private git dir, whose commondir names the repository every worktree shares; that repository is readable (git status, git log) and never writable from a unit child")
fn ! commonGit! root: String -> (List String)
  (let [dot (str root "/.git")]
    (if (not (file? dot))
      (list)
      (let [line (firstLine (resultOr (fileReadString dot) ""))
            raw (if (stringStartsWith? line "gitdir:") (stringTrim (optionOr (stringSlice line 7 (stringLength line)) "")) "")
            gitDir (if (stringEmpty? raw) "" (normPath (if (stringStartsWith? raw "/") raw (str root "/" raw))))
            rel (firstLine (resultOr (fileReadString (str gitDir "/commondir")) ""))
            common (cond
                     ((stringEmpty? gitDir) "")
                     ((stringEmpty? rel) gitDir)
                     ((stringStartsWith? rel "/") (normPath rel))
                     (else (normPath (str gitDir "/" rel))))]
        (if (stringEmpty? common) (list) (list (realOr! common))))))

fn ! probe! argv: (List String) -> Bool
  (match (procSpawnv argv (none) (some (list "PATH=/usr/bin:/bin")))
    ((err _) false)
    ((ok sp)
      (let [closedIn (fdClose sp.stdin)
            closedOut (fdClose sp.stdout)
            closedErr (fdClose sp.stderr)]
        (match (procWaitPid sp.pid false) ((ok code) (= (optionOr code 1) 0)) ((err _) false)))))

fn ! bwrapPath! -> String
  (optionOr (listHead (filter (fn [p] (file? p)) (list "/usr/bin/bwrap" "/bin/bwrap" "/usr/local/bin/bwrap"))) "")

; (:m :ref LEON-RUN-HOME-JAIL :do "the sandbox tool that applies right now, proven by running true under it: a process already inside a sandbox cannot start a second one (sandbox_apply fails), and bwrap needs user namespaces, so presence alone is not enough")
fn ! jailTool! -> String
  (cond
    ((file? "/usr/bin/sandbox-exec")
      (if (probe! (list "/usr/bin/sandbox-exec" "-p" "(version 1)(allow default)" "/usr/bin/true")) "sandbox-exec" ""))
    ((not (stringEmpty? (bwrapPath!)))
      (if (probe! (list (bwrapPath!) "--ro-bind" "/" "/" "--dev" "/dev" "true")) (bwrapPath!) ""))
    (else ""))

fn lexicalJail root: String net: Bool -> Jail
  (Jail :mode "lexical" :tool "" :root root :writes (list) :reads (list) :lists (list) :realHome "" :net net)

fn dedupe xs: (List String) acc: (List String) -> (List String)
  (if (listEmpty? xs)
    (listReverse acc)
    (let [x (optionOr (listHead xs) "")
          rest (optionOr (listTail xs) (list))]
      (dedupe rest (if (or (stringEmpty? x) (listContains? acc x)) acc (cons x acc)))))

; (:m :ref FABLE-BLIND-03 :do "fail-closed: with a sandbox tool the mode is os; with none the child is refused, unless the machine's owner opted into the lexical guard alone")
fn jailMode tool: String lexicalOnly: Bool -> String
  (cond
    ((not (stringEmpty? tool)) "os")
    (lexicalOnly "lexical")
    (else "refused"))

; (:m :ref FABLE-BLIND-03 :do "the opt-in is a file row, never an env name and never under the unit's root (a unit could write it there): <real HOME>/.asl/config.asn, :agentLoop (:jailLexicalOnly true)")
fn ! lexicalOptIn! realHome: String -> Bool
  (and (not (stringEmpty? realHome))
    (= (optionOr (ac/agentLoopValue (resultOr (fileReadString (str realHome "/.asl/config.asn")) "") ":jailLexicalOnly") "") "true"))

; (:m :ref LEON-RUN-HOME-JAIL :do "the jail of one child: writes are the root, the jail home (its private caches inside) and the scratch directories the harness adds; reads under the real HOME are those plus the shared repository, the tool root, the shared caches (read-only) and the PATH entries that live there; the root's ancestors up to the real HOME are listable (path and import resolution list them; without that an asl test in the jail cannot stage its sources) but their other children are not readable")
fn ! jailPlan! tool: String lexicalOnly: Bool root: String home: String envRows: (List String) extraReads: (List String) extraWrites: (List String) net: Bool realHomeRaw: String sources: (List String) -> Jail
  (let [mode (jailMode tool lexicalOnly)]
    (if (!= mode "os")
      (with (lexicalJail root net) :mode mode :why (if (= mode "refused") "no OS sandbox applies here (sandbox-exec, bwrap) and <HOME>/.asl/config.asn has no :agentLoop (:jailLexicalOnly true)" ""))
      (let [rroot (realOr! root)
            realHome (if (stringEmpty? realHomeRaw) "" (realOr! realHomeRaw))
            pathRow (optionOr (listHead (filter (fn [r] (= (envKey r) "PATH")) envRows)) "")
            pathDirs (filter (fn [d] (under? d realHome)) (map realOr! (filter dir? (stringSplit (envValue pathRow) ":"))))
            writes (dedupe (listAppend (list rroot (realOr! home)) (map realOr! (filter dir? extraWrites))) (list))
            reads (dedupe (listAppend (listAppend (listAppend (commonGit! rroot) (map realOr! (filter dir? extraReads))) (map realOr! (filter dir? sources))) pathDirs) (list))
            lists (if (and (under? rroot realHome) (!= rroot realHome)) (cons realHome (ancestorsIn rroot realHome (list))) (list))]
        (Jail :mode "os" :tool tool :root rroot :writes writes :reads reads :lists lists :realHome realHome :net net))))

fn ! jailOf! root: String home: String envRows: (List String) extraReads: (List String) extraWrites: (List String) net: Bool -> Jail
  (let [realHome (optionOr (envGet "HOME") "")]
    (jailPlan! (jailTool!) (lexicalOptIn! realHome) root home envRows extraReads extraWrites net realHome
      (map pairSecond (cacheSources! (envList) realHome))))

fn sbQuote p: String -> String
  (str "\"" (stringReplace (stringReplace p "\\" "\\\\") "\"" "\\\"") "\"")

fn sbPaths kind: String ps: (List String) -> String
  (stringJoin (map (fn [p] (str "(" kind " " (sbQuote p) ")")) ps) " ")

fn seatbeltNet j: Jail -> String
  (if j.net
    ""
    (str "(deny network*)"
      "(allow network-outbound (remote ip \"localhost:*\"))(allow network-inbound (local ip \"localhost:*\"))(allow network-bind (local ip \"localhost:*\"))"
      "(allow network* (remote unix-socket " (sbPaths "subpath" j.writes) "))(allow network* (local unix-socket " (sbPaths "subpath" j.writes) "))"))

; (:m :ref LEON-RUN-HOME-JAIL :do "later rules win: writes are denied everywhere and re-allowed for the jail's own directories, the null and tty devices, the xcrun database clang needs in the Darwin temp dir and the capture files the ASL runtime's processRun creates in /tmp; the root's .git is denied again after that; reads under the real HOME are denied and re-allowed for the jail's directories, with metadata (stat, realpath) left open. FABLE-BLIND-03: nothing runs outside the sandbox. ps is setuid, which a sandboxed process may not exec, and the earlier exemption (ps with no-sandbox) ran ps with no boundary at all, so a unit child read the command line of every process of the user (and their environment on a system whose ps prints it), so it is gone: a unit child has no ps, and the descendant count and tree kill of a unit are the harness's, outside the jail. Process information and signals reach only processes in the same sandbox, so a unit child cannot inspect or kill the harness, the gateway or another unit")
fn seatbeltProfile j: Jail -> String
  (str "(version 1)(allow default)"
    "(deny file-write*)"
    "(allow file-write* " (sbPaths "subpath" j.writes)
    " (literal \"/dev/null\") (literal \"/dev/zero\") (literal \"/dev/tty\") (literal \"/dev/dtracehelper\") (regex #\"^/dev/fd/\") (regex #\"^/dev/ttys[0-9]+$\")"
    " (regex #\"^/private/var/folders/[^/]+/[^/]+/T/xcrun_db\") (regex #\"^/private/tmp/asl_sp_(out|err)_[A-Za-z0-9]+$\"))"
    "(deny file-write* " (sbPaths "subpath" (list (str j.root "/.git"))) ")"
    (if (stringEmpty? j.realHome)
      ""
      (str "(deny file-read* " (sbPaths "subpath" (list j.realHome)) ")"
        "(allow file-read-metadata)"
        "(allow file-read* " (sbPaths "subpath" (listAppend j.writes j.reads)) ")"
        (if (listEmpty? j.lists) "" (str "(allow file-read* " (sbPaths "literal" j.lists) ")"))))
    "(deny process-info*)(allow process-info* (target same-sandbox))"
    "(deny signal)(allow signal (target same-sandbox))"
    (seatbeltNet j))

fn flagPairs flag: String ps: (List String) -> (List String)
  (fold (fn [acc p] (listAppend acc (list flag p p))) (list) ps)

; (:m :ref LEON-RUN-HOME-JAIL :do "bwrap: the whole file system read-only, its own process namespace (so /proc shows no other process's environment) and its own /tmp, a tmpfs over the real HOME, then the jail's reads bound back read-only and its writes read-write, the root's .git read-only on top, and a private network namespace (loopback only) unless the unit declared :net true. Not yet run on a Linux host")
fn ! bwrapArgs j: Jail -> (List String)
  (let [hide (if (or (stringEmpty? j.realHome) (under? j.realHome j.root)) (list) (list "--tmpfs" j.realHome))
        dotGit (str j.root "/.git")
        git (if (or (dir? dotGit) (file? dotGit)) (list "--ro-bind" dotGit dotGit) (list))]
    (listAppend (list j.tool "--die-with-parent" "--unshare-pid" "--ro-bind" "/" "/" "--dev" "/dev" "--proc" "/proc" "--tmpfs" "/tmp")
      (listAppend hide
        (listAppend (flagPairs "--ro-bind" j.reads)
          (listAppend (flagPairs "--bind" j.writes)
            (listAppend git
              (listAppend (if j.net (list) (list "--unshare-net")) (list "--chdir" j.root "--"))))))))

; (:m :ref FABLE-BLIND-03 :do "what runs in place of a refused child: one line naming the refusal and exit 126, so every caller of jailWrap! fails closed whether or not it reads the mode")
fn absentNote j: Jail -> String
  (str "ERR_RUN_SANDBOX_ABSENT: not run, " j.why "; a unit process runs only inside an OS sandbox")

fn refusedArgv j: Jail -> (List String)
  (list "/bin/sh" "-c" "printf '%s\\n' \"$1\" >&2; exit 126" "sh" (absentNote j))

fn ! jailWrap! j: Jail argv: (List String) -> (List String)
  (cond
    ((= j.mode "lexical") argv)
    ((!= j.mode "os") (refusedArgv j))
    ((= j.tool "sandbox-exec") (listAppend (list "/usr/bin/sandbox-exec" "-p" (seatbeltProfile j)) argv))
    (else (listAppend (bwrapArgs j) argv)))

; (:m :ref LEON-RUN-HOME-JAIL :do "what a sandbox refusal looks like in a child's output: EPERM from seatbelt, EROFS from a read-only bind")
fn denialText? text: String -> Bool
  (or (stringContains? text "Operation not permitted") (stringContains? text "Read-only file system"))

fn sandboxNote j: Jail -> String
  (str "the OS sandbox refused an operation: a unit process may write only under :root (its .git excluded) and its scratch HOME, cannot read the real HOME, its temporary files go under $TMPDIR (the shared /tmp is not writable), it has no ps and cannot signal a process outside its own tree"
    (if j.net "" ", and has no network beyond loopback unless the unit declares :net true"))
