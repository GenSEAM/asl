(module asl-target-llvm/tests/foreignTest
  :x [runTests]
  :i [(asl-ir/types :a ty)
      (asl-ir/lower :a low)
      (asl-ir/verify :a vfy)
      (asl-target-llvm/libc :a libc)
      (asl-target-llvm/sysRoute :a rt)
      (asl-target-llvm/ffiRoute :a ffi)
      (asl-target-llvm/ssa :a llvm)
      (asl-tools/fleet/run :a run)])

; (:m :ref FFI1 :do "foreign end to end: ffiRoute turns each stub into a checked wrapper with a typed extern, wasm rejects it, and bin/asl build links a fixture that calls libm cbrt, libc strlen toupper isdigit strerror and libz crc32 adler32 (named by :linkLibraries) natively; outputs are compared with the C results")
fn unitSource -> String
  (stringJoin (list
    "(module ffiUnit :x [cubeRoot crc toUpper errorText digit scale combine seven] :i [])"
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
    ""
    "fn ! scale x: Float64 n: Int64 -> Float64"
    "  (foreign \"m\" \"scalbln\" \"f64 i64 -> f64\")"
    ""
    "fn ! combine a: Int64 b: Int64 n: Int64 -> Int64"
    "  (foreign \"z\" \"crc32_combine\" \"u64 u64 i64 -> u64\")"
    ""
    "fn ! seven a: Int64 b: Int64 c: Int64 d: Int64 e: Int64 f: Int64 g: Int64 h: Float64 -> Float64"
    "  (foreign \"c\" \"aslSevenProbe\" \"i64 i64 i64 i64 i64 i64 i64 f64 -> f64\")"
    "") "\n")

; (:m :ref LINUXFFI :do "a C symbol is declared and called with the C convention even when its signature is only i64 and f64: as an ASL tailcc extern, cbrt returned garbage and crashed on x86_64 Linux, and a seventh scalar argument would go to asl_rt_spill instead of the C stack")
fn cDeclared? ll: String ret: String sym: String args: String -> Bool
  (and (stringContains? ll (str "declare " ret " @" sym "(" args ")"))
       (not (stringContains? ll (str "tailcc " ret " @" sym "("))))

