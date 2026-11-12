(module asl-cli/nativeCli
  :x [kwPrev? plainArg? cacheDir! headPath toolchainRootPaths rootsText pinned? relayPinned? formsPinned? formsOnly? formsPinOn? underRoot clangFacts! clangCommand! clangFor! clangCandidates clangPick configClang configNative nearestConfigText! clangOnPathIn! fresh? probe? alive? verbKind nativeGate! hostEntry! pruneEntries! pruneNativeCache! StoreEntry storeEntry! sweepEntries! treeBytes! headRoot! sweepNativeCache! entryStamp! treeStamp! leaseEntry! dropLeases! sharedFloorNs]
  :i [(asl/packages/asl-cli/src/system :a sys) (asl-tools/fleet/run :a run) (asl-parser/reader :a rd)])

fn ! cacheDir! -> String
  (let [(configured (optionOr (envGet "ASL_NATIVE_CLI_CACHE") ""))
        (home (optionOr (envGet "HOME") ""))]
    (cond
      ((not (stringEmpty? configured)) configured)
      ((stringEmpty? home) "/tmp/.asl/run/nativeCli")
      (else (str home "/.asl/run/nativeCli"))))

fn headPath cache: String root: String -> String
  (str cache "/head" (stringReplace root "/" "_"))

fn verbKind args: (List String) -> String
  (let [(verb (optionOr (listHead args) "help"))]
    (cond
      ((or (listContains? (list "run" "test" "parse" "eval" "launch" "check" "pkg" "-e") verb) (or (stringEndsWith? verb ".asl") (stringContains? verb "/"))) "native")
      ((or (stringStartsWith? verb "(")
           (or (stringStartsWith? verb ":")
               (listContains? (list "rpc" "intel" "coupling" "graph" "complexity" "vitality" "full" "stubs" "trace"
                                     "crawler" "crawl" "engine" "mesh" "train" "timeout" "version" "-v" "--version"
                                     "build" "audit" "pack" "target" "vcs" "help" "-h" "--help"
                                     "note" "doc" "heal" "lens" "consilium" "browser" "web" "search" "research"
                                     "gateway" "relay" "rla" "mem" "tool" "lint" "gate" "-" "-f") verb)))
        "forms")
      (else "host")))

fn ! direct? -> Bool
  (= (optionOr (envGet "ASL_CLI_ENTRY_PID") "") (stringFromInt64 (procSelf)))

fn underRoot root: String path: String -> String
  (if (stringStartsWith? path "/") path (str root "/" path))

fn ! sameBytes? a: String b: String -> Bool
  (match (fileReadBytes a)
    ((err _) false)
    ((ok x) (match (fileReadBytes b) ((err _) false) ((ok y) (= x y)))))

fn ! allSame? root: String dir: String paths: (List String) -> Bool
  (match (listHead paths)
    ((none) true)
    ((some p) (if (sameBytes? (underRoot root p) (str dir "/src/" p)) (allSame? root dir (optionOr (listTail paths) (list))) false)))

fn ! shQuote s: String -> String
  (str "'" (stringReplace s "'" "'\\''") "'")

fn ! boundedCapture! cmd: String timeoutMs: Int64 -> sys/Captured
  (match (processSpawn cmd)
    ((err e) (sys/Captured :exitCode 127 :stdout "" :stderr e))
    ((ok h) (match (processWait h timeoutMs)
              ((err e) (sys/Captured :exitCode 127 :stdout "" :stderr e))
              ((ok o) (sys/Captured :exitCode o.exitCode :stdout o.stdout :stderr o.stderr)))))

; (:m :ref BIN-ASL-FORKS :do "the warm path needs clang's version and target triple on every call (the CLI freshness gate, the nativeTest fingerprint); spawning clang for them forks, so where no child can start (ulimit -u, a full process table) a warm call failed. The facts are recorded once per clang identity, the stat of the clang command and of the Xcode toolchain it dispatches to plus CLANG, DEVELOPER_DIR and the xcode-select link, and read back without a spawn; an unreadable record spawns clang as before and a failed spawn records nothing")
; (:m :ref CLI-CLANG-PROBE :do "one clang for every native step: the :native :clang row of the nearest .asl.config.asn or ~/.asl/config.asn, else CLANG, else the first of clang, clang-19 .. clang-15 on PATH (build.sh's probe order; a distro may ship only clang-18). A row or CLANG is taken as given. ASL has no process-global state, so each call resolves again: a substring test of the config text and at most six names per PATH entry, no fork")
fn clangCandidates -> (List String)
  (list "clang" "clang-19" "clang-18" "clang-17" "clang-16" "clang-15")

fn rowAfter items: (List rd/SExpr) key: String -> (Option rd/SExpr)
  (match (listHead items)
    ((none) (none))
    ((some h) (if (and (rd/isAtom? h) (= (rd/sexprHead h) key)) (listGet items 1) (rowAfter (optionOr (listTail items) (list)) key))))

; (:m :ref LLVM-NODE2-REDS :do "the :native row names any tool by key, :clang and now :llc :opt :wasmLd :llvmNm :node, so a test resolves its tool the way the native steps resolve clang")
fn configNative text: String key: String -> (Option String)
  (if (not (stringContains? text (str ":" key)))
    (none)
    (match (rowAfter (rd/sexprToList (rd/parseSexpr text)) ":native")
      ((none) (none))
      ((some native) (match (rowAfter (rd/sexprToList native) (str ":" key))
                       ((some v) (if (rd/isAtom? v) (let [(w (stringReplace (rd/sexprHead v) "\"" ""))] (if (stringEmpty? w) (none) (some w))) (none)))
                       ((none) (none))))))

fn configClang text: String -> (Option String)
  (configNative text "clang")

fn ! clangOnPathIn! pathVar: String -> (List String)
  (filter (fn [(c String)] -> Bool
            (fold (fn [(acc Bool) (d String)] -> Bool
                    (or acc (let [(p (str (if (stringEmpty? d) "." d) "/" c))] (and (sys/isFile? p) (sys/executable? p)))))
                  false (stringSplit pathVar ":")))
          (clangCandidates))

fn clangPick row: (Option String) envClang: (Option String) found: (List String) -> (Result String String)
  (let [(given (filter (fn [(c String)] -> Bool (not (stringEmpty? c))) (listAppend (optionOr (optionMap (fn [(r String)] -> (List String) (list r)) row) (list))
                                                                                   (optionOr (optionMap (fn [(c String)] -> (List String) (list c)) envClang) (list)))))]
    (match (listHead (listAppend given found))
      ((some c) (ok c))
      ((none) (err (str "no clang: no :native :clang row in .asl.config.asn or ~/.asl/config.asn, CLANG unset, and none of " (stringJoin (clangCandidates) " ") " on PATH; install clang or set one of them")))))

