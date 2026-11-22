(module asl-cli/tests/buildCacheTest
  :x [runTests]
  :i [(asl/packages/asl-cli/src/system :a sys)
      (asl/packages/asl-cli/src/nativeBuild :a nb)
      (asl/packages/asl-cli/src/irSplit :a ir)
      (asl/packages/asl-cli/src/objStore :a os)
      (asl/packages/asl-cli/src/asl1Cache :a cache)
      (asl/packages/asl-cli/src/nativeCli :a nc)
      (asl-tools/fleet/run :a run)])

; (:m :ref BUILD-CACHE :do "the module object cache, end to end on a three-module program built into a temp store: a cold build compiles every part, a rebuild of the same IR compiles none, a body edit in the entry module compiles exactly its part, switching back compiles none, a body edit in an imported module whose body the importer inlines recompiles the importer too and the output follows the edit, a corrupted object is found, compiled again and not linked, objects are compiled under a tmp name and renamed into place, and the sweep removes nothing while another build holds a lease")
fn configText -> String
  "(:aslConfig :workspace \"bcfx\" :root true)\n"

fn libText factor: String -> String
  (stringJoin (list "(module bcfx/lib :x [greet twice] :i [])" ""
                    "fn greet name: String -> String" "  (str \"hello \" name)" ""
                    "fn twice n: Int64 -> Int64" (str "  (* n " factor ")") "") "\n")

fn midText -> String
  (stringJoin (list "(module bcfx/mid :x [shout] :i [(bcfx/lib :a l)])" ""
                    "fn shout name: String -> String" "  (str (l/greet name) \"! \" (stringFromInt64 (l/twice 21)))" "") "\n")

fn mainText who: String -> String
  (stringJoin (list "(module bcfx/main :x [main] :i [(bcfx/mid :a m) (bcfx/lib :a l)])" ""
                    "fn ! main args: (List String) -> (Result Int64 String)"
                    (str "  (do (println (m/shout \"world\")) (println (l/greet \"" who "\")) (ok 0))") "") "\n")

(schema Env
  (:f root String)
  (:f dir String)
  (:f store String)
  (:f asl1 String)
  (:f clang String)
  (:f lib String))

(schema Step
  (:f receipt (Option nb/ObjLink))
  (:f err String)
  (:f out String))

fn ! write! env: Env factor: String who: String -> Bool
  (and (ok? (fileWrite (str env.dir "/lib.asl") (libText factor)))
       (and (ok? (fileWrite (str env.dir "/mid.asl") (midText)))
            (ok? (fileWrite (str env.dir "/main.asl") (mainText who)))))

fn ! runIn argv: (List String) cwd: String -> run/Done
  (run/runOneLimited (run/job argv cwd (run/childEnv (list))) (run/limits 300 16))

fn ! buildWith! env: Env n: Int64 -> Step
  (buildIn! env n 0)

fn ! buildIn! env: Env n: Int64 buckets: Int64 -> Step
  (let [(tmp (str env.store "/tmp." (stringFromInt64 (procSelf))))
        (_ (dirCreate tmp))
        (ll (str tmp "/main.ll"))
        (exe (str env.dir "/main." (stringFromInt64 n)))
        (emitted (runIn (list env.asl1 "build" "main.asl" "-o" ll) env.dir))]
    (if (!= emitted.exit 0)
      (Step :receipt (none) :err (str "asl1 build exited " emitted.exit ": " emitted.out) :out "")
      (let [(b (nb/Build :root env.dir :cache env.store :tmp tmp :lib env.lib :base "" :clangVersion "" :owner ""
                         :deadlineNs (+ (monotonicNs) 600000000000) :maxDesc 24 :objs (nb/objDirOf env.store) :buckets buckets))
            (linked (nb/linkCached! b env.clang (list "-O2") ll exe 4))
            (_ (pathRemove tmp))]
        (match linked
          ((err e) (Step :receipt (none) :err e :out ""))
          ((ok r) (let [(ran (runIn (list exe) env.dir))]
                    (Step :receipt (some r) :err (if (= ran.exit 0) "" (str "the binary exited " ran.exit)) :out ran.out)))))))

