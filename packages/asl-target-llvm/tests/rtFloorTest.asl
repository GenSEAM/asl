(module asl-target-llvm/tests/rtFloorTest
  :x [runTests]
  :i [(asl-ir/link :a lk) (asl-ir/types :a irTy) (asl-target-llvm :a llvm)])

fn rtLib -> String
  "asl/host/out/libaslrt.a"

fn ! sh cmd: String -> ProcessOutput
  (processRun cmd)

fn formatDiags ds: (List irTy/IrDiag) -> String
  (stringJoin (map (fn [(d irTy/IrDiag)] -> String (str d.locus ": [" d.code "] " d.message)) ds) "; ")

fn ! emitted path: String -> String
  (mt (lk/linkEntry! path)
    ((err ds) (do (assert false (str path ": links; " (formatDiags ds))) ""))
    ((ok m) (mt (llvm/emitLlvmProgramNative! m (str m.name ".main"))
              ((err ds) (do (assert false (str path ": emits; " (formatDiags ds))) ""))
              ((ok code) code))))

fn ! defined obj: String -> (List String)
  (let [(out (sh (str "nm -g " obj)))]
    (do (assert (= out.exitCode 0) (str "nm -g " obj ": exit " out.exitCode "; " out.stderr))
        (map (fn [(line String)] -> String
               (let [(name (optionOr (listLast (stringSplit (stringTrim line) " ")) ""))]
                 (if (stringStartsWith? name "_") (optionOr (stringSlice name 1 (stringLength name)) name) name)))
             (filter (fn [(line String)] -> Bool (not (stringContains? line " U "))) (filter (fn [(line String)] -> Bool (not (stringEmpty? (stringTrim line)))) (stringLines out.stdout))))))

fn ! testMembers work: String -> Bool
  (let [(listed (sh (str "ar t " (rtLib))))
        (members (filter (fn [(m String)] -> Bool (and (not (stringEmpty? m)) (not (stringStartsWith? m "__.SYMDEF")))) (stringLines listed.stdout)))
        (taken (sh (str "ar p " (rtLib) " rtFloor.o > " work "/rtFloor.o")))]
    (do (assert (= listed.exitCode 0) (str "ar t lists libaslrt.a; " listed.stderr))
        (assert (= members (list "rtFloor.o" "rtAbi.o" "gcAsl.o")) (str "libaslrt.a holds rtFloor.o rtAbi.o gcAsl.o, every one emitted from ASL; got " (stringJoin members " ")))
        (assert (= taken.exitCode 0) (str "rtFloor.o taken from libaslrt.a; " taken.stderr))
        (let [(names (defined (str work "/rtFloor.o")))]
          (do (assert (listContains? names "gcFloorFail") (str "rtFloor.o defines gcFloorFail; got " (stringJoin names " ")))
              (assert (listContains? names "gcFloorGuard") (str "rtFloor.o defines gcFloorGuard; got " (stringJoin names " ")))
              (assert (listContains? names "gcFloorRaise") (str "rtFloor.o defines gcFloorRaise; got " (stringJoin names " ")))))
        true))

fn ! testFailure work: String -> Bool
  (let [(ll (str work "/list.ll"))
        (bin (str work "/list"))]
    (do (assert (ok? (fileWrite ll (emitted "bench/native/list.asl"))) "list: .ll written")
        (let [(linked (sh (str "/usr/bin/clang -O2 -Wno-override-module -x ir " ll " -x none " (rtLib) " -lm -o " bin)))]
          (assert (= linked.exitCode 0) (str "list: links against libaslrt.a; " linked.stderr)))
        (let [(fits (sh (str bin " 1000")))
              (capped (sh (str "ASL_GC_MAX_MIB=1 " bin " 2000000")))]
          (do (assert (= fits.exitCode 0) (str "list 1000: exits 0; " fits.stderr))
              (assert (= capped.exitCode 1) (str "list 2000000 under ASL_GC_MAX_MIB=1: exits 1 through the floor; got " capped.exitCode " " capped.stderr))
              (assert (= capped.stderr "ERR_OOM: live heap exceeds ASL_GC_MAX_MIB=1\n") (str "the floor prints the collector's formatted ERR_OOM line; got " capped.stderr))
              (assert (= capped.stdout "") (str "nothing reaches stdout; got " capped.stdout))))
        true))

