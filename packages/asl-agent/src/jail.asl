(module aslAgent/jail
  :x [Jail envKey secretName? passName? scrubEnv cacheNames jailHome jailCacheEnv! cacheSources! seedCaches! seedCachesWith! seedHow linkFree! CliSource resyncNeeded? pickSource resyncCli! cloneKind! cliHeadName cliCopyArgv currentHeads seedReportText childEnv! childEnvIn! jailOf! jailPlan! jailMode lexicalOptIn! jailTool! jailWrap! jailTmp envSignals! refusedArgv lexicalJail seatbeltProfile bwrapArgs denialText? sandboxNote absentNote]
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
  (:f why String :default "")
  (:f signalEnv String :default ""))

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

; (:m :ref AGENT-LINUX-REDS-2 :do "JAIL-TMPDIR-IN-WORKTREE: the child TMPDIR lies outside the task tree, so a fixture made under it is not inside the repository the gate runs in; one directory per task root under /tmp, created by childEnvIn!, bound writable by jailPlan!")
fn ! jailTmp absRoot: String -> String
  (str "/tmp/aslJailTmp-" (stringReplace (resultOr (realPath absRoot) absRoot) "/" "_"))

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
    (map (fn [r] (let [made (if (linkFree! absRoot (str home (pairSecond r))) (ok? (dirCreate (str home (pairSecond r)))) false)] (str (pairFirst r) "=" home (pairSecond r)))) wanted))

fn ! linkFreeFrom! at: String segs: (List String) -> Bool
  (match (listHead segs)
    ((none) true)
    ((some s) (let [next (str at "/" s)]
                (match (fileLstat next)
                  ((err _) true)
                  ((ok st) (and (not st.isSymlink) (linkFreeFrom! next (optionOr (listTail segs) (list)))))))))

; (:m :ref JAIL-SEED-SYMLINK :do "the harness writes the jail home and seeds its caches outside the sandbox, and the unit child can plant a symlink anywhere under its root between calls; a write through one would land where the link points (the real HOME, its key files). p is safe when it lies under base, has no .. segment and no part of it below base that exists is a symlink (lstat, the final part included); base itself is the caller's, outside the unit's reach")
fn ! linkFree! base: String p: String -> Bool
  (let [segs (filter (fn [x] (not (stringEmpty? x))) (stringSplit (optionOr (stringSlice p (stringLength base) (stringLength p)) "") "/"))]
    (and (under? p base) (and (not (listContains? segs "..")) (linkFreeFrom! base segs))))

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
  (let [ptr (firstLine (readPlain! (str src "/" head) 4096))
        plain (match (fileLstat ptr) ((ok st) (and st.isDir (not st.isSymlink))) ((err _) false))]
    (if (and (stringStartsWith? (lastSeg ptr) "cli-") (and plain (= (realOr! ptr) (str (realOr! src) "/" (lastSeg ptr))))) ptr ""))

; (:m :ref JAIL-SEED-SYMLINK :do "a regular file by lstat: a head pointer that is a symlink is never read or copied, so a pointer cannot hand the seed the contents of a file outside the shared cache")
fn ! plainFile? p: String -> Bool
  (match (fileLstat p) ((ok st) (and st.isFile (not st.isSymlink))) ((err _) false))

fn ! stampOf! p: String -> Int64
  (match (fileLstat p) ((ok st) (if (and st.isFile (not st.isSymlink)) st.mtimeNs -1)) ((err _) -1))

; (:m :ref LEON-JAIL-CLI-CACHE :do "the stamp a borrowed pointer gets, 1 s past the epoch: every source of the root is newer, so the child's bin/asl takes it as suspect and its refresh verifies the entry byte for byte against the root's own sources (nativeBuild coldCode!) before trusting it, and builds only when they differ")
fn verifyStamp -> Int64
  1000000000

; (:m :ref LEON-JAIL-CLI-CACHE :do "one shared pointer a private head may follow: the cli directory it names (empty when it names none, cliDirOf!), its mtime, own true for the head's own pointer and false for one borrowed from the tool root, fits true when that entry's source snapshot equals the root's sources byte for byte")
(schema CliSource
  (:f dir String)
  (:f stamp Int64)
  (:f own Bool)
  (:f fits Bool :default false))

fn ! sourceOf! src: String head: String own: Bool -> CliSource
  (let [dir (cliDirOf! src head)]
    (CliSource :dir dir :stamp (if (stringEmpty? dir) -1 (stampOf! (str src "/" head))) :own own))

; (:m :ref LEON-JAIL-CLI-CACHE :do "fix round M1/M2: the harness reads a file for the re-seed only when lstat calls it a regular file, not a symlink, and no larger than cap; a FIFO, a device, a directory, a symlink or an oversize file is never opened (an open of a FIFO blocks forever), and reads as absent. There is no open-without-follow primitive, so the lstat type check is the bar")
fn ! plainSize! p: String cap: Int64 -> Int64
  (match (fileLstat p) ((ok st) (if (and st.isFile (and (not st.isSymlink) (<= st.size cap))) st.size -1)) ((err _) -1))

