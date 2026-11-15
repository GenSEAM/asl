(module aslAgent/tests/jailCliCacheTest
  :x [runTests]
  :i [(aslAgent/jail :a jl) (aslAgent/core :a c) (asl-tools/fleet/run :a fr)])

; (:m :ref LEON-JAIL-CLI-CACHE :do "the private native CLI cache of a jail home follows the shared one: the decision as data, the re-seed on fake shared caches (a deploy moves the pointer, a second call is a no-op, a child's own newer build stays, a worktree without a shared pointer borrows the tool root's with the verify stamp), JAIL-SEED-SYMLINK refusals (a symlink at the private cache, a private head, a private cli directory, a shared head or cli directory, the jail home itself), and one real jailed bin/asl check after a deploy that must run without a native build. Fixtures under one <tmp>/leonjailcli-<ns> directory removed at the end; where this test already runs inside a sandbox the tool probe is empty and the real jailed call is skipped by name")
fn ! tmpBase! -> String
  (match (fileStat "/private/tmp") ((ok st) (if st.isDir "/private/tmp" "/tmp")) ((err _) "/tmp"))

fn ! readText! p: String -> String
  (resultOr (fileReadString p) "")

fn ! mtimeOf! p: String -> Int64
  (match (fileLstat p) ((ok st) st.mtimeNs) ((err _) -1))

fn ! entries! p: String -> (List String)
  (resultOr (dirList p) (list))

fn ! entry! dir: String body: String -> Bool
  (and (ok? (dirCreate dir)) (ok? (fileWrite (str dir "/bin") body)))

fn ! pointer! file: String target: String stamp: Int64 -> Bool
  (and (ok? (fileWrite file (str target "\n"))) (ok? (fileUtime file stamp)))

fn ! clone! from: String to: String -> Bool
  (= (fr/runOneLimited (fr/job (jl/cliCopyArgv from to) "/" (list "PATH=/usr/bin:/bin")) (fr/limits 120 4)).exit 0)

fn cliRows rows: (List (Pair String String)) -> (List String)
  (map pairSecond (filter (fn [r] (= (pairFirst r) "ASL_NATIVE_CLI_CACHE")) rows))

fn buildMark? name: String -> Bool
  (or (= name "lock") (or (stringStartsWith? name "tmp.") (or (stringStartsWith? name "bg") (or (= name "build.log") (stringStartsWith? name "asl1-")))))

fn src dir: String stamp: Int64 own: Bool fits: Bool -> jl/CliSource
  (jl/CliSource :dir dir :stamp stamp :own own :fits fits)

fn ! decisionGates! -> Bool
  (let [a5 (src "cli-a" 5 true false)
        b9 (src "cli-b" 9 false false)
        b9fit (src "cli-b" 9 false true)
        a5fit (src "cli-a" 5 true true)]
    (do
      (assert (jl/resyncNeeded? -1 false (list a5)) "a missing private head is looked at")
      (assert (jl/resyncNeeded? 5 false (list b9)) "a shared pointer newer than the private head (a deploy moved it) is looked at")
      (assert (jl/resyncNeeded? 9 true (list a5)) "a private entry the root's sources moved past is looked at")
      (assert (not (jl/resyncNeeded? 12 false (list a5 b9))) "a private head newer than every shared pointer, with no source moved, stays")
      (assert (not (jl/resyncNeeded? 9 false (list b9))) "a private head as new as the shared one stays")
      (assert (not (jl/resyncNeeded? -1 true (list))) "nothing to follow is nothing to do")
      (assert (= (jl/pickSource true (list a5 b9fit) 77) (pair "" 77)) "a private entry that fits the root is kept and stamped now")
      (assert (= (jl/pickSource false (list a5 b9fit) 77) (pair "cli-b" 77)) "else the shared entry that fits the root, stamped now: an unmodified worktree runs main's fresh build")
      (assert (= (jl/pickSource false (list a5fit b9fit) 77) (pair "cli-b" 77)) "of several fitting entries the newest")
      (assert (= (jl/pickSource false (list a5 b9) 77) (pair "cli-a" 5)) "with none fitting, the head's own pointer with its mtime: a worktree whose CLI sources differ keeps its own entry")
      (assert (= (jl/pickSource false (list b9) 77) (pair "cli-b" 1000000000)) "with none fitting and no own pointer, the borrowed one with the verify stamp, which the child verifies before trusting")
      true))

