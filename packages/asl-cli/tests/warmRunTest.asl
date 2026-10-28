(module asl-cli/tests/warmRunTest
  :x [runTests]
  :i [(asl-tools/fleet/run :a run) (asl-tools/nativeTest :a nt)])

; (:m :ref RUN-ENTRY-REBUILD-COST :do "a warm asl run of an unchanged script compiles nothing: every unit object, the entry wrapper's included, and the full prelude come from the store, so the spawn log holds one clang (the link), no uname, and the exec of the ephemeral binary, which is gone once the run ends")
; (:m :ref KEPTRUN-AUDIT :do "a prepared script's kept binary is only reused while its import closure is unchanged: an edit to an imported module rebuilds the run")
fn ! sh! cwd: String script: String args: (List String) env: (List String) -> run/Done
  (run/runOneLimited (run/job (listAppend (list "/bin/sh" "-c" script "sh") args) cwd (run/childEnv env)) (run/limits 900 24))

fn ! aslRun! root: String store: String file: String spawnLog: String -> run/Done
  (sh! root "exec ./bin/asl run \"$1\" 2>&1" (list file)
       (list "ASL_ROOT=" "ASL_PRELUDE=" (str "ASL_NATIVE_TEST_CACHE=" store) "ASL_NATIVE_TRACE=1" (str "ASL_SPAWN_LOG=" spawnLog)))

fn ! spawned! log: String -> (List String)
  (map (fn [(l String)] -> String (optionOr (listHead (stringSplit l " ")) ""))
       (filter (fn [(l String)] -> Bool (not (stringEmpty? l))) (stringLines (resultOr (fileReadString log) ""))))

fn ! filesUnder! path: String -> (List String)
  (match (fileLstat path)
    ((err _) (list))
    ((ok st) (if (and st.isDir (not st.isSymlink))
               (fold (fn [(acc (List String)) (n String)] -> (List String) (listAppend acc (filesUnder! (str path "/" n)))) (list) (resultOr (dirList path) (list)))
               (list path))))

fn moduleSrc name: String word: String -> String
  (str "(module " name " :x [word])\n\nfn word -> String\n  \"" word "\"\n")

fn scriptSrc name: String lib: String -> String
  (str "(module " name " :x [main] :i [(" lib " :a lib)])\n\nfn ! main -> Int64\n  (do (println (lib/word)) 0)\n")

fn ! testWarmRun root: String base: String store: String -> Bool
  (let [(lib (str base "/warmLib.asl"))
        (script (str base "/warm.asl"))
        (wroteLib (fileWrite lib (moduleSrc (nt/importPathOf (nt/relativeTo root lib)) "warm-one")))
        (wroteScript (fileWrite script (scriptSrc (nt/importPathOf (nt/relativeTo root script)) (nt/importPathOf (nt/relativeTo root lib)))))
        (cold (aslRun! root store script (str base "/cold.log")))
        (coldSpawns (spawned! (str base "/cold.log")))
        (before (filesUnder! store))
        (warm (aslRun! root store script (str base "/warm.log")))
        (warmSpawns (spawned! (str base "/warm.log")))
        (after (filesUnder! store))
        (fresh (filter (fn [(p String)] -> Bool (not (listContains? before p))) after))
        (clangs (filter (fn [(a String)] -> Bool (= a "clang")) warmSpawns))
        (execd (filter (fn [(a String)] -> Bool (stringContains? a "/ephemeral/run.")) warmSpawns))]
    (do (assert (and (ok? wroteLib) (ok? wroteScript)) "the script and the module it imports are written")
        (assert (and (= cold.exit 0) (stringContains? cold.out "warm-one\n")) (str "a cold run builds and prints the imported word: " cold.out))
        (assert (listContains? coldSpawns "clang") (str "the cold run compiles with clang: " (stringJoin coldSpawns " ")))
        (assert (and (= warm.exit 0) (stringContains? warm.out "warm-one\n")) (str "the warm run prints the same word: " warm.out))
        (assert (stringContains? warm.out ":cache :hit") (str "the warm run reports a cache hit: no unit was recompiled: " warm.out))
        (refute (stringContains? warm.out "NATIVE-MODULE-PHASE") (str "the warm run lowers and compiles no module, the entry wrapper included: " warm.out))
        (assert (= (listLength clangs) 1) (str "the warm run spawns clang once, for the link, and never to compile: " (stringJoin warmSpawns " ")))
        (refute (listContains? warmSpawns "uname") (str "the warm run forks no uname: the host facts are kept per fingerprint: " (stringJoin warmSpawns " ")))
        (assert (= (listLength execd) 1) (str "it execs the binary it linked into an ephemeral slot: " (stringJoin warmSpawns " ")))
        (assert (listEmpty? (resultOr (dirList (str store "/ephemeral")) (list))) "the ephemeral slot and its binary are gone after the run")
        (assert (listEmpty? fresh) (str "the warm run adds no file to the store: " (stringJoin (listTake fresh 3) " ")))
        true))