fn ! nearestConfigText! dir: String -> String
  (let [(cfg (str dir "/.asl.config.asn"))]
    (cond
      ((fileExists? cfg) (resultOr (fileReadString cfg) ""))
      ((or (stringEmpty? dir) (= dir "/")) "")
      (else (nearestConfigText! (sys/parentOf dir)))))

fn ! clangFor! dir: String -> (Result String String)
  (let [(home (optionOr (envGet "HOME") ""))
        (row (match (configClang (nearestConfigText! dir))
               ((some r) (some r))
               ((none) (if (stringEmpty? home) (none) (configClang (resultOr (fileReadString (str home "/.asl/config.asn")) ""))))))
        (envClang (envGet "CLANG"))]
    (clangPick row envClang (if (or (some? row) (some? envClang)) (list) (clangOnPathIn! (optionOr (envGet "PATH") "")))))

; (:m :ref CLI-CLANG-PROBE :do "the clang a native step spawns, resolved from the cwd; when nothing resolves the bare name stays, so the spawn fails and clangFor!'s error is what a caller that checks reports")
fn ! clangCommand! -> String
  (resultOr (clangFor! (resultOr (realPath ".") ".")) "clang")

fn ! statStamp path: String -> String
  (match (fileStat path)
    ((ok st) (str path " " (stringFromInt64 st.size) " " (stringFromInt64 st.mtimeNs)))
    ((err _) (str path " absent")))

fn ! clangIdentity! -> String
  (let [(cmd (clangCommand!))
        (found (if (stringContains? cmd "/") cmd (optionOr (sys/onPath! cmd) cmd)))
        (developer (optionOr (envGet "DEVELOPER_DIR") (resultOr (realPath "/var/db/xcode_select_link") "")))]
    (stringJoin (list (str "CLANG=" cmd) (str "DEVELOPER_DIR=" developer)
                      (statStamp found) (statStamp (resultOr (realPath found) found))
                      (statStamp (str developer "/Toolchains/XcodeDefault.xctoolchain/usr/bin/clang"))
                      (statStamp (str developer "/usr/bin/clang")))
                "\n"))

fn ! firstLine! cmd: String -> (Option String)
  (let [(o (boundedCapture! cmd 10000))
        (line (stringTrim (optionOr (listHead (stringLines o.stdout)) "")))]
    (if (and (= o.exitCode 0) (not (stringEmpty? line))) (some line) (none)))

; (:m :ref TOOLCACHE-SANDBOX :do "clang facts are the one thing a native asl test writes under HOME/.asl/run; where that is read-only (a sandboxed caller) they are kept under $TMPDIR/asl-cache-home-<sha16 of HOME>/clang instead, no fork on the warm path, so the facts are not recomputed with clang on every call")
fn ! factsDirs! -> (List String)
  (let [(tmp (optionOr (envGet "TMPDIR") "/tmp"))
        (base (if (stringEndsWith? tmp "/") (optionOr (stringSlice tmp 0 (- (stringLength tmp) 1)) tmp) tmp))
        (id (optionOr (stringSlice (bytesSha256 (stringToBytes (optionOr (envGet "HOME") ""))) 0 16) "x"))]
    (list (str (cacheDir!) "/clang") (str base "/asl-cache-home-" id "/clang")))

fn ! recordClangIn! dirs: (List String) name: String version: String triple: String lastErr: String -> Bool
  (match (listHead dirs)
    ((none) (sys/sayErr! (str "asl: cannot record clang facts at " name ": " lastErr)))
    ((some dir)
      (let [(made (dirCreate dir))
            (path (str dir "/" name))
            (part (str path ".part." (stringFromInt64 (procSelf))))]
        (match (fileWrite part (str version "\n" triple "\n"))
          ((err e) (recordClangIn! (optionOr (listTail dirs) (list)) name version triple (str e (match made ((err m) (str " (" m ")")) ((ok _) "")))))
          ((ok _) (match (pathRename part path)
                    ((err e) (let [(gone (pathRemove part))]
                               (sys/sayErr! (str "asl: cannot record clang facts at " path ": " e (if (err? gone) (str "; " part " stays") "")))))
                    ((ok _) true)))))))

fn ! recordedFacts! dirs: (List String) name: String -> (List String)
  (match (listHead dirs)
    ((none) (list))
    ((some dir)
      (let [(recorded (filter (fn [(l String)] -> Bool (not (stringEmpty? l))) (stringLines (resultOr (fileReadString (str dir "/" name)) ""))))]
        (if (= (listLength recorded) 2) recorded (recordedFacts! (optionOr (listTail dirs) (list)) name)))))

fn ! clangFacts! -> (List String)
  (let [(name (bytesSha256 (stringToBytes (clangIdentity!))))
        (recorded (recordedFacts! (factsDirs!) name))]
    (if (= (listLength recorded) 2)
      recorded
      (let [(q (shQuote (clangCommand!)))]
        (match (firstLine! (str q " --version"))
          ((none) (list))
          ((some version) (match (firstLine! (str q " -dumpmachine"))
                            ((none) (list))
                            ((some triple) (do (recordClangIn! (factsDirs!) name version triple "") (list version triple)))))))))

fn ! fresh? root: String dir: String -> Bool
  (if (or (stringEmpty? dir) (not (sys/executable? (str dir "/bin"))))
    false
    (match (fileReadString (str dir "/clang-version"))
      ((err _) false)
      ((ok expected) (let [(actual (optionOr (listHead (clangFacts!)) ""))]
        (and (not (stringEmpty? actual))
          (and (= (stringTrim expected) actual)
            (match (fileReadString (str dir "/deps"))
              ((err _) false)
              ((ok text) (let [(paths (filter (fn [(p String)] -> Bool (not (stringEmpty? p))) (stringLines text)))]
                           (if (listEmpty? paths) false (allSame? root dir paths)))))))))))

