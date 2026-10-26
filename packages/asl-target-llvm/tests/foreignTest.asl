(module asl-target-llvm/tests/foreignTest
  :x [runTests]
  :i [(asl-ir/types :a ty)
      (asl-ir/lower :a low)
      (asl-ir/verify :a vfy)
      (asl-target-llvm/libc :a libc)
      (asl-target-llvm/sysRoute :a rt)
      (asl-target-llvm/ffiRoute :a ffi)
      (asl-tools/fleet/run :a run)])

; (:m :ref FFI1 :do "foreign end to end: ffiRoute turns each stub into a checked wrapper with a typed extern, wasm rejects it, and bin/asl build links a fixture that calls libm cbrt, libc strlen toupper isdigit strerror and libz crc32 adler32 (named by :linkLibraries) natively; outputs are compared with the C results")
fn unitSource -> String
  (stringJoin (list
    "(module ffiUnit :x [cubeRoot crc toUpper errorText digit] :i [])"
    ""
    "fn ! cubeRoot x: Float64 -> Float64"
    "  (foreign \"m\" \"cbrt\" \"f64 -> f64\")"
    ""
    "fn ! crc seed: Int64 data: Bytes -> Int64"
    "  (foreign \"z\" \"crc32\" \"u64 bytes32 -> u64\")"
    ""
    "fn ! toUpper c: Int64 -> (Result Int64 String)"
    "  (foreign \"c\" \"toupper\" \"i32 -> i32\")"
    ""
    "fn ! errorText code: Int64 -> String"
    "  (foreign \"c\" \"strerror\" \"i32 -> cstr\")"
    ""
    "fn ! digit c: Int64 -> Bool"
    "  (foreign \"c\" \"isdigit\" \"i32 -> bool\")"
    "") "\n")

fn clashSource -> String
  (stringJoin (list
    "(module ffiClash :x [a b] :i [])"
    ""
    "fn ! a x: Float64 -> Float64"
    "  (foreign \"m\" \"cbrt\" \"f64 -> f64\")"
    ""
    "fn ! b x: Int64 -> Float64"
    "  (foreign \"m\" \"cbrt\" \"i64 -> f64\")"
    "") "\n")

fn externNamed m: ty/SsaModule name: String -> (Option ty/SsaExtern)
  (listFind (fn [(e ty/SsaExtern)] -> Bool (= e.name name)) m.externs)

fn tyNames ts: (List ty/SsaTy) -> (List String)
  (map (fn [(t ty/SsaTy)] -> String (ty/ssaTyName t)) ts)

fn diagCodes ds: (List ty/IrDiag) -> (List String)
  (map (fn [(d ty/IrDiag)] -> String d.code) ds)

fn ! testRoute -> Bool
  (match (low/lowerSource (unitSource))
    ((err ds) (do (assert (listEmpty? ds) (str "the unit source lowers: " (stringJoin (diagCodes ds) " "))) false))
    ((ok m)
      (let [(stubs (ffi/foreignNames m))
            (native (rt/routeModule (libc/darwinArm64Facts) m))
            (wasm (rt/routeModule (libc/wasm32Facts) m))]
        (do (assert (= (listLength stubs) 5) (str "the five foreign fns lower to stubs: " (stringJoin stubs " ")))
            (match native
              ((err ds) (do (assert (listEmpty? ds) (str "the native route binds every stub: " (stringJoin (diagCodes ds) " "))) false))
              ((ok r) (let [(out r.result)
                            (crc (externNamed out "crc32"))
                            (upper (externNamed out "toupper"))
                            (cbrt (externNamed out "cbrt"))]
                        (do (assert (not (ffi/foreign? out)) "no foreign builtin is left after the route")
                            (assert (= (optionMap (fn [(e ty/SsaExtern)] -> (List String) (tyNames e.params)) crc) (some (list "i64" "ptr" "i32"))) "crc32 is declared (i64, ptr, i32): u64 then bytes32 as pointer and u32 length")
                            (assert (= (optionMap (fn [(e ty/SsaExtern)] -> String (ty/ssaTyName e.ret)) crc) (some "i64")) "crc32 returns i64")
                            (assert (= (optionMap (fn [(e ty/SsaExtern)] -> (List String) (tyNames e.params)) upper) (some (list "i32"))) "toupper takes a C int")
                            (assert (= (optionMap (fn [(e ty/SsaExtern)] -> (List String) (tyNames e.params)) cbrt) (some (list "f64"))) "cbrt takes a double")
                            (assert (ok? (vfy/verifySsa out)) (str "the routed module verifies: " (match (vfy/verifySsa out) ((err ds) (stringJoin (diagCodes ds) " ")) ((ok _) ""))))
                            true))))
            (assert (listContains? (match wasm ((err ds) (diagCodes ds)) ((ok _) (list))) "ERR_FOREIGN_TARGET") "wasm32 rejects foreign with ERR_FOREIGN_TARGET")
            (match (low/lowerSource (clashSource))
              ((err ds) (assert (listEmpty? ds) (str "the clash source lowers: " (stringJoin (diagCodes ds) " "))))
              ((ok c) (assert (listContains? (match (rt/routeModule (libc/darwinArm64Facts) c) ((err ds) (diagCodes ds)) ((ok _) (list))) "ERR_FOREIGN_EXTERN")
                              "two signatures for one C symbol are ERR_FOREIGN_EXTERN")))
            true))))