fn refusedReallocIr -> String
  (stringJoin
    (list "@KW_SOME = global i32 0" "@KW_NONE = global i32 0" "@KW_OK = global i32 0" "@KW_ERR = global i32 0" "@KW_PARTIAL = global i32 0" "@slot = global [2 x i64] zeroinitializer"
          "define i32 @aslInternShared(ptr %s, i64 %n) {\n  ret i32 0\n}"
          "define ptr @realloc(ptr %p, i64 %n) {\n  ret ptr null\n}"
          "declare void @asl_rt_global_root(ptr)"
          "define i32 @main() {\n  call void @asl_rt_global_root(ptr @slot)\n  ret i32 0\n}")
    "\n")

fn ! testRootTableFailure work: String -> Bool
  (let [(ll (str work "/refused.ll"))
        (bin (str work "/refused"))]
    (do (assert (ok? (fileWrite ll (str (refusedReallocIr) "\n"))) "refused: .ll written")
        (let [(linked (sh (str "/usr/bin/clang -O2 -Wno-override-module -x ir " ll " -x none " (rtLib) " -lm -o " bin)))]
          (assert (= linked.exitCode 0) (str "refused: links against libaslrt.a; " linked.stderr)))
        (let [(run (sh bin))]
          (do (assert (= run.exitCode 1) (str "refused: exits 1 through the floor; got " run.exitCode " " run.stderr))
              (assert (= run.stderr "ERR_OOM: out of memory growing the global root table to 16 slots\n") (str "rtAbi formats the slot count into its floor message; got " run.stderr))))
        true))

fn raiseHookIr -> String
  (stringJoin
    (list "@gcFloorRaise = external global ptr"
          "@code = private constant [6 x i8] c\"ERR_X\\00\""
          "@msg = private constant [5 x i8] c\"boom\\00\""
          "@fmt = private constant [14 x i8] c\"raised %s %s\\0A\\00\""
          "declare void @gcFloorFail(ptr, ptr, ...)"
          "declare i32 @printf(ptr, ...)"
          "declare void @exit(i32)"
          "define void @raise(ptr %c, ptr %m) {\n  %p = call i32 (ptr, ...) @printf(ptr @fmt, ptr %c, ptr %m)\n  call void @exit(i32 3)\n  unreachable\n}"
          "define i32 @main() {\n  store ptr @raise, ptr @gcFloorRaise\n  call void (ptr, ptr, ...) @gcFloorFail(ptr @code, ptr @msg)\n  ret i32 0\n}")
    "\n")

fn ! testRaiseHook work: String -> Bool
  (let [(ll (str work "/raise.ll"))
        (bin (str work "/raise"))]
    (do (assert (ok? (fileWrite ll (str (raiseHookIr) "\n"))) "raise: .ll written")
        (let [(linked (sh (str "/usr/bin/clang -O2 -Wno-override-module -x ir " ll " -x none " (rtLib) " -lm -o " bin)))]
          (assert (= linked.exitCode 0) (str "raise: links against libaslrt.a, which defines gcFloorRaise; " linked.stderr)))
        (let [(run (sh bin))]
          (do (assert (= run.exitCode 3) (str "raise: the floor hands the failure to gcFloorRaise before printing; got " run.exitCode " " run.stderr))
              (assert (= run.stdout "raised ERR_X boom\n") (str "raise: gcFloorRaise gets the code and message; got " run.stdout))
              (assert (= run.stderr "") (str "raise: the floor prints nothing once the hook takes over; got " run.stderr))))
        true))

fn ! runTests -> Bool
  (let [(made (sh "mktemp -d"))
        (work (stringReplace made.stdout "\n" ""))]
    (do (assert (= made.exitCode 0) "mktemp -d makes a work directory")
        (testMembers work)
        (testFailure work)
        (testRootTableFailure work)
        (testRaiseHook work)
        (assert (= (sh (str "rm -rf " work)).exitCode 0) "work directory removed")
        true))
