(module asl-cli/tests/binNoPersistTest
  :x [runTests]
  :i [(asl-tools/fleet/run :a run) (asl/packages/asl-cli/src/nativeCli :a nc) (asl/packages/asl-cli/src/nativeBuild :a nb) (asl-tools/nativeTest :a nt)])

; (:m :ref BIN-NO-PERSIST-20261026 :do "inline runs persist no binary or object, and the build stores are held under a byte cap with live worktree heads pinned")
fn ! filesUnder! path: String -> (List String)
  (match (fileLstat path)
    ((err _) (list))
    ((ok st) (if (and st.isDir (not st.isSymlink))
               (fold (fn [(acc (List String)) (n String)] -> (List String) (listAppend acc (filesUnder! (str path "/" n)))) (list) (resultOr (dirList path) (list)))
               (list path))))

fn ! put! path: String bytes: Int64 -> Bool
  (ok? (fileWrite path (stringRepeat "x" bytes)))

fn ! entry! dir: String bytes: Int64 ageHours: Int64 -> Bool
  (let [(at (- (nowNs) (* ageHours 3600000000000)))]
    (and (ok? (dirCreate dir)) (and (put! (str dir "/bin") bytes) (and (ok? (fileUtime (str dir "/bin") at)) (ok? (fileUtime dir at))))))

fn ! entries! cache: String prefix: String n: Int64 ageHours: Int64 -> Int64
  (listLength (filter (fn [(i Int64)] -> Bool (entry! (str cache "/" prefix (stringFromInt64 i)) 1000 ageHours)) (range 0 n)))

fn ! oldFile! path: String bytes: Int64 ageHours: Int64 -> Bool
  (and (put! path bytes) (ok? (fileUtime path (- (nowNs) (* ageHours 3600000000000)))))

; (:m :ref INLINE-STAGE-FLAKE :do "the inline texts carry a tag of this run (pid and clock), so the staged file each one gets is named by a digest no other run can produce: before, the 101 texts were the same in every run of this test in a tree, and a staged file of a run beside this one, still on disk at the after snapshot, counted as a leak of this one")
fn inlineCode tag: String i: Int64 -> String
  (str "(let [(tag \"" tag "\")] (println (+ " (stringFromInt64 i) " 1000)))")

fn ! inlineRun! asl: String cwd: String store: String tag: String i: Int64 -> Bool
  (let [(r (run/runGuarded (list asl "-e" (inlineCode tag i)) cwd (run/childEnv (list (str "ASL_NATIVE_TEST_CACHE=" store))) (run/limits 900 24)))]
    (and (= r.exitCode 0) (= r.stdout (str (stringFromInt64 (+ i 1000)) "\n"))))

; (:m :ref BIN-NO-PERSIST-20261026 :do "the runs use a store of their own, so a suite running beside this one cannot add files to it; the staged text and entry wrappers stay in the workspace store, which is watched too")
; (:m :ref RUNCOST :do "the workspace dirs are shared with suites running in parallel, so only what these runs can write there is watched: the wrappers of this store (entries/<key of the store>, as nativeTest's wrapperDirIn names them) and staged text named by the digest of one of these texts; the whole store is still watched")
fn ! ownStaged? digests: (List String) path: String -> Bool
  (fold (fn [(acc Bool) (d String)] -> Bool (or acc (stringEndsWith? path (str "x" d ".asl")))) false digests)

fn ! watched! root: String store: String digests: (List String) -> (List String)
  (listAppend (filesUnder! store)
              (listAppend (filter (fn [(p String)] -> Bool (ownStaged? digests p)) (filesUnder! (str root "/.asl/cache/nativeTest/outside")))
                          (filesUnder! (str root "/.asl/cache/nativeTest/entries/" (nt/slotKey "entries" (resultOr (realPath store) store))))))

fn ! testInlineLeavesNothing root: String work: String -> Bool
  (let [(asl (str root "/bin/asl"))
        (store (str work "/store"))
        (tag (str "inlineFlake-" (stringFromInt64 (procSelf)) "-" (stringFromInt64 (nowNs))))
        (digests (map (fn [(i Int64)] -> String (optionOr (stringSlice (bytesSha256 (stringToBytes (inlineCode tag i))) 0 16) "")) (range 0 101)))
        (warm (inlineRun! asl root store tag 0))
        (before (watched! root store digests))
        (ran (listLength (filter (fn [(i Int64)] -> Bool (inlineRun! asl root store tag i)) (range 1 101))))
        (after (watched! root store digests))
        (fresh (filter (fn [(p String)] -> Bool (not (listContains? before p))) after))]
    (do (assert warm "a first asl -e runs")
        (assert (= ran 100) (str "100 distinct asl -e texts print their values: " (stringFromInt64 ran)))
        (assert (listEmpty? fresh) (str "and leave no new file in the store: " (stringFromInt64 (listLength fresh)) " " (stringJoin (listTake fresh 3) " ")))
        (assert (listEmpty? (resultOr (dirList (str store "/ephemeral")) (list))) "no ephemeral slot is left behind")
        true))