fn fixtureManifest -> String
  "(:package ffiFixture :version \"0.1.0\" :entry \"main.asl\" :linkLibraries [\"z\"])\n"

fn fixtureSource -> String
  (stringJoin (list
    "(module ffiFixture :x [main] :i [])"
    ""
    "fn ! cubeRoot x: Float64 -> Float64"
    "  (foreign \"m\" \"cbrt\" \"f64 -> f64\")"
    ""
    "fn ! cLength s: String -> Int64"
    "  (foreign \"c\" \"strlen\" \"cstr -> u64\")"
    ""
    "fn ! cLengthChecked s: String -> (Result Int64 String)"
    "  (foreign \"c\" \"strlen\" \"cstr -> u64\")"
    ""
    "fn ! crc seed: Int64 data: Bytes -> Int64"
    "  (foreign \"z\" \"crc32\" \"u64 bytes32 -> u64\")"
    ""
    "fn ! adler seed: Int64 data: String -> Int64"
    "  (foreign \"z\" \"adler32\" \"u64 str32 -> u64\")"
    ""
    "fn ! upper c: Int64 -> (Result Int64 String)"
    "  (foreign \"c\" \"toupper\" \"i32 -> i32\")"
    ""
    "fn ! lower c: Int64 -> Int64"
    "  (foreign \"c\" \"tolower\" \"i32 -> i32\")"
    ""
    "fn ! digit c: Int64 -> Bool"
    "  (foreign \"c\" \"isdigit\" \"i32 -> bool\")"
    ""
    "fn ! errorText code: Int64 -> String"
    "  (foreign \"c\" \"strerror\" \"i32 -> cstr\")"
    ""
    "fn ! main args: (List String) -> (Result Int64 String)"
    "  (if (listContains? args \"trap\")"
    "    (do (println (str (lower 4294967296))) (ok 0))"
    "    (do (println (str \"cbrt \" (cubeRoot 27.0) \" \" (cubeRoot -8.0)))"
    "        (println (str \"strlen \" (cLength \"héllo\") \" \" (cLength \"\")))"
    "        (println (str \"crc32 \" (crc 0 (stringToBytes \"hello\")) \" \" (crc 0 (stringToBytes \"\"))))"
    "        (println (str \"adler32 \" (adler 1 \"hello\")))"
    "        (println (str \"upper \" (upper 97) \" \" (lower 66)))"
    "        (println (str \"range \" (upper 4294967296) \" \" (upper -2147483649)))"
    "        (println (str \"digit \" (digit 55) \" \" (digit 65)))"
    "        (println (str \"errno2 \" (errorText 2)))"
    "        (println (str \"nul \" (cLengthChecked \"a\\x00b\")))"
    "        (ok 0)))"
    "") "\n")