fn ! matchGates! base: String -> Bool
  (let [root (str base "/root")
        shared (str base "/shared")
        home (str base "/home")
        cli (str home "/.asl/run/nativeCli")
        heads (list "head_own" "head_tool")
        sources (list (pair "ASL_NATIVE_CLI_CACHE" shared))
        snap (fn [name body] (and (entry! (str shared "/" name) "bin\n") (and (ok? (fileWrite (str shared "/" name "/deps") "a.asl\n")) (and (ok? (dirCreate (str shared "/" name "/src"))) (ok? (fileWrite (str shared "/" name "/src/a.asl") body))))))
        made (and (ok? (dirCreate root)) (and (snap "cli-x" "X\n") (and (snap "cli-y" "Y\n") (and (pointer! (str shared "/head_own") (str shared "/cli-x") 1700000000000000000) (and (pointer! (str shared "/head_tool") (str shared "/cli-y") 1700000100000000000) (ok? (fileWrite (str root "/a.asl") "X\n")))))))
        rows1 (cliRows (jl/seedCachesWith! "none" home sources heads root))
        own1 (readText! (str cli "/head_own"))
        stamp1 (mtimeOf! (str cli "/head_own"))
        rebased (and (ok? (fileWrite (str root "/a.asl") "Y\n")) (ok? (fileUtime (str root "/a.asl") (+ stamp1 1000000000))))
        rows2 (cliRows (jl/seedCachesWith! "none" home sources heads root))
        own2 (readText! (str cli "/head_own"))
        stamp2 (mtimeOf! (str cli "/head_own"))
        edited (and (ok? (fileWrite (str root "/a.asl") "Z\n")) (ok? (fileUtime (str root "/a.asl") (+ stamp2 1000000000))))
        rows3 (cliRows (jl/seedCachesWith! "none" home sources heads root))
        own3 (readText! (str cli "/head_own"))
        stamp3 (mtimeOf! (str cli "/head_own"))
        rows4 (cliRows (jl/seedCachesWith! "none" home sources heads root))
        planted (and (ok? (fileWrite (str base "/guess.txt") "Q\n")) (and (ok? (pathRemove (str cli "/cli-x/src/a.asl"))) (and (ok? (pathSymlink (str base "/guess.txt") (str cli "/cli-x/src/a.asl"))) (and (ok? (fileWrite (str root "/a.asl") "Q\n")) (ok? (fileUtime (str root "/a.asl") (+ stamp3 1000000000)))))))
        rows5 (cliRows (jl/seedCachesWith! "none" home sources heads root))
        stamp5 (mtimeOf! (str cli "/head_own"))
        cleaned (pathRemove base)]
    (do
      (assert (and made (and rebased edited)) "the fake shared cache with two snapshots and the root were written")
      (assert (and (= rows1 (list "cliEntry")) (and (= own1 (str cli "/cli-x\n")) (> stamp1 1700000100000000000))) (str "an unmodified worktree whose sources equal its own entry keeps it, restamped, though main's pointer is newer: " (c/joinSep rows1 " ") " " own1))
      (assert (and (= rows2 (list "resync")) (and (= own2 (str cli "/cli-y\n")) (> stamp2 stamp1))) (str "a worktree rebased onto main's sources follows main's entry, stamped now, so its child runs it without a build: " (c/joinSep rows2 " ") " " own2))
      (assert (and (= rows3 (list "resync")) (and (= own3 (str cli "/cli-x\n")) (= stamp3 1700000000000000000))) (str "a worktree whose CLI sources fit no entry gets its own shared pointer with its mtime, so its child verifies and builds once: " (c/joinSep rows3 " ") " " own3))
      (assert (listEmpty? rows4) (str "the next call with nothing moved since changes nothing: " (c/joinSep rows4 " ")))
      (assert (and planted (and (listEmpty? rows5) (= stamp5 1700000000000000000))) "a snapshot file the unit replaced by a symlink never counts as fitting, so the head is not restamped as verified")
      (assert (ok? cleaned) "this part's fixture directory was removed")
      true))