fn ! testCConvention out: ty/SsaModule -> Bool
  (match (llvm/emitLlvmModule out)
    ((err ds) (do (assert (listEmpty? ds) (str "the routed module emits LLVM: " (stringJoin (diagCodes ds) " "))) false))
    ((ok ll) (do (assert (cDeclared? ll "double" "cbrt" "double") "cbrt (f64 -> f64) is declared and called with the C convention, not tailcc")
                 (assert (cDeclared? ll "double" "scalbln" "double, i64") "scalbln (f64 i64 -> f64) is a plain C declaration, not tailcc")
                 (assert (cDeclared? ll "i64" "crc32_combine" "i64, i64, i64") "crc32_combine (u64 u64 i64 -> u64) is a plain C declaration, not tailcc")
                 (assert (not (stringContains? ll "musttail call tailcc double @cbrt")) "the cbrt wrapper calls C without musttail")
                 (assert (stringContains? ll "= call double (double) @cbrt(double %x)") (str "the cbrt wrapper calls cbrt with the C convention: " (stringJoin (filter (fn [(l String)] -> Bool (stringContains? l "@cbrt")) (stringLines ll)) " | ")))
                 (assert (cDeclared? ll "double" "aslSevenProbe" "i64, i64, i64, i64, i64, i64, i64, double") "a C symbol with seven i64 arguments is declared with all of them, so x86_64 passes the seventh on the C stack")
                 (assert (stringContains? ll "= call double (i64, i64, i64, i64, i64, i64, i64, double) @aslSevenProbe(") "the seven i64 arguments reach the C call itself, none through asl_rt_spill")
                 true)))

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
        (do (assert (= (listLength stubs) 8) (str "the eight foreign fns lower to stubs: " (stringJoin stubs " ")))
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
                            (assert (testCConvention out) "every foreign C symbol keeps the C calling convention")
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
    "fn ! swap x: Int64 -> (Result Int64 String)"
    "  (foreign \"c\" \"htonl\" \"u32 -> u32\")"
    ""
    "fn ! swapSigned x: Int64 -> (Result Int64 String)"
    "  (foreign \"c\" \"htonl\" \"i32 -> i32\")"
    ""
    "fn ! crcChecked seed: Int64 data: Bytes -> (Result Int64 String)"
    "  (foreign \"z\" \"crc32\" \"u64 bytes32 -> u64\")"
    ""
    "fn ! absBool b: Bool -> Int64"
    "  (foreign \"c\" \"abs\" \"bool -> i32\")"
    ""
    "fn ! scale x: Float64 n: Int64 -> Float64"
    "  (foreign \"m\" \"scalbln\" \"f64 i64 -> f64\")"
    ""
    "fn ! nearest x: Float64 -> Int64"
    "  (foreign \"m\" \"lround\" \"f64 -> i64\")"
    ""
    "fn ! fused a: Float64 b: Float64 c: Float64 -> Float64"
    "  (foreign \"m\" \"fma\" \"f64 f64 f64 -> f64\")"
    ""
    "fn ! combine a: Int64 b: Int64 n: Int64 -> Int64"
    "  (foreign \"z\" \"crc32_combine\" \"u64 u64 i64 -> u64\")"
    ""
    "fn ! nameInfo sa: String saLen: Int64 host: String hostLen: Int64 serv: String servLen: Int64 flags: Int64 -> Int64"
    "  (foreign \"c\" \"getnameinfo\" \"cstr u32 cstr u32 cstr u32 i32 -> i32\")"
    ""
    "fn ! envText name: String -> String"
    "  (foreign \"c\" \"getenv\" \"cstr -> cstr\")"
    ""
    "fn ! twice x: Int64 -> (Result Int64 String)"
    "  (match (swap x) ((ok y) (swap y)) ((err e) (err e)))"
    ""
    "fn ! twiceSigned x: Int64 -> (Result Int64 String)"
    "  (match (swapSigned x) ((ok y) (swapSigned y)) ((err e) (err e)))"
    ""
    "fn ! main args: (List String) -> (Result Int64 String)"
    "  (cond"
    "    ((listContains? args \"trap\") (do (println (str (lower 4294967296))) (ok 0)))"
    "    ((listContains? args \"nul\") (do (println (str (cLength \"a\\x00b\"))) (ok 0)))"
    "    ((listContains? args \"null\") (do (println (str (stringLength (envText \"ASL_FFI1_UNSET_PROBE_NAME\")))) (ok 0)))"
    "    (else (do (println (str \"cbrt \" (cubeRoot 8.0) \" \" (cubeRoot 64.0) \" \" (cubeRoot -8.0)))"
    "        (println (str \"mixed \" (scale 3.0 4) \" \" (nearest 2.5) \" \" (fused 2.0 3.0 1.0) \" \" (combine (crc 0 (stringToBytes \"hel\")) (crc 0 (stringToBytes \"lo\")) 2)))"
    "        (println (str \"seven \" (nameInfo \"\" 0 \"\" 0 \"\" 0 -1) \" \" (nameInfo \"\" 0 \"\" 0 \"\" 0 0)))"
    "        (println (str \"strlen \" (cLength \"héllo\") \" \" (cLength \"\")))"
    "        (println (str \"crc32 \" (crc 0 (stringToBytes \"hello\")) \" \" (crc 0 (stringToBytes \"\"))))"
    "        (println (str \"adler32 \" (adler 1 \"hello\")))"
    "        (println (str \"upper \" (upper 97) \" \" (lower 66)))"
    "        (println (str \"range \" (upper 4294967296) \" \" (upper -2147483649)))"
    "        (println (str \"digit \" (digit 55) \" \" (digit 65)))"
    "        (println (str \"errno2 \" (errorText 2)))"
    "        (println (str \"nul \" (cLengthChecked \"a\\x00b\")))"
    "        (println (str \"i32 \" (twiceSigned -2147483648) \" \" (twiceSigned 2147483647) \" \" (twiceSigned -2147483649) \" \" (twiceSigned 2147483648)))"
    "        (println (str \"u32 \" (twice 0) \" \" (twice 2147483648) \" \" (twice 4294967295) \" \" (swap 4294967295) \" \" (swap 1)))"
    "        (println (str \"u32out \" (twice -1) \" \" (twice 4294967296)))"
    "        (println (str \"u64 \" (crcChecked 9223372036854775807 (stringToBytes \"hi\")) \" \" (crcChecked -1 (stringToBytes \"hi\"))))"
    "        (println (str \"bool \" (absBool true) \" \" (absBool false)))"
    "        (ok 0))))"
    "") "\n")

