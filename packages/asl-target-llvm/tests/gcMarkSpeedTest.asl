(module asl-target-llvm/tests/gcMarkSpeedTest
  :x [runTests]
  :i [(asl-ir/link :a lk) (asl-ir/types :a ty) (asl-target-llvm :a llvm) (asl-target-llvm/libc :a libc) (asl-target-llvm/gcRoute :a gr)
      (asl-target-llvm/gcAsl :a gc) (asl-tools/fleet/run :a run)])

fn clangLink -> String
  "/usr/bin/clang -O2 -Wno-override-module -x ir "

fn lib -> String
  " -x none asl/host/out/libaslrt.a -lm -o "

(schema Captured
  (:f exitCode Int64)
  (:f stdout String)
  (:f stderr String))

fn ! shWithin cmd: String timeoutS: Int64 -> Captured
  (let [(root (optionOr (envGet "ASL_ROOT") "."))
        (prelude (optionOr (envGet "ASL_PRELUDE") (str root "/asl/prelude/prelude.asl")))
        (path (optionOr (envGet "PATH") "/usr/bin:/bin"))
        (base (str (optionOr (envGet "TMPDIR") "/tmp") "/gcMarkSpeedTest." (monotonicNs)))
        (outPath (str base ".out"))
        (errPath (str base ".err"))
        (done (run/runOneLimited (run/job (list "sh" "-c" (str "(cd '" root "' && (" cmd ")) > " outPath " 2> " errPath)) root
                                         (run/childEnv (list (str "ASL_ROOT=" root) (str "ASL_PRELUDE=" prelude) (str "PATH=" path))))
                                 (run/limits timeoutS 32)))
        (outText (resultOr (fileReadString outPath) ""))
        (errText (resultOr (fileReadString errPath) ""))
        (_ (pathRemove outPath))
        (_ (pathRemove errPath))]
    (Captured :exitCode done.exit :stdout outText :stderr (if (= done.verdict "exit") errText (str errText done.out))))

fn ! sh cmd: String -> Captured
  (shWithin cmd 1200)

fn formatDiags ds: (List ty/IrDiag) -> String
  (stringJoin (map (fn [(d ty/IrDiag)] -> String (str d.locus ": [" d.code "] " d.message)) ds) "; ")

fn ! hostTriple -> String
  (let [(k (stringReplace (sh "uname -s").stdout "\n" ""))
        (m (stringReplace (sh "uname -m").stdout "\n" ""))]
    (cond
      ((and (= k "Darwin") (= m "arm64")) "darwin-arm64")
      ((and (= k "Linux") (= m "x86_64")) "linux-x86_64")
      ((and (= k "Linux") (or (= m "aarch64") (= m "arm64"))) "linux-aarch64")
      (else "")))

fn ! drainOf -> (Option ty/SsaFunction)
  (match (libc/libcFacts (hostTriple))
    ((none) none)
    ((some facts) (match (gr/collectorModule facts)
                    ((err ds) (do (assert false (str "collectorModule: " (formatDiags ds))) none))
                    ((ok m) (listHead (filter (fn [(f ty/SsaFunction)] -> Bool (= f.name (gc/functionName "drain"))) m.functions))))))

fn instrsOf f: ty/SsaFunction -> (List ty/SsaInstr)
  (fold (fn [(acc (List ty/SsaInstr)) (b ty/SsaBlock)] -> (List ty/SsaInstr) (listAppend acc b.instrs)) (list) f.blocks)

fn defOf all: (List ty/SsaInstr) name: String -> (Option ty/SsaInstr)
  (listHead (filter (fn [(i ty/SsaInstr)] -> Bool (= i.dest name)) all))

fn constOf all: (List ty/SsaInstr) name: String -> (Option Int64)
  (match (defOf all name)
    ((none) none)
    ((some i) (match i.op ((opConst c) (match c ((constInt v) (some v)) (_ none))) (_ none))))

fn primOf i: ty/SsaInstr -> (Pair String (List String))
  (match i.op ((opPrim name args) (pair name args)) (_ (pair "" (list))))

fn baseOf all: (List ty/SsaInstr) name: String -> String
  (match (defOf all name)
    ((none) name)
    ((some i) (let [(p (primOf i))] (if (= (pairFirst p) "rawIntToPtr") (optionOr (listHead (pairSecond p)) name) name))))