; (:m :ref INTEG9-F1 :do "the self-probe runs asl test with --jobserverDir none: an internal check of the binary takes no machine-wide token and so writes nothing under HOME, which a dry-run install of a fresh root must leave unchanged")
fn ! probe? root: String dir: String -> Bool
  (let [(cmd (str "cd " (shQuote root) " && ASL_CLI_ROOT=" (shQuote root) " ASL_CLI_SCRIPT_DIR=" (shQuote (str root "/bin")) " ASL_CLI_ARGV0=" (shQuote (str root "/bin/asl")) " ASL_CLI_ENTRY_PID=$$ ASL_NATIVE_CLI_DIR=" (shQuote dir) " ASL_NATIVE_QUIET_PID=$$ exec " (shQuote (str dir "/bin")) " test --jobserverDir none " (shQuote (str root "/asl/packages/asl-cli/tests/fixtures/sweep/passTest.asl"))))
        (result (boundedCapture! cmd 30000))]
    (if (and (= result.exitCode 0)
          (and (stringContains? result.stdout "passTest.asl: 1 assertion(s) executed") (not (stringContains? result.stdout "asl-host"))))
      true
      (do (sys/sayErr! (str "native CLI self-probe: exit=" (stringFromInt64 result.exitCode) " stdout=" result.stdout " stderr=" result.stderr)) false)))

fn envName row: String -> String
  (match (stringIndexOf row "=") ((some i) (optionOr (stringSlice row 0 i) row)) ((none) row))

fn ! execWith! argv: (List String) drop: (List String) extra: (List String) -> Int64
  (let [(names (listAppend drop (map envName extra)))
        (kept (filter (fn [(row String)] -> Bool (not (listContains? names (envName row)))) (envList)))]
    (match (procExecv argv (some (listAppend kept extra)))
      ((ok _) 0)
      ((err e) (do (sys/sayErr! (str "asl: cannot exec " (optionOr (listHead argv) "") ": " e)) (if (= e "notFound") 127 126)))))

fn ! hostExec! ctx: sys/Context args: (List String) extra: (List String) -> Int64
  (if (sys/executable? ctx.hostBin)
    (execWith! (listAppend (list ctx.hostBin "run" (str ctx.root "/asl/packages/asl-cli/src/command.asl")) args) (list "ASL_NATIVE_CLI_DIR" "ASL_NATIVE_QUIET_PID") extra)
    (do (sys/say! "(:asl :status :failed :error ERR_HOST_ABSENT :message \"asl runs on the stage-0 host at asl/host/out/asl-host; build it with sh asl/host/build.sh or set ASL_HOST\")") 2))

; (:m :ref MAC-CLI-REBUILD-STALL :do "the sources whose bytes key the native compile cache (nativeTest fingerprints exactly these); every CLI dir carries them, with its entry's package, as its roots file, written by the build that made it")
fn toolchainRootPaths -> (List String)
  (list "asl/packages/asl-compiler/src" "asl/packages/asl-checker/src" "asl/packages/asl-codegen/src" "asl/packages/asl-ir/src"
        "asl/packages/asl-parser/src" "asl/packages/asl-syntax/src/core" "asl/packages/asl-target-llvm/src"
        "asl/host/out/libaslrt.a" "asl/host/out/prelude.asl" "asl/prelude/prelude.asl" "asl/prelude/native" "asl/tools/nativeTest.asl")

fn rootsText entry: String -> String
  (let [(parts (stringSplit entry "/"))
        (pkg (if (and (>= (listLength parts) 3) (= (optionOr (listGet parts 1) "") "packages")) (stringJoin (listTake parts 3) "/") entry))]
    (str (stringJoin (listAppend (toolchainRootPaths) (list pkg)) "\n") "\n"))

fn ! mtimeOf path: String -> Int64
  (match (fileStat path) ((ok st) st.mtimeNs) ((err _) 0))

fn under? path: String roots: (List String) -> Bool
  (listAny? (fn [(r String)] -> Bool (or (= path r) (stringStartsWith? path (str r "/")))) roots)

; (:m :ref MAC-CLI-REBUILD-STALL :do "run tools/remote/vps.asl keeps the current CLI without the lock when every dep that moved since the head lies outside the roots its build wrote: such an edit changes neither what the CLI compiles (the compile cache key) nor its own package; no roots file, no deps, a missing dep or a moved path under a root is not pinned, and the next unpinned call refreshes; aslNativeBuild refresh and the native CLI's own stale gate both ask it")
fn ! pinned? root: String dir: String stampPath: String cmd: (List String) -> Bool
  (let [(roots (filter (fn [(l String)] -> Bool (not (stringEmpty? l))) (stringLines (resultOr (fileReadString (str dir "/roots")) ""))))
        (deps (filter (fn [(l String)] -> Bool (not (stringEmpty? l))) (stringLines (resultOr (fileReadString (str dir "/deps")) ""))))
        (stamp (mtimeOf stampPath))]
    (and (= (listTake cmd 2) (list "run" "tools/remote/vps.asl"))
      (and (not (listEmpty? roots))
        (and (not (listEmpty? deps))
          (listAll? (fn [(p String)] -> Bool (and (fileExists? (str root "/" p)) (or (<= (mtimeOf (str root "/" p)) stamp) (not (under? p roots))))) deps)))))

; (:m :ref RELAY-CLIENT-PINNED :do "run tools/remote/vps.asl also keeps the current CLI when a toolchain root moved, as long as the relay client's own sources (.asl.config.asn :nativeCli :relayPaths, tests directories skipped) are no newer than the head file and :nativeCli :relayPin is true: the relay tool is read from the tree at run time, so a CLI built before the toolchain edit still runs it; a moved relay source, a missing path, an absent head or the knob off is not pinned and the call rebuilds first; nativeGate then starts the new build in the background")
fn configWord text: String key: String -> String
  (match (stringIndexOf text (str ":" key " "))
    ((none) "")
    ((some i) (let [(rest (stringTrim (optionOr (stringSlice text (+ i (+ (stringLength key) 2)) (stringLength text)) "")))]
                (optionOr (listHead (stringSplit (optionOr (listHead (stringSplit (optionOr (listHead (stringLines rest)) "") " ")) "") ")")) ""))))

fn configStrings text: String key: String -> (List String)
  (match (stringIndexOf text (str ":" key " ["))
    ((none) (list))
    ((some i) (let [(rest (optionOr (stringSlice text (+ i (+ (stringLength key) 3)) (stringLength text)) ""))
                    (body (optionOr (stringSlice rest 0 (optionOr (stringIndexOf rest "]") (stringLength rest))) ""))]
                (filter (fn [(p String)] -> Bool (not (stringEmpty? (stringTrim p)))) (stringSplit body "\"")))))

fn ! newestSource! path: String -> Int64
  (match (fileLstat path)
    ((err _) 4611686018427387904)
    ((ok st) (if (and st.isDir (not st.isSymlink))
               (if (= (sys/baseName path) "tests")
                 0
                 (fold (fn [(acc Int64) (n String)] -> Int64 (max acc (newestSource! (str path "/" n)))) 0 (resultOr (dirList path) (list))))
               st.mtimeNs)))

