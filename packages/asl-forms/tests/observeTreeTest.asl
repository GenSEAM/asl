(module asl-forms/tests/observeTreeTest
  :x [runTests]
  :i [(asl-forms/evalOp :a ev) (asl-ir/link :a lk) (asl-tools/fleet/run :a fr)])

; (:m :ref NODE-CLI-REBUILD-PER-TREE :do "asl/tools/observe is out of the native CLI's key: the CLI entry's import closure does not hold observe.asl, and an (:observe) step run inside a tree answers with that tree's observe code, compiled there by evalOp#nativeEntry!, not with code linked into the running binary; the fixture tree links every path of this tree except asl/tools/observe, which is a copy whose tokenCost answer is mutated")
fn ! repoRoot! -> String
  (resultOr (realPath ".") ".")

fn marker -> String
  ":treeMutant 7"

fn mutantSource src: String -> String
  (stringReplace src "(finish (tc/observeTokenCost! root scope limit ctx))" (str "(finish (ok \"(:observe :dim tokenCost " (marker) ")\"))"))

fn ! isDir? path: String -> Bool
  (match (fileLstat path) ((ok st) st.isDir) ((err _) false))

fn ! copyFile! src: String dst: String -> Bool
  (match (fileReadBytes src) ((err _) false) ((ok b) (ok? (fileWrite dst b))))

; (:m :ref NODE-CLI-REBUILD-PER-TREE :do "the module index skips symlinks, so the package and tool sources a build resolves are real copies; tests and fixtures directories are left out")
fn ! copyTree! from: String to: String -> Bool
  (and (ok? (dirCreate to))
    (listAll? (fn [(n String)] -> Bool
                (let [(src (str from "/" n)) (dst (str to "/" n))]
                  (cond
                    ((listContains? (list "tests" "fixtures" "out" ".asl") n) true)
                    ((isDir? src) (copyTree! src dst))
                    (else (copyFile! src dst)))))
              (resultOr (dirList from) (list))))

fn ! mirror! from: String to: String copied: (List String) skip: (List String) -> Bool
  (listAll? (fn [(n String)] -> Bool
              (let [(src (str from "/" n)) (dst (str to "/" n))]
                (cond
                  ((listContains? skip n) true)
                  ((listContains? copied n) (copyTree! src dst))
                  ((isDir? src) (ok? (pathSymlink src dst)))
                  (else (copyFile! src dst)))))
            (resultOr (dirList from) (list)))

fn ! mutate! root: String -> Bool
  (let [(p (str root "/asl/tools/observe/observe.asl"))]
    (match (fileReadString p) ((err _) false) ((ok text) (ok? (fileWrite p (mutantSource text))))))

fn ! gitInit! root: String -> Bool
  (let [(d (fr/runOneLimited (fr/job (list "git" "init" "-q") root (fr/childEnv (list))) (fr/limits 60 8)))] (= d.exit 0))

fn ! fixture! ws: String root: String -> Bool
  (and (and (ok? (dirCreate (str root "/asl"))) (ok? (dirCreate (str root "/.asl/mem"))))
    (and (mirror! ws root (list) (list ".asl" ".git" "asl"))
      (and (mirror! (str ws "/asl") (str root "/asl") (list "packages" "tools" "prelude" "grammar") (list))
        (and (mutate! root) (gitInit! root)))))

; (:m :ref NODE-CLI-REBUILD-PER-TREE :do "the modules of the native CLI's import closure, loaded as its build loads them, that lie under dir; empty when none, the load failure otherwise")
fn ! observeInClosure! entry: String dir: String -> String
  (match (lk/loadClosure! entry)
    ((err _) (str "the closure of " entry " does not load"))
    ((ok units) (stringJoin (filter (fn [(p String)] -> Bool (stringStartsWith? p (str dir "/"))) (map (fn [(u lk/LinkUnit)] -> String (resultOr (realPath u.path) u.path)) units)) " ")))

fn ! runIn! bin: String cwd: String args: (List String) env: (List String) -> fr/Done
  (fr/runOneLimited (fr/job (cons bin args) cwd (fr/childEnv env)) (fr/limits 900 64))