fn ! readPlain! p: String cap: Int64 -> String
  (if (>= (plainSize! p cap) 0) (resultOr (fileReadString p) "") "")

fn depsCap -> Int64
  1048576

fn depsRowsCap -> Int64
  4096

fn sourceCap -> Int64
  16777216

; (:m :ref LEON-JAIL-CLI-CACHE :do "the dependency list of a cli directory: its deps file read only as a plain file of at most depsCap bytes and depsRowsCap rows, and only when every row is relative and has no .. segment: the deps file of a private copy is the unit's to write, and a row must never make the harness read outside the root. Anything else is the empty list, which never matches and is always suspect")
fn ! depsOf! dir: String -> (List String)
  (let [rows (filter (fn [l] (not (stringEmpty? l))) (map stringTrim (stringSplit (readPlain! (str dir "/deps") (depsCap)) "\n")))]
    (if (or (> (listLength rows) (depsRowsCap)) (listAny? (fn [p] (or (stringStartsWith? p "/") (listContains? (stringSplit p "/") ".."))) rows)) (list) rows))

; (:m :ref LEON-JAIL-CLI-CACHE :do "one source and its snapshot are the same when both are plain files on symlink-free paths, of equal size by lstat and at most sourceCap bytes, with equal bytes; unequal sizes are a mismatch without a read")
fn ! samePlain! root: String dir: String p: String -> Bool
  (let [a (str root "/" p)
        b (str dir "/src/" p)
        sa (if (linkFree! root a) (plainSize! a (sourceCap)) -1)
        sb (if (linkFree! dir b) (plainSize! b (sourceCap)) -1)]
    (and (>= sa 0) (and (= sa sb) (sameBytes! a b))))

fn ! sameFrom! root: String dir: String deps: (List String) -> Bool
  (match (listHead deps)
    ((none) true)
    ((some p) (and (samePlain! root dir p) (sameFrom! root dir (optionOr (listTail deps) (list))))))

; (:m :ref LEON-JAIL-CLI-CACHE :do "the check nativeCli fresh? makes, without the clang version: every dependency of the entry exists in the root, outside any symlink, with the bytes of the entry's snapshot")
fn ! sourceMatches! root: String dir: String -> Bool
  (let [deps (if (stringEmpty? root) (list) (depsOf! dir))]
    (and (not (listEmpty? deps)) (sameFrom! root dir deps)))

; (:m :ref LEON-JAIL-CLI-CACHE :do "bin/asl's suspect, by lstat only: a dependency of the entry that is missing in the root, behind a symlink, not a regular file, or not older than the pointer (bin/asl -ot; ext4 stamps from a coarse clock, so a source written in the pointer's tick has its mtime, JAIL-SHARED-LINUX); an unreadable dependency list is suspect")
fn ! sourceSuspect! root: String dir: String stamp: Int64 -> Bool
  (let [deps (depsOf! dir)]
    (or (listEmpty? deps)
      (listAny? (fn [p] (let [rp (str root "/" p)]
                          (or (not (linkFree! root rp))
                            (match (fileLstat rp) ((ok st) (or (not st.isFile) (or st.isSymlink (>= st.mtimeNs stamp)))) ((err _) true)))))
        deps)))

; (:m :ref LEON-JAIL-CLI-CACHE :do "the gate of the re-seed, as data: nothing to follow is nothing to do; a missing private head, a shared pointer newer than it (a deploy moved it) or a private entry the root's sources moved past (bin/asl would take it as stale) is looked at again; anything else costs one stat per pointer")
fn resyncNeeded? privStamp: Int64 privSuspect: Bool cands: (List CliSource) -> Bool
  (and (not (listEmpty? cands)) (or (< privStamp 0) (or privSuspect (listAny? (fn [(c CliSource)] -> Bool (> c.stamp privStamp)) cands))))

fn newestOf cands: (List CliSource) -> (Option CliSource)
  (fold (fn [best c] (match best ((none) (some c)) ((some b) (if (> c.stamp b.stamp) (some c) best)))) (none) cands)

; (:m :ref LEON-JAIL-CLI-CACHE :do "what the private head becomes, as (cli dir, stamp), dir empty meaning keep the private entry: a private entry whose snapshot fits the root is kept and stamped now (the harness just made the check bin/asl's refresh would make); else the newest shared entry that fits, stamped now; else the head's own shared pointer with its mtime, as the first seed (an unmodified tree whose sources predate it runs it, a moved one is verified by the child); else the newest borrowed one with verifyStamp. So a worktree runs main's fresh build after a deploy when its CLI sources equal main's, keeps its own when they differ, and builds only when no entry anywhere fits")
fn pickSource privFits: Bool cands: (List CliSource) now: Int64 -> (Pair String Int64)
  (let [fit (newestOf (filter (fn [(c CliSource)] -> Bool c.fits) cands))
        own (listHead (filter (fn [(c CliSource)] -> Bool c.own) cands))
        newest (newestOf cands)]
    (if privFits
      (pair "" now)
      (match fit
        ((some f) (pair f.dir now))
        ((none) (match own
                  ((some o) (pair o.dir o.stamp))
                  ((none) (match newest ((some n) (pair n.dir (verifyStamp))) ((none) (pair "" now)))))))))

