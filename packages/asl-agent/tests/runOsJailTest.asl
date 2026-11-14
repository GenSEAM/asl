(module aslAgent/tests/runOsJailTest
  :x [runTests]
  :i [(aslAgent/runOps :a r) (aslAgent/gitOps :a g) (aslAgent/core :a c) (aslAgent/tests/gitInitKit :a gk) (aslAgent/jail :a jl)])

; (:m :ref LEON-RUN-HOME-JAIL :do "B-02 gate: a unit child (run op or gate) cannot write outside its root, cannot write the root's .git, cannot list the real HOME, cannot reach off the machine and inherits no credential or harness setting. Every path the fixture writes is under one <tmp>/leonjail-fable-<ns> directory removed at the end (tmp is /private/tmp where that is a directory, else /tmp): realHome and sibling stand for the real HOME and a sibling worktree, and the true HOME is asked for a directory listing and, only under an OS sandbox, one write that must be refused (the name is removed again should a broken sandbox let it through). JAIL-LINUX: where seatbelt and bwrap differ by design the assertion branches on the OS and says why; under bwrap /run holds no socket. The escapes live in script files because the lexical guard does not read script files, which is the hole the OS sandbox closes. Where no sandbox applies (no tool, or this test already runs inside one, which cannot nest) the receipt must say lexical and the escape assertions rest on that")
fn ! runWith! ctx: r/RunCtx cmd: String -> String
  (let [res (r/execRunOp! (c/parseKv (str "(:step :op \"run\" :argv \"" (c/escapeAsn cmd) "\")")) ctx (r/newProcs) "r1" (fn [rel pre mode] true))]
    (r/serRec res.rec))

fn ! readText! p: String -> String
  (resultOr (fileReadString p) "")

fn leaky? name: String -> Bool
  (let [up (stringUpper name)]
    (or (stringContains? up "KEY") (or (stringContains? up "TOKEN") (stringContains? up "SECRET"))))

fn harnessAsl? name: String -> Bool
  (and (stringStartsWith? name "ASL_")
    (not (listContains? (list "ASL_NATIVE_CLI_CACHE" "ASL_HOST_CACHE_DIR" "ASL_NATIVE_ASL1_CACHE" "ASL_CHECK_CACHE" "ASL_CORPUS_CACHE" "ASL_NATIVE_TEST_CACHE" "ASL_FLEET_TAG" "ASL_NATIVE_BUILD_WAIT" "ASL_RUN_TMP") name)))

; (:m :ref JAIL-LINUX :do "D4: macOS keeps its fixtures under /private/tmp, the real path of /tmp there; Linux has no /private")
fn ! tmpBase! -> String
  (match (fileStat "/private/tmp") ((ok st) (if st.isDir "/private/tmp" "/tmp")) ((err _) "/tmp"))

fn ! darwin? -> Bool
  (match (platformInfo) ((ok p) (= p.os "Darwin")) ((err _) false))

fn linesOf text: String -> (List String)
  (filter (fn [n] (not (stringEmpty? n))) (stringSplit text "\n"))

; (:m :ref JAIL-LINUX :do "the entry of home a path lies under, empty for a path elsewhere: bwrap shows these names in the tmpfs over the real HOME, as the mount points of the jail's binds")
fn entryUnder home: String p: String -> String
  (if (and (not (stringEmpty? home)) (stringStartsWith? p (str home "/")))
    (optionOr (listHead (stringSplit (optionOr (stringSlice p (+ (stringLength home) 1) (stringLength p)) "") "/")) "")
    "")

