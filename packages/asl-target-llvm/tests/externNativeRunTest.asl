(module asl-target-llvm/tests/externNativeRunTest
  :x [runTests]
  :i [(asl-ir/types :a ty)
      (asl-target-llvm :a llvm)])

fn clang -> String
  "/usr/bin/clang -Wno-override-module"

fn ! sh cmd: String -> ProcessOutput
  (processRun cmd)

fn ! expectExit label: String cmd: String want: Int64 -> Bool
  (let [(out (sh cmd))]
    (do (assert (= out.exitCode want) (str label ": exit " out.exitCode ", want " want "; stderr: " out.stderr))
        true))

fn ! writeAndLink work: String name: String text: String -> Bool
  (let [(ll (str work "/" name ".ll"))]
    (do (assert (ok? (fileWrite ll text)) (str name ": .ll written"))
        (expectExit (str name ": clang links") (str (clang) " -x ir " ll " -x none -o " work "/" name) 0)))

fn ! compileAndRun work: String name: String csrc: String args: String -> ProcessOutput
  (let [(c (str work "/" name ".c"))]
    (do (assert (ok? (fileWrite c csrc)) (str name ".c: written"))
        (sh (str (clang) " " c " -o " work "/" name " 2>&1 && " work "/" name " " args))))

fn o_wronlyCreatFlags -> String
  "#include <fcntl.h>\n#include <stdio.h>\nint main(void) { printf(\"%d\\n\", O_WRONLY | O_CREAT); return 0; }\n"

fn statModeSource -> String
  "#include <sys/stat.h>\n#include <stdio.h>\nint main(int argc, char** argv) {\n  struct stat st;\n  if (argc < 2 || stat(argv[1], &st) != 0) { printf(\"-1\\n\"); return 1; }\n  printf(\"%d\\n\", (int)(st.st_mode & 07777));\n  return 0;\n}\n"

fn ! probeFlags work: String -> Int64
  (optionOr (stringToInt64 (stringReplace (compileAndRun work "flagsProbe" (o_wronlyCreatFlags) "").stdout "\n" "")) -1)

fn ! probeMode work: String path: String -> Int64
  (optionOr (stringToInt64 (stringReplace (compileAndRun work "statModeProbe" (statModeSource) path).stdout "\n" "")) -1)

fn ! optBin -> (Option String)
  (let [(known (filter (fn [(c String)] -> Bool (= (sh (str "test -x " c)).exitCode 0))
                        (list "/opt/homebrew/opt/llvm/bin/opt" "/opt/homebrew/opt/llvm@22/bin/opt" "/usr/local/opt/llvm/bin/opt")))]
    (mt (listGet known 0)
      ((some o) (some o))
      ((none) (if (= (sh "command -v opt >/dev/null 2>&1").exitCode 0) (some "opt") (none)))))

fn ! verifyLl label: String work: String file: String -> Bool
  (mt (optBin)
    ((none) (do (println (str label ": opt not found on this host, skipping -passes=verify")) true))
    ((some o) (expectExit (str label ": opt -passes=verify accepts the emitted IR") (str o " -passes=verify -disable-output " work "/" file ".ll") 0)))

fn mkParam name: String -> ty/SsaParam
  (ty/ssaParam name (ty/tyVal))

fn letTy dest: String t: ty/SsaTy op: ty/SsaOp -> ty/SsaInstr
  (ty/ssaInstr dest t op)

fn intConst dest: String t: ty/SsaTy n: Int64 -> ty/SsaInstr
  (ty/ssaInstr dest t (ty/opConst (ty/constInt n)))

fn strConst dest: String t: ty/SsaTy i: Int64 -> ty/SsaInstr
  (ty/ssaInstr dest t (ty/opConst (ty/constStr i)))

fn mkBlock label: String instrs: (List ty/SsaInstr) term: ty/SsaTerm -> ty/SsaBlock
  (ty/ssaBlock label (list) instrs term)