fn ! relayPinned? root: String dir: String stampPath: String cmd: (List String) -> Bool
  (let [(text (resultOr (fileReadString (str root "/.asl.config.asn")) ""))
        (paths (configStrings text "relayPaths"))
        (stamp (mtimeOf stampPath))]
    (and (= (listTake cmd 2) (list "run" "tools/remote/vps.asl"))
      (and (= (configWord text "relayPin") "true")
        (and (not (listEmpty? paths))
          (and (> stamp 0) (and (fileExists? (str dir "/roots"))
            (and (sys/executable? (str dir "/bin"))
              (listAll? (fn [(p String)] -> Bool (<= (newestSource! (str root "/" p)) stamp)) paths))))))))

fn ! relayRefresh! ctx: sys/Context -> Bool
  (let [(native (str ctx.root "/asl/host/out/aslNativeBuild"))]
    (if (and (sys/executable? native) (fresh? ctx.root (str ctx.root "/asl/host/out/aslNativeBuild-fresh")))
      (do (eprintln (str "asl: native CLI kept for the relay client; its refresh runs in the background: " (startBuild! ctx (cacheDir!) 2 ""))) true)
      false))

; (:m :ref FORMS-PINNED-CLI :do "an argv that is only ASN forms of the edit family (read query observe edit write diff flush discard, intel outline) runs on the newest already-built CLI without a staleness rebuild: such a form reads or stages text and never needs the toolchain edit that made the CLI stale; every keyword of every form, nested ones included, must be in the op's allow-list (allowedKeys) so a :gates, :run or :cmd field never rides along; check, test, run and every other verb keep the staleness rule; only .asl.config.asn :nativeCli :formsPin true turns it on, absent or any other word is off")
fn formsAllowed -> (List String)
  (list ":read" ":query" ":observe" ":edit" ":write" ":diff" ":flush" ":discard" ":intel :outline" ":intel :op outline")

fn allowedKeys head: String -> (List String)
  (cond
    ((= head ":read") (list ":file" ":symbol" ":anchor" ":limit" ":start" ":end"))
    ((= head ":query") (list ":text" ":in" ":limit"))
    ((= head ":observe") (list ":dim" ":scope" ":limit" ":symbol" ":module" ":path" ":spec" ":id"))
    ((= head ":edit") (list ":file" ":old" ":new" ":all" ":autofix" ":force"))
    ((= head ":write") (list ":file" ":content" ":force"))
    ((= head ":diff") (list ":file"))
    ((= head ":flush") (list ":file"))
    ((= head ":discard") (list ":file"))
    ((= head ":intel :outline") (list ":outline" ":file" ":symbol" ":limit" ":module" ":target"))
    ((= head ":intel :op outline") (list ":op" ":file" ":symbol" ":limit" ":module" ":target"))
    (else (list)))

fn charAt s: String i: Int64 -> String
  (optionOr (stringSlice s i (+ i 1)) "")

fn blank? c: String -> Bool
  (or (= c " ") (or (= c "\n") (or (= c "\t") (= c "\r"))))

fn wordAt s: String i: Int64 -> String
  (let [(c (charAt s i))]
    (if (or (stringEmpty? c) (or (blank? c) (or (= c "(") (= c ")"))))
      ""
      (str c (wordAt s (+ i 1)))))

fn headAt s: String i: Int64 -> String
  (let [(w (wordAt s (+ i 1)))]
    (if (= w ":intel")
      (let [(w2 (wordAt s (+ i (+ (stringLength w) 2))))]
        (if (= w2 ":op")
          (str w " " w2 " " (wordAt s (+ i (+ (stringLength w) (+ (stringLength w2) 3)))))
          (str w " " w2)))
      w))

; (:m :ref FORMS-PINNED-CLI :do "a :word counts as a keyword after a blank, an open or close paren or a closing quote; rows (HEAD, KEYWORD) of the top-level forms of one argv element, KEYWORD empty for the head row itself: every :word that starts a token outside a string counts, nested form heads too, only the head right after a top-level open paren is the head; none for text outside a form or unbalanced delimiters")
fn kwPrev? prev: String -> Bool
  (or (blank? prev) (listContains? (list "(" ")" "[" "]" "{" "}" "\"") prev))

fn scanForms s: String i: Int64 n: Int64 depth: Int64 inStr: Bool esc: Bool cur: String acc: (List (Pair String String)) -> (Option (List (Pair String String)))
  (if (>= i n)
    (if (and (= depth 0) (not inStr)) (some acc) (none))
    (let [(c (charAt s i))
          (prev (if (= i 0) "" (charAt s (- i 1))))]
      (cond
        (inStr (scanForms s (+ i 1) n depth (or esc (not (= c "\""))) (and (not esc) (= c "\\")) cur acc))
        ((= c "(") (if (= depth 0)
                     (let [(h (headAt s i))] (scanForms s (+ i 1) n 1 false false h (cons (pair h "") acc)))
                     (scanForms s (+ i 1) n (+ depth 1) false false cur acc)))
        ((= c ")") (if (= depth 0) (none) (scanForms s (+ i 1) n (- depth 1) false false cur acc)))
        ((= c "\"") (if (= depth 0) (none) (scanForms s (+ i 1) n depth true false cur acc)))
        ((blank? c) (scanForms s (+ i 1) n depth false false cur acc))
        ((and (= c ":") (and (> depth 0) (kwPrev? prev)))
          (scanForms s (+ i 1) n depth false false cur (if (and (= depth 1) (= prev "(")) acc (cons (pair cur (wordAt s i)) acc))))
        (else (if (= depth 0) (none) (scanForms s (+ i 1) n depth false false cur acc))))))

fn rowOk? row: (Pair String String) -> Bool
  (and (listContains? (formsAllowed) (pairFirst row))
    (or (stringEmpty? (pairSecond row)) (listContains? (allowedKeys (pairFirst row)) (pairSecond row))))

; (:m :ref FORMS-PINNED-CLI :do "a trailing argument of intel outline is a plain path: it starts with neither ( nor : nor - and holds no quote, so no form or flag rides along")
fn plainArg? a: String -> Bool
  (and (not (stringEmpty? a))
    (and (not (stringStartsWith? a "(")) (and (not (stringStartsWith? a ":")) (and (not (stringStartsWith? a "-")) (not (stringContains? a "\""))))))

fn formsOnly? cmd: (List String) -> Bool
  (or (and (= (listTake cmd 2) (list "intel" "outline"))
        (listAll? plainArg? (optionOr (listTail (optionOr (listTail cmd) (list))) (list))))
    (and (not (listEmpty? cmd))
      (listAll? (fn [(a String)] -> Bool
                  (match (scanForms a 0 (stringLength a) 0 false false "" (list))
                    ((none) false)
                    ((some rows) (and (not (listEmpty? rows)) (listAll? rowOk? rows)))))
                cmd)))

