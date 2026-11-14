(module aslAgent/jail
  :x [Jail envKey secretName? passName? scrubEnv cacheNames jailHome jailCacheEnv! cacheSources! seedCaches! seedCachesWith! seedHow cloneKind! cliHeadName currentHeads seedReportText childEnv! childEnvIn! jailOf! jailPlan! jailMode lexicalOptIn! jailTool! jailWrap! refusedArgv lexicalJail seatbeltProfile bwrapArgs denialText? sandboxNote absentNote]
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

; (:m :ref JAIL-LINUX :do "one helper process of the harness (cp), bounded at 120 s and killed at the deadline; true only on exit 0")
fn ! runBounded! argv: (List String) -> Bool
  (match (procSpawnv argv (none) (some (list "PATH=/usr/bin:/bin")))
    ((err _) false)
    ((ok sp)
      (let [closedIn (fdClose sp.stdin)
            closedOut (fdClose sp.stdout)
            closedErr (fdClose sp.stderr)]
        (waitUntil! sp.pid (+ (monotonicNs) 120000000000)))))

; (:m :ref FABLE-BLIND-03 :do "a copy-on-write clone of one directory: cp -c on macOS (clonefile), cp --reflink=always elsewhere; never a plain copy, the shared caches hold gigabytes")
fn cloneArgv kind: String src: String dst: String -> (List String)
  (if (= kind "clonefile") (list "/bin/cp" "-cRp" src dst) (list "cp" "-Rp" "--reflink=always" src dst))

; (:m :ref JAIL-LINUX :do "D2: how this machine clones into dir: clonefile on macOS; elsewhere reflink only when one probe file clones inside dir, else none (ext4 has no reflink, and cp --reflink=always over a whole cache would fail file by file)")
fn ! cloneKind! dir: String -> String
  (if (file? "/usr/bin/sandbox-exec")
    "clonefile"
    (let [from (str dir "/.reflinkProbe-" (stringFromInt64 (monotonicNs)))
          to (str from ".to")
          can (and (ok? (fileWrite from "probe\n")) (runBounded! (list "cp" "--reflink=always" from to)))
          sweptFrom (if (file? from) (ok? (pathRemove from)) true)
          sweptTo (if (file? to) (ok? (pathRemove to)) true)]
      (if (and can (and sweptFrom sweptTo)) "reflink" "none")))

fn seededNames -> (List String)
  (list "ASL_NATIVE_CLI_CACHE" "ASL_HOST_CACHE_DIR" "ASL_NATIVE_ASL1_CACHE" "ASL_CHECK_CACHE" "ASL_NATIVE_TEST_CACHE")

; (:m :ref JAIL-LINUX :do "bin/asl names the pointer of a root head<root with / as _> inside the native CLI cache; the file holds the path of the cli-<digest> directory that root runs")
fn cliHeadName root: String -> String
  (str "head" (stringReplace root "/" "_"))

; (:m :ref JAIL-LINUX :do "the pointers a unit child can start from: its own root's, and the tool root's the harness itself was started from (the inherited ASL_CLI_ROOT row; a test op runs that root's bin/asl on a foreign root)")
fn currentHeads absRoot: String inherited: (List String) -> (List String)
  (dedupe (map cliHeadName (filter (fn [p] (not (stringEmpty? p))) (list absRoot (rowValue inherited "ASL_CLI_ROOT")))) (list))

; (:m :ref JAIL-LINUX :do "D2: what seeds one private cache. A clone that worked is the seed; without one the native CLI cache gets its active entry copied (cliEntry), any other cache starts cold where the file system cannot clone (none) and counts as failed where it could and the clone broke")
fn seedHow kind: String cloned: Bool name: String -> String
  (cond
    (cloned "clone")
    ((= name "ASL_NATIVE_CLI_CACHE") "cliEntry")
    ((= kind "none") "cold")
    (else "failed: the clone did not complete"))

fn lastSeg p: String -> String
  (optionOr (listLast (filter (fn [x] (not (stringEmpty? x))) (stringSplit p "/"))) "")

; (:m :ref JAIL-LINUX :do "the cli directory one head pointer names, only when it is a cli-<digest> directory directly inside the shared cache; empty otherwise, so a pointer never makes the seed copy anything else")
fn ! cliDirOf! src: String head: String -> String
  (let [ptr (firstLine (resultOr (fileReadString (str src "/" head)) ""))]
    (if (and (stringStartsWith? (lastSeg ptr) "cli-") (and (= (realOr! (parentOf ptr)) (realOr! src)) (dir? ptr))) ptr ""))

; (:m :ref JAIL-LINUX :do "the private pointer names the private copy, and keeps the shared pointer's mtime: bin/asl calls the CLI stale when a source is newer than the pointer, and a pointer written now would hide that")
fn ! repoint! src: String tmp: String dst: String head: String dir: String -> Bool
  (match (fileStat (str src "/" head))
    ((err _) false)
    ((ok st) (and (ok? (fileWrite (str tmp "/" head) (str dst "/" (lastSeg dir) "\n"))) (ok? (fileUtime (str tmp "/" head) st.mtimeNs)))))

; (:m :ref JAIL-LINUX :do "D2: the active entry of the shared native CLI cache, plain cp -Rp (about 56M): every head pointer file, and the cli directory of each pointer in heads, which is then repointed at the copy; the other pointers keep naming the shared cache, which the jail reads. Built under a private name and renamed into place; returns the reason it failed, empty on success, and a failed seed leaves nothing behind")
fn ! seedCliEntry! src: String dst: String heads: (List String) -> String
  (let [tmp (str dst ".seed-" (stringFromInt64 (monotonicNs)))
        names (filter (fn [n] (and (stringStartsWith? n "head") (file? (str src "/" n)))) (resultOr (dirList src) (list)))
        live (filter (fn [p] (not (stringEmpty? (pairSecond p)))) (map (fn [h] (pair h (cliDirOf! src h))) (filter (fn [h] (listContains? names h)) heads)))
        why (cond
              ((listEmpty? live) "no head pointer of this root names a cli directory in the shared cache")
              ((not (ok? (dirCreate tmp))) "the private cache directory was not created")
              ((not (runBounded! (listAppend (cons "cp" (cons "-p" (map (fn [n] (str src "/" n)) names))) (list tmp)))) "the head pointers were not copied")
              ((not (listAll? (fn [d] (runBounded! (list "cp" "-Rp" d tmp))) (dedupe (map pairSecond live) (list)))) "the cli directory was not copied")
              ((not (listAll? (fn [p] (repoint! src tmp dst (pairFirst p) (pairSecond p))) live)) "a head pointer was not rewritten")
              ((not (ok? (pathRename tmp dst))) "the seeded cache was not renamed into place")
              (else ""))
        swept (if (or (stringEmpty? why) (not (ok? (fileStat tmp)))) true (ok? (pathRemove tmp)))]
    (if swept why (str why "; its partial copy was not removed")))

; (:m :ref FABLE-BLIND-03 :do "a private cache that does not exist yet starts as a clone of its shared source, so the first asl run of a unit is warm; the clone lands under a private name and is renamed into place, a failed clone is removed; the corpus cache is not seeded. JAIL-LINUX D2: kind is how the machine clones (cloneKind!), passed as data so the no-clone path runs on any file system; returns one (cache name, outcome) row per cache it tried: clone, cliEntry, cold, or failed: <why>")
fn ! seedCachesWith! kind: String home: String sources: (List (Pair String String)) heads: (List String) -> (List (Pair String String))
  (fold (fn [acc r]
          (let [name (pairFirst r)
                dst (str home (pairSecond r))
                src (optionOr (listHead (map pairSecond (filter (fn [s] (= (pairFirst s) name)) sources))) "")]
            (if (or (stringEmpty? src) (or (not (listContains? (seededNames) name)) (ok? (fileStat dst))))
              acc
              (let [tmp (str dst ".seed-" (stringFromInt64 (monotonicNs)))
                    parent (dirCreate (parentOf dst))
                    cloned (and (!= kind "none") (and (runBounded! (cloneArgv kind src tmp)) (ok? (pathRename tmp dst))))
                    swept (if (or cloned (not (ok? (fileStat tmp)))) true (ok? (pathRemove tmp)))
                    how (seedHow kind cloned name)
                    why (if (= how "cliEntry") (seedCliEntry! src dst heads) "")]
                (listAppend acc (list (pair name (cond
                                                   ((not swept) "failed: a partial clone was not removed")
                                                   ((stringEmpty? why) how)
                                                   (else (str "failed: " why))))))))))
    (list) (jailCacheRows))

fn seedFailed? row: (Pair String String) -> Bool
  (stringStartsWith? (pairSecond row) "failed")

; (:m :ref JAIL-LINUX :do "D2: a seed outcome is never dropped: every row goes to <jail home>/.asl/seedReport.asn, and a failed one also to the harness's stderr as one line naming the cache and the reason (no path, no env value)")
fn seedReportText rows: (List (Pair String String)) -> String
  (stringJoin (map (fn [r] (str "(:seed :cache \"" (pairFirst r) "\" :how \"" (pairSecond r) "\")\n")) rows) "")

fn ! seedReport! home: String rows: (List (Pair String String)) -> Bool
  (if (listEmpty? rows)
    true
    (let [wrote (and (ok? (dirCreate (str home "/.asl"))) (ok? (fileWrite (str home "/.asl/seedReport.asn") (seedReportText rows))))]
      (do
        (map (fn [r] (eprintln (str "(:leon :seed :cache \"" (pairFirst r) "\" :how \"" (pairSecond r) "\")"))) (filter seedFailed? rows))
        (if wrote true (do (eprintln "(:leon :seed :failed \"the seed report was not written\")") false)))))

; (:m :ref JAIL-LINUX :do "the clone probe runs only when some cache is still to be seeded; jailCacheEnv! creates every private directory right after, so a jail home is seeded once")
fn ! seedCaches! home: String sources: (List (Pair String String)) heads: (List String) -> (List (Pair String String))
  (if (listAny? (fn [r] (and (listContains? (seededNames) (pairFirst r)) (and (listAny? (fn [s] (= (pairFirst s) (pairFirst r))) sources) (not (ok? (fileStat (str home (pairSecond r)))))))) (jailCacheRows))
    (seedCachesWith! (cloneKind! home) home sources heads)
    (list))

; (:m :ref LEON-RUN-HOME-JAIL :do "B-02: the child env is an allowlist, not the parent env minus a few names: of the inherited rows only the names passName? knows pass, so provider keys and ASL_ settings never reach a unit child; the rows the harness sets (PWD, HOME, TMPDIR, the private cache directories) are added after, and the names the run hides are dropped last. seed true clones the shared caches into the private ones first; they hold tens of thousands of files inside the root, so <jail home>/.asl then carries a .gitignore of * and the run snapshot (git ls-files of untracked files) never walks them")
fn ! childEnvIn! absRoot: String inherited: (List String) hidden: (List String) realHome: String seed: Bool -> (List String)
  (let [home (jailHome absRoot)
        made (and (ok? (dirCreate home)) (ok? (dirCreate (str home "/tmp"))))
        kept (filter (fn [r] (passName? (envKey r))) inherited)
        seeded (if seed (seedCaches! home (cacheSources! inherited realHome) (currentHeads (realOr! absRoot) inherited)) (list))
        reported (seedReport! home seeded)
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

; (:m :ref LEON-RUN-HOME-JAIL :do "bwrap: the whole file system read-only, its own process namespace (so /proc shows no other process's environment) and its own /tmp, a tmpfs over the real HOME, then the jail's reads bound back read-only and its writes read-write, the root's .git read-only on top, and a private network namespace (loopback only) unless the unit declared :net true. JAIL-LINUX D1: /run is an empty tmpfs too, because the session and system D-Bus, the user systemd manager, gnupg agents and snapd listen on sockets there and would run a command outside the jail; with :net true only the resolver's directory is bound back, resolv.conf points into it. D3: the tmpfs over the real HOME is remounted read-only after the binds (bwrap remounts that one mount, the binds inside it keep their mode), so a write there fails with EROFS and gets the ERR_RUN_SANDBOX receipt instead of vanishing; not when the HOME itself is a write of the jail")
fn ! bwrapArgs j: Jail -> (List String)
  (let [hide (if (or (stringEmpty? j.realHome) (under? j.realHome j.root)) (list) (list "--tmpfs" j.realHome))
        seal (if (or (listEmpty? hide) (listContains? j.writes j.realHome)) (list) (list "--remount-ro" j.realHome))
        resolve (if j.net (list "--ro-bind-try" "/run/systemd/resolve" "/run/systemd/resolve") (list))
        dotGit (str j.root "/.git")
        git (if (or (dir? dotGit) (file? dotGit)) (list "--ro-bind" dotGit dotGit) (list))]
    (listAppend (list j.tool "--die-with-parent" "--unshare-pid" "--ro-bind" "/" "/" "--dev" "/dev" "--proc" "/proc" "--tmpfs" "/tmp" "--tmpfs" "/run")
      (listAppend resolve
        (listAppend hide
          (listAppend (flagPairs "--ro-bind" j.reads)
            (listAppend (flagPairs "--bind" j.writes)
              (listAppend git
                (listAppend seal
                  (listAppend (if j.net (list) (list "--unshare-net")) (list "--chdir" j.root "--"))))))))))

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
