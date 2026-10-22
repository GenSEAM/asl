(module asl-target-llvm/tests/rcTest
  :x [runTests Libs Captured runtimes! sh shellQuote linkCmd statOf diagText]
  :i [(asl-ir/link :a lk)
      (asl-ir/types :a irTy)
      (asl-target-llvm :a llvm)
      (asl/packages/asl-cli/src/system :a sys)
      (asl/packages/asl-cli/src/asl1Cache :a cache)
      (asl/packages/asl-cli/src/nativeBuild :a nb)
      (tools/fleet/run :a run)])

(schema Libs
  (:f plain String)
  (:f asan String)
  (:f notrace String))

(schema Captured
  (:f exitCode Int64)
  (:f stdout String)
  (:f stderr String))

(schema Built
  (:f code String)
  (:f run Captured))

fn shellQuote s: String -> String
  (str "'" (stringReplace s "'" "'\\''") "'")

fn ! root -> String
  (resultOr (realPath ".") ".")

fn ! runtimes! -> (Result Libs String)
  (let [(r (root))
        (plain (str r "/asl/host/out/libaslrt.a"))
        (cacheDir (str r "/.asl/cache/rcRuntime"))
        (_ (dirCreate (str r "/.asl/cache")))
        (_ (dirCreate cacheDir))
        (ctx (sys/Context :root r :scriptDir "" :argv0 "" :hostBin ""))
        (b (nb/Build :root r :cache cacheDir :tmp cacheDir :lib plain :base "" :clangVersion "" :owner ""
                     :deadlineNs (+ (monotonicNs) 900000000000) :maxDesc 16))]
    (if (not (sys/isFile? plain))
      (err (str plain " is absent: the native build (sh asl/host/build.sh) makes it"))
      (match (cache/nativeAsl1! ctx plain (optionOr (envGet "CLANG") "clang"))
        ((err e) (err (str "native asl1: " e)))
        ((ok asl1) (match (nb/asanRuntime! b asl1 (str r "/asl/packages"))
                     ((err e) (err (str "ASan runtime: " e)))
                     ((ok asan) (match (nb/notraceRuntime! b asl1 (str r "/asl/packages"))
                                  ((err e) (err (str "untraced runtime: " e)))
                                  ((ok notrace) (ok (Libs :plain plain :asan asan :notrace notrace))))))))))

fn ! testVariantTmpCleared dir: String -> Bool
  (let [(r (root))
        (plain (str r "/asl/host/out/libaslrt.a"))
        (cacheDir (str dir "/rtFresh"))
        (made (dirCreate cacheDir))
        (ctx (sys/Context :root r :scriptDir "" :argv0 "" :hostBin ""))
        (b (nb/Build :root r :cache cacheDir :tmp cacheDir :lib plain :base "" :clangVersion "" :owner ""
                     :deadlineNs (+ (monotonicNs) 900000000000) :maxDesc 16))]
    (match (cache/nativeAsl1! ctx plain (optionOr (envGet "CLANG") "clang"))
      ((err e) (do (assert false (str "native asl1: " e)) false))
      ((ok asl1)
        (match (nb/notraceRuntime! b asl1 (str r "/asl/packages"))
          ((err e) (do (assert false (str "untraced runtime in a fresh cache: " e)) false))
          ((ok lib)
            (let [(entries (resultOr (dirList cacheDir) (list)))
                  (libDir (sys/parentOf lib))]
              (do (assert (ok? made) "fresh runtime cache directory created")
                  (assert (sys/isFile? lib) (str "the untraced runtime is installed at " lib))
                  (assert (= entries (list (sys/baseName libDir))) (str "a fresh variant build leaves only its installed directory, no rt-notrace.PID work directory: " (stringJoin entries " ")))
                  (assert (ok? (pathRemove lib)) "fresh runtime library removed")
                  (assert (ok? (pathRemove libDir)) "fresh runtime directory removed")
                  (assert (ok? (pathRemove cacheDir)) "fresh runtime cache directory removed")
                  true)))))))