; (:m :ref LEON-JAIL-CLI-CACHE :do "the shared cli directory copied into the private cache under its own name, plain cp -Rp of a fresh private directory renamed into place; never a hard link, which would let the child rewrite the shared executable through the same inode. An existing private directory of that name is the earlier copy and is kept; one that is a symlink or not a directory is refused. Returns the reason it failed, empty on success")
fn ! cliCopy! dir: String dst: String -> String
  (let [name (lastSeg dir)
        to (str dst "/" name)]
    (match (fileLstat to)
      ((ok st) (cond (st.isSymlink "the private cli directory is a symlink") (st.isDir "") (else "the private cli path is not a directory")))
      ((err _)
        (let [tmp (str dst "/.seed-" (stringFromInt64 (monotonicNs)))
              why (cond
                    ((ok? (fileLstat tmp)) "the private seed directory already exists")
                    ((not (ok? (dirCreate tmp))) "the private seed directory was not created")
                    ((not (runBounded! (cliCopyArgv dir tmp))) "the cli directory was not copied")
                    ((not (ok? (pathRename (str tmp "/" name) to))) "the cli directory was not renamed into place")
                    (else ""))
              swept (if (and (!= why "the private seed directory already exists") (ok? (fileLstat tmp))) (ok? (pathRemove tmp)) true)]
          (if swept why (str why "; its partial copy was not removed"))))))

fn ! pointHead! dst: String head: String dir: String stamp: Int64 -> Bool
  (let [part (str dst "/.head-" (stringFromInt64 (monotonicNs)) ".part")]
    (and (not (ok? (fileLstat part)))
      (and (ok? (fileWrite part (str dst "/" (lastSeg dir) "\n")))
        (and (ok? (fileUtime part stamp)) (ok? (pathRename part (str dst "/" head)))))))

; (:m :ref LEON-JAIL-SHARED-CLI :do "the shared store is keyed by content, cli-<digest>, and its head pointers name only the newest entry per root: a writer branched from an older base has sources equal to an older entry no head names, and it rebuilt the CLI. When no head candidate fits, every other cli-* directory of the shared store (plain directories, at most scanCap, read-only) is checked against the root with sourceMatches! and the fitting ones become candidates, stamped with their directory mtime; the store is never written, the chosen entry is copied into the private cache as before and a root that fits none still builds privately")
fn scanCap -> Int64
  64

fn ! scanFits! src: String here: String skip: (List String) -> (List CliSource)
  (let [names (listTake (filter (fn [n] (stringStartsWith? n "cli-")) (resultOr (dirList src) (list))) (scanCap))
        dirs (filter (fn [d] (and (not (listContains? skip d)) (and (linkFree! src d) (match (fileLstat d) ((ok st) (and st.isDir (not st.isSymlink))) ((err _) false))))) (map (fn [n] (str src "/" n)) names))
        fit (filter (fn [d] (sourceMatches! here d)) dirs)]
    (map (fn [d] (CliSource :dir d :stamp (match (fileLstat d) ((ok st) st.mtimeNs) ((err _) -1)) :own false :fits true)) fit))