fn ! testCap work: String -> Bool
  (let [(cache (str work "/cli"))
        (_ (dirCreate cache))
        (made (listLength (filter (fn [(i Int64)] -> Bool (entry! (str cache "/cli-" (stringFromInt64 i)) 1000 (- 100 i))) (range 0 50))))
        (removed (nc/sweepNativeCache! cache 10000 600000000000))
        (left (filter (fn [(n String)] -> Bool (stringStartsWith? n "cli-")) (resultOr (dirList cache) (list))))
        (bytes (fold (fn [(acc Int64) (n String)] -> Int64 (+ acc (nc/treeBytes! (str cache "/" n)))) 0 left))
        (mods (str work "/modules"))
        (_ (dirCreate mods))
        (_m (map (fn [(i Int64)] -> Bool (and (oldFile! (str mods "/k" (stringFromInt64 i) ".o") 900 (- 100 i)) (oldFile! (str mods "/k" (stringFromInt64 i) ".meta") 100 (- 100 i)))) (range 0 50)))
        (swept (nc/sweepEntries! (nt/moduleEntries! mods) 10000 600000000000))
        (modNames (resultOr (dirList mods) (list)))
        (orphans (filter (fn [(n String)] -> Bool (not (listContains? modNames (if (stringEndsWith? n ".o") (stringReplace n ".o" ".meta") (stringReplace n ".meta" ".o"))))) modNames))]
    (do (assert (= made 50) "50 synthetic cli entries of 1000 bytes")
        (assert (<= bytes 10000) (str "the cli store stays under its 10000-byte cap: " (stringFromInt64 bytes)))
        (assert (= removed 40) (str "by removing the 40 oldest: " (stringFromInt64 removed)))
        (assert (listContains? left "cli-49") "the newest entry stays")
        (assert (<= (pairFirst swept) 10000) (str "50 module objects are swept under the cap too: " (stringFromInt64 (pairFirst swept))))
        (assert (= (listLength modNames) 20) (str "the 10 newest .o and .meta pairs stay: " (stringFromInt64 (listLength modNames))))
        (assert (listEmpty? orphans) (str "an object and its meta go together: " (stringJoin orphans " ")))
        true))

fn ! testPinnedHead work: String -> Bool
  (let [(cache (str work "/pin"))
        (root (str work "/wt_a"))
        (_ (dirCreate cache))
        (_ (dirCreate root))
        (_a (entry! (str cache "/cli-live") 1000 300))
        (_b (entry! (str cache "/cli-dead") 1000 200))
        (_c (entry! (str cache "/cli-new") 1000 100))
        (_n (entries! cache "cli-f" 4 10))
        (liveHead (nc/headPath cache root))
        (deadHead (nc/headPath cache (str work "/gone_wt")))
        (_w (fileWrite liveHead (str cache "/cli-live\n")))
        (_e (fileWrite deadHead (str cache "/cli-dead\n")))
        (_u (fileUtime deadHead (- (nowNs) 36000000000000)))
        (_t (entry! (str cache "/tmp.999999") 1000 100))
        (removed (nc/sweepNativeCache! cache 0 600000000000))
        (names (resultOr (dirList cache) (list)))]
    (do (assert (some? (nc/headRoot! (stringReplace liveHead (str cache "/") ""))) "a head names its root back through the underscores of the path")
        (assert (listContains? names "cli-live") "the oldest entry survives a sweep to cap 0 while a live head names it")
        (assert (fileExists? liveHead) "and the live head stays")
        (refute (listContains? names "cli-dead") "an entry only a dead head names goes")
        (refute (fileExists? deadHead) "the head of a removed worktree goes")
        (refute (listContains? names "cli-new") "an unpinned entry beyond the newest 4 goes under cap 0")
        (refute (listContains? names "tmp.999999") "a tmp dir of a dead builder goes")
        (assert (= removed 4) (str "four removed: " (stringFromInt64 removed)))
        true))