fn ! sh cmd: String -> Captured
  (let [(base (str (optionOr (envGet "TMPDIR") "/tmp") "/rcTest." (procSelf) "." (monotonicNs)))
        (outPath (str base ".out"))
        (errPath (str base ".err"))
        (done (run/runOneLimited (run/job (list "sh" "-c" (str "(cd " (shellQuote (root)) " && (" cmd ")) > " (shellQuote outPath) " 2> " (shellQuote errPath))) (root)
                                         (run/childEnv (list "ASL_RC_STATS=1")))
                                 (run/limits 300 8)))
        (outText (resultOr (fileReadString outPath) ""))
        (errText (resultOr (fileReadString errPath) ""))
        (_ (pathRemove outPath))
        (_ (pathRemove errPath))]
    (Captured :exitCode done.exit :stdout outText :stderr (if (= done.verdict "exit") errText (str errText " verdict " done.verdict " " done.out))))

fn fixture name: String -> String
  (str "asl/packages/asl-target-llvm/tests/fixtures/rc/" name ".asl")

fn diagText diags: (List irTy/IrDiag) -> String
  (stringJoin (map (fn [(d irTy/IrDiag)] -> String (str d.code ": " d.message)) diags) "; ")

fn ! linkCmd libs: Libs mode: String ll: String exe: String -> String
  (if (= mode "asan")
    (str "/usr/bin/clang " (stringJoin (nb/sanitizeFlags) " ") " -Wno-override-module -x ir " (shellQuote ll) " -x none " (shellQuote libs.asan) " -lm -o " (shellQuote exe))
    (str "/usr/bin/clang -O1 -Wno-override-module -x ir " (shellQuote ll) " -x none " (shellQuote (if (= mode "notrace") libs.notrace libs.plain)) " -lm -o " (shellQuote exe)))

fn ! buildRun libs: Libs dir: String name: String mode: String -> (Result Built String)
  (match (lk/linkEntry! (fixture name))
    ((err ds) (err (str name " links: " (diagText ds))))
    ((ok m)
     (match (llvm/emitLlvmProgramNativeWith! m (str m.name ".main") mode)
       ((err ds) (err (str name " emits in mode " mode ": " (diagText ds))))
       ((ok code)
        (let [(ll (str dir "/" name "." mode ".ll"))
              (exe (str dir "/" name "." mode))]
          (match (fileWrite ll code)
            ((err e) (err (str "cannot write " ll ": " e)))
            ((ok _)
             (let [(linked (sh (linkCmd libs mode ll exe)))]
               (if (!= linked.exitCode 0)
                 (err (str name " " mode " links: " linked.stderr))
                 (ok (Built :code code :run (sh (shellQuote exe)))))))))))))

fn statOf text: String key: String -> Int64
  (match (stringIndexOf text (str ":" key " "))
    ((none) -1)
    ((some at) (let [(rest (optionOr (stringSlice text (+ at (+ (stringLength key) 2)) (stringLength text)) ""))
                     (digits (optionOr (listHead (stringSplit (optionOr (listHead (stringSplit rest ")")) rest) " ")) ""))]
                 (optionOr (stringToInt64 digits) -1))))

fn callCount code: String sym: String -> Int64
  (- (listLength (stringSplit code (str "call tailcc i64 @" sym "("))) 1)