; (:m :ref LEON-JAIL-CLI-CACHE :do "one private head: the shared pointers it may follow are its own and, for the first head (the unit's own root, currentHeads), the tool root's; the private entry counts only when it is a plain cli directory inside the private cache. Returns resync when it moved the head, failed: <why>, or empty when nothing changed or the private entry was only restamped")
; (:m :ref LEON-STEP-BODY-LOST :do "root may name several roots, one per line: each head is checked against the root it is named after (head_X against the sources of X) and may borrow any other head's fitting entry, so a jail seeds both the tool root's head, which the jailed tool bin/asl reads, and a task root's own head where it has a bin/asl, which its gates and runs read (grader 2026-11-18 on 9424129aa: a worktree without its own shared head went to a cold build). A head no root is named after keeps the old rule: the first head is checked against the first root")
fn ! resyncHead! src: String dst: String heads: (List String) head: String root: String -> String
  (let [roots (filter (fn [r] (not (stringEmpty? r))) (stringSplit root "\n"))
        lead (= (optionOr (listHead heads) "") head)
        here (match (listFind (fn [r] (= (cliHeadName r) head)) roots) ((some r) r) ((none) (if lead (optionOr (listHead roots) "") "")))
        first (or lead (not (stringEmpty? here)))
        cands (filter (fn [(c CliSource)] -> Bool (not (stringEmpty? c.dir))) (cons (sourceOf! src head true) (if first (map (fn [o] (sourceOf! src o false)) (filter (fn [o] (!= o head)) heads)) (list))))
        priv (str dst "/" head)
        link (match (fileLstat priv) ((ok st) st.isSymlink) ((err _) false))
        privStamp (stampOf! priv)
        target (if (< privStamp 0) "" (firstLine (readPlain! priv 4096)))
        privDir (if (and (stringStartsWith? (lastSeg target) "cli-") (and (= target (str dst "/" (lastSeg target))) (and (linkFree! dst target) (dir? target)))) target "")
        privSuspect (and (not (stringEmpty? here)) (and (not (stringEmpty? privDir)) (sourceSuspect! here privDir privStamp)))]
    (cond
      (link "failed: a private head pointer is a symlink")
      ((not (resyncNeeded? privStamp privSuspect cands)) "")
      (else
        (let [privFits (and (not (stringEmpty? privDir)) (sourceMatches! here privDir))
              fitted (map (fn [(c CliSource)] -> CliSource (with c :fits (sourceMatches! here c.dir))) cands)
              more (if (or privFits (or (stringEmpty? here) (listAny? (fn [(c CliSource)] -> Bool c.fits) fitted))) (list) (scanFits! src here (map (fn [(c CliSource)] -> String c.dir) cands)))
              pick (pickSource privFits (listAppend fitted more) (nowNs))
              dir (pairFirst pick)
              stamp (pairSecond pick)]
          (cond
            ((stringEmpty? dir) (cond ((stringEmpty? privDir) "") ((pointHead! dst head privDir stamp) "") (else "failed: a private head pointer was not restamped")))
            ((and (= (lastSeg dir) (lastSeg target)) (= stamp privStamp)) "")
            (else (let [why (cliCopy! dir dst)]
                    (cond
                      ((not (stringEmpty? why)) (str "failed: " why))
                      ((pointHead! dst head dir stamp) "resync")
                      (else "failed: a private head pointer was not rewritten")))))))))

; (:m :ref LEON-JAIL-CLI-CACHE :do "the private native CLI cache follows the shared one on every jailed call, not only at the first seed: a deploy of main rebuilds the shared entry and moves its pointer, and a private pointer frozen at the first seed made every later jailed bin/asl rebuild the whole CLI (asl1 and cli, 10 to 25 minutes of clang per worktree) inside its jail. root is the unit's own root (empty: no source check). One outcome per head it moved: resync or failed: <why>; nothing when the private cache does not exist")
fn ! resyncCli! src: String dst: String heads: (List String) root: String -> (List String)
  (if (not (dir? dst))
    (list)
    (let [outcomes (filter (fn [w] (not (stringEmpty? w))) (map (fn [h] (resyncHead! src dst heads h root)) heads))
          pruned (if (listContains? outcomes "resync") (pruneCli! dst) 0)]
      outcomes))

; (:m :ref LEON-JAIL-CLI-CACHE :do "fix round L3: a copy of a cli directory is a clone where the platform has one (clonefile on macOS, reflink where the file system offers it, plain copy otherwise), never a hard link, which would let the child rewrite the shared executable through the same inode")
fn cliCopyArgv from: String to: String -> (List String)
  (if (file? "/usr/bin/sandbox-exec") (list "/bin/cp" "-cRp" from to) (list "cp" "-Rp" "--reflink=auto" from to))

; (:m :ref LEON-JAIL-CLI-CACHE :do "fix round L3: after a re-seed moved a head, every private cli-* entry no private head pointer names is removed: each re-seed after a deploy left one copy behind per jail home (about 49M each). Only direct children of the private cache, whose path the caller found symlink-free; a planted symlink is unlinked, never followed (pathRemove does not follow links). Returns the number removed")
fn ! pruneCli! dst: String -> Int64
  (let [names (resultOr (dirList dst) (list))
        kept (map (fn [h] (lastSeg (firstLine (readPlain! (str dst "/" h) 4096)))) (filter (fn [n] (stringStartsWith? n "head")) names))
        stale (filter (fn [n] (and (stringStartsWith? n "cli-") (not (listContains? kept n)))) names)]
    (fold (fn [acc n] (if (ok? (pathRemove (str dst "/" n))) (+ acc 1) acc)) 0 stale))

; (:m :ref JAIL-LINUX :do "the private pointer names the private copy, and keeps the shared pointer's mtime: bin/asl calls the CLI stale when a source is newer than the pointer, and a pointer written now would hide that")
fn ! repoint! src: String tmp: String dst: String head: String dir: String -> Bool
  (match (fileStat (str src "/" head))
    ((err _) false)
    ((ok st) (and (ok? (fileWrite (str tmp "/" head) (str dst "/" (lastSeg dir) "\n"))) (ok? (fileUtime (str tmp "/" head) st.mtimeNs)))))