fn memOps all: (List ty/SsaInstr) instrs: (List ty/SsaInstr) -> (List (List String))
  (fold (fn [(acc (List (List String))) (i ty/SsaInstr)] -> (List (List String))
          (let [(p (primOf i)) (name (pairFirst p)) (args (pairSecond p))]
            (if (or (stringStartsWith? name "rawLoad") (stringStartsWith? name "rawStore"))
              (listAppend acc (list (list name (baseOf all (optionOr (listGet args 0) "")) (stringFromInt64 (optionOr (constOf all (optionOr (listGet args 1) "")) -1)))))
              acc)))
        (list) instrs)

fn derives? all: (List ty/SsaInstr) name: String src: String depth: Int64 -> Bool
  (if (= depth 0) false
    (match (defOf all name)
      ((none) false)
      ((some i) (let [(p (primOf i)) (args (pairSecond p))]
                  (if (and (= (pairFirst p) "rawLshrI64") (= (optionOr (listGet args 0) "") src) (= (constOf all (optionOr (listGet args 1) "")) (some 32)))
                    true
                    (listAny? (fn [(a String)] -> Bool (derives? all a src (- depth 1))) args))))))

fn blockOf f: ty/SsaFunction label: String -> (Option ty/SsaBlock)
  (listHead (filter (fn [(b ty/SsaBlock)] -> Bool (= b.label label)) f.blocks))

fn targets t: ty/SsaTerm -> (List String)
  (match t
    ((termJump e) (list e.target))
    ((termBranch c a b) (list a.target b.target))
    (_ (list)))

fn typeGated? all: (List ty/SsaInstr) b: ty/SsaBlock -> Bool
  (match b.term ((termBranch c a e) (derives? all c "oh" 8)) (_ false))

fn reachUngated f: ty/SsaFunction all: (List ty/SsaInstr) todo: (List String) seen: (List String) fuel: Int64 -> (List String)
  (match (listHead todo)
    ((none) seen)
    ((some l) (let [(rest (optionOr (listTail todo) (list)))]
                (if (or (listContains? seen l) (<= fuel 0))
                  (reachUngated f all rest seen (- fuel 1))
                  (match (blockOf f l)
                    ((none) (reachUngated f all rest (cons l seen) (- fuel 1)))
                    ((some b) (reachUngated f all (if (or (= l "kids") (typeGated? all b)) rest (listAppend rest (targets b.term))) (cons l seen) (- fuel 1))))))))

fn opCount b: ty/SsaBlock -> Int64
  (listLength (filter (fn [(i ty/SsaInstr)] -> Bool (match i.op ((opConst c) false) (_ true))) b.instrs))

fn pathOps f: ty/SsaFunction labels: (List String) -> Int64
  (fold (fn [(acc Int64) (l String)] -> Int64 (+ acc (match (blockOf f l) ((some b) (opCount b)) ((none) 0)))) 0 labels)

fn interiorPath -> (List String)
  (list "kid" "test" "ptest" "page" "push" "room" "put")

fn leafPath gated: Bool -> (List String)
  (if gated (list "kid" "test" "ptest" "page" "push") (list "kid" "test" "ptest" "page" "push" "put" "loop" "pop" "t0" "t1" "t2" "t3" "leaf"))

fn markedBytesOffset -> String
  (stringFromInt64 (* 8 56))

