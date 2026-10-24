(module asl-target-llvm/tests/rcSelfCompileTest
  :x [runTests]
  :i [(asl-tools/seed :a seed) (asl-tools/fleet/run :a fr)
      (asl/packages/asl-cli/src/system :a sys)
      (asl/packages/asl-cli/src/asl1Cache :a cache)
      (asl/packages/asl-cli/src/nativeBuild :a nb)])

(schema Libs
  (:f plain String)
  (:f asan String)
  (:f notrace String))

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

fn ! newWork label: String -> String
  (let [(dir (str (optionOr (envGet "TMPDIR") "/tmp") "/" label "." (procSelf) "." (monotonicNs)))
        (_ (dirCreate dir))]
    dir)

fn ! fileSha path: String -> String
  (match (fileReadBytes path) ((ok b) (bytesSha256 b)) ((err e) (str "unreadable " e)))

fn ! job argv: (List String) env: (List String) -> fr/Done
  (fr/runOneLimited (fr/job argv (root) (fr/childEnv env)) (fr/limits 1500 16))

fn ! linkWith libs: Libs ll: String out: String asan: Bool -> (Result String String)
  (linkMode libs ll out (if asan "asan" "1"))

fn ! linkMode libs: Libs ll: String out: String mode: String -> (Result String String)
  (let [(argv (cond
                ((= mode "asan") (listAppend (cons "clang" (nb/sanitizeFlags)) (list "-Wno-override-module" "-x" "ir" ll "-x" "none" libs.asan "-lm" "-o" out)))
                ((= mode "notrace") (list "clang" "-O1" "-Wno-override-module" "-x" "ir" ll "-x" "none" libs.notrace "-lm" "-o" out))
                (else (list "clang" "-O1" "-Wno-override-module" "-x" "ir" ll "-x" "none" libs.plain "-lm" "-o" out))))
        (d (job argv (list)))]
    (if (and (= d.exit 0) (fileExists? out)) (ok out) (err (str "clang " ll " (" d.verdict " exit " d.exit "): " (stringTrim d.out)))))

fn ! errFile work: String label: String -> String
  (str work "/" label ".stderr")

fn ! compileMode compiler: String mode: String work: String label: String entry: String -> (Result String String)
  (let [(out (str work "/" label ".ll"))
        (errPath (errFile work label))
        (d (job (listAppend (list "sh" "-c" (str "exec \"$0\" build \"$1\" -o \"$2\" $4 2> \"$3\"") compiler entry out errPath) (if (= mode "0") (list) (list (str "--rc " mode))))
                (list (str "ASL_ROOT=" (root)) (str "ASL_PRELUDE=" (root) "/asl/prelude/prelude.asl") "ASL_HOST_CACHE=0" "ASL_RC_STATS=1")))]
    (if (and (= d.exit 0) (fileExists? out)) (ok out)
      (err (str compiler " build " entry " mode " mode " (" d.verdict " exit " d.exit "): " (stringTrim d.out) " " (resultOr (fileReadString errPath) "")))))

fn statOf text: String key: String -> Int64
  (match (stringIndexOf text (str ":" key " "))
    ((none) -1)
    ((some at) (let [(rest (optionOr (stringSlice text (+ at (+ (stringLength key) 2)) (stringLength text)) ""))
                     (digits (optionOr (listHead (stringSplit (optionOr (listHead (stringSplit rest ")")) rest) " ")) ""))]
                 (optionOr (stringToInt64 digits) -1))))

fn ! andThen r: (Result String String) next: (fn [String] -> (Result String String)) -> (Result String String)
  (match r ((ok v) (next v)) ((err e) (err e)))

schema Stages
  stage2: String
  traced: String
  counted: String
  countedOut: String
  asanOut: String
  untracedOut: String

fn ! stages libs: Libs work: String -> (Result Stages String)
  (let [(c (seed/compilerSource))]
    (match (seed/verify (root) (resultOr (fileReadString (str (root) "/" (seed/manifestPath))) "") work)
      ((err x) (err x))
      ((ok e)
       (match (andThen (andThen (seed/verifyEntry (root) e work) (fn [(s String)] -> (Result String String) (linkWith libs s (str work "/stage1") false)))
                    (fn [(s1 String)] -> (Result String String) (andThen (compileMode s1 "0" work "stage2" c) (fn [(l String)] -> (Result String String) (linkWith libs l (str work "/stage2") false)))))
         ((err x) (err x))
         ((ok s2)
          (match (compileMode s2 "0" work "stage3" c)
            ((err x) (err x))
            ((ok traced)
             (match (andThen (andThen (compileMode s2 "1" work "stage3rc" c) (fn [(l String)] -> (Result String String) (linkWith libs l (str work "/stage3rc") false)))
                          (fn [(b String)] -> (Result String String) (compileMode b "0" work "stage4rc" c)))
               ((err x) (err x))
               ((ok countedOut)
                (match (andThen (andThen (compileMode s2 "asan" work "stage3asan" c) (fn [(l String)] -> (Result String String) (linkWith libs l (str work "/stage3asan") true)))
                             (fn [(b String)] -> (Result String String) (compileMode b "0" work "stage4asan" c)))
                  ((err x) (err x))
                  ((ok asanOut)
                   (match (andThen (andThen (compileMode s2 "notraceStats" work "stage3nt" c) (fn [(l String)] -> (Result String String) (linkMode libs l (str work "/stage3nt") "notrace")))
                                (fn [(b String)] -> (Result String String) (compileMode b "0" work "stage4nt" c)))
                     ((err x) (err x))
                     ((ok untracedOut) (ok (Stages :stage2 s2 :traced traced :counted (str work "/stage3rc.ll") :countedOut countedOut :asanOut asanOut :untracedOut untracedOut)))))))))))))))