fn expectedLines -> (List String)
  (list "cbrt 3.0 -2.0"
        "strlen 6 0"
        "crc32 907060870 0"
        "adler32 103547413"
        "upper (ok 65) 98"
        "range (err \"ERR_RANGE: ffiFixture.upper (C toupper) argument 1 is outside C i32\") (err \"ERR_RANGE: ffiFixture.upper (C toupper) argument 1 is outside C i32\")"
        "digit true false"
        "errno2 No such file or directory"
        "nul (err \"ERR_FOREIGN_NUL: ffiFixture.cLengthChecked (C strlen) argument 1 holds a NUL byte, which a C string cannot carry\")")

fn shellQuote s: String -> String
  (str "'" (stringReplace s "'" "'\\''") "'")

fn ! runIn argv: (List String) cwd: String secs: Int64 -> run/Done
  (run/runOneLimited (run/job argv cwd (run/childEnv (list))) (run/limits secs 24))

fn ! testBuild root: String work: String -> Bool
  (let [(dir (str work "/ffiFixture"))
        (made (dirCreate dir))
        (wroteManifest (fileWrite (str dir "/manifest.asn") (fixtureManifest)))
        (wroteSource (fileWrite (str dir "/main.asl") (fixtureSource)))
        (exe (str dir "/fixture"))
        (errFile (str dir "/build.err"))
        (built (runIn (list "/bin/sh" "-c" (str "exec \"$0\" build \"$1\" -o \"$2\" 2> " (shellQuote errFile)) (str root "/bin/asl") (str dir "/main.asl") exe) root 1500))
        (buildErr (resultOr (fileReadString errFile) ""))
        (ran (if (= built.exit 0) (runIn (list exe) dir 60) built))
        (trapped (if (= built.exit 0) (runIn (list "/bin/sh" "-c" "exec \"$0\" trap 2>&1" exe) dir 60) built))
        (lines (filter (fn [(l String)] -> Bool (not (stringEmpty? l))) (stringLines ran.out)))]
    (do (assert (ok? made) (str "the fixture directory " dir " was created"))
        (assert (and (ok? wroteManifest) (ok? wroteSource)) "the fixture files were written")
        (assert (= built.exit 0) (str "bin/asl build links the foreign fixture with -lz from :linkLibraries: exit " built.exit " " built.out " " buildErr))
        (assert (= ran.exit 0) (str "the fixture runs: exit " ran.exit " " ran.out))
        (assert (= (listLength lines) (listLength (expectedLines))) (str "the fixture prints " (listLength (expectedLines)) " lines: " ran.out))
        (fold (fn [(acc Bool) (i Int64)] -> Bool
                (do (assert (= (optionOr (listGet lines i) "") (optionOr (listGet (expectedLines) i) "")) (str "line " (+ i 1) " is the C result: got " (optionOr (listGet lines i) "") ", want " (optionOr (listGet (expectedLines) i) "")))
                    acc))
              true (range 0 (listLength (expectedLines))))
        (assert (!= trapped.exit 0) (str "a plain foreign fn traps on an out-of-range argument: exit " trapped.exit))
        (assert (stringContains? trapped.out "ERR_RANGE") (str "the trap names ERR_RANGE: " trapped.out))
        (assert (stringContains? trapped.out "C tolower") (str "the trap names the C symbol: " trapped.out))
        true))

fn ! runTests -> Bool
  (let [(root (resultOr (realPath ".") "."))
        (work (str root "/.asl/cache/foreignTest." (stringFromInt64 (procSelf))))
        (_ (dirCreate (str root "/.asl/cache")))
        (made (dirCreate work))
        (routed (testRoute))
        (built (if (ok? made) (testBuild root work) false))
        (cleaned (run/runOneLimited (run/job (list "/bin/rm" "-rf" work) root (run/childEnv (list))) (run/limits 60 4)))]
    (do (assert routed "ffiRoute binds and rejects as declared")
        (assert built "the native foreign fixture builds and prints the C results")
        (assert (= cleaned.exit 0) "the work directory was removed")
        true))