fn ! testStructure -> Bool
  (match (drainOf)
    ((none) (do (assert false "drain: the collector module for this host has a drain function") false))
    ((some f)
      (let [(all (instrsOf f))
            (inLoop (filter (fn [(b ty/SsaBlock)] -> Bool (not (listContains? (list "entry" "start" "done") b.label))) f.blocks))
            (loopMem (memOps all (fold (fn [(acc (List ty/SsaInstr)) (b ty/SsaBlock)] -> (List ty/SsaInstr) (listAppend acc b.instrs)) (list) inLoop)))
            (pageCount (filter (fn [(m (List String))] -> Bool (= (optionOr (listGet m 2) "") "48")) (memOps all all)))
            (markedBytes (filter (fn [(m (List String))] -> Bool (and (= (optionOr (listGet m 1) "") "s") (= (optionOr (listGet m 2) "") (markedBytesOffset)))) loopMem))
            (pushes (filter (fn [(b ty/SsaBlock)] -> Bool
                              (listAny? (fn [(i ty/SsaInstr)] -> Bool (let [(p (primOf i))] (and (= (pairFirst p) "rawStoreI64") (= (optionOr (listGet (pairSecond p) 2) "") "obj")))) b.instrs))
                            f.blocks))
            (pushLabel (optionOr (listHead (map (fn [(b ty/SsaBlock)] -> String b.label) pushes)) ""))
            (fromPage (reachUngated f all (list "page") (list) 200))
            (fromLarge (reachUngated f all (list "lset") (list) 200))
            (gated (match (blockOf f "push") ((some b) (typeGated? all b)) ((none) false)))
            (interior (pathOps f (interiorPath)))
            (leaf (pathOps f (leafPath gated)))]
        (do (assert (= (listLength pushes) 1) (str "drain: exactly one block pushes a child onto the mark stack; got " (listLength pushes)))
            (assert (= (listLength pageCount) 0) (str "drain: no per-object load or store of the page header's mark count at offset 48; got " (listLength pageCount)))
            (assert (= (listLength markedBytes) 0) (str "drain: marked bytes stay in a register inside the loop, no state slot 56 access outside entry, start and done; got " (listLength markedBytes)))
            (assert (listAny? (fn [(l String)] -> Bool (match (blockOf f l) ((some b) (and (typeGated? all b) (listContains? (targets b.term) "kids"))) ((none) false))) fromPage)
                    (str "drain: a marked pooled child meets a branch on its type byte that returns a fieldless child to the child loop; reached " (stringJoin fromPage " ")))
            (refute (listContains? fromPage pushLabel) (str "drain: a marked pooled child reaches the push block " pushLabel " only through a branch on its type byte; reached " (stringJoin fromPage " ")))
            (refute (listContains? fromLarge pushLabel) (str "drain: a marked large child reaches the push block " pushLabel " only through a branch on its type byte; reached " (stringJoin fromLarge " ")))
            (assert (<= interior 56) (str "drain: a newly marked pooled child with fields costs at most 56 non-constant SSA instructions (base dd434074c: 61); got " interior))
            (assert (<= leaf 50) (str "drain: a newly marked pooled child without fields costs at most 50 non-constant SSA instructions (base dd434074c: 75, its push, pop and dispatch included); got " leaf))
            true))))

fn statsField text: String key: String -> Int64
  (let [(line (optionOr (listHead (filter (fn [(l String)] -> Bool (stringStartsWith? l "(:gcStats ")) (stringLines text))) ""))
        (tokens (filter (fn [(t String)] -> Bool (not (stringEmpty? t))) (stringSplit line " ")))]
    (match (listIndexOf tokens key)
      ((some i) (optionOr (stringToInt64 (stringReplace (optionOr (listGet tokens (+ i 1)) "") ")" "")) -1))
      ((none) -1)))

fn ! emitted path: String -> String
  (match (lk/linkEntry! path)
    ((err ds) (do (assert false (str path ": links; " (formatDiags ds))) ""))
    ((ok m) (match (llvm/emitLlvmProgramNative! m (str m.name ".main"))
              ((err ds) (do (assert false (str path ": emits; " (formatDiags ds))) ""))
              ((ok code) code))))

fn ! built work: String name: String path: String -> String
  (let [(ll (str work "/" name ".ll"))
        (bin (str work "/" name))]
    (do (assert (ok? (fileWrite ll (emitted path))) (str name ": .ll written"))
        (let [(linked (sh (str (clangLink) ll (lib) bin)))]
          (assert (= linked.exitCode 0) (str name ": links against libaslrt.a; " linked.stderr)))
        bin))