fn formsPinOn? text: String -> Bool
  (= (configWord text "formsPin") "true")

fn ! formsPinned? root: String dir: String cmd: (List String) -> Bool
  (let [(text (resultOr (fileReadString (str root "/.asl.config.asn")) ""))]
    (and (formsPinOn? text)
      (and (sys/executable? (str dir "/bin")) (formsOnly? cmd))))

fn ! nativeGate! ctx: sys/Context args: (List String) -> (Option Int64)
  (let [(dir (optionOr (envGet "ASL_NATIVE_CLI_DIR") ""))]
    (cond
      ((not (direct?)) (none))
      ((= (verbKind args) "host") (some (hostExec! ctx args (list))))
      ((or (stringEmpty? dir) (fresh? ctx.root dir)) (none))
      ((formsPinned? ctx.root dir args) (none))
      ((pinned? ctx.root dir (headPath (cacheDir!) ctx.root) args) (none))
      ((relayPinned? ctx.root dir (headPath (cacheDir!) ctx.root) args) (do (relayRefresh! ctx) (none)))
      (else (some (awaitStaleRebuild! ctx dir args)))))

fn leadingDigitsAt s: String n: Int64 i: Int64 -> String
  (if (and (< i n) (stringContains? "0123456789" (optionOr (stringSlice s i (+ i 1)) "x")))
    (leadingDigitsAt s n (+ i 1))
    (optionOr (stringSlice s 0 i) ""))

fn leadingDigits s: String -> String
  (leadingDigitsAt s (stringLength s) 0)

fn configInt text: String key: String -> (Option Int64)
  (match (stringIndexOf text (str ":" key " "))
    ((none) (none))
    ((some i) (let [(after (+ i (+ (stringLength key) 2)))
                    (digits (leadingDigits (stringTrim (optionOr (stringSlice text after (stringLength text)) ""))))]
                (if (stringEmpty? digits) (none) (stringToInt64 digits)))))

; (:m :ref NATIVE-STALE-CONVERGE :do "ASL_NATIVE_BUILD_WAIT stays as the override an existing test (binAslStaleTest.asl, nativeStaleHeadTest.asl) injects to force a short, deterministic wait deadline without rewriting .asl.config.asn per case; when unset, the deadline comes from .asl.config.asn's :nativeCli :buildWaitS, falling back to 3600 only if the config file itself is absent or lacks the key (a stripped-down tree)")
fn ! buildWaitS! ctx: sys/Context -> Int64
  (optionOr (stringToInt64 (optionOr (envGet "ASL_NATIVE_BUILD_WAIT") ""))
    (optionOr (configInt (resultOr (fileReadString (str ctx.root "/.asl.config.asn")) "") "buildWaitS") 3600))

fn ! awaitStaleRebuild! ctx: sys/Context stale: String args: (List String) -> Int64
  (let [(cache (cacheDir!))
        (startMsg (startBuild! ctx cache 2 ""))
        (waitS (buildWaitS! ctx))
        (_ (eprintln (str "asl: native CLI predates its sources (" stale "); " startMsg "; waiting up to " (stringFromInt64 waitS) "s for the rebuild (.asl.config.asn :nativeCli :buildWaitS, or ASL_NATIVE_BUILD_WAIT)")))
        (deadline (+ (monotonicNs) (* waitS 1000000000)))
        (why (awaitNative! ctx cache stale args deadline))]
    (do (sys/say! (str "(:asl :status :failed :error ERR_NATIVE_STALE :message \"" why "; see " cache "/build.log\")")) 2))

fn ! heldPid lock: String -> Int64
  (optionOr (stringToInt64 (stringTrim (resultOr (fileReadString (str lock "/pid")) ""))) 0)

fn ! alive? pid: Int64 -> Bool
  (and (> pid 1) (resultOr (procAlive? pid) false))

fn detachScript -> String
  "perl -MPOSIX -e 'POSIX::setsid(); exec @ARGV or exit 127' \"$@\" < /dev/null >> \"$NATIVE_CLI_LOG\" 2>&1 & echo $!"

fn ! nativeBuildReady? ctx: sys/Context native: String freshMark: String -> Bool
  (if (and (sys/executable? native) (fresh? ctx.root freshMark))
    true
    (do (boundedCapture! (str "sh " (shQuote (str ctx.root "/asl/host/build.sh"))) 600000)
        (and (sys/executable? native) (fresh? ctx.root freshMark))))


; (:m :ref NATIVE-STALE-CONVERGE :do "no longer passes --lock-owner: the shared ~/.asl/run/nativeCli/build.log showed a cascading 'owner-gone' retry storm (16 lines in 66) against the main checkout, traced to aslNativeBuild's own --lock-owner liveness check self-aborting a detached build the instant its SHORT-LIVED triggering CLI invocation (a bounded test/harness call, routinely shorter than a from-scratch asl1+CLI bootstrap) exited, which then made the next caller see a dead lock/pid and restart the whole build from zero, forever; the lock dir's own pid (the detached build process itself, tracked via heldPid/alive? in waitBuild!) is the trustworthy liveness signal and the build's own deadlineNs already bounds a truly orphaned run, so no separate owner-liveness coupling is needed for the common case of a build outliving its triggering caller")
fn ! spawnBuilder! ctx: sys/Context cache: String lock: String -> String
  (let [(log (str cache "/build.log"))
        (native (str ctx.root "/asl/host/out/aslNativeBuild"))
        (freshMark (str ctx.root "/asl/host/out/aslNativeBuild-fresh"))]
    (if (not (nativeBuildReady? ctx native freshMark))
      (do (pathRemove lock) "its build helper is stale and the hostless refresh (sh asl/host/build.sh) did not restore it")
      (let [(argv (listAppend (list "/bin/sh" "-c" (detachScript) "sh" "nice" "-n" "15") (list native ctx.root cache)))
            (d (match (sys/captureWith! argv (some ctx.root) (list (str "NATIVE_CLI_LOG=" log)))
                 ((ok c) c)
                 ((err e) (sys/Captured :exitCode 127 :stdout "" :stderr e))))
            (pid (optionOr (stringToInt64 (stringTrim d.stdout)) 0))
            (part (str lock "/pid.part"))]
        (if (or (!= d.exitCode 0) (<= pid 1))
          (do (pathRemove lock) (str "its build did not start: " (stringReplace (stringTrim (str d.stdout " " d.stderr)) "\n" " ")))
          (do (match (fileWrite part (str (stringFromInt64 pid) "\n")) ((ok _) (pathRename part (str lock "/pid"))) ((err e) (err e)))
              (str "its build started in the background (log " log ")"))))))