fn oneBlockFn name: String retTy: ty/SsaTy instrs: (List ty/SsaInstr) term: ty/SsaTerm -> ty/SsaFunction
  (ty/ssaFunction name (list) (list) retTy (list (mkBlock "entry" instrs term)))

fn moduleOf strings: (List String) externs: (List ty/SsaExtern) functions: (List ty/SsaFunction) -> ty/SsaModule
  (ty/ssaModule "fixture" strings (list) (list) externs (list) functions)

fn getpidWriteModule -> ty/SsaModule
  (moduleOf (list "ok\n")
    (list (ty/ssaExternTyped "getpid" (list) (ty/tyI32))
          (ty/ssaExternTyped "write" (list (ty/tyI32) (ty/tyPtr) (ty/tyI64)) (ty/tyI64)))
    (list (oneBlockFn "run" (ty/tyI64)
            (list (letTy "pid" (ty/tyI32) (ty/opCall "getpid" (list)))
                  (intConst "fd" (ty/tyI32) 1)
                  (strConst "msg" (ty/tyPtr) 0)
                  (intConst "len" (ty/tyI64) 3)
                  (letTy "n" (ty/tyI64) (ty/opCall "write" (list "fd" "msg" "len"))))
            (ty/termReturn "n"))))

fn openModule path: String flagsVal: Int64 modeVal: Int64 -> ty/SsaModule
  (moduleOf (list path "DECOY_POOL_STRING_AFTER_PATH")
    (list (ty/ssaExternVariadic "open" (list (ty/tyPtr) (ty/tyI32)) (ty/tyI32)))
    (list (oneBlockFn "run" (ty/tyI64)
            (list (strConst "path" (ty/tyPtr) 0)
                  (intConst "flags" (ty/tyI32) flagsVal)
                  (intConst "mode" (ty/tyI32) modeVal)
                  (letTy "fd" (ty/tyI32) (ty/opCall "open" (list "path" "flags" "mode")))
                  (intConst "zero" (ty/tyI64) 0))
            (ty/termReturn "zero"))))

fn primI dest: String t: ty/SsaTy name: String args: (List String) -> ty/SsaInstr
  (ty/ssaInstr dest t (ty/opPrim name args))

