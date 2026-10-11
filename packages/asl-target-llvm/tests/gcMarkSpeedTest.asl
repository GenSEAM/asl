(module asl-target-llvm/tests/gcMarkSpeedTest
  :x [runTests]
  :i [(asl-ir/link :a lk) (asl-ir/types :a ty) (asl-target-llvm :a llvm) (asl-target-llvm/libc :a libc) (asl-target-llvm/gcRoute :a gr)
      (asl-target-llvm/gcAsl :a gc) (tools/fleet/run :a run)])

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
  (mt (libc/libcFacts (hostTriple))
    ((none) none)
    ((some facts) (mt (gr/collectorModule facts)
                    ((err ds) (do (assert false (str "collectorModule: " (formatDiags ds))) none))
                    ((ok m) (listHead (filter (fn [(f ty/SsaFunction)] -> Bool (= f.name (gc/functionName "drain"))) m.functions))))))

fn instrsOf f: ty/SsaFunction -> (List ty/SsaInstr)
  (fold (fn [(acc (List ty/SsaInstr)) (b ty/SsaBlock)] -> (List ty/SsaInstr) (listAppend acc b.instrs)) (list) f.blocks)

fn defOf all: (List ty/SsaInstr) name: String -> (Option ty/SsaInstr)
  (listHead (filter (fn [(i ty/SsaInstr)] -> Bool (= i.dest name)) all))

fn constOf all: (List ty/SsaInstr) name: String -> (Option Int64)
  (mt (defOf all name)
    ((none) none)
    ((some i) (mt i.op ((opConst c) (mt c ((constInt v) (some v)) (_ none))) (_ none))))

fn primOf i: ty/SsaInstr -> (Pair String (List String))
  (mt i.op ((opPrim name args) (pair name args)) (_ (pair "" (list))))

fn baseOf all: (List ty/SsaInstr) name: String -> String
  (mt (defOf all name)
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
    (mt (defOf all name)
      ((none) false)
      ((some i) (let [(p (primOf i)) (args (pairSecond p))]
                  (if (and (= (pairFirst p) "rawLshrI64") (= (optionOr (listGet args 0) "") src) (= (constOf all (optionOr (listGet args 1) "")) (some 32)))
                    true
                    (listAny? (fn [(a String)] -> Bool (derives? all a src (- depth 1))) args))))))

fn blockOf f: ty/SsaFunction label: String -> (Option ty/SsaBlock)
  (listHead (filter (fn [(b ty/SsaBlock)] -> Bool (= b.label label)) f.blocks))

fn targets t: ty/SsaTerm -> (List String)
  (mt t
    ((termJump e) (list e.target))
    ((termBranch c a b) (list a.target b.target))
    (_ (list)))

fn typeGated? all: (List ty/SsaInstr) b: ty/SsaBlock -> Bool
  (mt b.term ((termBranch c a e) (derives? all c "oh" 8)) (_ false))

fn reachUngated f: ty/SsaFunction all: (List ty/SsaInstr) todo: (List String) seen: (List String) fuel: Int64 -> (List String)
  (mt (listHead todo)
    ((none) seen)
    ((some l) (let [(rest (optionOr (listTail todo) (list)))]
                (if (or (listContains? seen l) (<= fuel 0))
                  (reachUngated f all rest seen (- fuel 1))
                  (mt (blockOf f l)
                    ((none) (reachUngated f all rest (cons l seen) (- fuel 1)))
                    ((some b) (reachUngated f all (if (or (= l "kids") (typeGated? all b)) rest (listAppend rest (targets b.term))) (cons l seen) (- fuel 1))))))))

fn opCount b: ty/SsaBlock -> Int64
  (listLength (filter (fn [(i ty/SsaInstr)] -> Bool (mt i.op ((opConst c) false) (_ true))) b.instrs))

fn pathOps f: ty/SsaFunction labels: (List String) -> Int64
  (fold (fn [(acc Int64) (l String)] -> Int64 (+ acc (mt (blockOf f l) ((some b) (opCount b)) ((none) 0)))) 0 labels)

fn interiorPath -> (List String)
  (list "kid" "test" "ptest" "page" "push" "room" "put")

fn leafPath gated: Bool -> (List String)
  (if gated (list "kid" "test" "ptest" "page" "push") (list "kid" "test" "ptest" "page" "push" "put" "loop" "pop" "t0" "t1" "t2" "t3" "leaf"))

fn markedBytesOffset -> String
  (stringFromInt64 (* 8 56))