fn compiledOf s: Step -> (List String)
  (match s.receipt ((some r) r.compiled) ((none) (list "<no receipt>")))

fn corruptOf s: Step -> (List String)
  (match s.receipt ((some r) r.corrupt) ((none) (list "<no receipt>")))

fn objectsOf s: Step -> (List String)
  (match s.receipt ((some r) r.objects) ((none) (list)))

fn partsOf s: Step -> Int64
  (listLength (objectsOf s))

fn want factor: String who: String -> String
  (str "hello world! " (if (= factor "2") "42" "63") "\nhello " who "\n")

fn ! testCycle env: Env -> Bool
  (let [(_ (write! env "2" "x"))
        (cold (buildWith! env 1))
        (again (buildWith! env 2))
        (_ (write! env "2" "y"))
        (edited (buildWith! env 3))
        (_ (write! env "2" "x"))
        (back (buildWith! env 4))
        (_ (write! env "3" "x"))
        (inlined (buildWith! env 5))
        (_ (write! env "2" "x"))
        (restored (buildWith! env 6))
        (victim (optionOr (listGet (objectsOf restored) 3) ""))
        (size (match (fileStat victim) ((ok st) st.size) ((err _) 0)))
        (_ (fileWrite victim (stringRepeat "x" size)))
        (healed (buildWith! env 7))]
    (do (assert (= cold.err "") (str "the cold build links and runs: " cold.err))
        (assert (= cold.out (want "2" "x")) (str "the cold binary prints the program output: " cold.out))
        (assert (= (partsOf cold) 6) (str "the program splits into @globals, lib, mid, main, @entry and rt: " (stringFromInt64 (partsOf cold))))
        (assert (= (listLength (compiledOf cold)) 6) (str "a cold store compiles every part: " (stringJoin (compiledOf cold) " ")))
        (assert (listEmpty? (compiledOf again)) (str "the same IR again compiles no part: " (stringJoin (compiledOf again) " ")))
        (assert (= again.out cold.out) "the warm binary prints the same output")
        (assert (= (compiledOf edited) (list "bcfx$2Fmain")) (str "a body edit in the entry module compiles exactly its part: " (stringJoin (compiledOf edited) " ")))
        (assert (= edited.out (want "2" "y")) (str "the edited binary prints the edit: " edited.out))
        (assert (listEmpty? (compiledOf back)) (str "switching back to the first version compiles no part: " (stringJoin (compiledOf back) " ")))
        (assert (= back.out (want "2" "x")) (str "the switched-back binary prints the first output: " back.out))
        (assert (listContains? (compiledOf inlined) "bcfx$2Flib") (str "an edit of lib compiles lib: " (stringJoin (compiledOf inlined) " ")))
        (assert (listContains? (compiledOf inlined) "bcfx$2Fmid") (str "mid inlines lib's twice, so its part is compiled again: " (stringJoin (compiledOf inlined) " ")))
        (assert (not (listContains? (compiledOf inlined) "@globals")) (str "the globals part does not change with a body edit: " (stringJoin (compiledOf inlined) " ")))
        (assert (= inlined.out (want "3" "x")) (str "the importer follows the edited body it inlines: " inlined.out))
        (assert (listEmpty? (compiledOf restored)) (str "the first version is still warm: " (stringJoin (compiledOf restored) " ")))
        (assert (> size 0) (str "the main object exists to corrupt: " victim))
        (assert (= (corruptOf healed) (list "bcfx$2Fmain")) (str "the corrupted object is detected: " (stringJoin (corruptOf healed) " ")))
        (assert (= (compiledOf healed) (list "bcfx$2Fmain")) (str "the corrupted object is compiled again: " (stringJoin (compiledOf healed) " ")))
        (assert (= healed.out (want "2" "x")) (str "the binary over the rebuilt object runs correctly: " healed.out healed.err))
        true))