; (:m :ref BIN-NO-PERSIST-20261026 :do "the native CLI store keeps the old prune's floor: nothing younger than 6 hours and the newest 4 of each kind stay at cap 0")
fn ! testFloors work: String -> Bool
  (let [(cache (str work "/floor"))
        (_ (dirCreate cache))
        (_s (entries! cache "seed-f" 4 1))
        (_r (entry! (str cache "/seed-recent") 1000 3))
        (_x (map (fn [(i Int64)] -> Bool (entry! (str cache "/asl1-" (stringFromInt64 i)) 1000 (+ 100 i))) (range 0 5)))
        (removed (nc/sweepNativeCache! cache 0 600000000000))
        (names (resultOr (dirList cache) (list)))
        (asl1s (filter (fn [(n String)] -> Bool (stringStartsWith? n "asl1-")) names))]
    (do (assert (listContains? names "seed-recent") "an entry younger than 6 hours survives cap 0 though it is not among the newest 4")
        (assert (= (listLength asl1s) 4) (str "the newest 4 old asl1 entries stay at cap 0: " (stringJoin asl1s " ")))
        (refute (listContains? names "asl1-4") "the oldest asl1 goes")
        (assert (= removed 1) (str "one removed: " (stringFromInt64 removed)))
        true))

; (:m :ref BIN-NO-PERSIST-20261026 :do "a sweep never deletes what a build in flight uses: a live tmp.PID with no lease stops the sweep, a lock held by another live pid stops it, a leased entry is pinned and the live tmp.PID itself stays")
fn ! drain! g: run/Guarded -> Bool
  (let [(st (run/guardAdvance! g))]
    (match st.out
      ((some _) true)
      ((none) (do (sleepMs 20) (drain! st.guard)))))

fn ! testInFlight work: String -> Bool
  (match (run/guardStart! (list "/bin/sleep" "60") "/" (run/childEnv (list)) (run/limits 90 2))
    ((err _) (do (assert false "a fake build process started") false))
    ((ok g) (let [(pid g.run.pid)
                  (cache (str work "/flight"))
                  (tmp (str cache "/tmp." (stringFromInt64 pid)))
                  (_ (dirCreate tmp))
                  (_t (fileUtime tmp (- (nowNs) 360000000000000)))
                  (_a (entry! (str cache "/rt-held") 1000 300))
                  (_b (entry! (str cache "/rt-free") 1000 300))
                  (_n (entries! cache "rt-f" 4 10))
                  (unleased (nc/sweepNativeCache! cache 0 600000000000))
                  (afterUnleased (resultOr (dirList cache) (list)))
                  (_d (dirCreate (str cache "/leases")))
                  (_u (fileWrite (str cache "/leases/rt-held@" (stringFromInt64 pid)) (str (stringFromInt64 pid) " 0\n")))
                  (_v (fileWrite (str cache "/leases/rt-gone@999999") "999999 0\n"))
                  (_l (dirCreate (str cache "/lock")))
                  (_p (fileWrite (str cache "/lock/pid") (str (stringFromInt64 pid) "\n")))
                  (locked (nc/sweepNativeCache! cache 0 600000000000))
                  (_r (pathRemove (str cache "/lock")))
                  (leased (nc/sweepNativeCache! cache 0 600000000000))
                  (names (resultOr (dirList cache) (list)))
                  (leases (resultOr (dirList (str cache "/leases")) (list)))
                  (_k (run/killTree! pid))
                  (_f (drain! g))]
              (do (assert (and (= unleased 0) (listContains? afterUnleased "rt-free")) (str "a live build holding no lease stops the sweep: " (stringFromInt64 unleased)))
                  (assert (= locked 0) (str "a lock held by another live pid stops the sweep: " (stringFromInt64 locked)))
                  (assert (listContains? names "rt-held") "an entry a live build leases survives a sweep to cap 0")
                  (assert (listContains? names (str "tmp." (stringFromInt64 pid))) "the live build's tmp dir survives")
                  (refute (listContains? names "rt-free") "an unleased old entry beyond the newest 4 goes once the lock is free")
                  (assert (= leased 1) (str "one removed: " (stringFromInt64 leased)))
                  (assert (= leases (list (str "rt-held@" (stringFromInt64 pid)))) (str "a dead pid's lease is dropped, the live one kept: " (stringJoin leases " ")))
                  (refute (fileExists? (str cache "/lock")) "the sweep releases the lock it took")
                  true))))