fn ! resyncGates! base: String -> Bool
  (let [shared (str base "/shared")
        home (str base "/home")
        cli (str home "/.asl/run/nativeCli")
        heads (list "head_own" "head_tool")
        sources (list (pair "ASL_NATIVE_CLI_CACHE" shared))
        made (and (entry! (str shared "/cli-a") "a\n") (pointer! (str shared "/head_tool") (str shared "/cli-a") 1700000000000000000))
        rows1 (cliRows (jl/seedCachesWith! "none" home sources heads ""))
        tool1 (readText! (str cli "/head_tool"))
        own1 (readText! (str cli "/head_own"))
        toolStamp1 (mtimeOf! (str cli "/head_tool"))
        ownStamp1 (mtimeOf! (str cli "/head_own"))
        rows2 (cliRows (jl/seedCachesWith! "none" home sources heads ""))
        deployed (and (entry! (str shared "/cli-b") "b\n") (pointer! (str shared "/head_tool") (str shared "/cli-b") 1700000100000000000))
        rows3 (cliRows (jl/seedCachesWith! "none" home sources heads ""))
        tool3 (readText! (str cli "/head_tool"))
        own3 (readText! (str cli "/head_own"))
        toolStamp3 (mtimeOf! (str cli "/head_tool"))
        ownStamp3 (mtimeOf! (str cli "/head_own"))
        bin3 (readText! (str cli "/cli-b/bin"))
        dirs3 (cliDirs! cli)
        built (and (entry! (str cli "/cli-own") "own\n") (ok? (fileWrite (str cli "/head_own") (str cli "/cli-own\n"))))
        rows4 (cliRows (jl/seedCachesWith! "none" home sources heads ""))
        own4 (readText! (str cli "/head_own"))
        left (filter (fn [n] (stringStartsWith? n ".")) (entries! cli))
        outsideP (str base "/outsideP")
        plantedP (and (ok? (dirCreate outsideP)) (and (ok? (fileWrite (str outsideP "/keep.txt") "keep\n")) (ok? (pathSymlink outsideP (str cli "/cli-zz")))))
        deployedC (and (entry! (str shared "/cli-c") "c\n") (pointer! (str shared "/head_tool") (str shared "/cli-c") 1700000200000000000))
        rows5 (cliRows (jl/seedCachesWith! "none" home sources heads ""))
        dirs5 (cliDirs! cli)
        keptP (readText! (str outsideP "/keep.txt"))
        cleaned (pathRemove base)]
    (do
      (assert (and made (and deployed built)) "the fake shared cache and its moves were written")
      (assert (= rows1 (list "cliEntry" "resync")) (str "the first seed copies the tool root's entry and the own root borrows it: " (c/joinSep rows1 " ")))
      (assert (and (= tool1 (str cli "/cli-a\n")) (= own1 (str cli "/cli-a\n"))) (str "both private heads name the private copy: " tool1 " " own1))
      (assert (= toolStamp1 1700000000000000000) "the own pointer keeps the shared mtime")
      (assert (= ownStamp1 1000000000) "a borrowed pointer carries the verify stamp, so the child verifies it against its own sources")
      (assert (listEmpty? rows2) (str "a second call with nothing moved re-seeds nothing: " (c/joinSep rows2 " ")))
      (assert (= rows3 (list "resync" "resync")) (str "a deploy that moved the shared pointer re-seeds both heads: " (c/joinSep rows3 " ")))
      (assert (and (= tool3 (str cli "/cli-b\n")) (and (= own3 (str cli "/cli-b\n")) (= bin3 "b\n"))) (str "the private heads follow the new entry, copied: " tool3 " " own3 " " bin3))
      (assert (and (= toolStamp3 1700000100000000000) (= ownStamp3 1000000000)) "the re-seed keeps the shared mtime for the own pointer and the verify stamp for the borrowed one")
      (assert (and (listEmpty? rows4) (= own4 (str cli "/cli-own\n"))) (str "a private head the child rebuilt after the deploy stays: " own4))
      (assert (= dirs3 (list "cli-b")) (str "L3: after the deploy re-pointed both heads, the private cache holds one cli directory per referenced entry: " (c/joinSep dirs3 " ")))
      (assert (and plantedP (and deployedC (= rows5 (list "resync")))) (str "a later deploy re-points the tool head: " (c/joinSep rows5 " ")))
      (assert (and (= dirs5 (list "cli-c" "cli-own")) (= keptP "keep\n")) (str "L3: unreferenced copies are removed and a planted cli symlink is unlinked, not followed: " (c/joinSep dirs5 " ") " " keptP))
      (assert (listEmpty? left) (str "no partial seed or pointer file is left in the private cache: " (c/joinSep left " ")))
      (assert (ok? cleaned) "this part's fixture directory was removed")
      true))