; (:m :ref BUILD-CACHE :do "with the CLI default of 16 buckets the three modules land in buckets; a body edit in main compiles exactly one bucket part and the binary follows the edit")
fn ! testBuckets env: Env -> Bool
  (let [(_ (write! env "2" "x"))
        (cold (buildIn! env 11 16))
        (_ (write! env "2" "z"))
        (edited (buildIn! env 12 16))
        (_ (write! env "2" "x"))
        (back (buildIn! env 13 16))]
    (do (assert (= cold.out (want "2" "x")) (str "the bucketed cold binary prints the program output: " cold.out cold.err))
        (assert (listAll? (fn [(p String)] -> Bool (or (stringStartsWith? p "bucket") (stringStartsWith? p "@"))) (compiledOf cold)) (str "every part is a bucket, @globals or @entry: " (stringJoin (compiledOf cold) " ")))
        (assert (= (listLength (compiledOf edited)) 1) (str "a body edit in main compiles exactly one bucket: " (stringJoin (compiledOf edited) " ")))
        (assert (= (compiledOf edited) (list (ir/bucketOf "bcfx$2Fmain" 16))) (str "the compiled bucket is main's: " (stringJoin (compiledOf edited) " ")))
        (assert (= edited.out (want "2" "z")) (str "the bucketed binary follows the edit: " edited.out))
        (assert (listEmpty? (compiledOf back)) (str "switching back compiles no bucket: " (stringJoin (compiledOf back) " ")))
        true))

fn ! fieldOf out: String key: String -> Int64
  (optionOr (stringToInt64 (optionOr (listHead (stringSplit (optionOr (listGet (stringSplit (stringReplace out ")" " ") (str ":" key " ")) 1) "") " ")) "")) -1)

fn ! raceExe! env: Env -> (Result String String)
  (let [(tmp (str env.store "/race.tmp." (stringFromInt64 (procSelf))))
        (_ (dirCreate tmp))
        (ll (str tmp "/race.ll"))
        (exe (str env.store "/objStoreRace"))
        (emitted (runIn (list env.asl1 "build" "asl/packages/asl-cli/tests/fixtures/objStoreRace.asl" "-o" ll) env.root))]
    (if (!= emitted.exit 0)
      (err (str "asl1 build of the race fixture exited " emitted.exit ": " emitted.out))
      (let [(b (nb/Build :root env.root :cache env.store :tmp tmp :lib env.lib :base "" :clangVersion "" :owner ""
                         :deadlineNs (+ (monotonicNs) 600000000000) :maxDesc 24 :objs (str env.store "/raceObjs") :buckets 0))
            (linked (nb/linkCached! b env.clang (list "-O2") ll exe 4))
            (_ (pathRemove tmp))]
        (match linked ((err e) (err e)) ((ok _) (ok exe))))))