fn ! checkFixture libs: Libs dir: String name: String want: String minFreed: Int64 minReused: Int64 maxFresh: Int64 maxPinned: Int64 -> Bool
  (let [(traced (buildRun libs dir name "0"))
        (counted (buildRun libs dir name "1"))
        (asan (buildRun libs dir name "asan"))]
    (match traced
      ((err e) (do (assert false (str "tracing build: " e)) false))
      ((ok t)
       (match counted
         ((err e) (do (assert false (str "RC build: " e)) false))
         ((ok c)
          (match asan
            ((err e) (do (assert false (str "RC ASan build: " e)) false))
            ((ok a)
             (let [(stats c.run.stderr)
                   (freed (statOf stats "freed"))
                   (reused (statOf stats "reused"))
                   (fresh (statOf stats "fresh"))
                   (pinned (statOf stats "pinned"))
                   (stuck (statOf stats "stuck"))]
               (do (assert (= t.run.exitCode 0) (str name " tracing exits 0, got " t.run.exitCode ": " t.run.stderr))
                   (assert (= c.run.exitCode 0) (str name " RC exits 0, got " c.run.exitCode ": " c.run.stderr))
                   (assert (= a.run.exitCode 0) (str name " RC under ASan exits 0, got " a.run.exitCode ": " a.run.stderr))
                   (assert (= t.run.stdout want) (str name " tracing prints " want ", got " t.run.stdout))
                   (assert (= c.run.stdout t.run.stdout) (str name " RC output equals tracing output: " c.run.stdout " vs " t.run.stdout))
                   (assert (= a.run.stdout t.run.stdout) (str name " RC ASan output equals tracing output: " a.run.stdout))
                   (refute (stringContains? a.run.stderr "Sanitizer") (str name " ASan reports nothing: " a.run.stderr))
                   (refute (stringContains? t.run.stderr ":rcStats") (str name " the tracing build carries no RC runtime"))
                   (assert (= (callCount t.code "aslRcDrop") 0) (str name " tracing IR has no drop calls"))
                   (assert (> (callCount c.code "aslRcDrop") 0) (str name " RC IR calls aslRcDrop"))
                   (assert (stringContains? a.code "sanitize_address") (str name " ASan-mode IR marks functions sanitize_address"))
                   (assert (>= freed minFreed) (str name " RC frees at least " minFreed " cells, freed " freed " (" stats ")"))
                   (assert (>= reused minReused) (str name " RC reuses at least " minReused " freed cells, reused " reused " (" stats ")"))
                   (assert (and (>= fresh 0) (<= fresh maxFresh)) (str name " RC takes at most " maxFresh " fresh cells from the collector, took " fresh " (" stats ")"))
                   (assert (= (statOf a.run.stderr "freed") freed) (str name " ASan-mode RC frees the same cells as RC mode"))
                   (assert (and (>= pinned 0) (<= pinned maxPinned)) (str name " RC pins at most " maxPinned " cells for the collector, pinned " pinned " (" stats ")"))
                   (assert (= stuck 0) (str name " RC leaves no freed cell sticky, small size classes included, stuck " stuck " (" stats ")"))
                   true)))))))))

fn ! testRejectsUnknownMode -> Bool
  (match (lk/linkEntry! (fixture "rcLoop"))
    ((err ds) (do (assert false (str "rcLoop links: " (diagText ds))) false))
    ((ok m)
     (match (llvm/emitLlvmProgramNativeWith! m (str m.name ".main") "yes")
       ((ok _) (do (assert false "an unknown RC mode is rejected, not silently traced") false))
       ((err ds) (do (assert (listAny? (fn [(d irTy/IrDiag)] -> Bool (= d.code "ERR_LLVM_RC_MODE")) ds) (str "unknown mode reports ERR_LLVM_RC_MODE: " (diagText ds)))
                     true)))))

fn ! testPartialNames libs: Libs dir: String -> Bool
  (match (buildRun libs dir "rcPartial" "1")
    ((err e) (do (assert false (str "RC partial build: " e)) false))
    ((ok b) (do (assert (= b.run.exitCode 1) (str "over-applied partial exits 1 under RC, got " b.run.exitCode))
                (assert (stringStartsWith? b.run.stderr "ERR_ARITY: add3 expects 3 argument(s), got 4\n") (str "the arity error names add3, not an RC wrapper call: " b.run.stderr))
                true)))

fn fnBody code: String sym: String -> String
  (fnBodyOf code "i64" sym)

fn fnBodyOf code: String ret: String sym: String -> String
  (match (stringIndexOf code (str "define tailcc " ret " @" sym "("))
    ((none) "")
    ((some at) (let [(rest (optionOr (stringSlice code at (stringLength code)) ""))]
                 (match (stringIndexOf rest "\n}\n") ((some e) (optionOr (stringSlice rest 0 e) "")) ((none) rest)))))

fn ! testBorrow libs: Libs dir: String -> Bool
  (match (buildRun libs dir "rcBorrow" "1")
    ((err e) (do (assert false (str "RC borrow build: " e)) false))
    ((ok b) (let [(walk (fnBody b.code "rcBorrow$2Ewalk"))]
              (do (assert (= b.run.stdout "14999850000 1\n") (str "rcBorrow prints the sum under RC, got " b.run.stdout))
                  (assert (stringContains? walk "musttail call tailcc i64 @rcBorrow$2Ewalk(") (str "walk stays a musttail loop: " walk))
                  (assert (= (- (listLength (stringSplit walk "@aslRcDup(")) 1) 0) (str "walk borrows cfg and xs: no dup in its body: " walk))
                  (assert (= (- (listLength (stringSplit walk "@aslRcDrop(")) 1) 0) (str "walk borrows cfg and xs: no drop in its body: " walk))
                  true))))