fn rawPrimsModule -> ty/SsaModule
  (moduleOf (list)
    (list (ty/ssaExternTyped "malloc" (list (ty/tyI64)) (ty/tyPtr)))
    (list (oneBlockFn "run" (ty/tyI1)
            (list
              (intConst "size" (ty/tyI64) 64)
              (letTy "buf" (ty/tyPtr) (ty/opCall "malloc" (list "size")))
              (primI "isNull" (ty/tyI1) "rawPtrIsNull" (list "buf"))
              (primI "notNull" (ty/tyI1) "notBool" (list "isNull"))
              (intConst "off0" (ty/tyI64) 0)
              (intConst "v1" (ty/tyI64) -12345678901234)
              (primI "store1" (ty/tyI1) "rawStoreI64" (list "buf" "off0" "v1"))
              (primI "load1" (ty/tyI64) "rawLoadI64" (list "buf" "off0"))
              (primI "check1" (ty/tyI1) "eqInt" (list "load1" "v1"))
              (intConst "off8" (ty/tyI64) 8)
              (intConst "w1" (ty/tyI32) 300000)
              (primI "store2" (ty/tyI1) "rawStoreI32" (list "buf" "off8" "w1"))
              (primI "load2" (ty/tyI32) "rawLoadI32" (list "buf" "off8"))
              (primI "check2" (ty/tyI1) "rawEqI32" (list "load2" "w1"))
              (primI "widened" (ty/tyI64) "rawWidenI32" (list "load2"))
              (primI "narrowed" (ty/tyI32) "rawNarrowI32" (list "widened"))
              (primI "check3" (ty/tyI1) "rawEqI32" (list "narrowed" "w1"))
              (intConst "off20" (ty/tyI64) 20)
              (intConst "b1" (ty/tyI32) 200)
              (primI "store3" (ty/tyI1) "rawStoreI8" (list "buf" "off20" "b1"))
              (primI "load3" (ty/tyI32) "rawLoadI8" (list "buf" "off20"))
              (primI "check4" (ty/tyI1) "rawEqI32" (list "load3" "b1"))
              (intConst "a2" (ty/tyI64) -8)
              (intConst "sc" (ty/tyI64) 65)
              (primI "shl1" (ty/tyI64) "rawShlI64" (list "a2" "sc"))
              (intConst "negSixteen" (ty/tyI64) -16)
              (primI "check5" (ty/tyI1) "eqInt" (list "shl1" "negSixteen"))
              (primI "ashr1" (ty/tyI64) "rawAshrI64" (list "a2" "sc"))
              (intConst "negFour" (ty/tyI64) -4)
              (primI "check6" (ty/tyI1) "eqInt" (list "ashr1" "negFour"))
              (intConst "one64" (ty/tyI64) 1)
              (primI "lshr1" (ty/tyI64) "rawLshrI64" (list "a2" "one64"))
              (intConst "lshrExpected" (ty/tyI64) 9223372036854775804)
              (primI "check7" (ty/tyI1) "eqInt" (list "lshr1" "lshrExpected"))
              (intConst "fifteen" (ty/tyI64) 15)
              (primI "and1" (ty/tyI64) "rawAndI64" (list "a2" "fifteen"))
              (intConst "eight" (ty/tyI64) 8)
              (primI "check8" (ty/tyI1) "eqInt" (list "and1" "eight"))
              (intConst "zero64" (ty/tyI64) 0)
              (intConst "five" (ty/tyI64) 5)
              (primI "or1" (ty/tyI64) "rawOrI64" (list "zero64" "five"))
              (primI "check9" (ty/tyI1) "eqInt" (list "or1" "five"))
              (intConst "three" (ty/tyI64) 3)
              (primI "xor1" (ty/tyI64) "rawXorI64" (list "five" "three"))
              (intConst "six" (ty/tyI64) 6)
              (primI "check10" (ty/tyI1) "eqInt" (list "xor1" "six"))
              (intConst "maxI32" (ty/tyI32) 2147483647)
              (intConst "one32" (ty/tyI32) 1)
              (primI "wrapped" (ty/tyI32) "rawAddI32" (list "maxI32" "one32"))
              (intConst "minI32" (ty/tyI32) -2147483648)
              (primI "check11" (ty/tyI1) "rawEqI32" (list "wrapped" "minI32"))
              (intConst "eight32" (ty/tyI32) 8)
              (intConst "sc32" (ty/tyI32) 33)
              (primI "shl32" (ty/tyI32) "rawShlI32" (list "eight32" "sc32"))
              (intConst "sixteen32" (ty/tyI32) 16)
              (primI "check12" (ty/tyI1) "rawEqI32" (list "shl32" "sixteen32"))
              (primI "ptrToIntVal" (ty/tyI64) "rawPtrToInt" (list "buf"))
              (primI "check13" (ty/tyI1) "neInt" (list "ptrToIntVal" "zero64"))
              (primI "backToPtr" (ty/tyPtr) "rawIntToPtr" (list "ptrToIntVal"))
              (primI "backToPtrIsNull" (ty/tyI1) "rawPtrIsNull" (list "backToPtr"))
              (primI "backToPtrNotNull" (ty/tyI1) "notBool" (list "backToPtrIsNull"))
              (primI "roundTripInt" (ty/tyI64) "rawPtrToInt" (list "backToPtr"))
              (primI "check14" (ty/tyI1) "eqInt" (list "roundTripInt" "ptrToIntVal"))
              (primI "nullPtr" (ty/tyPtr) "rawIntToPtr" (list "zero64"))
              (primI "check15" (ty/tyI1) "rawPtrIsNull" (list "nullPtr"))
              (primI "r1" (ty/tyI1) "andBool" (list "notNull" "check1"))
              (primI "r2" (ty/tyI1) "andBool" (list "r1" "check2"))
              (primI "r3" (ty/tyI1) "andBool" (list "r2" "check3"))
              (primI "r4" (ty/tyI1) "andBool" (list "r3" "check4"))
              (primI "r5" (ty/tyI1) "andBool" (list "r4" "check5"))
              (primI "r6" (ty/tyI1) "andBool" (list "r5" "check6"))
              (primI "r7" (ty/tyI1) "andBool" (list "r6" "check7"))
              (primI "r8" (ty/tyI1) "andBool" (list "r7" "check8"))
              (primI "r9" (ty/tyI1) "andBool" (list "r8" "check9"))
              (primI "r10" (ty/tyI1) "andBool" (list "r9" "check10"))
              (primI "r11" (ty/tyI1) "andBool" (list "r10" "check11"))
              (primI "r12" (ty/tyI1) "andBool" (list "r11" "check12"))
              (primI "r13" (ty/tyI1) "andBool" (list "r12" "check13"))
              (primI "r14" (ty/tyI1) "andBool" (list "r13" "backToPtrNotNull"))
              (primI "r15" (ty/tyI1) "andBool" (list "r14" "check14"))
              (primI "allOk" (ty/tyI1) "andBool" (list "r15" "check15")))
            (ty/termReturn "allOk"))))