; (:m :ref JAIL-LINUX :do "a private cache is seeded when it is missing or empty: a gate or run env created it empty before the first asl op")
fn ! seedable? dst: String -> Bool
  (match (fileStat dst)
    ((err _) true)
    ((ok _) (listEmpty? (resultOr (dirList dst) (list "x")))))

; (:m :ref LEON-JAIL-CLI-CACHE :do "why one head pointer of the shared cache names no cli directory, so a failed seed names the check that refused it: the pointer file is missing, a symlink, not a regular file or empty; or the path it holds is not a cli-* name, not a plain directory, or does not resolve directly inside the shared cache")
fn ! headWhy! src: String head: String -> String
  (let [p (str src "/" head)
        ptr (firstLine (readPlain! p 4096))
        why (match (fileLstat p)
              ((err _) "no such pointer file")
              ((ok st)
                (cond
                  (st.isSymlink "the pointer file is a symlink")
                  ((not st.isFile) "the pointer file is not a regular file")
                  ((stringEmpty? ptr) "the pointer file is empty or over 4096 bytes")
                  ((not (stringStartsWith? (lastSeg ptr) "cli-")) (str "names " ptr ", not a cli-* directory"))
                  ((not (match (fileLstat ptr) ((ok d) (and d.isDir (not d.isSymlink))) ((err _) false))) (str "names " ptr ", not a plain directory"))
                  ((!= (realOr! ptr) (str (realOr! src) "/" (lastSeg ptr))) (str "names " ptr ", which resolves to " (realOr! ptr) ", not inside " (realOr! src)))
                  (else "names a cli directory"))))]
    (str head ": " why))

; (:m :ref JAIL-LINUX :do "D2: the active entry of the shared native CLI cache, plain cp -Rp (about 56M): every head pointer file, and the cli directory of each pointer in heads, which is then repointed at the copy; the other pointers keep naming the shared cache, which the jail reads. Built under a private name and renamed into place; returns the reason it failed, empty on success, and a failed seed leaves nothing behind")
fn ! seedCliEntry! src: String dst: String heads: (List String) -> String
  (let [tmp (str dst ".seed-" (stringFromInt64 (monotonicNs)))
        names (filter (fn [n] (and (stringStartsWith? n "head") (plainFile? (str src "/" n)))) (resultOr (dirList src) (list)))
        live (filter (fn [p] (not (stringEmpty? (pairSecond p)))) (map (fn [h] (pair h (cliDirOf! src h))) (filter (fn [h] (listContains? names h)) heads)))
        why (cond
              ((listEmpty? live) (str "no head pointer of this root names a cli directory in the shared cache (" (stringJoin (map (fn [h] (headWhy! src h)) heads) "; ") ")"))
              ((ok? (fileLstat tmp)) "the private seed directory already exists")
              ((not (ok? (dirCreate tmp))) "the private cache directory was not created")
              ((not (runBounded! (listAppend (cons "cp" (cons "-p" (map (fn [n] (str src "/" n)) names))) (list tmp)))) "the head pointers were not copied")
              ((not (listAll? (fn [d] (runBounded! (cliCopyArgv d tmp))) (dedupe (map pairSecond live) (list)))) "the cli directory was not copied")
              ((not (listAll? (fn [p] (repoint! src tmp dst (pairFirst p) (pairSecond p))) live)) "a head pointer was not rewritten")
              ((not (ok? (pathRename tmp dst))) "the seeded cache was not renamed into place")
              (else ""))
        swept (if (or (stringEmpty? why) (or (= why "the private seed directory already exists") (not (ok? (fileLstat tmp))))) true (ok? (pathRemove tmp)))]
    (if swept why (str why "; its partial copy was not removed")))

; (:m :ref FABLE-BLIND-03 :do "a private cache that does not exist yet starts as a clone of its shared source, so the first asl run of a unit is warm; the clone lands under a private name and is renamed into place, a failed clone is removed; the corpus cache is not seeded. JAIL-LINUX D2: kind is how the machine clones (cloneKind!), passed as data so the no-clone path runs on any file system; returns one (cache name, outcome) row per cache it tried: clone, cliEntry, cold, or failed: <why>")
fn ! seedCachesWith! kind: String home: String sources: (List (Pair String String)) heads: (List String) root: String -> (List (Pair String String))
  (fold (fn [acc r]
          (let [name (pairFirst r)
                dst (str home (pairSecond r))
                src (optionOr (listHead (map pairSecond (filter (fn [s] (= (pairFirst s) name)) sources))) "")]
            (cond
              ((or (stringEmpty? src) (not (listContains? (seededNames) name))) acc)
              ((not (linkFree! home dst)) (listAppend acc (list (pair name "failed: a symlink in the private cache path"))))
              (else
                (let [seededRows (if (seedable? dst) (list (pair name (seedOne! kind name src dst heads))) (list))
                      again (if (and (= name "ASL_NATIVE_CLI_CACHE") (not (listAny? seedFailed? seededRows))) (map (fn [w] (pair name w)) (resyncCli! src dst heads root)) (list))]
                  (listAppend acc (listAppend seededRows again)))))))
    (list) (jailCacheRows))