; (:m :ref BIN-NO-PERSIST-20261026 :do "an entry used after the sweep scanned the store is re-stamped right before deletion and kept")
fn ! testRecheck work: String -> Bool
  (let [(mods (str work "/recheck"))
        (_ (dirCreate mods))
        (_m (map (fn [(i Int64)] -> Bool (and (oldFile! (str mods "/k" (stringFromInt64 i) ".o") 1000 (+ 10 i)) (oldFile! (str mods "/k" (stringFromInt64 i) ".meta") 10 (+ 10 i)))) (range 0 3)))
        (scanned (nt/moduleEntries! mods))
        (_t (fileUtime (str mods "/k0.meta") (nowNs)))
        (swept (nc/sweepEntries! scanned 0 3600000000000))
        (names (resultOr (dirList mods) (list)))]
    (do (assert (listContains? names "k0.o") "an object whose meta was touched after the scan stays")
        (refute (listContains? names "k1.o") "an object untouched since the scan goes")
        (assert (= (pairSecond swept) 2) (str "two removed: " (stringFromInt64 (pairSecond swept))))
        true))

; (:m :ref BIN-NO-PERSIST-20261026 :do "an entry is stamped by the newest file inside it: an old dir holding a freshly written file is recent")
fn ! testInnerStamp work: String -> Bool
  (let [(dir (str work "/inner"))
        (made (entry! dir 100 100))
        (_ (fileUtime (str dir "/bin") (nowNs)))
        (_ (fileUtime dir (- (nowNs) 360000000000000)))
        (e (nc/storeEntry! (list dir) false))
        (swept (nc/sweepEntries! (list e) 0 3600000000000))]
    (do (assert made "the entry was made")
        (assert (< (- (nowNs) e.stamp) 3600000000000) (str "its stamp is the fresh inner file, not the 100-hour-old dir: " (stringFromInt64 (/ (- (nowNs) e.stamp) 1000000000)) "s"))
        (assert (and (= (pairSecond swept) 0) (fileExists? (str dir "/bin"))) "so a sweep to cap 0 keeps it")
        true))

; (:m :ref BIN-NO-PERSIST-20261026 :do "a slot a build has leased survives a sweep to cap 0 however old its files, an unleased old slot goes; the CLI store is swept unless a config row turns it off")
fn ! testSlotLease work: String -> Bool
  (let [(cDir (str work "/nt"))
        (fpDir (str cDir "/" (stringRepeat "a" 64)))
        (held (str fpDir "/" (stringRepeat "b" 64)))
        (free (str fpDir "/" (stringRepeat "c" 64)))
        (_a (entry! held 1000 100))
        (_b (entry! free 1000 100))
        (leased (nt/leaseSlot! held))
        (_u (fileUtime (str held "/lock") (- (nowNs) 360000000000000)))
        (_v (fileUtime held (- (nowNs) 360000000000000)))
        (removed (nt/sweepStoreWith! cDir 0 3600000000000))]
    (do (assert leased "the slot was leased")
        (assert (fileExists? (str held "/bin")) "a slot leased by a live build survives a sweep to cap 0")
        (refute (fileExists? free) "an unleased old slot goes")
        (assert (= removed 1) (str "one removed: " (stringFromInt64 removed)))
        true))

fn ! testSweepDefault work: String -> Bool
  (let [(off (str work "/off"))
        (_ (dirCreate off))
        (_ (fileWrite (str off "/.asl.config.asn") "(:aslConfig :native (:sweep false))\n"))]
    (do (assert (nb/sweepOn? work) "with no :sweep row a native CLI build sweeps")
        (refute (nb/sweepOn? off) ":native :sweep false turns it off")
        true))

; (:m :ref BIN-NO-PERSIST-20261026 :do "a .failed marker is not one of the newest 4 of its kind")
fn ! testFailedMarkers work: String -> Bool
  (let [(cache (str work "/failed"))
        (_ (dirCreate cache))
        (_e (entries! cache "cli-k" 5 100))
        (_f (map (fn [(i Int64)] -> Bool (oldFile! (str cache "/cli-m" (stringFromInt64 i) ".failed") 10 1)) (range 0 4)))
        (_r (nc/sweepNativeCache! cache 0 600000000000))
        (names (resultOr (dirList cache) (list)))
        (kept (filter (fn [(n String)] -> Bool (stringStartsWith? n "cli-k")) names))]
    (do (assert (= (listLength kept) 4) (str "four markers do not push real entries out of the newest 4: " (stringJoin kept " ")))
        true))