fn ! testStructure -> Bool
  (mt (drainOf)
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
            (gated (mt (blockOf f "push") ((some b) (typeGated? all b)) ((none) false)))
            (interior (pathOps f (interiorPath)))
            (leaf (pathOps f (leafPath gated)))]
        (do (assert (= (listLength pushes) 1) (str "drain: exactly one block pushes a child onto the mark stack; got " (listLength pushes)))
            (assert (= (listLength pageCount) 0) (str "drain: no per-object load or store of the page header's mark count at offset 48; got " (listLength pageCount)))
            (assert (= (listLength markedBytes) 0) (str "drain: marked bytes stay in a register inside the loop, no state slot 56 access outside entry, start and done; got " (listLength markedBytes)))
            (assert (listAny? (fn [(l String)] -> Bool (mt (blockOf f l) ((some b) (and (typeGated? all b) (listContains? (targets b.term) "kids"))) ((none) false))) fromPage)
                    (str "drain: a marked pooled child meets a branch on its type byte that returns a fieldless child to the child loop; reached " (stringJoin fromPage " ")))
            (refute (listContains? fromPage pushLabel) (str "drain: a marked pooled child reaches the push block " pushLabel " only through a branch on its type byte; reached " (stringJoin fromPage " ")))
            (refute (listContains? fromLarge pushLabel) (str "drain: a marked large child reaches the push block " pushLabel " only through a branch on its type byte; reached " (stringJoin fromLarge " ")))
            (assert (<= interior 56) (str "drain: a newly marked pooled child with fields costs at most 56 non-constant SSA instructions (base dd434074c: 61); got " interior))
            (assert (<= leaf 50) (str "drain: a newly marked pooled child without fields costs at most 50 non-constant SSA instructions (base dd434074c: 75, its push, pop and dispatch included); got " leaf))
            true))))

fn statsField text: String key: String -> Int64
  (let [(line (optionOr (listHead (filter (fn [(l String)] -> Bool (stringStartsWith? l "(:gcStats ")) (stringLines text))) ""))
        (tokens (filter (fn [(t String)] -> Bool (not (stringEmpty? t))) (stringSplit line " ")))]
    (mt (listIndexOf tokens key)
      ((some i) (optionOr (stringToInt64 (stringReplace (optionOr (listGet tokens (+ i 1)) "") ")" "")) -1))
      ((none) -1)))

fn ! emitted path: String -> String
  (mt (lk/linkEntry! path)
    ((err ds) (do (assert false (str path ": links; " (formatDiags ds))) ""))
    ((ok m) (mt (llvm/emitLlvmProgramNative! m (str m.name ".main"))
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
          "  (mt t ((tip l) (+ l.weight (stringLength l.label))) ((fork a b nm) (+ (weigh a) (+ (weigh b) (stringLength nm)))))"
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

fn runs -> (List (List String))
  (list (list "record" "3000" "ASL_GC_STRESS=1" "0 1" "3035" "3035" "3024" "169050" "276")
        (list "list" "2000" "ASL_GC_STRESS=1" "3003000" "5036" "5036" "4025" "201056" "40259")
        (list "allocMix" "2000" "ASL_GC_STRESS=1" "164708" "10034" "10034" "10023" "417006" "297")
        (list "deep" "5" "ASL_GC_STRESS=1" "19512 39012 8893" "5396" "5396" "4397" "167885" "41124")
        (list "record" "200000" "ASL_GC_MIN_MIB=1" "780 -39" "10" "200045" "187259" "11201374" "296")
        (list "list" "200000" "ASL_GC_MIN_MIB=1" "30000300000" "3" "500046" "34" "20001380" "9428611")
        (list "allocMix" "200000" "ASL_GC_MIN_MIB=1" "509154" "39" "1000044" "983060" "41601322" "355")
        (list "deep" "13" "ASL_GC_MIN_MIB=1" "1208473736 2416947460 24893" "3" "354521" "51317" "13672033" "5451447"))

fn ! sameRun work: String bins: (List (Pair String String)) row: (List String) -> Bool
  (let [(name (optionOr (listGet row 0) ""))
        (arg (optionOr (listGet row 1) ""))
        (env (optionOr (listGet row 2) ""))
        (bin (optionOr (mt (listHead (filter (fn [(p (Pair String String))] -> Bool (= (pairFirst p) name)) bins)) ((some p) (some (pairSecond p))) ((none) none)) ""))
        (out (sh (str "ASL_GC_STATS=1 " env " " bin " " arg)))
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
        (bins (list (pair "record" (built work "record" "bench/native/record.asl")) (pair "list" (built work "list" "bench/native/list.asl"))
                    (pair "allocMix" (built work "allocMix" "bench/native/allocMix.asl")) (pair "deep" (built work "deep" deep))))]
    (do (assert (ok? written) (str "fileWrite " deep))
        (assert (> (listLength (runs)) 0) "runs: base rows recorded")
        (listAll? (fn [(row (List String))] -> Bool (sameRun work bins row)) (runs))))

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