fn ! chmodAll! mode: String root: String base: String -> Bool
  (let [(d (fr/runOneLimited (fr/job (list "/bin/chmod" "-R" mode root) base (fr/childEnv (list))) (fr/limits 60 4)))] (= d.exit 0))

fn ! runTests -> Bool
  (let [(ws (repoRoot!))
        (observe (resultOr (realPath (str ws "/asl/tools/observe")) ""))
        (inKey (observeInClosure! (str ws "/asl/packages/asl-cli/src/native.asl") observe))
        (base (optionOr (envGet "TMPDIR") "/tmp"))
        (root (str (if (stringEndsWith? base "/") (optionOr (stringSlice base 0 (- (stringLength base) 1)) base) base) "/observeTreeTest_" (stringFromInt64 (procSelf)) "_" (stringFromInt64 (monotonicNs))))
        (built (fixture! ws root))
        (mutated (stringContains? (resultOr (fileReadString (str root "/asl/tools/observe/observe.asl")) "") (marker)))
        (driver (ev/nativeEntry! ws "asl-forms/tests/observeTreeDriver" false))
        (bin (resultOr driver ""))
        (cacheEnv (list (str "ASL_NATIVE_TEST_CACHE=" root "-cache")))
        (locked (and built (chmodAll! "a-w" root base)))
        (readOnly (if (and locked (ok? driver)) (runIn! bin root (list "memory") cacheEnv) (fr/Done :idx 0 :exit -1 :out "not run" :ms 0 :verdict "notRun")))
        (readOnlyCallers (if (and locked (ok? driver)) (runIn! bin root (list "callers" "symbol" "runObserve") cacheEnv) (fr/Done :idx 0 :exit -1 :out "not run" :ms 0 :verdict "notRun")))
        (unlocked (chmodAll! "u+w" root base))
        (inTree (if (and built (ok? driver)) (runIn! bin root (list) cacheEnv) (fr/Done :idx 0 :exit -1 :out "not run" :ms 0 :verdict "notRun")))
        (inRepo (if (ok? driver) (runIn! bin ws (list) (list)) (fr/Done :idx 0 :exit -1 :out "not run" :ms 0 :verdict "notRun")))
        (removed (fr/runOneLimited (fr/job (list "/bin/rm" "-rf" root (str root "-cache")) base (fr/childEnv (list))) (fr/limits 120 4)))]
    (do
      (assert (not (stringEmpty? observe)) "asl/tools/observe resolves in this tree")
      (assert (and built mutated) (str "fixture tree with a mutated observe copy is set up at " root))
      (assert (ok? driver) (str "the observe driver builds natively: " (match driver ((ok b) b) ((err e) e))))
      (assert (and (= inTree.exit 0) (stringContains? inTree.out (str ":dim tokenCost " (marker))))
        (str "an (:observe :dim tokenCost) step inside the fixture tree answers with that tree's mutated observe: exit " (stringFromInt64 inTree.exit) " " inTree.out))
      (assert (and locked (and unlocked (and (= readOnly.exit 0) (stringContains? readOnly.out ":dim memory"))))
        (str "with the fixture tree read-only from the start (cold) and the compile cache outside it, (:observe :dim memory) answers: exit " (stringFromInt64 readOnly.exit) " " readOnly.out))
      (assert (and (= readOnlyCallers.exit 0) (stringContains? readOnlyCallers.out ":dim callers"))
        (str "in the same read-only tree (:observe :dim callers :symbol runObserve) answers: exit " (stringFromInt64 readOnlyCallers.exit) " " readOnlyCallers.out))
      (assert (and (= inRepo.exit 0) (and (stringContains? inRepo.out ":dim tokenCost") (not (stringContains? inRepo.out (marker)))))
        (str "the same driver binary inside this tree answers with this tree's observe: exit " (stringFromInt64 inRepo.exit) " " inRepo.out))
      (assert (= removed.exit 0) "the fixture tree is removed")
      (assert (= inKey "") (str "the native CLI entry's import closure holds no module of asl/tools/observe: " inKey))
      true))