; (:m :ref LINUXFFI :do "the double ABI lines: cbrt of exact cubes (glibc cbrt 27.0 is 3.0000000000000004, so no inexact root), scalbln f64 i64, lround f64 -> i64, fma f64 f64 f64, crc32_combine u64 u64 i64, and getnameinfo with seven arguments so x86_64 passes flags on the stack; glibc rejects flags -1 with EAI_BADFLAGS before it reads the empty address (EAI_FAMILY), macOS returns 0 for both")
fn sevenLine os: String -> String
  (if (= os "Linux") "seven -1 -6" "seven 0 0")

fn expectedLines os: String -> (List String)
  (list "cbrt 2.0 4.0 -2.0"
        "mixed 48.0 3 7.0 907060870"
        (sevenLine os)
        "strlen 6 0"
        "crc32 907060870 0"
        "adler32 103547413"
        "upper (ok 65) 98"
        "range (err \"ERR_RANGE: ffiFixture.upper (C toupper) argument 1 is outside C i32\") (err \"ERR_RANGE: ffiFixture.upper (C toupper) argument 1 is outside C i32\")"
        "digit true false"
        "errno2 No such file or directory"
        "nul (err \"ERR_FOREIGN_NUL: ffiFixture.cLengthChecked (C strlen) argument 1 holds a NUL byte, which a C string cannot carry\")"
        "i32 (ok -2147483648) (ok 2147483647) (err \"ERR_RANGE: ffiFixture.swapSigned (C htonl) argument 1 is outside C i32\") (err \"ERR_RANGE: ffiFixture.swapSigned (C htonl) argument 1 is outside C i32\")"
        "u32 (ok 0) (ok 2147483648) (ok 4294967295) (ok 4294967295) (ok 16777216)"
        "u32out (err \"ERR_RANGE: ffiFixture.swap (C htonl) argument 1 is outside C u32\") (err \"ERR_RANGE: ffiFixture.swap (C htonl) argument 1 is outside C u32\")"
        "u64 (ok 1723189164) (err \"ERR_RANGE: ffiFixture.crcChecked (C crc32) argument 1 is outside C u64\")"
        "bool 1 0")

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
        (os (stringTrim (runIn (list "/bin/sh" "-c" "uname -s") dir 30).out))
        (errFile (str dir "/build.err"))
        (built (runIn (list "/bin/sh" "-c" (str "exec \"$0\" build \"$1\" -o \"$2\" 2> " (shellQuote errFile)) (str root "/bin/asl") (str dir "/main.asl") exe) root 1500))
        (buildErr (resultOr (fileReadString errFile) ""))
        (ran (if (= built.exit 0) (runIn (list exe) dir 60) built))
        (trapped (if (= built.exit 0) (runIn (list "/bin/sh" "-c" "exec \"$0\" trap 2>&1" exe) dir 60) built))
        (nulTrap (if (= built.exit 0) (runIn (list "/bin/sh" "-c" "exec \"$0\" nul 2>&1" exe) dir 60) built))
        (nullTrap (if (= built.exit 0) (runIn (list "/usr/bin/env" "-u" "ASL_FFI1_UNSET_PROBE_NAME" "/bin/sh" "-c" "exec \"$0\" null 2>&1" exe) dir 60) built))
        (lines (filter (fn [(l String)] -> Bool (not (stringEmpty? l))) (stringLines ran.out)))]
    (do (assert (ok? made) (str "the fixture directory " dir " was created"))
        (assert (and (ok? wroteManifest) (ok? wroteSource)) "the fixture files were written")
        (assert (or (= os "Linux") (= os "Darwin")) (str "the host is Linux or Darwin: " os))
        (assert (= built.exit 0) (str "bin/asl build links the foreign fixture with -lz from :linkLibraries: exit " built.exit " " built.out " " buildErr))
        (assert (= ran.exit 0) (str "the fixture runs: exit " ran.exit " " ran.out))
        (assert (= (listLength lines) (listLength (expectedLines os))) (str "the fixture prints " (listLength (expectedLines os)) " lines: " ran.out))
        (fold (fn [(acc Bool) (i Int64)] -> Bool
                (do (assert (= (optionOr (listGet lines i) "") (optionOr (listGet (expectedLines os) i) "")) (str "line " (+ i 1) " is the C result: got " (optionOr (listGet lines i) "") ", want " (optionOr (listGet (expectedLines os) i) "")))
                    acc))
              true (range 0 (listLength (expectedLines os))))
        (assert (!= trapped.exit 0) (str "a plain foreign fn traps on an out-of-range argument: exit " trapped.exit))
        (assert (stringContains? trapped.out "ERR_RANGE") (str "the trap names ERR_RANGE: " trapped.out))
        (assert (stringContains? trapped.out "C tolower") (str "the trap names the C symbol: " trapped.out))
        (assert (!= nulTrap.exit 0) (str "a plain foreign fn traps on a NUL byte: exit " nulTrap.exit))
        (assert (stringContains? nulTrap.out "ERR_FOREIGN_NUL: ffiFixture.cLength (C strlen)") (str "the plain NUL trap raises its own code: " nulTrap.out))
        (assert (!= nullTrap.exit 0) (str "a plain foreign fn traps on a NULL C string: exit " nullTrap.exit))
        (assert (stringContains? nullTrap.out "ERR_FOREIGN_NULL: ffiFixture.envText (C getenv) returned a NULL C string") (str "the plain NULL trap raises its own code: " nullTrap.out))
        (assert (not (stringContains? (str nulTrap.out nullTrap.out) "unknown error code")) "no foreign trap code is unknown to the runtime")
        true))