fn deepSource -> String
  (stringJoin
    (list "(module deepMod"
          "  :x [main]"
          "  :i [])"
          ""
          "(schema Leaf (:f label String) (:f weight Int64))"
          ""
          "(enum Tree (:c tip [(leaf Leaf)] \"tip\") (:c fork [(left Tree) (right Tree) (name String)] \"fork\"))"
          ""
          "fn grow depth: Int64 seed: Int64 -> Tree"
          "  (if (= depth 0)"
          "    (tip (Leaf :label (str \"l\" (stringFromInt64 seed)) :weight seed))"
          "    (fork (grow (- depth 1) (* seed 2)) (grow (- depth 1) (+ (* seed 2) 1)) (str \"n\" (stringFromInt64 seed))))"
          ""
          "fn weigh t: Tree -> Int64"
          "  (match t ((tip l) (+ l.weight (stringLength l.label))) ((fork a b nm) (+ (weigh a) (+ (weigh b) (stringLength nm)))))"
          ""
          "fn churn i: Int64 acc: Int64 -> Int64"
          "  (if (= i 0) acc (churn (- i 1) (+ acc (stringLength (str \"c\" (stringFromInt64 i))))))"
          ""
          "fn ! main args: (List String) -> (Result Unit String)"
          "  (let [(n (optionOr (stringToInt64 (optionOr (listHead args) \"5\")) 5))"
          "        (trees (map (fn [(i Int64)] -> Tree (grow n i)) (range 0 6)))"
          "        (getters (map (fn [(t Tree)] -> (Fn Int64 -> Int64) (fn [(x Int64)] -> Int64 (+ x (weigh t)))) trees))"
          "        (pairs (map (fn [(t Tree)] -> (List Tree) (cons t (cons t (list)))) trees))"
          "        (noise (churn (* n 400) 0))"
          "        (a (fold (fn [(acc Int64) (g (Fn Int64 -> Int64))] -> Int64 (+ acc (g 1))) 0 getters))"
          "        (b (fold (fn [(acc Int64) (p (List Tree))] -> Int64 (+ acc (fold (fn [(s Int64) (t Tree)] -> Int64 (+ s (weigh t))) 0 p))) 0 pairs))]"
          "    (do (println (str a \" \" b \" \" noise))"
          "        (ok ())))"
          "")
    "\n")

; (:m :ref RECSROA :do "the two record rows measure the escaping copy fixtures/recordScalar/alloc/record.asl, since recordScalar removes bench/native/record.asl's per-step Body: one more 16-byte object live from start to exit, every per-step figure unchanged")
; (:m :ref UNBOXFIELDS :do "record, allocMix and deep rows repinned: records of Int64/Float64/Bool fields store raw words (Body 56 -> 40 B), so bytesAllocated, bytesLive and collection counts drop; stdout and objectsAllocated unchanged")
; (:m :ref WAVE2 :do "list, allocMix and deep rows repinned on the integrated tree from its own output: CLOSPEC loop-only closure clones remove fold closures (24 B each: list -1 object -24 B, allocMix -1 object -24 B, deep -3 objects -72 B); allocMix stress objectsFreed 10001->10000 under UFEMIT alone was one extra fold closure live at the exit snapshot (+24 B live, records -8 B = bytesLive +16), gone once CLOSPEC removes the closure: 9 live objects as on main, bytesLive 274 = 282 - 8 from the unboxed record")
; (:m :ref TOKEN-DEFAULTS :do "list and allocMix rows repinned from the integrated tree's own output: the benches became short scripts whose argInt reads the argument without the spelled-out fallback string, one object and 21 B fewer for list; the collector is unchanged, and on the base tree the old programs still give the old rows")
fn runs -> (List (List String))
  (list (list "record" "3000" "ASL_GC_STRESS=1" "0 1" "3012" "3012" "3003" "120345" "213")
        (list "list" "2000" "ASL_GC_STRESS=1" "3003000" "5010" "5010" "4005" "200306" "40109")
        (list "allocMix" "2000" "ASL_GC_STRESS=1" "164708" "10008" "10008" "10000" "384256" "253")
        (list "deep" "5" "ASL_GC_STRESS=1" "19512 39012 8893" "5384" "5384" "4392" "166040" "39443")
        (list "record" "200000" "ASL_GC_MIN_MIB=1" "780 -39" "7" "200012" "183502" "8000357" "140")
        (list "list" "200000" "ASL_GC_MIN_MIB=1" "30000300000" "3" "500010" "3" "20000318" "9436647")
        (list "allocMix" "200000" "ASL_GC_MIN_MIB=1" "509154" "36" "1000008" "983048" "38400260" "183")
        (list "deep" "13" "ASL_GC_MIN_MIB=1" "1208473736 2416947460 24893" "3" "354504" "52330" "13278352" "5350784"))