fn ! runTests -> Bool
  (let [base (str (tmpBase!) "/leonjail-fable-" (stringFromInt64 (monotonicNs)))
        mac (darwin?)
        root (str base "/root")
        fakeHome (str base "/realHome")
        sibling (str base "/sibling")
        madeDirs (and (ok? (dirCreate base)) (and (ok? (dirCreate root)) (and (ok? (dirCreate fakeHome)) (ok? (dirCreate sibling)))))
        wroteSubject (fileWrite (str root "/subject.txt") "subject\n")
        repo (gk/initGitRepo! root "leonJail" "leon-jail@example.invalid")
        homeMarker (str fakeHome "/marker.txt")
        siblingMarker (str sibling "/marker.txt")
        gateMarker (str sibling "/gateMarker.txt")
        wroteMarkers (and (ok? (fileWrite homeMarker "keep\n")) (and (ok? (fileWrite siblingMarker "keep\n")) (ok? (fileWrite gateMarker "keep\n"))))
        headBefore (readText! (str root "/.git/HEAD"))
        trueHome (optionOr (envGet "HOME") "/nonexistent-home")
        wroteEscape (fileWrite (str root "/escape.sh")
                      (str "echo changed > " homeMarker "\n" "echo changed > " siblingMarker "\n" "echo new > " sibling "/created.txt\n"))
        wroteGate (fileWrite (str root "/gateEscape.sh") (str "env | cut -d= -f1 > gateNames.txt\n" "echo changed > " gateMarker "\n"))
        wroteGit (fileWrite (str root "/git.sh") "echo changed > .git/HEAD\necho new > .git/leonJailMarker\n")
        wroteProbe (fileWrite (str root "/probe.sh")
                     (str "env | cut -d= -f1 > names.txt\n" "ls -A " trueHome " > homeEntries.txt 2> /dev/null; echo \"homeList=$?\" > homeList.txt\n"
                       "find /run -type s 2> /dev/null | wc -l > runSockets.txt\n"
                       "echo inside > inside.txt\n" "echo scratch > \"$HOME/scratch.txt\"\n" "echo temp > \"$TMPDIR/temp.txt\"\n"
                       "curl -s -m 3 -o /dev/null http://192.0.2.1/; echo \"curl=$?\" > curl.txt\n"))
        ctx (r/makeRunCtx root (list) "leonJail" 30 (list) root)
        probeRec (runWith! ctx "sh probe.sh")
        escapeRec (runWith! ctx "sh escape.sh")
        gateText (g/serRecs "gates" (g/runGates! (list (pair "g1" "sh gateEscape.sh")) root 30 (none) (none)))
        gateNames (filter (fn [n] (not (stringEmpty? n))) (stringSplit (readText! (str root "/gateNames.txt")) "\n"))
        gateKept (readText! gateMarker)
        gitRec (runWith! ctx "sh git.sh")
        lexical (stringContains? escapeRec "(sandbox \"lexical\")")
        homeDenied (str trueHome "/.leonjail-denied-" (stringFromInt64 (monotonicNs)))
        wroteHomeWrite (fileWrite (str root "/homeWrite.sh") (str "echo x > " homeDenied "\n"))
        homeWriteRec (if lexical "" (runWith! ctx "sh homeWrite.sh"))
        homeWritten (ok? (fileStat homeDenied))
        sweptHomeWrite (if homeWritten (ok? (pathRemove homeDenied)) true)
        jail (jl/jailOf! root (r/jailHome root) (r/spawnEnv! ctx root) (list root) (list) false)
        skeleton (filter (fn [e] (not (stringEmpty? e))) (map (fn [p] (entryUnder jail.realHome p)) (listAppend jail.reads jail.writes)))
        strangers (filter (fn [e] (not (listContains? skeleton e))) (linesOf (readText! (str root "/homeEntries.txt"))))
        runSockets (stringTrim (readText! (str root "/runSockets.txt")))
        names (filter (fn [n] (not (stringEmpty? n))) (stringSplit (readText! (str root "/names.txt")) "\n"))
        homeKept (readText! homeMarker)
        siblingKept (readText! siblingMarker)
        created (ok? (fileStat (str sibling "/created.txt")))
        headAfter (readText! (str root "/.git/HEAD"))
        gitMarker (ok? (fileStat (str root "/.git/leonJailMarker")))
        homeList (readText! (str root "/homeList.txt"))
        curlSeen (readText! (str root "/curl.txt"))
        insideSeen (readText! (str root "/inside.txt"))
        scratchSeen (readText! (str (r/jailHome root) "/scratch.txt"))
        tempSeen (readText! (str (r/jailHome root) "/tmp/temp.txt"))
        cleaned (pathRemove base)]
    (do
      (assert (and madeDirs (and (ok? wroteSubject) (and repo (and wroteMarkers (and (ok? wroteEscape) (and (ok? wroteGate) (and (ok? wroteGit) (and (ok? wroteHomeWrite) (ok? wroteProbe))))))))) "the jail fixture (root repo, stand-in home and sibling markers, scripts) was built")
      (assert (and (listContains? names "PATH") (and (listContains? names "HOME") (listContains? names "TMPDIR"))) (str "the unit child ran and has PATH, HOME and TMPDIR: " probeRec))
      (assert (not (listAny? leaky? names)) (str "no env name of a unit child matches KEY, TOKEN or SECRET, got " (c/joinSep (filter leaky? names) " ")))
      (assert (not (listAny? harnessAsl? names)) (str "no ASL_ setting of the harness reaches a unit child, got " (c/joinSep (filter harnessAsl? names) " ")))
      (assert (stringContains? insideSeen "inside") "a unit child still writes inside the root")
      (assert (and (stringContains? scratchSeen "scratch") (stringContains? tempSeen "temp")) "a unit child still writes its scratch HOME and TMPDIR")
      (assert (or lexical (stringContains? escapeRec "(sandbox \"os\")")) (str "the receipt names its boundary, os or lexical: " escapeRec))
      (assert (or lexical (if mac (stringContains? escapeRec "ERR_RUN_SANDBOX") (stringContains? escapeRec "(status \"failed\")")))
        (str "writing outside the root " (if mac "gets a refusal receipt (seatbelt answers EPERM)" "fails (bwrap: the sibling under the private /tmp does not exist in the jail, so the shell answers ENOENT and the receipt is a failed run, not a sandbox refusal)") ": " escapeRec))
      (assert (or lexical (= homeKept "keep\n")) "the marker under the stand-in HOME is unchanged")
      (assert (or lexical (= siblingKept "keep\n")) "the marker in the sibling directory is unchanged")
      (assert (or lexical (not created)) "no file was created in the sibling directory")
      (assert (listContains? gateNames "PATH") (str "the gate child ran: " gateText))
      (assert (not (listAny? leaky? gateNames)) (str "no env name of a gate child matches KEY, TOKEN or SECRET, got " (c/joinSep (filter leaky? gateNames) " ")))
      (assert (not (listAny? harnessAsl? gateNames)) (str "no ASL_ setting of the harness reaches a gate child, got " (c/joinSep (filter harnessAsl? gateNames) " ")))
      (assert (or lexical (= gateKept "keep\n")) "a gate child cannot change the marker in the sibling directory")
      (assert (or lexical (not (stringContains? gateText "(exit 0)"))) (str "a gate that writes outside the root fails: " gateText))
      (assert (or lexical (stringContains? gitRec "ERR_RUN_SANDBOX")) (str "writing the root's .git gets a refusal receipt: " gitRec))
      (assert (or lexical (and (= headAfter headBefore) (not (stringEmpty? headBefore)))) "the root's .git/HEAD is unchanged")
      (assert (or lexical (not gitMarker)) "no file was created in the root's .git")
      (assert (or lexical (if mac (and (stringContains? homeList "homeList=") (not (stringContains? homeList "homeList=0"))) (and (stringContains? homeList "homeList=0") (listEmpty? strangers))))
        (str (if mac "the real HOME cannot be listed from a unit child (seatbelt denies the read)" "listing the real HOME from a unit child shows only the mount points of the jail's binds (bwrap puts an empty tmpfs over it, so ls succeeds)") ": " homeList " other entries: " (stringFromInt64 (listLength strangers))))
      (assert (or lexical (= runSockets "0")) (str "D1: a unit child finds no socket under /run (D-Bus, the user systemd manager, agents), sockets found: " runSockets))
      (assert (or lexical (stringContains? homeWriteRec "ERR_RUN_SANDBOX")) (str "D3: writing into the true HOME gets a refusal receipt (seatbelt EPERM, bwrap EROFS on the sealed tmpfs) instead of vanishing: " homeWriteRec))
      (assert (and sweptHomeWrite (or lexical (not homeWritten))) "D3: the write into the true HOME created nothing there")
      (assert (or lexical (stringContains? curlSeen "curl=7")) (str "a connection off the machine is refused at once, not timed out: " curlSeen))
      (assert (and (stringContains? probeRec "(status \"ok\")") (not (stringContains? probeRec "ERR_RUN_SANDBOX"))) (str "a run that stays inside its jail is not refused: " probeRec))
      (assert (ok? cleaned) "the fixture directory was removed")
      true))