fn ! testBorrowTail libs: Libs dir: String -> Bool
  (match (buildRun libs dir "rcBorrowTail" "1")
    ((err e) (do (assert false (str "RC borrow tail build: " e)) false))
    ((ok b) (let [(total (fnBody b.code "rcBorrowTail$2Etotal"))]
              (do (assert (= b.run.stdout "149850000\n") (str "rcBorrowTail sums a fresh list three hundred times under RC, got " b.run.stdout))
                  (assert (stringContains? total "musttail call tailcc i64 @rcBorrowTail$2Etotal(") (str "total stays a musttail loop: " total))
                  (assert (= (- (listLength (stringSplit total "@aslRcDup(")) 1) 0) (str "probe tail-calls total with a list it owns, outside total's cycle: total still borrows xs: no dup: " total))
                  (assert (= (- (listLength (stringSplit total "@aslRcDrop(")) 1) 0) (str "probe tail-calls total with a list it owns, outside total's cycle: total still borrows xs: no drop: " total))
                  true))))

fn rcCalls body: String -> Int64
  (+ (- (listLength (stringSplit body "@aslRcDup(")) 1) (- (listLength (stringSplit body "@aslRcDrop(")) 1))

fn ! testProject libs: Libs dir: String -> Bool
  (match (buildRun libs dir "rcProject" "1")
    ((err e) (do (assert false (str "RC projection build: " e)) false))
    ((ok b) (let [(dropN (fnBodyOf b.code "%Val" "rcProject$2EdropN"))
                  (second (fnBodyOf b.code "%Val" "rcProject$2Esecond"))
                  (itemsOf (fnBodyOf b.code "%Val" "rcProject$2EitemsOf"))]
              (do (assert (= b.run.stdout "2572500 2400 600\n") (str "rcProject prints the sums under RC, got " b.run.stdout))
                  (assert (stringContains? dropN "musttail call tailcc %Val @rcProject$2EdropN(") (str "dropN stays a musttail loop: " dropN))
                  (assert (= (rcCalls dropN) 0) (str "dropN returns a suffix of its borrowed list: no dup or drop: " dropN))
                  (assert (= (rcCalls second) 0) (str "second returns the rest of its borrowed list: no dup or drop: " second))
                  (assert (= (rcCalls itemsOf) 0) (str "itemsOf returns a field of its borrowed record: no dup or drop: " itemsOf))
                  true))))

fn ! testSink libs: Libs dir: String -> Bool
  (match (buildRun libs dir "rcSink" "1")
    ((err e) (do (assert false (str "RC sink build: " e)) false))
    ((ok b) (let [(lookup (fnBodyOf b.code "%Val" "rcSink$2Elookup"))]
              (do (assert (= b.run.stdout "2288\n") (str "rcSink prints the found name lengths under RC, got " b.run.stdout))
                  (assert (= (- (listLength (stringSplit lookup "@aslRcDup(")) 1) 2) (str "lookup duplicates the shared none and the name, the name only where some takes it: " lookup))
                  (assert (= (- (listLength (stringSplit lookup "@aslRcDrop(")) 1) 0) (str "lookup drops nothing: its boxed key is an immediate and the name is never dropped on the paths that recurse: " lookup))
                  true))))

fn ! testHof libs: Libs dir: String -> Bool
  (match (buildRun libs dir "rcHof" "1")
    ((err e) (do (assert false (str "RC higher-order build: " e)) false))
    ((ok b) (let [(walk (fnBodyOf b.code "%Val" "rcHof$2Ewalk"))]
              (do (assert (= b.run.stdout "897\n") (str "rcHof prints the nested list length under RC, got " b.run.stdout))
                  (assert (stringContains? walk "musttail call tailcc %Val @rcHof$2Ewalk(") (str "walk stays a musttail loop: " walk))
                  (assert (= (- (listLength (stringSplit walk "@aslRcDup(")) 1) 1) (str "walk calls its closure only in plain position, so the lambda that tail-calls walk with an owned list is outside walk's tail cycle and walk borrows xs: it duplicates only the head it conses, not the rest it walks: " walk))
                  (refute (stringContains? walk "@aslRcDrop(%Val %xs)") (str "walk borrows xs: it never drops it: " walk))
                  true))))