; (:m :ref BUILD-CACHE :do "two writer processes and one observer on one temp store, started through fleet/run with a 180 s bound: the writers run the part protocol of linkCached! over 600 shared keys in opposite orders, the observer polls every key; no object is ever seen without its meta row, no writer finds an entry corrupt or loses a hit, and every key ends verified")
fn ! testRace env: Env -> Bool
  (let [(race (str env.store "/race"))
        (objs (str race "/obj"))
        (made (and (ok? (dirCreate objs)) true))
        (exe (raceExe! env))
        (rounds 4)
        (n 150)
        (argsOf (fn [(mode String) (last String)] -> (List String) (list (resultOr exe "") mode race (stringFromInt64 rounds) (stringFromInt64 n) last)))
        (jobs (map (fn [(a (List String))] -> run/Job (run/job a race (run/childEnv (list)))) (list (argsOf "observer" "2") (argsOf "writer" "0") (argsOf "writer" "1"))))
        (done (if (and made (ok? exe)) (run/runPoolLimited jobs 3 (run/limits 180 8)) (list)))
        (outs (map (fn [(d run/Done)] -> String d.out) (listSortBy (fn [(d run/Done)] -> Int64 d.idx) done)))
        (obs (optionOr (listGet outs 0) ""))
        (w0 (optionOr (listGet outs 1) ""))
        (w1 (optionOr (listGet outs 2) ""))
        (keys (listFlatMap (fn [(r Int64)] -> (List String) (map (fn [(i Int64)] -> String (str "k" (stringFromInt64 r) "x" (stringFromInt64 i))) (range 0 n))) (range 0 rounds)))
        (unverified (filter (fn [(k String)] -> Bool (not (os/objVerified! objs k))) keys))
        (left (filter (fn [(f String)] -> Bool (stringContains? f ".tmp.")) (resultOr (dirList objs) (list))))]
    (do (assert (ok? exe) (str "the race fixture builds: " (match exe ((err e) e) ((ok p) p))))
        (assert (= (listLength done) 3) (str "all three processes ran: " (stringFromInt64 (listLength done))))
        (assert (listAll? (fn [(d run/Done)] -> Bool (= d.exit 0)) done) (str "every process exits 0: " (stringJoin outs " | ")))
        (assert (> (fieldOf obs "checks") 0) (str "the observer checked keys while the writers ran: " obs))
        (assert (= (fieldOf obs "violations") 0) (str "no object is ever visible without its meta row: " obs))
        (assert (> (+ (fieldOf w0 "installed") (fieldOf w1 "installed")) 0) (str "the writers installed objects: " w0 " " w1))
        (assert (and (= (fieldOf w0 "corrupt") 0) (= (fieldOf w1 "corrupt") 0)) (str "no writer finds another's entry corrupt: " w0 " " w1))
        (assert (and (= (fieldOf w0 "lost") 0) (= (fieldOf w1 "lost") 0)) (str "no hit disappears before it is linked: " w0 " " w1))
        (assert (and (= (fieldOf w0 "failed") 0) (= (fieldOf w1 "failed") 0)) (str "every install succeeds: " w0 " " w1))
        (assert (listEmpty? unverified) (str "every key ends verified: " (stringFromInt64 (listLength unverified)) " not"))
        (assert (listEmpty? left) (str "no tmp file is left in the race store: " (stringJoin left " ")))
        true))

; (:m :ref BUILD-CACHE :do "a relative :native :objStore row is taken against the directory of the config that holds it, from any directory below it; an absolute row stays as written")
fn ! testStoreFor env: Env -> Bool
  (let [(top (str env.store "/cfg"))
        (deep (str top "/a/b"))
        (_ (dirCreate deep))
        (_ (fileWrite (str top "/.asl.config.asn") "(:aslConfig :workspace \"cfg\" :root true :native (:objStore \"objs\"))\n"))
        (rel (nb/objStoreFor! deep))
        (_ (fileWrite (str top "/.asl.config.asn") "(:aslConfig :workspace \"cfg\" :root true :native (:objStore \"/var/tmp/objs\"))\n"))
        (abs (nb/objStoreFor! deep))]
    (do (assert (= rel (str top "/objs")) (str "a relative store resolves against its config's directory: " rel))
        (assert (= abs "/var/tmp/objs") (str "an absolute store stays as written: " abs))
        true))

fn ! testAtomic env: Env -> Bool
  (let [(objs (nb/objDirOf env.store))
        (argv (nb/objCompileArgv "clang" (list "-O2") "p.ll" (os/objTmpPath objs "k" 42)))
        (left (filter (fn [(n String)] -> Bool (stringContains? n ".tmp.")) (resultOr (dirList objs) (list))))]
    (do (assert (= (listLast argv) (some (os/objTmpPath objs "k" 42))) "clang writes the object to its tmp name")
        (assert (!= (os/objTmpPath objs "k" 42) (os/objPath objs "k")) "the tmp name is not the final name")
        (assert (stringContains? (os/objTmpPath objs "k" 42) ".tmp.42") "the tmp name carries the writer pid")
        (assert (listEmpty? left) (str "no tmp object is left in the store after the builds: " (stringJoin left " ")))
        true))

fn ! metaCount objs: String -> Int64
  (listLength (filter (fn [(n String)] -> Bool (stringEndsWith? n ".meta")) (resultOr (dirList objs) (list))))