fn ! startBuild! ctx: sys/Context cache: String tries: Int64 last: String -> String
  (let [(lock (str cache "/lock"))]
    (if (<= tries 0)
      last
      (match (dirCreate lock)
        ((err e) (str "cannot create " lock ": " e))
        ((ok _) (match (fileCreateExclusive (str lock "/pid") (str (stringFromInt64 (procSelf)) "\n"))
          ((ok _) (spawnBuilder! ctx cache lock))
          ((err e) (let [(held (heldPid lock))]
                     (if (alive? held)
                       (str "pid " (stringFromInt64 held) " is building it")
                       (do (pathRemove lock) (startBuild! ctx cache (- tries 1) "a stale build lock was cleared"))))))))))

fn ! waitBuild! lock: String deadlineNs: Int64 -> Bool
  (let [(owner (optionOr (stringToInt64 (stringTrim (resultOr (fileReadString (str lock "/owner")) ""))) 0))]
  (if (and (alive? (heldPid lock)) (or (= owner 0) (alive? owner)) (< (monotonicNs) deadlineNs))
    (do (sleepMs 1000) (waitBuild! lock deadlineNs))
    true))

fn ! execNative! ctx: sys/Context dir: String args: (List String) -> String
  (let [(code (execWith! (cons (str dir "/bin") args) (list) (list (str "ASL_NATIVE_CLI_DIR=" dir) (str "ASL_NATIVE_QUIET_PID=" (stringFromInt64 (procSelf))))))]
    (str "exec of " dir "/bin failed with " (stringFromInt64 code)))

fn ! timeoutS! -> Int64
  (optionOr (stringToInt64 (optionOr (envGet "ASL_NATIVE_CLI_TIMEOUT") "")) 1800)

fn ! headDir! cache: String root: String -> String
  (stringTrim (resultOr (fileReadString (headPath cache root)) ""))

fn ! awaitNative! ctx: sys/Context cache: String stale: String args: (List String) deadline: Int64 -> String
  (let [(_ (waitBuild! (str cache "/lock") deadline))
        (built (headDir! cache ctx.root))]
    (cond
      ((and (!= built stale) (fresh? ctx.root built) (probe? ctx.root built)) (execNative! ctx built args))
      ((>= (monotonicNs) deadline) "its build exceeded its wait budget")
      (else (str "its build did not finish (see " cache "/build.log)"))))

fn ! nativeWhy! ctx: sys/Context args: (List String) -> String
  (let [(cache (cacheDir!))
        (stale (optionOr (envGet "ASL_NATIVE_CLI_STALE") ""))
        (dir (headDir! cache ctx.root))]
    (cond
      ((not (sys/isFile? (str ctx.root "/asl/host/out/libaslrt.a"))) "asl/host/out/libaslrt.a is absent (sh asl/host/build.sh)")
      ((and (!= dir stale) (fresh? ctx.root dir)) (if (probe? ctx.root dir) (execNative! ctx dir args) "the cached binary failed its self-probe"))
      (else
        (let [(why (startBuild! ctx cache 2 ""))]
          (cond
            ((not (stringEmpty? (optionOr (envGet "ASL_NATIVE_CLI_WAIT") ""))) (awaitNative! ctx cache stale args (+ (monotonicNs) (* (timeoutS!) 1000000000))))
            ((stringEmpty? stale) why)
            (else (str "the cached binary predates its sources and " why)))))))

fn ! hostEntry! ctx: sys/Context args: (List String) -> Unit
  (let [(verb (optionOr (listHead args) "help"))
        (kind (verbKind args))]
    (cond
      ((or (not (direct?)) (!= (optionOr (envGet "ASL_CLI_HOST_UNSET") "") "1")) ())
      ((= kind "host") (do (eprintln (str "asl: " verb " is not native yet, so it runs on asl-host")) ()))
      ((= kind "native") (do (eprintln (str "asl: " verb " runs on asl-host: no native toolchain, " (nativeWhy! ctx args))) ()))
      (else ())))

; (:m :ref OUTSIDEPKG-STAGE-SOURCES-20261024 :do "bounded cache: the newest keep entries of dir whose name starts with prefix stay; an older one goes only when its last use (newest of its mtime and its .used file's) is older than minAgeNs and its name is not in protected; a removed directory holding symlinks drops the links, never their targets; returns the count removed")
fn ! entryStamp! path: String -> Int64
  (match (fileStat path)
    ((err _) 0)
    ((ok st) (match (fileStat (str path "/.used"))
               ((ok u) (if (> u.mtimeNs st.mtimeNs) u.mtimeNs st.mtimeNs))
               ((err _) st.mtimeNs))))

fn ! pruneEntries! dir: String prefix: String keep: Int64 minAgeNs: Int64 protected: (List String) -> Int64
  (match (dirList dir)
    ((err _) 0)
    ((ok names)
      (let [(now (nowNs))
            (stamped (map (fn [(n String)] -> (Pair String Int64) (pair n (entryStamp! (str dir "/" n)))) (filter (fn [(n String)] -> Bool (stringStartsWith? n prefix)) names)))
            (newestFirst (listSortBy (fn [(e (Pair String Int64))] -> Int64 (- 0 (pairSecond e))) stamped))
            (state (fold (fn [(acc (Pair Int64 Int64)) (e (Pair String Int64))] -> (Pair Int64 Int64)
                           (let [(idx (pairFirst acc)) (removed (pairSecond acc))]
                             (if (and (>= idx keep) (and (not (listContains? protected (pairFirst e))) (> (- now (pairSecond e)) minAgeNs)))
                               (pair (+ idx 1) (if (ok? (pathRemove (str dir "/" (pairFirst e)))) (+ removed 1) removed))
                               (pair (+ idx 1) removed))))
                         (pair 0 0) newestFirst))]
        (pairSecond state))))

; (:m :ref NATIVECLI-PRUNE :do "after a native CLI is built, cli-* and asl1-* directories of the cache older than 6h that no head* file names are removed, keeping the newest keep of each kind; a head's target is protected whatever its age")
fn ! headTargets! cache: String -> (List String)
  (map (fn [(h String)] -> String (sys/baseName (stringTrim (resultOr (fileReadString (str cache "/" h)) ""))))
       (filter (fn [(n String)] -> Bool (and (stringStartsWith? n "head") (not (stringContains? n ".part.")))) (resultOr (dirList cache) (list))))