fn ! symlinkGates! base: String -> Bool
  (let [shared (str base "/shared")
        outside (str base "/outside")
        heads (list "head_tool")
        sources (list (pair "ASL_NATIVE_CLI_CACHE" shared))
        made (and (entry! (str shared "/cli-a") "a\n") (and (pointer! (str shared "/head_tool") (str shared "/cli-a") 1700000000000000000) (and (ok? (dirCreate outside)) (ok? (fileWrite (str outside "/victim.txt") "victim\n")))))
        homeA (str base "/homeA")
        linkedA (and (ok? (dirCreate (str homeA "/.asl/run"))) (ok? (pathSymlink outside (str homeA "/.asl/run/nativeCli"))))
        rowsA (cliRows (jl/seedCachesWith! "none" homeA sources heads ""))
        outsideA (entries! outside)
        homeB (str base "/homeB")
        cliB (str homeB "/.asl/run/nativeCli")
        seededB (cliRows (jl/seedCachesWith! "none" homeB sources heads ""))
        linkedB (and (ok? (pathRemove (str cliB "/head_tool"))) (ok? (pathSymlink (str outside "/victim.txt") (str cliB "/head_tool"))))
        movedB (and (entry! (str shared "/cli-b") "b\n") (pointer! (str shared "/head_tool") (str shared "/cli-b") 1700000100000000000))
        rowsB (cliRows (jl/seedCachesWith! "none" homeB sources heads ""))
        victimB (readText! (str outside "/victim.txt"))
        homeC (str base "/homeC")
        cliC (str homeC "/.asl/run/nativeCli")
        seededC (cliRows (jl/seedCachesWith! "none" homeC sources heads ""))
        outsideC (str base "/outsideC")
        linkedC (and (ok? (dirCreate outsideC)) (and (ok? (pathRemove (str cliC "/cli-b"))) (ok? (pathSymlink outsideC (str cliC "/cli-b")))))
        movedC (pointer! (str shared "/head_tool") (str shared "/cli-b") 1700000200000000000)
        rowsC (cliRows (jl/seedCachesWith! "none" homeC sources heads ""))
        outsideCLeft (entries! outsideC)
        headC (readText! (str cliC "/head_tool"))
        shared2 (str base "/shared2")
        secret (str base "/secret.txt")
        made2 (and (entry! (str shared2 "/cli-e") "e\n") (and (pointer! (str shared2 "/head_tool") (str shared2 "/cli-e") 1700000000000000000) (and (ok? (fileWrite secret "SECRETVALUE\n")) (and (ok? (pathSymlink secret (str shared2 "/head_link"))) (and (ok? (pathSymlink outside (str shared2 "/cli-f"))) (pointer! (str shared2 "/head_tool2") (str shared2 "/cli-f") 1700000000000000000))))))
        homeD (str base "/homeD")
        cliD (str homeD "/.asl/run/nativeCli")
        rowsD (cliRows (jl/seedCachesWith! "none" homeD (list (pair "ASL_NATIVE_CLI_CACHE" shared2)) (list "head_tool" "head_tool2") ""))
        entriesD (entries! cliD)
        copiedSecret (listAny? (fn [n] (stringContains? (readText! (str cliD "/" n)) "SECRETVALUE")) entriesD)
        tool2D (readText! (str cliD "/head_tool2"))
        rowsF (cliRows (jl/seedCachesWith! "none" (str base "/homeF") (list (pair "ASL_NATIVE_CLI_CACHE" shared2)) (list "head_link" "head_tool2" "head_none") ""))
        whyF (optionOr (listHead rowsF) "")
        rootE (str base "/rootE")
        fakeHome (str base "/fakeHome")
        decoys (and (ok? (dirCreate (str fakeHome "/.asl"))) (and (ok? (fileWrite (str fakeHome "/.asl/keys.env") "DECOY_KEY=1\n")) (ok? (fileWrite (str fakeHome "/.asl/gateway.asn") "(:decoy)\n"))))
        linkedE (and (ok? (dirCreate (str rootE "/.asl/run/agentLoop"))) (ok? (pathSymlink (str fakeHome "/.asl") (jl/jailHome rootE))))
        rowsE (jl/childEnvIn! rootE (list "PATH=/usr/bin:/bin" (str "ASL_NATIVE_CLI_CACHE=" shared)) (list) fakeHome true)
        fakeLeft (listSort (entries! (str fakeHome "/.asl")))
        planE (jl/jailPlan! "sandbox-exec" false rootE (jl/jailHome rootE) rowsE (list) (list) false fakeHome (list shared))
        fakeReal (resultOr (realPath (str fakeHome "/.asl")) (str fakeHome "/.asl"))
        granted (filter (fn [p] (or (= p fakeReal) (stringStartsWith? fakeReal (str p "/")))) (listAppend planE.writes planE.reads))
        freePlain (jl/linkFree! base (str base "/homeB/.asl/run/absent/deeper"))
        freeLinked (jl/linkFree! base (str homeA "/.asl/run/nativeCli/x"))
        freeDots (jl/linkFree! base (str base "/../s"))
        freeOutside (jl/linkFree! (str base "/homeB") (str base "/homeC"))
        cleaned (pathRemove base)]
    (do
      (assert (and made (and linkedA (and linkedB (and movedB (and linkedC (and movedC (and made2 (and decoys linkedE)))))))) "the symlink fixtures were planted")
      (assert (= rowsA (list "failed: a symlink in the private cache path")) (str "a private cache that is a symlink is refused: " (c/joinSep rowsA " ")))
      (assert (= outsideA (list "victim.txt")) (str "nothing was written through the private cache symlink: " (c/joinSep outsideA " ")))
      (assert (= seededB (list "cliEntry")) "the private cache of the head symlink case was seeded first")
      (assert (= rowsB (list "failed: a private head pointer is a symlink")) (str "a private head pointer that is a symlink is refused: " (c/joinSep rowsB " ")))
      (assert (= victimB "victim\n") "the file a planted head symlink names is not overwritten")
      (assert (= seededC (list "cliEntry")) "the private cache of the cli symlink case was seeded first")
      (assert (= rowsC (list "failed: the private cli directory is a symlink")) (str "a private cli directory that is a symlink is refused: " (c/joinSep rowsC " ")))
      (assert (and (listEmpty? outsideCLeft) (= headC (str cliC "/cli-b\n"))) (str "nothing was copied through the cli symlink and the head was not moved onto it: " (c/joinSep outsideCLeft " ") " " headC))
      (assert (and (stringStartsWith? whyF "failed: no head pointer of this root names a cli directory in the shared cache (head_link: the pointer file is a symlink; head_tool2: names ") (and (stringContains? whyF "/cli-f, not a plain directory; ") (stringEndsWith? whyF "head_none: no such pointer file)"))) (str "a failed seed names the check that refused each head: " whyF))
      (assert (= rowsD (list "cliEntry")) (str "a shared cache with planted symlinks still seeds its plain entry: " (c/joinSep rowsD " ")))
      (assert (and (not (listContains? entriesD "head_link")) (not copiedSecret)) (str "a shared head pointer that is a symlink is not copied: " (c/joinSep entriesD " ")))
      (assert (and (not (listContains? entriesD "cli-f")) (= tool2D (str shared2 "/cli-f\n"))) (str "a shared cli directory that is a symlink is not copied, its pointer keeps naming the shared cache: " tool2D))
      (assert (= fakeLeft (list "gateway.asn" "keys.env")) (str "a jail home planted as a symlink to the HOME's .asl gets nothing created, seeded or written through it: " (c/joinSep fakeLeft " ")))
      (assert (listEmpty? granted) (str "the plan grants no read or write that covers the HOME's .asl behind the planted jail home: " (c/joinSep granted " ")))
      (assert (= (listTake planE.writes 1) (list (resultOr (realPath rootE) rootE))) "the root itself stays writable")
      (assert freePlain "a path whose parts below base are plain directories or absent is link free")
      (assert (not freeLinked) "a symlinked part makes a path not link free")
      (assert (not freeDots) "a .. segment is not link free")
      (assert (not freeOutside) "a path outside base is not link free")
      (assert (ok? cleaned) "this part's fixture directory was removed")
      true))