fn ! testSweep env: Env -> Bool
  (let [(objs (nb/objDirOf env.store))
        (before (metaCount objs))
        (_ (nc/leaseEntry! env.store "cli-test" (monotonicNs)))
        (held (nb/sweepObjectsAs! env.store objs 0 0 0))
        (afterHeld (metaCount objs))
        (_ (nc/dropLeases! env.store))
        (swept (nb/sweepObjectsAs! env.store objs 0 0 0))
        (afterSwept (metaCount objs))]
    (do (assert (> before 0) (str "the store holds objects to sweep: " (stringFromInt64 before)))
        (assert (= held 0) (str "with another build's lease live the sweep removes nothing: " (stringFromInt64 held)))
        (assert (= afterHeld before) "every object survives while a lease is held")
        (assert (= swept before) (str "with no build in flight a zero cap sweeps every entry: " (stringFromInt64 swept)))
        (assert (= afterSwept 0) "the store is empty after the sweep")
        true))

fn ! testSplitNames -> Bool
  (do (assert (= (ir/groupOf "bcfx$2Flib$2Egreet") "bcfx$2Flib") "a body's group is its module")
      (assert (= (ir/groupOf "prelude$2Efold$24cs0$24asl$2Dchecker$2Fresolve$2EcollectSummary") "asl$2Dchecker$2Fresolve") "a prelude clone goes with its caller's module")
      (assert (= (ir/groupOf "valrt.hash") "rt") "a body with no module path is in rt")
      (assert (= (ir/groupOf "main") "@entry") "the C entry is a part of its own")
      (assert (= (ir/groupOf "asl.main") "@entry") "the entry wrapper goes with the C entry")
      (assert (= (ir/bucketOf "asl$2Dintel$2Fsearch" 24) (ir/bucketOf "asl$2Dintel$2Fsearch" 24)) "a module's bucket is a function of its name")
      (assert (= (ir/bucketOf "@globals" 24) "@globals") "@globals is never bucketed")
      (assert (= (ir/bucketOf "bcfx$2Fmain" 0) "bcfx$2Fmain") "zero buckets keeps one part per module")
      (assert (= (ir/renameLocal "@str.7 = private c\"@str.9\"\n  call @f(ptr @strVal.4, ptr @str.7)\n") "@str.0 = private c\"@str.9\"\n  call @f(ptr @strVal.0, ptr @str.0)\n") "string constants and cells are renumbered by first use, quoted text untouched")
      true)

fn ! runTests -> Bool
  (let [(root (resultOr (realPath ".") "."))
        (work (str root "/.asl/cache/buildCacheTest." (stringFromInt64 (procSelf))))
        (dir (str work "/fx"))
        (store (str work "/store"))
        (lib (str root "/asl/host/out/libaslrt.a"))
        (clang (resultOr (nc/clangFor! root) "clang"))
        (made (and (ok? (dirCreate dir)) (and (ok? (dirCreate store)) (ok? (fileWrite (str dir "/.asl.config.asn") (configText))))))
        (asl1 (cache/nativeAsl1! (sys/Context :root root :scriptDir "" :argv0 "" :hostBin "") lib clang))
        (env (Env :root root :dir dir :store store :asl1 (resultOr asl1 "") :clang clang :lib lib))
        (names (testSplitNames))
        (cycle (if (and made (ok? asl1)) (testCycle env) false))
        (buckets (if (and made (ok? asl1)) (testBuckets env) false))
        (race (if (and made (ok? asl1)) (testRace env) false))
        (storeFor (testStoreFor env))
        (atomic (testAtomic env))
        (sweep (testSweep env))
        (cleaned (pathRemove work))]
    (do (assert made (str "the work directory " work " was created"))
        (assert (ok? asl1) (str "a native asl1 is available: " (match asl1 ((err e) e) ((ok p) p))))
        (assert names "module groups and local names")
        (assert cycle "the cached build cycle")
        (assert buckets "the bucketed build cycle")
        (assert race "the multi-process store race")
        (assert storeFor "the configured object store path")
        (assert atomic "objects land by rename")
        (assert sweep "the sweep respects leases")
        (assert (ok? cleaned) "the work directory was removed")
        true))