fn runtimeBody code: String sym: String -> String
  (match (stringIndexOf code (str "define internal void @" sym "("))
    ((none) "")
    ((some at) (let [(rest (optionOr (stringSlice code at (stringLength code)) ""))]
                 (match (stringIndexOf rest "\n}\n") ((some e) (optionOr (stringSlice rest 0 e) "")) ((none) rest)))))

fn ! testSpine libs: Libs dir: String -> Bool
  (match (buildRun libs dir "rcList" "1")
    ((err e) (do (assert false (str "RC spine build: " e)) false))
    ((ok b) (let [(chain (runtimeBody b.code "aslRc.freeChain"))]
              (do (assert (= b.run.stdout "834000\n") (str "rcList prints its sum under RC, got " b.run.stdout))
                  (assert (stringContains? chain "call i1 @aslRc.claim(ptr %t)") (str "freeChain frees a cons tail whose count reaches zero in the same loop: " chain))
                  (assert (stringContains? (runtimeBody b.code "aslRc.drain") "call void @aslRc.freeChain(ptr %o)") "drain frees each pending cell through freeChain")
                  (assert (stringContains? (runtimeBody b.code "aslRc.freeOne") "call void @aslRc.freeChain(ptr %o)") "freeOne frees through freeChain")
                  (assert (stringContains? b.code "define internal void @aslRc.recycle(ptr %o, i64 %h) alwaysinline {") "recycle is inlined into the free path")
                  (assert (stringContains? (runtimeBody b.code "aslRc.recycle") "call void @aslRc.recycleSlow(ptr %o, i64 %h)") "large, small and sticky cells take the outlined recycleSlow")
                  true))))

fn ! testOpStats libs: Libs dir: String -> Bool
  (match (buildRun libs dir "rcTree" "asan")
    ((err e) (do (assert false (str "RC ASan tree build: " e)) false))
    ((ok a) (match (buildRun libs dir "rcTree" "1")
              ((err e) (do (assert false (str "RC tree build: " e)) false))
              ((ok c) (let [(ops (statOf a.run.stderr "ops"))
                            (imm (statOf a.run.stderr "immediate"))]
                        (do (assert (> ops 10000) (str "ASan-mode RC counts every dup and drop rcTree runs, over ten thousand: " a.run.stderr))
                            (assert (and (> imm 0) (< imm ops)) (str "ASan-mode RC counts the dups and drops whose value is no heap object, some but not all: " a.run.stderr))
                            (assert (= (statOf c.run.stderr "ops") 0) (str "the production RC runtime carries no op counter: " c.run.stderr))
                            (assert (= (statOf c.run.stderr "immediate") 0) (str "the production RC runtime carries no immediate counter: " c.run.stderr))
                            true))))))

fn ! pushedOf libs: Libs dir: String name: String -> Int64
  (match (buildRun libs dir name "asan")
    ((err e) (do (assert false (str "RC ASan " name " build: " e)) -1))
    ((ok a) (do (assert (= a.run.exitCode 0) (str name " RC under ASan exits 0: " a.run.stderr))
                (statOf a.run.stderr "pushed"))))

fn ! testFreeQueue libs: Libs dir: String -> Bool
  (let [(tree (pushedOf libs dir "rcTree"))
        (strs (pushedOf libs dir "rcBuiltins"))]
    (do (assert (and (>= tree 0) (< tree 1000)) (str "a freed tree path frees each dying node as the next turn of the loop, not through the pending stack: rcTree pushed " tree " cells, base 6204"))
        (assert (= strs 0) (str "dying kids with no kids (strings) are recycled on the spot, never pushed: rcBuiltins pushed " strs " cells, base 80000"))
        true))

fn ! testReuse libs: Libs dir: String -> Bool
  (match (buildRun libs dir "rcReuse" "asan")
    ((err e) (do (assert false (str "RC ASan rcReuse build: " e)) false))
    ((ok a) (let [(stats a.run.stderr)
                  (hits (statOf stats "fbip"))
                  (resets (statOf stats "resets"))
                  (freed (statOf stats "freed"))
                  (ops (statOf stats "ops"))]
              (do (assert (= a.run.stdout "6008445041\n") (str "rcReuse prints its sum under RC ASan: " a.run.stdout " " stats))
                  (assert (>= hits 9000) (str "a unique matched value dying at or before a construct of its size hands its cell over: widen, bump and flip reuse 3000 cells each, fbip " hits " (" stats ")"))
                  (assert (= (- resets hits) 3000) (str "the value kept in a pair is shared at its reset, so its cell is not reused and its moved fields are duplicated: resets " resets " fbip " hits))
                  (assert (and (> freed 0) (< freed 30000)) (str "a reused cell is never freed: rcReuse frees " freed " cells, base 37930"))
                  (assert (and (> ops 0) (< ops 40000)) (str "moved fields of a reused cell skip their dup and release: rcReuse runs " ops " RC ops, base 51502"))
                  true))))