fn ! testSelfCompile libs: Libs -> Bool
  (let [(work (newWork "rcSelfCompile"))
        (built (stages libs work))
        (countedText (resultOr (fileReadString (str work "/stage3rc.ll")) ""))
        (rcStats (resultOr (fileReadString (errFile work "stage4rc")) ""))
        (asanErr (resultOr (fileReadString (errFile work "stage4asan")) ""))
        (ntStats (resultOr (fileReadString (errFile work "stage4nt")) ""))
        (ntText (resultOr (fileReadString (str work "/stage3nt.ll")) ""))
        (fib (match built
               ((err x) (err x))
               ((ok s) (andThen (compileMode (str work "/stage3rc") "0" work "fib" (seed/fibSource)) (fn [(l String)] -> (Result String String) (linkWith libs l (str work "/fib") false))))))
        (fibRun (match fib ((ok b) (some (job (list b) (list)))) ((err _) (none))))
        (_ (do (eprintln (str "rcSelfCompile stage4rc " rcStats " stage4nt " ntStats)) true))
        (shas (match built ((ok s) (list (fileSha s.traced) (fileSha s.countedOut) (fileSha s.asanOut) (fileSha s.untracedOut))) ((err _) (list "" "counted missing" "asan missing" "untraced missing"))))
        (_ (do (eprintln (str "rcSelfCompile sha traced/counted/asan " (stringJoin shas " "))) true))
        (_ (pathRemove work))]
    (do (assert (match built ((ok _) true) ((err x) (do (eprintln x) false))) "seed -> stage2 -> stage3 (tracing), stage3rc, stage3asan and stage3nt build and each recompiles asl1")
        (assert (and (= (stringLength (optionOr (listGet shas 0) "")) 64) (= (listGet shas 1) (listGet shas 0))) "asl1 built with RC compiles asl1 to IR byte-identical to the tracing build's output")
        (assert (and (= (stringLength (optionOr (listGet shas 0) "")) 64) (= (listGet shas 2) (listGet shas 0))) "asl1 built with RC under ASan compiles asl1 to IR byte-identical to the tracing build's output")
        (assert (stringContains? countedText "call tailcc i64 @aslRcDrop(") "the RC build of asl1 carries compiler-inserted drops")
        (assert (> (statOf rcStats "freed") 1000000) (str "the RC-built compiler frees over a million cells while compiling asl1: " rcStats))
        (assert (> (statOf rcStats "reused") 1000000) (str "the RC-built compiler reuses over a million freed cells: " rcStats))
        (assert (and (> (statOf rcStats "freed") 0) (< (* 100 (statOf rcStats "pinned")) (statOf rcStats "freed"))) (str "the RC-built compiler pins under 1% as many cells as it frees (builtins and list builders borrow): " rcStats))
        (refute (stringContains? asanErr "Sanitizer") (str "ASan reports nothing while the RC-built compiler compiles asl1: " asanErr))
        (assert (and (= (stringLength (optionOr (listGet shas 0) "")) 64) (= (listGet shas 3) (listGet shas 0))) "asl1 built with RC and no tracing collector compiles asl1 to IR byte-identical to the tracing build's output")
        (assert (stringContains? ntText "label %largeFree") "the untraced RC build frees unpooled objects itself")
        (assert (> (statOf ntStats "largeFreed") 1000000) (str "the untraced compiler frees over a million unpooled objects (arrays, bytes, over 512 B) itself: " ntStats))
        (assert (< (* 100 (- (statOf ntStats "large") (statOf ntStats "largeFreed"))) (statOf ntStats "large")) (str "the untraced compiler leaves under 1% of its unpooled objects live at exit: " ntStats))
        (assert (and (> (statOf ntStats "freed") 1000000) (= (statOf ntStats "stuck") 0)) (str "the untraced compiler frees its pooled cells and leaves none sticky: " ntStats))
        (assert (match fibRun ((some d) (= d.exit 42)) ((none) false)) "fibProgram built by the RC-built compiler exits 42")
        (refute (fileExists? work) "the work directory is removed")
        true))

fn ! runTests -> Bool
  (do (assert (match (runtimes!) ((ok libs) (testSelfCompile libs)) ((err e) (do (eprintln (str "rcSelfCompile runtimes: " e)) false))) "RC self-compile matches tracing")
      true)