fn ! realHead! toolRoot: String -> String
  (firstLine (readText! (str (optionOr (envGet "HOME") "") "/.asl/run/nativeCli/" (jl/cliHeadName toolRoot))))

fn firstLine text: String -> String
  (stringTrim (optionOr (listHead (stringSplit text "\n")) ""))

fn ! jailedGates! base: String -> Bool
  (let [toolRoot (resultOr (realPath ".") ".")
        realDir (realHead! toolRoot)
        key (optionOr (listLast (stringSplit realDir "/")) "")
        root (str base "/root")
        shared (str base "/shared")
        made (and (ok? (dirCreate root)) (and (ok? (dirCreate shared)) (ok? (fileWrite (str root "/a.asl") "(module fx/a\n  :x [one])\n\nfn one -> Int64\n  1\n"))))
        clonedNew (and (stringStartsWith? key "cli-") (clone! realDir (str shared "/" key)))
        clonedOld (and clonedNew (clone! realDir (str shared "/cli-stale")))
        dep (firstLine (readText! (str shared "/cli-stale/deps")))
        altered (ok? (fileWrite (str shared "/cli-stale/src/" dep) (str (readText! (str shared "/cli-stale/src/" dep)) "\n; stale\n")))
        headFile (str shared "/" (jl/cliHeadName toolRoot))
        oldPointed (pointer! headFile (str shared "/cli-stale") 1700000000000000000)
        inherited (list "PATH=/usr/bin:/bin" (str "ASL_CLI_ROOT=" toolRoot) (str "ASL_NATIVE_CLI_CACHE=" shared))
        fakeHome (str base "/fakeHome")
        rows0 (jl/childEnvIn! root inherited (list) fakeHome true)
        home (jl/jailHome root)
        cli (str home "/.asl/run/nativeCli")
        before (readText! (str cli "/" (jl/cliHeadName toolRoot)))
        deployed (ok? (fileWrite headFile (str shared "/" key "\n")))
        rows (jl/childEnvIn! root inherited (list) fakeHome true)
        after (readText! (str cli "/" (jl/cliHeadName toolRoot)))
        tool (jl/jailTool!)
        plan (jl/jailPlan! tool false root home rows (list toolRoot) (list) false (optionOr (envGet "HOME") "") (list shared))
        done (if (stringEmpty? tool) (fr/Done :idx 0 :exit -1 :out "" :ms 0 :verdict "skipped")
               (fr/runOneLimited (fr/job (jl/jailWrap! plan (list (str toolRoot "/bin/asl") "check" "a.asl")) root (cons (str "ASL_ROOT=" root) rows)) (fr/limits 90 64)))
        marks (filter buildMark? (entries! cli))
        report (readText! (str home "/.asl/seedReport.asn"))
        cleaned (pathRemove base)]
    (do
      (assert (and made (and clonedNew (and clonedOld (and altered (and oldPointed deployed))))) (str "a real pinned entry of the tool root exists and was cloned into the fake shared cache, key " key))
      (assert (= before (str cli "/cli-stale\n")) (str "the first jailed call seeded the stale entry: " before))
      (assert (listEmpty? marks) (str "no native build ran in the private cache (no lock, tmp., bg, build.log or asl1- entry): " (c/joinSep marks " ")))
      (assert (not (stringContains? done.out "predates its sources")) (str "the jailed call did not take the native CLI as stale: " done.out))
      (assert (or (stringEmpty? tool) (= done.exit 0)) (str "the jailed bin/asl check ran, exit " (stringFromInt64 done.exit) " verdict " done.verdict ": " done.out))
      (assert (or (stringEmpty? tool) (stringContains? done.out "ok a.asl")) (str "the jailed check printed its result: " done.out))
      (assert (= after (str cli "/" key "\n")) (str "after the deploy the next jailed call follows the shared pointer to the new entry: " after))
      (assert (and (stringContains? report ":how \"cliEntry\")\n(:seed :cache \"ASL_NATIVE_CLI_CACHE\" :how \"resync\")") (= (listLength (stringSplit report ":how \"resync\"")) 4)) (str "the seed report keeps the first seed and appends the re-seed of the later call: " report))
      (assert (ok? cleaned) "this part's fixture directory was removed")
      true))