fn loadGlobalModule -> ty/SsaModule
  (moduleOf (list) (list)
    (list (oneBlockFn "run" (ty/tyI1)
            (list
              (ty/ssaInstr "envp" (ty/tyPtr) (ty/opLoadGlobal "environ"))
              (primI "envpIsNull" (ty/tyI1) "rawPtrIsNull" (list "envp"))
              (primI "envpNotNull" (ty/tyI1) "notBool" (list "envpIsNull"))
              (intConst "off0" (ty/tyI64) 0)
              (primI "firstInt" (ty/tyI64) "rawLoadI64" (list "envp" "off0"))
              (primI "first" (ty/tyPtr) "rawIntToPtr" (list "firstInt"))
              (primI "firstIsNull" (ty/tyI1) "rawPtrIsNull" (list "first"))
              (primI "firstNotNull" (ty/tyI1) "notBool" (list "firstIsNull"))
              (primI "allOk" (ty/tyI1) "andBool" (list "envpNotNull" "firstNotNull")))
            (ty/termReturn "allOk"))))

fn ! testLoadGlobal work: String -> Bool
  (let [(text (textOf (llvm/emitLlvmProgram (loadGlobalModule) "run")))]
    (do (assert (not (stringStartsWith? text "ERR")) (str "loadGlobal: emits: " text))
        (assert (stringContains? text "@environ = external global ptr") "loadGlobal: declares environ as an external global ptr")
        (assert (stringContains? text "load ptr, ptr @environ") "loadGlobal: opLoadGlobal lowers to a direct load of @environ")
        (writeAndLink work "loadGlobal" text)
        (verifyLl "loadGlobal" work "loadGlobal")
        (let [(out (sh (str "env FOO=bar " work "/loadGlobal")))]
          (do (assert (= out.exitCode 1) (str "loadGlobal: exit " out.exitCode ", want 1 (environ and environ[0] both non-null)"))
              true))))