fn ! testKeptRunClosure root: String base: String store: String -> Bool
  (let [(lib (str base "/keptLib.asl"))
        (script (str base "/kept.asl"))
        (libName (nt/importPathOf (nt/relativeTo root lib)))
        (wroteLib (fileWrite lib (moduleSrc libName "kept-one")))
        (wroteScript (fileWrite script (scriptSrc (nt/importPathOf (nt/relativeTo root script)) libName)))
        (prepared (sh! root "exec ./bin/asl run asl/tools/nativeTest.asl prepare \"$1\" 2>&1" (list script)
                       (list "ASL_ROOT=" "ASL_PRELUDE=" (str "ASL_NATIVE_TEST_CACHE=" store))))
        (kept (aslRun! root store script (str base "/kept1.log")))
        (keptSpawns (spawned! (str base "/kept1.log")))
        (edited (fileWrite lib (moduleSrc libName "kept-two")))
        (rebuilt (aslRun! root store script (str base "/kept2.log")))
        (rebuiltSpawns (spawned! (str base "/kept2.log")))]
    (do (assert (and (ok? wroteLib) (ok? wroteScript)) "the kept script and its module are written")
        (assert (= prepared.exit 0) (str "nativeTest prepare keeps a binary for the script: " prepared.out))
        (assert (and (= kept.exit 0) (stringContains? kept.out "kept-one\n")) (str "the prepared script prints its module's word: " kept.out))
        (refute (listContains? keptSpawns "clang") (str "it runs from the kept binary with no clang: " (stringJoin keptSpawns " ")))
        (assert (ok? edited) "the imported module is edited")
        (assert (and (= rebuilt.exit 0) (stringContains? rebuilt.out "kept-two\n")) (str "after the imported module changes the run prints the new word, not the kept binary's: " rebuilt.out))
        (assert (listContains? rebuiltSpawns "clang") (str "and that run rebuilt: " (stringJoin rebuiltSpawns " ")))
        true))

; (:m :do "a failed assert ends the suite before its cleanup, so each run first removes the scratch roots of runs whose process is gone")
fn ! deadScratch! root: String -> (List String)
  (filter (fn [(n String)] -> Bool
            (and (stringStartsWith? n "warmRun-")
                 (not (resultOr (procAlive? (optionOr (stringToInt64 (optionOr (stringSlice n 8 (stringLength n)) "")) 0)) false))))
          (resultOr (dirList (str root "/.asl/cache")) (list)))

fn ! sweepStale! root: String -> (List String)
  (do (map (fn [(n String)] -> Int64 (sh! "/" "rm -rf \"$1\"" (list (str root "/.asl/cache/" n)) (list)).exit) (deadScratch! root))
      (deadScratch! root))

fn ! runTests -> Bool
  (let [(root (resultOr (realPath ".") "."))
        (stale (sweepStale! root))
        (base (str root "/.asl/cache/warmRun-" (stringFromInt64 (procSelf))))
        (store (str base "/store"))
        (made (dirCreate store))
        (warmOk (testWarmRun root base store))
        (keptOk (testKeptRunClosure root base store))
        (cleaned (sh! "/" "rm -rf \"$1\"" (list base) (list)))]
    (do (assert (listEmpty? stale) (str "the scratch roots of dead runs are swept first: " (stringJoin stale " ")))
        (assert (ok? made) "the scratch store is created")
        (assert warmOk "a warm run compiles nothing and leaves nothing")
        (assert keptOk "a kept run notices an edited import")
        (assert (= cleaned.exit 0) "the scratch root is removed")
        true))