fn ! partBase! tag: String -> String
  (let [p (str (tmpBase!) "/leonjailcli-" (stringFromInt64 (monotonicNs)) "-" tag)
        made (dirCreate p)]
    p)

fn ! runTests -> Bool
  (let [typed (typeGates! (partBase! "t"))
        jailed (jailedGates! (partBase! "j"))
        decided (decisionGates!)
        resynced (resyncGates! (partBase! "u"))
        matched (matchGates! (partBase! "m"))
        refused (symlinkGates! (partBase! "s"))]
    (do
      (assert (and decided (and resynced (and matched (and typed (and refused jailed))))) "every part ran")
      true))

fn ! cliDirs! cli: String -> (List String)
  (listSort (filter (fn [n] (stringStartsWith? n "cli-")) (entries! cli)))

; (:m :ref LEON-JAIL-CLI-CACHE :do "fix round M1/M2/L5: one fixture per case, a private cli-x seeded from a shared pointer with mtime T1 whose snapshot does not fit the root, then one file of the private entry or the root disturbed and one re-seed run in its own process through fleet/run, bounded at 90 s. Every case must return in time and leave the private head at T1: the entry is suspect, nothing fits, and the own pointer it already names is kept. A stamp other than T1 means the harness read through the disturbance (a symlinked deps file, an oversize deps file, a .. or absolute row) and found it fitting; a timeout means it opened a FIFO")
fn ! typeCase! base: String tag: String disturb: (fn [String String String] -> Bool) -> (Pair Bool String)
  (let [dir (str base "/" tag)
        root (str dir "/root")
        shared (str dir "/shared")
        home (str dir "/home")
        priv (str home "/.asl/run/nativeCli/cli-x")
        made (and (ok? (dirCreate root)) (and (entry! (str shared "/cli-x") "bin\n") (and (ok? (fileWrite (str shared "/cli-x/deps") "a.asl\n")) (and (ok? (dirCreate (str shared "/cli-x/src"))) (and (ok? (fileWrite (str shared "/cli-x/src/a.asl") "X\n")) (and (pointer! (str shared "/head_own") (str shared "/cli-x") 1700000000000000000) (and (ok? (fileWrite (str root "/a.asl") "R\n")) (ok? (fileUtime (str root "/a.asl") 1600000000000000000)))))))))
        seeded (cliRows (jl/seedCachesWith! "none" home (list (pair "ASL_NATIVE_CLI_CACHE" shared)) (list "head_own") root))
        disturbed (disturb dir root priv)
        done (fr/runOneLimited (fr/job (list "./bin/asl" "run" "asl/packages/asl-agent/tests/jailCliCacheDriver.asl" home shared root "head_own") "." (fr/childEnv (list))) (fr/limits 90 16))]
    (pair (and made (and (= seeded (list "cliEntry")) disturbed)) (str "exit " (stringFromInt64 done.exit) " " done.verdict " " (stringTrim done.out))))