fn ! seedOne! kind: String name: String src: String dst: String heads: (List String) -> String
  (let [tmp (str dst ".seed-" (stringFromInt64 (monotonicNs)))
        parent (dirCreate (parentOf dst))
        cloned (and (!= kind "none") (and (!= name "ASL_NATIVE_CLI_CACHE") (and (not (ok? (fileLstat tmp))) (and (runBounded! (cloneArgv kind src tmp)) (ok? (pathRename tmp dst))))))
        swept (if (or cloned (not (ok? (fileStat tmp)))) true (ok? (pathRemove tmp)))
        how (seedHow kind cloned name)
        why (if (= how "cliEntry") (seedCliEntry! src dst heads) "")]
    (cond
      ((not swept) "failed: a partial clone was not removed")
      ((stringEmpty? why) how)
      (else (str "failed: " why))))

fn seedFailed? row: (Pair String String) -> Bool
  (stringStartsWith? (pairSecond row) "failed")

; (:m :ref JAIL-LINUX :do "D2: a seed outcome is never dropped: every row goes to <jail home>/.asl/seedReport.asn, and a failed one also to the harness's stderr as one line naming the cache and the reason (no path, no env value)")
fn seedReportText rows: (List (Pair String String)) -> String
  (stringJoin (map (fn [r] (str "(:seed :cache \"" (pairFirst r) "\" :how \"" (pairSecond r) "\")\n")) rows) "")

; (:m :ref LEON-JAIL-CLI-CACHE :do "the report keeps every row: the first seed's, then each re-seed of a later call, appended; written only where no symlink lies on its path (JAIL-SEED-SYMLINK)")
fn ! seedReport! home: String rows: (List (Pair String String)) -> Bool
  (if (listEmpty? rows)
    true
    (let [path (str home "/.asl/seedReport.asn")
          before (readPlain! path (depsCap))
          wrote (and (linkFree! home path) (and (ok? (dirCreate (str home "/.asl"))) (ok? (fileWrite path (str before (seedReportText rows))))))]
      (do
        (map (fn [r] (eprintln (str "(:leon :seed :cache \"" (pairFirst r) "\" :how \"" (pairSecond r) "\")"))) (filter seedFailed? rows))
        (if wrote true (do (eprintln "(:leon :seed :failed \"the seed report was not written\")") false)))))

; (:m :ref JAIL-LINUX :do "the clone probe runs only when some cache is still to be seeded; jailCacheEnv! creates every private directory right after, so a jail home is seeded once. LEON-JAIL-CLI-CACHE: the native CLI cache is re-seeded on every call (seedCachesWith!, resyncCli!), which needs no clone kind")
fn ! seedCaches! home: String sources: (List (Pair String String)) heads: (List String) root: String -> (List (Pair String String))
  (if (listAny? (fn [r] (and (listContains? (seededNames) (pairFirst r)) (and (listAny? (fn [s] (= (pairFirst s) (pairFirst r))) sources) (seedable? (str home (pairSecond r)))))) (jailCacheRows))
    (seedCachesWith! (cloneKind! home) home sources heads root)
    (seedCachesWith! "none" home sources heads root))

; (:m :ref LEON-RUN-HOME-JAIL :do "B-02: the child env is an allowlist, not the parent env minus a few names: of the inherited rows only the names passName? knows pass, so provider keys and ASL_ settings never reach a unit child; the rows the harness sets (PWD, HOME, TMPDIR, the private cache directories) are added after, and the names the run hides are dropped last. seed true clones the shared caches into the private ones first; they hold tens of thousands of files inside the root, so <jail home>/.asl then carries a .gitignore of * and the run snapshot (git ls-files of untracked files) never walks them. JAIL-SEED-SYMLINK: where a symlink lies on the jail home's path inside the root, the harness creates, seeds and writes nothing there and says so on stderr; the rows are the same, and jailPlan! grants no home outside the root")
; (:m :ref LEON-STEP-BODY-LOST :do "the root a jail's CLI head is checked against is the tool root the harness runs (the inherited ASL_CLI_ROOT row), not the task root: a task with its own repository (a test fixture, a consumer project such as vtbot) runs the tool root's bin/asl, and checking that head against the task root, which has none of the CLI's sources, left its private pointer at the shared mtime, so bin/asl saw sources newer than it and rebuilt the CLI in the jail (grader 2026-11-18, 263 s, ERR_NATIVE_STALE); with no ASL_CLI_ROOT the task root is the tool root, as before")
fn ! seedRoot! absRoot: String inherited: (List String) -> String
  (let [tool (rowValue inherited "ASL_CLI_ROOT")]
    (realOr! (if (stringEmpty? tool) absRoot tool)))