fn testCapValue -> Bool
  (do (assert (= (nb/capValue "2G") (some 2147483648)) "2G is 2^31 bytes")
      (assert (= (nb/capValue "512M") (some 536870912)) "512M")
      (assert (= (nb/capValue "\"100K\"") (some 102400)) "a quoted value with a K suffix")
      (assert (= (nb/capValue "4096") (some 4096)) "plain bytes")
      (assert (none? (nb/capValue "lots")) "a word is no cap")
      (assert (none? (nb/capValue "0")) "nor is zero")
      (assert (none? (nb/capValue "9999999999G")) "a cap past Int64 is no cap, not a trap")
      (assert (= (nb/ageValue "60m") (some 3600000000000)) "60m")
      (assert (= (nb/ageValue "6h") (some 21600000000000)) "6h")
      (assert (= (nb/ageValue "90") (some 5400000000000)) "plain minutes")
      (assert (none? (nb/ageValue "9999999999999h")) "an age past Int64 is none")
      true)

; (:m :ref NATIVECLI-HEAD-LEAK :do "with the deadHeadSweep marker in a test-local store a fresh head of a deleted root goes at the first sweep and a fresh head of a live root stays; a store without the marker keeps the 6 hour floor, so the shared store is untouched until the principal opts in")
fn ! testFreshDeadHead work: String -> Bool
  (let [(on (str work "/headOn"))
        (off (str work "/headOff"))
        (root (str work "/wt_live"))
        (gone (str work "/wt_deleted"))
        (_a (dirCreate on))
        (_b (dirCreate off))
        (_c (dirCreate root))
        (_d (dirCreate gone))
        (_m (fileWrite (str on "/deadHeadSweep") ""))
        (liveOn (nc/headPath on root))
        (deadOn (nc/headPath on gone))
        (deadOff (nc/headPath off gone))
        (_w (and (ok? (fileWrite liveOn (str on "/cli-x\n"))) (and (ok? (fileWrite deadOn (str on "/cli-y\n"))) (ok? (fileWrite deadOff (str off "/cli-y\n"))))))
        (aliveFirst (some? (nc/headRoot! (stringReplace deadOn (str on "/") ""))))
        (_g (pathRemove gone))
        (removedOn (nc/sweepNativeCache! on 1000000000 600000000000))
        (removedOff (nc/sweepNativeCache! off 1000000000 600000000000))]
    (do (assert aliveFirst "the head resolves to its root while the root exists")
        (refute (fileExists? deadOn) "with the marker a fresh head of a deleted root is removed at the first sweep")
        (assert (fileExists? liveOn) "a fresh head of a live root stays")
        (assert (= removedOn 1) (str "one removed with the marker: " (stringFromInt64 removedOn)))
        (assert (fileExists? deadOff) "without the marker the 6 hour floor keeps a fresh dead head")
        (assert (= removedOff 0) (str "nothing removed without the marker: " (stringFromInt64 removedOff)))
        (assert (fileExists? (str on "/deadHeadSweep")) "the marker itself is never swept")
        true))

fn ! runTests -> Bool
  (let [(root (resultOr (realPath ".") "."))
        (work (str "/tmp/aslBinNoPersist." (stringFromInt64 (procSelf))))
        (made (dirCreate work))
        (caps (testCapValue))
        (cap (if (ok? made) (testCap work) false))
        (pinned (if (ok? made) (testPinnedHead work) false))
        (flight (if (ok? made) (testInFlight work) false))
        (floors (if (ok? made) (testFloors work) false))
        (recheck (if (ok? made) (testRecheck work) false))
        (inner (if (ok? made) (testInnerStamp work) false))
        (slotLease (if (ok? made) (testSlotLease work) false))
        (sweepDefault (if (ok? made) (testSweepDefault work) false))
        (freshDead (if (ok? made) (testFreshDeadHead work) false))
        (markers (if (ok? made) (testFailedMarkers work) false))
        (inline (if (ok? made) (testInlineLeavesNothing root work) false))
        (cleaned (run/runGuarded (list "/bin/rm" "-rf" work) "/" (run/childEnv (list)) (run/limits 60 4)))]
    (do (assert (ok? made) (str "the work directory " work " was created"))
        (assert caps "the :storeCap row parses")
        (assert cap "a store stays under its cap after 50 synthetic entries")
        (assert pinned "a live head's entry survives the sweep")
        (assert flight "an entry a build in flight uses survives the sweep")
        (assert floors "the 6 hour and newest-4 floors hold at cap 0")
        (assert recheck "an entry used during the sweep is kept")
        (assert inner "an entry is stamped by its newest inner file")
        (assert slotLease "a leased slot survives the store sweep")
        (assert sweepDefault "the CLI store sweep is on by default")
        (assert freshDead "with the opt-in marker a fresh dead head goes, without it the floor holds")
        (assert markers ".failed markers are not counted as newest entries")
        (assert inline "100 distinct asl -e runs leave no new files")
        (assert (= cleaned.exitCode 0) "the work directory was removed")
        true))