; (:m :ref FFI1 :do "a :linkLibraries entry reaches the clang command line, so bin/asl build refuses a flag, a space, a path or a response file before it compiles anything")
fn ! rejectsLink work: String root: String name: String i: Int64 -> Bool
  (let [(dir (str work "/badLink" (stringFromInt64 i)))
        (made (dirCreate dir))
        (wroteManifest (fileWrite (str dir "/manifest.asn") (str "(:package badLink :version \"0.1.0\" :entry \"main.asl\" :linkLibraries [\"" name "\"])\n")))
        (wroteSource (fileWrite (str dir "/main.asl") "(module badLink :x [main] :i [])\n\nfn ! main args: (List String) -> (Result Int64 String)\n  (ok (listLength args))\n"))
        (built (runIn (list "/bin/sh" "-c" "exec \"$0\" build \"$1\" -o \"$2\" 2>&1" (str root "/bin/asl") (str dir "/main.asl") (str dir "/never")) root 600))]
    (do (assert (and (ok? made) (and (ok? wroteManifest) (ok? wroteSource))) (str "the " name " fixture was written"))
        (assert (!= built.exit 0) (str "bin/asl build refuses :linkLibraries " name ": exit " built.exit))
        (assert (stringContains? built.out (str "ERR_BUILD: " dir "/manifest.asn: :linkLibraries names " name ", which is not a library name")) (str "the refusal names the entry " name ": " built.out))
        (assert (not (fileExists? (str dir "/never"))) (str "no executable is written for " name))
        true))

fn ! testLinkValidation root: String work: String -> Bool
  (listAll? (fn [(p (Pair Int64 String))] -> Bool (rejectsLink work root (pairSecond p) (pairFirst p)))
            (enumerate (list "-Wl,-x" "z m" "z/../x" "@file")))

fn ! runTests -> Bool
  (let [(root (resultOr (realPath ".") "."))
        (work (str root "/.asl/cache/foreignTest." (stringFromInt64 (procSelf))))
        (_ (dirCreate (str root "/.asl/cache")))
        (made (dirCreate work))
        (routed (testRoute))
        (built (if (ok? made) (testBuild root work) false))
        (validated (if (ok? made) (testLinkValidation root work) false))
        (cleaned (run/runOneLimited (run/job (list "/bin/rm" "-rf" work) root (run/childEnv (list))) (run/limits 60 4)))]
    (do (assert routed "ffiRoute binds and rejects as declared")
        (assert built "the native foreign fixture builds and prints the C results")
        (assert validated "bin/asl build validates :linkLibraries names")
        (assert (= cleaned.exit 0) "the work directory was removed")
        true))