fn ! childEnvIn! absRoot: String inherited: (List String) hidden: (List String) realHome: String seed: Bool -> (List String)
  (let [home (jailHome absRoot)
        free (listAll? (fn [p] (linkFree! absRoot (str home p))) (list "/tmp" "/.asl/seedReport.asn" "/.asl/.gitignore"))
        said (if free true (do (eprintln "(:leon :seed :failed \"a symlink lies on the jail home path; nothing was created or seeded there\")") false))
        tmpFree (linkFree! "/tmp" (jailTmp absRoot))
        madeTmp (if tmpFree (ok? (dirCreate (jailTmp absRoot))) false)
        made (and free (and (ok? (dirCreate home)) (ok? (dirCreate (str home "/tmp")))))
        kept (filter (fn [r] (passName? (envKey r))) inherited)
        toolRoot (seedRoot! absRoot inherited)
        taskRoot (realOr! absRoot)
        sources (if (and seed free) (cacheSources! inherited realHome) (list))
        cliSrc (match (listFind (fn [p] (= (pairFirst p) "ASL_NATIVE_CLI_CACHE")) sources) ((some p) (pairSecond p)) ((none) ""))
        heads0 (dedupe (cons (cliHeadName toolRoot) (currentHeads taskRoot inherited)) (list))
        hasOwnHead (and (not (stringEmpty? cliSrc)) (listAny? (fn [h] (not (stringEmpty? (cliDirOf! cliSrc h)))) heads0))
        envCliRaw (optionOr (envGet "ASL_CLI_ROOT") "")
        envCli (if (stringEmpty? envCliRaw) "" (realOr! envCliRaw))
        useEnvCli (and (not hasOwnHead) (and (not (stringEmpty? envCli)) (and (!= envCli toolRoot) (and (!= envCli taskRoot) (and (not (stringEmpty? cliSrc)) (not (stringEmpty? (cliDirOf! cliSrc (cliHeadName envCli)))))))))
        heads (if useEnvCli (listAppend heads0 (list (cliHeadName envCli))) heads0)
        roots0 (if (and (!= taskRoot toolRoot) (file? (str taskRoot "/bin/asl"))) (str toolRoot "\n" taskRoot) toolRoot)
        roots (if useEnvCli (str roots0 "\n" envCli) roots0)
        seeded (if (and seed free) (seedCaches! home sources heads roots) (list))
        reported (seedReport! home seeded)
        ignore (str home "/.asl/.gitignore")
        ignored (if (and (and seed free) (not (file? ignore))) (and (ok? (dirCreate (str home "/.asl"))) (ok? (fileWrite ignore "*\n"))) true)
        caches (jailCacheEnv! absRoot home)
        own (listAppend caches (list (str "PWD=" absRoot) (str "HOME=" home) (str "TMPDIR=" (jailTmp absRoot)) "PYTHONDONTWRITEBYTECODE=1"))]
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

; (:m :ref LEON-RUN-HOME-JAIL :do "the jail of one child: writes are the root, the jail home (its private caches inside) and the scratch directories the harness adds; reads under the real HOME are those plus the shared repository, the tool root, the shared caches (read-only) and the PATH entries that live there; the root's ancestors up to the real HOME are listable (path and import resolution list them; without that an asl test in the jail cannot stage its sources) but their other children are not readable. JAIL-SEED-SYMLINK: the jail home is granted only where its real path lies inside the root; a symlink the unit planted at <root>/.asl/run/agentLoop/home (or above it) pointing at the real HOME's .asl would otherwise make keys.env and gateway.asn readable and writable")
fn ! signalEnvFor! tool: String -> String
  (cond
    ((or (stringEmpty? tool) (= tool "sandbox-exec")) "")
    ((envSignals! "/usr/bin/env") "/usr/bin/env")
    (else (do (eprintln "(:leon :jail :warn \"env lacks --ignore-signal/--default-signal: a bwrap child is not shielded from TERM, so a child that ignores TERM dies with its supervisor\")") "")))

fn ! jailPlan! tool: String lexicalOnly: Bool root: String home: String envRows: (List String) extraReads: (List String) extraWrites: (List String) net: Bool realHomeRaw: String sources: (List String) -> Jail
  (let [mode (jailMode tool lexicalOnly)]
    (if (!= mode "os")
      (with (lexicalJail root net) :mode mode :why (if (= mode "refused") "no OS sandbox applies here (sandbox-exec, bwrap) and <HOME>/.asl/config.asn has no :agentLoop (:jailLexicalOnly true)" ""))
      (let [rroot (realOr! root)
            realHome (if (stringEmpty? realHomeRaw) "" (realOr! realHomeRaw))
            pathRow (optionOr (listHead (filter (fn [r] (= (envKey r) "PATH")) envRows)) "")
            pathDirs (filter (fn [d] (under? d realHome)) (map realOr! (filter dir? (stringSplit (envValue pathRow) ":"))))
            homeReal (realOr! home)
            writes (dedupe (listAppend (cons rroot (if (under? homeReal rroot) (list homeReal) (list))) (map realOr! (filter dir? (cons (jailTmp rroot) extraWrites)))) (list))
            reads (dedupe (listAppend (listAppend (listAppend (commonGit! rroot) (map realOr! (filter dir? extraReads))) (map realOr! (filter dir? sources))) pathDirs) (list))
            lists (if (and (under? rroot realHome) (!= rroot realHome)) (cons realHome (ancestorsIn rroot realHome (list))) (list))]
        (Jail :mode "os" :tool tool :root rroot :writes writes :reads reads :lists lists :realHome realHome :net net :signalEnv (signalEnvFor! tool)))))

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
        git (if (or (dir? dotGit) (file? dotGit)) (list "--ro-bind" dotGit dotGit) (list))
        parentReads (filter (fn [r] (and (not (stringEmpty? j.realHome)) (and (!= r j.realHome) (under? j.realHome r)))) j.reads)
        innerReads (filter (fn [r] (not (listContains? parentReads r))) j.reads)]
    (listAppend (list j.tool "--die-with-parent" "--unshare-pid" "--ro-bind" "/" "/" "--dev" "/dev" "--proc" "/proc" "--tmpfs" "/tmp" "--tmpfs" "/run")
      (listAppend resolve
        (listAppend (flagPairs "--ro-bind" parentReads)
          (listAppend hide
            (listAppend (flagPairs "--ro-bind" innerReads)
              (listAppend (flagPairs "--bind" j.writes)
                (listAppend git
                  (listAppend seal
                    (listAppend (if j.net (list) (list "--unshare-net")) (list "--chdir" j.root "--")))))))))))