; (:m :ref LLVM-NODE2-REDS-B :do "objectsFreed and bytesLive at the exit snapshot depend on what the target's stack and registers still hold when the program ends (macOS arm64 keeps a stale list head or a few objects the x86_64 code has already dropped), so each triple has its own recorded rows; the other columns, stdout, collections and bytesAllocated, are equal on both; linux-x86_64 rows measured on node2 (clang 20) 2026-10-30")
fn runsLinuxX8664 -> (List (List String))
  (list (list "record" "3000" "ASL_GC_STRESS=1" "0 1" "3012" "3012" "3004" "120345" "173")
        (list "list" "2000" "ASL_GC_STRESS=1" "3003000" "5010" "5010" "5004" "200306" "142")
        (list "allocMix" "2000" "ASL_GC_STRESS=1" "164708" "10008" "10008" "10003" "384256" "125")
        (list "deep" "5" "ASL_GC_STRESS=1" "19512 39012 8893" "5384" "5384" "5290" "166040" "3537")
        (list "record" "200000" "ASL_GC_MIN_MIB=1" "780 -39" "7" "200012" "183502" "8000357" "140")
        (list "list" "200000" "ASL_GC_MIN_MIB=1" "30000300000" "3" "500010" "3" "20000318" "9436647")
        (list "allocMix" "200000" "ASL_GC_MIN_MIB=1" "509154" "36" "1000008" "983045" "38400260" "295")
        (list "deep" "13" "ASL_GC_MIN_MIB=1" "1208473736 2416947460 24893" "3" "354504" "52330" "13278352" "5350784"))

; (:m :ref LLVM-NODE2-REDS-B :do "the exit snapshot counts what a stale stack word keeps alive, which moves with address randomisation (record 200000 gave bytesLive 140 and 180 on two linux runs), so Linux runs the fixtures with randomisation off and the recorded rows are reproducible")
fn ! noAslr! -> String
  (if (= (stringTrim (sh "uname -s").stdout) "Linux") (str "setarch " (stringTrim (sh "uname -m").stdout) " -R ") "")

fn ! hostRuns! -> (List (List String))
  (if (= (hostTriple) "linux-x86_64") (runsLinuxX8664) (runs))

fn ! sameRun work: String bins: (List (Pair String String)) row: (List String) -> Bool
  (let [(name (optionOr (listGet row 0) ""))
        (arg (optionOr (listGet row 1) ""))
        (env (optionOr (listGet row 2) ""))
        (bin (optionOr (match (listHead (filter (fn [(p (Pair String String))] -> Bool (= (pairFirst p) name)) bins)) ((some p) (some (pairSecond p))) ((none) none)) ""))
        (out (sh (str "ASL_GC_STATS=1 " env " " (noAslr!) bin " " arg)))
        (got (list (stringReplace out.stdout "\n" "")
                   (stringFromInt64 (statsField out.stderr ":collections")) (stringFromInt64 (statsField out.stderr ":objectsAllocated"))
                   (stringFromInt64 (statsField out.stderr ":objectsFreed")) (stringFromInt64 (statsField out.stderr ":bytesAllocated"))
                   (stringFromInt64 (statsField out.stderr ":bytesLive"))))
        (want (optionOr (listTail (optionOr (listTail (optionOr (listTail row) (list))) (list))) (list)))
        (label (str name " " arg " " env))]
    (do (assert (= out.exitCode 0) (str label ": exits 0; " out.stderr))
        (assert (> (statsField out.stderr ":collections") 0) (str label ": collects; " out.stderr))
        (assert (= got want) (str label ": stdout and (collections objectsAllocated objectsFreed bytesAllocated bytesLive) equal the base collector's; want " (stringJoin want " ") " got " (stringJoin got " ")))
        true))

fn ! testSemantics work: String -> Bool
  (let [(deep (str work "/deep.asl"))
        (written (fileWrite deep (deepSource)))
        (bins (list (pair "record" (built work "record" "asl/packages/asl-target-llvm/tests/fixtures/recordScalar/alloc/record.asl")) (pair "list" (built work "list" "bench/native/list.asl"))
                    (pair "allocMix" (built work "allocMix" "bench/native/allocMix.asl")) (pair "deep" (built work "deep" deep))))]
    (do (assert (ok? written) (str "fileWrite " deep))
        (assert (> (listLength (hostRuns!)) 0) "runs: base rows recorded")
        (listAll? (fn [(row (List String))] -> Bool (sameRun work bins row)) (hostRuns!))))

fn ! testTimeout -> Bool
  (let [(out (shWithin "sleep 30" 1))]
    (do (assert (= out.exitCode 124) (str "a child exceeding its one-second limit is killed with exit 124; got " out.exitCode " " out.stderr))
        (assert (stringEmpty? out.stdout) (str "a timed-out child leaves no stdout; got " out.stdout))
        true))

fn ! runTests -> Bool
  (let [(made (sh "mktemp -d"))
        (work (stringReplace made.stdout "\n" ""))]
    (do (assert (= made.exitCode 0) "mktemp -d makes a work directory")
        (testStructure)
        (testSemantics work)
        (testTimeout)
        (assert (= (sh (str "rm -rf " work)).exitCode 0) "work directory removed")
        true))