fn ! pruneNativeCache! cache: String keep: Int64 minAgeNs: Int64 -> Int64
  (let [(targets (headTargets! cache))]
    (+ (pruneEntries! cache "cli-" keep minAgeNs targets) (pruneEntries! cache "asl1-" keep minAgeNs targets)))

; (:m :ref BIN-NO-PERSIST-20261026 :do "a build store is bounded by bytes: each entry (a directory or a group of files) carries its last use and its size; the oldest unpinned entries older than minAgeNs go until the store fits the cap, each re-stamped right before it goes so one used since the scan stays; a pinned entry stays whatever its age and size")
(schema StoreEntry
  (:f paths (List String))
  (:f stamp Int64)
  (:f bytes Int64)
  (:f pinned Bool))

fn ! treeBytes! path: String -> Int64
  (match (fileLstat path)
    ((err _) 0)
    ((ok st) (if (and st.isDir (not st.isSymlink))
               (fold (fn [(acc Int64) (n String)] -> Int64 (+ acc (treeBytes! (str path "/" n)))) 0 (resultOr (dirList path) (list)))
               st.size)))

; (:m :ref BIN-NO-PERSIST-20261026 :do "an entry's last use is the newest mtime of anything inside it, so a file written deep in a slot or a touched object counts")
fn ! treeStamp! path: String -> Int64
  (match (fileLstat path)
    ((err _) 0)
    ((ok st) (if (and st.isDir (not st.isSymlink))
               (fold (fn [(acc Int64) (n String)] -> Int64 (max acc (treeStamp! (str path "/" n)))) st.mtimeNs (resultOr (dirList path) (list)))
               st.mtimeNs)))

fn ! pathsStamp! paths: (List String) -> Int64
  (fold (fn [(acc Int64) (p String)] -> Int64 (max acc (treeStamp! p))) 0 paths)

fn ! storeEntry! paths: (List String) pinned: Bool -> StoreEntry
  (StoreEntry :paths paths
              :stamp (pathsStamp! paths)
              :bytes (fold (fn [(acc Int64) (p String)] -> Int64 (+ acc (treeBytes! p))) 0 paths)
              :pinned pinned)

fn storeBytes entries: (List StoreEntry) -> Int64
  (fold (fn [(acc Int64) (e StoreEntry)] -> Int64 (+ acc e.bytes)) 0 entries)

fn ! dropEntry! e: StoreEntry -> Bool
  (fold (fn [(acc Bool) (p String)] -> Bool (and (ok? (pathRemove p)) acc)) true e.paths)

fn ! sweepEntries! entries: (List StoreEntry) capBytes: Int64 minAgeNs: Int64 -> (Pair Int64 Int64)
  (let [(now (nowNs))
        (oldestFirst (listSortBy (fn [(e StoreEntry)] -> Int64 e.stamp) entries))]
    (fold (fn [(acc (Pair Int64 Int64)) (e StoreEntry)] -> (Pair Int64 Int64)
            (if (and (> (pairFirst acc) capBytes) (and (not e.pinned) (and (> (- now e.stamp) minAgeNs) (> (- (nowNs) (pathsStamp! e.paths)) minAgeNs))))
              (if (dropEntry! e) (pair (- (pairFirst acc) e.bytes) (+ (pairSecond acc) 1)) acc)
              acc))
          (pair (storeBytes entries) 0) oldestFirst))

; (:m :ref BIN-NO-PERSIST-20261026 :do "a head file is named by its root with every slash made an underscore, so an underscore may be either; the walk takes each next path component as the shortest run of parts that exists as a directory, so only a root that exists today is found")
fn ! rootWalk! base: String parts: (List String) n: Int64 -> (Option String)
  (cond
    ((listEmpty? parts) (if (and (not (stringEmpty? base)) (sys/isDir? base)) (some base) (none)))
    ((> n (listLength parts)) (none))
    (else (let [(comp (stringJoin (listTake parts n) "_"))
                (next (str base "/" comp))]
            (match (if (and (not (stringEmpty? comp)) (sys/isDir? next)) (rootWalk! next (listDrop parts n) 1) (none))
              ((some root) (some root))
              ((none) (rootWalk! base parts (+ n 1)))))))

fn ! headRoot! name: String -> (Option String)
  (if (stringStartsWith? name "head_")
    (rootWalk! "" (stringSplit (optionOr (stringSlice name 5 (stringLength name)) "") "_") 1)
    (none))

fn headFile? name: String -> Bool
  (and (stringStartsWith? name "head") (not (stringContains? name ".part.")))

fn storeName? name: String -> Bool
  (listAny? (fn [(p String)] -> Bool (stringStartsWith? name p)) (list "cli-" "asl1-" "seed-" "rt-"))

fn ! tmpDead? name: String -> Bool
  (and (stringStartsWith? name "tmp.") (not (alive? (optionOr (stringToInt64 (optionOr (stringSlice name 4 (stringLength name)) "")) 0))))

; (:m :ref BIN-NO-PERSIST-20261026 :do "a sweep holds the build lock bin/asl and the CLI take (lock/pid made exclusively): a lock held by this process or one of its ancestors (bin/asl native_refresh runs the builder under its own lock) is used and left; one held by any other pid, live or not yet cleared, means no sweep this time")
fn ! takeLock! cache: String -> (Option Bool)
  (let [(lock (str cache "/lock"))
        (held (heldPid lock))]
    (cond
      ((= held (procSelf)) (some false))
      ((and (> held 1) (listContains? (run/descendantsOf (run/psSnapshot) held) (procSelf))) (some false))
      ((not (ok? (dirCreate lock))) (none))
      ((ok? (fileCreateExclusive (str lock "/pid") (str (stringFromInt64 (procSelf)) "\n"))) (some true))
      (else (none))))

; (:m :ref BIN-NO-PERSIST-20261026 :do "a build leases every seed, rt, asl1 or cli entry it reuses or makes before it touches it: leases/NAME@PID holds pid and start; a lease of a live pid pins NAME, a dead one is dropped, and the build drops its own at its end")
fn leaseDirOf cache: String -> String
  (str cache "/leases")

fn ! leaseEntry! cache: String name: String startNs: Int64 -> Bool
  (let [(dir (leaseDirOf cache))
        (_ (dirCreate dir))]
    (ok? (fileWrite (str dir "/" name "@" (stringFromInt64 (procSelf))) (str (stringFromInt64 (procSelf)) " " (stringFromInt64 startNs) "\n"))))

fn ! dropLeases! cache: String -> Int64
  (let [(dir (leaseDirOf cache))
        (mine (str "@" (stringFromInt64 (procSelf))))]
    (listLength (filter (fn [(n String)] -> Bool (and (stringEndsWith? n mine) (ok? (pathRemove (str dir "/" n))))) (resultOr (dirList dir) (list)))))