fn ! fifo! p: String -> Bool
  (= (fr/runOneLimited (fr/job (list "/usr/bin/mkfifo" p) "/" (list "PATH=/usr/bin:/bin")) (fr/limits 10 2)).exit 0)

fn heldAtT1? out: String -> Bool
  (and (stringStartsWith? out "exit 0 ") (stringContains? out ":stamp 1700000000000000000)"))

fn ! typeGates! base: String -> Bool
  (let [symlinked (typeCase! base "s" (fn [dir root priv] (and (ok? (dirCreate (str dir "/decoy"))) (and (ok? (fileWrite (str dir "/decoy/deps") "b.asl\n")) (and (ok? (pathRemove (str priv "/deps"))) (and (ok? (pathSymlink (str dir "/decoy/deps") (str priv "/deps"))) (and (ok? (fileWrite (str root "/b.asl") "B\n")) (ok? (fileWrite (str priv "/src/b.asl") "B\n")))))))))
        fifoDeps (typeCase! base "f" (fn [dir root priv] (and (ok? (pathRemove (str priv "/deps"))) (fifo! (str priv "/deps")))))
        fifoRoot (typeCase! base "r" (fn [dir root priv] (and (ok? (fileWrite (str priv "/deps") "c.asl\na.asl\n")) (and (ok? (fileWrite (str priv "/src/c.asl") "C\n")) (fifo! (str root "/c.asl"))))))
        fifoSnap (typeCase! base "n" (fn [dir root priv] (and (ok? (pathRemove (str priv "/src/a.asl"))) (and (fifo! (str priv "/src/a.asl")) (ok? (fileWrite (str root "/a.asl") "R\n"))))))
        oversize (typeCase! base "o" (fn [dir root priv] (and (ok? (fileWrite (str priv "/deps") (doubled "b.asl\n" 18))) (and (ok? (fileWrite (str root "/b.asl") "B\n")) (ok? (fileWrite (str priv "/src/b.asl") "B\n"))))))
        dotted (typeCase! base "d" (fn [dir root priv] (and (ok? (fileWrite (str priv "/deps") "../decoy/b.asl\n")) (and (ok? (dirCreate (str dir "/decoy"))) (and (ok? (fileWrite (str dir "/decoy/b.asl") "B\n")) (and (ok? (dirCreate (str priv "/decoy"))) (ok? (fileWrite (str priv "/decoy/b.asl") "B\n"))))))))
        absolute (typeCase! base "a" (fn [dir root priv] (and (ok? (fileWrite (str priv "/deps") "/abs/b.asl\n")) (and (ok? (dirCreate (str root "/abs"))) (and (ok? (fileWrite (str root "/abs/b.asl") "B\n")) (and (ok? (dirCreate (str priv "/src/abs"))) (ok? (fileWrite (str priv "/src/abs/b.asl") "B\n"))))))))
        cleaned (pathRemove base)]
    (do
      (assert (and (pairFirst symlinked) (heldAtT1? (pairSecond symlinked))) (str "M1: a private deps file replaced by a symlink to a decoy outside the root is not read through, its rows are not used: " (pairSecond symlinked)))
      (assert (and (pairFirst fifoDeps) (heldAtT1? (pairSecond fifoDeps))) (str "M2: a FIFO at the private deps file is not opened; the re-seed returns and takes the entry as suspect: " (pairSecond fifoDeps)))
      (assert (and (pairFirst fifoRoot) (heldAtT1? (pairSecond fifoRoot))) (str "M2: a FIFO at a root source a deps row names is not opened: " (pairSecond fifoRoot)))
      (assert (and (pairFirst fifoSnap) (heldAtT1? (pairSecond fifoSnap))) (str "M2: a FIFO at a snapshot file is not opened: " (pairSecond fifoSnap)))
      (assert (and (pairFirst oversize) (heldAtT1? (pairSecond oversize))) (str "M2: a deps file over the size cap is not read and is suspect: " (pairSecond oversize)))
      (assert (and (pairFirst dotted) (heldAtT1? (pairSecond dotted))) (str "L5: a deps row with .. never makes the harness stat or read the decoy outside the root: " (pairSecond dotted)))
      (assert (and (pairFirst absolute) (heldAtT1? (pairSecond absolute))) (str "L5: a deps row with an absolute path makes the entry not match: " (pairSecond absolute)))
      (assert (ok? cleaned) "this part's fixture directory was removed")
      true))

fn doubled s: String n: Int64 -> String
  (if (<= n 0) s (doubled (str s s) (- n 1)))