fn ! testRawPrims work: String -> Bool
  (let [(text (textOf (llvm/emitLlvmProgram (rawPrimsModule) "run")))]
    (do (assert (not (stringStartsWith? text "ERR")) (str "rawPrims: emits: " text))
        (assert (stringContains? text "declare ptr @malloc(i64)") "rawPrims: declares malloc as a native (ccc) ptr function")
        (assert (stringContains? text "icmp eq ptr") "rawPrims: rawPtrIsNull lowers to icmp eq ptr ... null")
        (assert (stringContains? text "getelementptr inbounds i8") "rawPrims: load/store address by getelementptr inbounds i8 at a byte offset")
        (assert (stringContains? text "sext i32") "rawPrims: rawWidenI32 lowers to sext i32 to i64")
        (assert (stringContains? text "trunc i64") "rawPrims: rawNarrowI32 lowers to trunc i64 to i32")
        (assert (stringContains? text "ptrtoint ptr") "rawPrims: rawPtrToInt lowers to ptrtoint")
        (assert (stringContains? text "inttoptr i64") "rawPrims: rawIntToPtr lowers to inttoptr")
        (assert (stringContains? text "call void @rterr.int(i32 7)") "rawPrims: rawNarrowI32's out-of-range path calls rtError's rterr.int, emitted into the module, so the program links against libc alone")
        (writeAndLink work "rawPrims" text)
        (verifyLl "rawPrims" work "rawPrims")
        (let [(out (sh (str work "/rawPrims")))]
          (do (assert (= out.exitCode 1) (str "rawPrims: exit " out.exitCode ", want 1 (every check true)"))
              true))))

fn textOf res: (Result String (List ty/IrDiag)) -> String
  (mt res ((ok text) text) ((err diags) (str "ERR: " (stringJoin (map (fn [(d ty/IrDiag)] -> String d.code) diags) ", "))))

fn ! testGetpidWrite work: String -> Bool
  (let [(text (textOf (llvm/emitLlvmProgram (getpidWriteModule) "run")))]
    (do (assert (not (stringStartsWith? text "ERR")) (str "getpidWrite: emits: " text))
        (assert (stringContains? text "declare i32 @getpid()") "getpidWrite: declares getpid as a native (ccc) i32 function")
        (assert (stringContains? text "declare i64 @write(i32, ptr, i64)") "getpidWrite: declares write(i32, ptr, i64)")
        (writeAndLink work "getpidWrite" text)
        (let [(out (sh (str work "/getpidWrite")))]
          (do (assert (= out.exitCode 3) (str "getpidWrite: exit " out.exitCode ", want 3 (bytes written)"))
              (assert (= out.stdout "ok\n") (str "getpidWrite: stdout is \"ok\\n\", got " out.stdout))
              true))))

fn ! testVariadicOpen work: String -> Bool
  (let [(path (str work "/opened.txt"))
        (mode 384)
        (flags (probeFlags work))
        (text (textOf (llvm/emitLlvmProgram (openModule path flags mode) "run")))]
    (do (assert (> flags 0) (str "variadicOpen: O_WRONLY|O_CREAT probed as " flags))
        (assert (not (stringStartsWith? text "ERR")) (str "variadicOpen: emits: " text))
        (assert (stringContains? text "declare i32 @open(ptr, i32, ...)") "variadicOpen: declares open as variadic")
        (assert (stringContains? text (str "@str.0 = private unnamed_addr constant [" (+ (stringLength path) 1) " x i8] c\"")) (str "variadicOpen: @str.0 is NUL-terminated (" (+ (stringLength path) 1) " bytes, path is " (stringLength path) "): " text))
        (assert (stringContains? text "\\00\"\n@str.1") (str "variadicOpen: @str.0's literal ends \\00 right before @str.1 (the decoy pool string): " text))
        (writeAndLink work "variadicOpen" text)
        (expectExit "variadicOpen: runs" (str "umask 0; " work "/variadicOpen") 0)
        (assert (= (sh (str "test -f " path)).exitCode 0) (str "variadicOpen: " path " exists"))
        (let [(got (probeMode work path))]
          (do (assert (= got mode) (str "variadicOpen: mode is " mode " (the mode passed to open), got " got))
              true))))

fn ! runTests -> Bool
  (let [(made (sh "mktemp -d"))
        (work (stringReplace made.stdout "\n" ""))]
    (do (assert (= made.exitCode 0) "mktemp -d makes a work directory")
        (testGetpidWrite work)
        (testVariadicOpen work)
        (testRawPrims work)
        (testLoadGlobal work)
        (assert (= (exitOf (str "rm -rf " work)) 0) "work directory removed")
        true))

fn ! exitOf cmd: String -> Int64
  (sh cmd).exitCode