fn ! runTests -> Bool
  (match (runtimes!)
    ((err e) (do (assert false (str "rcTest runtimes: " e)) false))
    ((ok libs) (runWith libs)))

fn ! runWith libs: Libs -> Bool
  (let [(dir (str (optionOr (envGet "TMPDIR") "/tmp") "/rcTest." (procSelf) "." (monotonicNs)))
        (made (dirCreate dir))]
    (do (assert (ok? made) "rcTest work directory created")
        (assert (testRejectsUnknownMode) "unknown RC mode rejected")
        (assert (testPartialNames libs dir) "closure prototypes keep the source name under RC wrappers")
        (assert (testBorrow libs dir) "a read-only traversal borrows its parameters: no RC traffic in the loop")
        (assert (testBorrowTail libs dir) "a callee tail-called from outside its own cycle keeps its borrowed parameters")
        (assert (testProject libs dir) "a projection of a borrowed parameter returns it without RC traffic")
        (assert (testSink libs dir) "a field consumed on one path is duplicated there, not where it is read")
        (assert (testHof libs dir) "a closure call in plain position does not tie the caller into the tail cycle of the lambdas it calls")
        (assert (testSpine libs dir) "a freed list spine is walked in one loop, not pushed cell by cell through the pending stack")
        (assert (testOpStats libs dir) "ASan-mode RC counts dups, drops and those on immediates; production RC counts none")
        (assert (testFreeQueue libs dir) "a freed object's dying kids continue the free loop or are recycled on the spot instead of queueing")
        (assert (testReuse libs dir) "an owned matched value that dies at or before a construct of its size class lends its cell, moved fields skip dup and release")
        (assert (checkFixture libs dir "rcReuse" "6008445041\n" 28000 28000 100 0) "reused cells, shared resets and moved fields stay correct and ASan-clean")
        (assert (checkFixture libs dir "rcSink" "2288\n" 500 400 2000 0) "names read from a tree and kept or replaced are freed once, ASan-clean")
        (assert (checkFixture libs dir "rcProject" "2572500 2400 600\n" 60000 59000 3500 0) "projections kept past their anchor are duplicated and freed once, ASan-clean")
        (assert (checkFixture libs dir "rcBorrow" "14999850000 1\n" 100000 0 200000 0) "borrowed parameters stay correct and ASan-clean")
        (assert (checkFixture libs dir "rcLoop" "499500 -499500\n" 999 999 8 0) "a record rebuilt each step is freed and its cell reused")
        (assert (checkFixture libs dir "rcShare" "1498500\n" 1999 1997 8 0) "a record passed twice to one call is duplicated then freed once, and a discarded result is freed")
        (assert (checkFixture libs dir "rcTree" "302841 19\n" 6000 6000 700 0) "path-copying tree insertion frees and reuses the replaced path")
        (assert (checkFixture libs dir "rcTail" "3000000 5\n" 2999000 2999000 10 0) "a closure call in tail position keeps musttail: its drops are deferred, three million frames never stack")
        (assert (checkFixture libs dir "rcList" "834000\n" 16000 15000 1000 0) "lists through the map builder are freed and reused under RC, none pinned")
        (assert (checkFixture libs dir "rcBuiltins" "388890\n" 279000 279000 100 0) "values passed to str, stringConcat, stringSlice, listTail and the filter and map builders are borrowed and freed, none pinned")
        (assert (checkFixture libs dir "rcSmall" "100000\n" 99999 99999 10 0) "16-byte none cells are freed onto the small-class stack and reused")
        (assert (checkFixture libs dir "rcSys" "10000\n" 10000 9000 1000 0) "arguments and results of the routed fileStat, realPath, fileReadString, dirList and fileExists? are borrowed and freed, none pinned")
        (assert (testVariantTmpCleared dir) "a variant runtime build removes its work directory")
        (assert (ok? (pathRemove dir)) "rcTest work directory removed")
        true))