fn leasePid name: String -> Int64
  (optionOr (stringToInt64 (optionOr (listLast (stringSplit name "@")) "")) 0)

fn leaseName name: String -> String
  (let [(parts (stringSplit name "@"))]
    (stringJoin (listTake parts (- (listLength parts) 1)) "@"))

fn ! liveLeases! cache: String -> (List String)
  (let [(dir (leaseDirOf cache))
        (names (resultOr (dirList dir) (list)))
        (_ (map (fn [(n String)] -> Bool (and (not (alive? (leasePid n))) (ok? (pathRemove (str dir "/" n))))) names))]
    (map leaseName (filter (fn [(n String)] -> Bool (alive? (leasePid n))) names)))

; (:m :ref BIN-NO-PERSIST-20261026 :do "a build in flight is a tmp.PID dir of a live pid; one that holds no lease yet (just started, or a builder from before leases) holds unknown entries, so nothing is swept while it runs")
fn ! tmpPid name: String -> Int64
  (if (stringStartsWith? name "tmp.") (optionOr (stringToInt64 (optionOr (stringSlice name 4 (stringLength name)) "")) 0) 0)

fn ! unleasedBuild? cache: String names: (List String) -> Bool
  (let [(holders (map leasePid (resultOr (dirList (leaseDirOf cache)) (list))))]
    (listAny? (fn [(n String)] -> Bool (let [(pid (tmpPid n))] (and (alive? pid) (and (!= pid (procSelf)) (not (listContains? holders pid)))))) names))

; (:m :ref BIN-NO-PERSIST-20261026 :do "the floor of the old prune stays: on the native CLI store nothing younger than 6 hours goes and the newest 4 entries of each kind stay, a .failed marker not counting as one; the cap only acts beyond that")
fn sharedFloorNs -> Int64
  21600000000000

fn staleAgeNs -> Int64
  1209600000000000

fn keepNewest -> Int64
  4

fn kindOf name: String -> String
  (optionOr (listHead (filter (fn [(p String)] -> Bool (stringStartsWith? name p)) (list "cli-" "asl1-" "seed-" "rt-"))) "")

fn ! newestOfKinds names: (List String) stamps: (Map String Int64) -> (List String)
  (fold (fn [(acc (List String)) (k String)] -> (List String)
          (listAppend acc (listTake (listSortBy (fn [(n String)] -> Int64 (- 0 (mapGetOr stamps n 0))) (filter (fn [(n String)] -> Bool (and (= (kindOf n) k) (not (stringEndsWith? n ".failed")))) names)) (keepNewest))))
        (list) (list "cli-" "asl1-" "seed-" "rt-"))

; (:m :ref BIN-NO-PERSIST-20261026 :do "after a native CLI build, under the build lock: a head whose root no longer exists is removed, a tmp dir whose builder is dead goes, and the cli, asl1, seed and rt entries are held under capBytes by last use above the floor, with the target of every live head and every leased entry pinned; returns the count removed")
fn ! sweepNativeCache! cache: String capBytes: Int64 minAgeNs: Int64 -> Int64
  (match (takeLock! cache)
    ((none) (sweepDeadTmp! cache (resultOr (dirList cache) (list))))
    ((some taken) (let [(removed (match (dirList cache)
                                   ((err _) 0)
                                   ((ok names) (if (unleasedBuild? cache names) 0 (sweepLocked! cache names (liveLeases! cache) capBytes (max minAgeNs (sharedFloorNs)))))))
                        (_ (if taken (pathRemove (str cache "/lock")) (ok ())))]
                    (+ (sweepDeadTmp! cache (resultOr (dirList cache) (list))) removed))))

; (:m :ref U6-NATIVECLI-REAP :do "a tmp.PID dir is private to its pid: one whose pid is dead goes at every sweep, before the build lock and the unleased-build gate and with no age floor; a live pid's tmp dir is never touched")
fn ! sweepDeadTmp! cache: String names: (List String) -> Int64
  (listLength (filter (fn [(n String)] -> Bool (and (tmpDead? n) (ok? (pathRemove (str cache "/" n))))) names))

; (:m :ref NATIVECLI-HEAD-LEAK :do "a head whose root is gone names nothing a build can use, yet the 6 hour floor kept every one a test made under /private/tmp; with the opt-in marker file deadHeadSweep in the store a dead head goes at the first sweep, and without it (every store until the principal adds it) the floor still holds")
fn deadHeadMarker -> String
  "deadHeadSweep"

fn ! freshDeadHeads? cache: String -> Bool
  (fileExists? (str cache "/" (deadHeadMarker)))

fn ! sweepLocked! cache: String names: (List String) leased: (List String) capBytes: Int64 minAgeNs: Int64 -> Int64
  (let [(now (nowNs))
        (old? (fn [(n String)] -> Bool (> (- now (treeStamp! (str cache "/" n))) minAgeNs)))
        (heads (filter headFile? names))
        (live (filter (fn [(h String)] -> Bool (some? (headRoot! h))) heads))
        (dead (filter (fn [(h String)] -> Bool (and (not (listContains? live h)) (or (freshDeadHeads? cache) (old? h)))) heads))
        (deadGone (listLength (filter (fn [(h String)] -> Bool (ok? (pathRemove (str cache "/" h)))) dead)))
        (stored (filter storeName? names))
        (stamps (fold (fn [(m (Map String Int64)) (n String)] -> (Map String Int64) (mapSet m n (treeStamp! (str cache "/" n)))) (mapEmpty) stored))
        (named (map (fn [(h String)] -> String (sys/baseName (stringTrim (resultOr (fileReadString (str cache "/" h)) "")))) live))
        (held (listAppend leased named))
        (stale? (fn [(n String)] -> Bool (and (> (- now (treeStamp! (str cache "/" n))) (staleAgeNs)) (not (listContains? held (stringReplace n ".failed" ""))))))
        (stale (filter stale? stored))
        (kept (filter (fn [(n String)] -> Bool (not (listContains? stale n))) stored))
        (staleGone (listLength (filter (fn [(n String)] -> Bool (ok? (pathRemove (str cache "/" n)))) stale)))
        (targets (listAppend (listAppend leased (newestOfKinds kept stamps)) named))
        (entries (map (fn [(n String)] -> StoreEntry (storeEntry! (list (str cache "/" n)) (listContains? targets (stringReplace n ".failed" "")))) kept))]
    (+ deadGone staleGone (pairSecond (sweepEntries! entries capBytes minAgeNs))))