; (:m :ref FABLE-BLIND-03 :do "what runs in place of a refused child: one line naming the refusal and exit 126, so every caller of jailWrap! fails closed whether or not it reads the mode")
fn absentNote j: Jail -> String
  (str "ERR_RUN_SANDBOX_ABSENT: not run, " j.why "; a unit process runs only inside an OS sandbox")

fn refusedArgv j: Jail -> (List String)
  (list "/bin/sh" "-c" "printf '%s\\n' \"$1\" >&2; exit 126" "sh" (absentNote j))

; (:m :ref AGENT-LINUX-REDS-2 :do "bwrap is the process the harness signals and it dies of SIGTERM at once, taking a child that ignores TERM down with it by its death signal, so a kill never reached its KILL step; bwrap now ignores TERM (env --ignore-signal) and the child gets the default again (env --default-signal), so TERM reaches the child alone and a child that survives it meets KILL as under sandbox-exec")
; (:m :ref AGENT-LINUX-REDS-2 :do "the TERM wrapper needs an env that knows --ignore-signal and --default-signal (coreutils 8.31); probed by running it, and a bwrap jail on an env without them keeps the plain argv and says so once on stderr")
fn ! envSignals! envPath: String -> Bool
  (probe! (list envPath "--ignore-signal=TERM" "--default-signal=TERM" "true"))

fn ! jailWrap! j: Jail argv: (List String) -> (List String)
  (cond
    ((= j.mode "lexical") argv)
    ((!= j.mode "os") (refusedArgv j))
    ((= j.tool "sandbox-exec") (listAppend (list "/usr/bin/sandbox-exec" "-p" (seatbeltProfile j)) argv))
    ((stringEmpty? j.signalEnv) (listAppend (bwrapArgs j) argv))
    (else (listAppend (list j.signalEnv "--ignore-signal=TERM") (listAppend (bwrapArgs j) (cons j.signalEnv (cons "--default-signal=TERM" argv))))))

; (:m :ref LEON-RUN-HOME-JAIL :do "what a sandbox refusal looks like in a child's output: EPERM from seatbelt, EROFS from a read-only bind")
fn denialText? text: String -> Bool
  (or (stringContains? text "Operation not permitted") (stringContains? text "Read-only file system"))

fn sandboxNote j: Jail -> String
  (str "the OS sandbox refused an operation: a unit process may write only under :root (its .git excluded) and its scratch HOME, cannot read the real HOME, its temporary files go under $TMPDIR (the shared /tmp is not writable), it has no ps and cannot signal a process outside its own tree"
    (if j.net "" ", and has no network beyond loopback unless the unit declares :net true"))

fn ! sameBytes! a: String b: String -> Bool
  (match (fileReadBytes a)
    ((err _) false)
    ((ok x) (match (fileReadBytes b) ((err _) false) ((ok y) (= x y)))))
