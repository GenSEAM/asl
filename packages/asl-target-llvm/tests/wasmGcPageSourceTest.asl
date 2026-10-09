(module asl/packages/asl-target-llvm/tests/wasmGcPageSourceTest
  :x [runTests]
  :i [(asl-ir/types :a irTy)
      (asl-target-llvm :a targetLlvm)
      (asl-target-llvm/gcRoute :a gr)
      (asl-target-llvm/target :a target)
      (asl-target-llvm/libc :a libc)])

fn ! sh cmd: String -> ProcessOutput
  (processRun cmd)

fn diagText errors: (List irTy/IrDiag) -> String
  (stringJoin (map (fn [(d irTy/IrDiag)] -> String d.message) errors) "; ")

fn ! llcBin -> String
  (let [(known (filter (fn [(c String)] -> Bool (= (sh (str "test -x " c)).exitCode 0))
                        (list "/opt/homebrew/opt/llvm/bin/llc" "/usr/local/opt/llvm/bin/llc" "/usr/lib/llvm-20/bin/llc" "/usr/lib/llvm-19/bin/llc" "/usr/lib/llvm-18/bin/llc")))]
    (mt (listHead known)
      ((some c) c)
      ((none) (stringReplace (sh "command -v llc 2>/dev/null").stdout "\n" ""))))

fn wasmGcText -> (Result String (List irTy/IrDiag))
  (mt (libc/libcFacts "darwin-arm64")
    ((none) (err (list (irTy/makeIrDiag "ERR_TEST" "libc.asl has no darwin-arm64 facts" "wasmGcPageSourceTest"))))
    ((some facts) (gr/collectorTextForTarget facts (target/wasm32TargetFacts))))

fn helloModule -> irTy/SsaModule
  (irTy/ssaModule "wasmHello" (list) (list) (list) (list) (list)
    (list (irTy/ssaFunction "main" (list) (list) (irTy/tyI64)
      (list (irTy/ssaBlock "entry" (list)
        (list (irTy/ssaInstr "zero" (irTy/tyI64) (irTy/opConst (irTy/constInt 0))))
        (irTy/termReturn "zero"))))))

fn wasmHelloText -> (Result String (List irTy/IrDiag))
  (mt (libc/libcFacts "darwin-arm64")
    ((none) (err (list (irTy/makeIrDiag "ERR_TEST" "libc.asl has no darwin-arm64 facts" "wasmGcPageSourceTest"))))
    ((some facts) (targetLlvm/emitLlvmProgramForTarget facts (target/wasm32TargetFacts) (helloModule) "main")))

fn ! llcObject llc: String work: String name: String text: String -> ProcessOutput
  (let [(ll (str work "/" name ".ll"))]
    (do (assert (ok? (fileWrite ll text)) (str "fileWrite " ll))
        (sh (str llc " -mtriple=wasm32-unknown-unknown -filetype=obj " ll " -o " work "/" name ".o"))))

fn ! testWasmText work: String -> Bool
  (let [(llc (llcBin))
        (gcText (wasmGcText))
        (helloText (wasmHelloText))
        (gc (mt gcText ((ok t) t) ((err _) "")))
        (hello (mt helloText ((ok t) t) ((err _) "")))]
    (do
      (assert (not (stringEmpty? llc)) "llc is installed (homebrew, /usr/lib/llvm-NN or PATH)")
      (assert (ok? gcText) (str "wasm collector emission: " (mt gcText ((ok _) "ok") ((err es) (diagText es)))))
      (assert (ok? helloText) (str "wasm hello emission: " (mt helloText ((ok _) "ok") ((err es) (diagText es)))))
      (assert (stringContains? gc "@llvm.wasm.memory.grow.i32") "wasm collector calls the linear-memory growth intrinsic")
      (refute (stringContains? gc "@mmap") "wasm collector has no mmap declaration or call")
      (refute (stringContains? gc "@munmap") "wasm collector has no munmap declaration or call")
      (refute (stringContains? gc "tailcc") "wasm collector uses the C calling convention")
      (refute (stringContains? hello "tailcc") "wasm hello uses the C calling convention")
      (assert (= (target/lowerLlvmText "define i64 @caller(i64 %x) {\n  %r = musttail call i64 @callee(i64 %x)\n  ret i64 %r\n}" (target/wasm32TargetFacts))
                 "define i64 @caller(i64 %x) \"target-features\"=\"+tail-call\" {\n  %r = musttail call i64 @callee(i64 %x)\n  ret i64 %r\n}")
              "matching wasm tail call retains musttail and advertises tail-call feature")
      (assert (= (target/lowerLlvmText "@s = private constant [15 x i8] c\"musttail tailcc \"\ndefine tailcc i64 @f() {\n  %r = musttail call tailcc i64 @f()" (target/wasm32TargetFacts))
                 "@s = private constant [15 x i8] c\"musttail tailcc \"\ndefine i64 @f() \"target-features\"=\"+tail-call\" {\n  %r = musttail call i64 @f()")
              "wasm32 lowering preserves matching musttail and string constant bytes")
      (assert (= (target/lowerLlvmText "define tailcc i64 @caller(i64 %x) {\n  %r = musttail call tailcc i64 @callee(i64 %x, i64 0)\n  ret i64 %r\n}" (target/wasm32TargetFacts))
                 "define i64 @caller(i64 %x) \"target-features\"=\"+tail-call\" {\n  %r = call i64 @callee(i64 %x, i64 0)\n  ret i64 %r\n}")
              "wasm32 lowering drops musttail on parameter count mismatch")
      (assert (= (target/lowerLlvmText "define void @rterr.raise(ptr %code, ptr %msg, i64 %len) noreturn {\n  ret void\n}" (target/wasm32TargetFacts))
                 "define void @rterr.raise(ptr %code, ptr %msg, i64 %len) noreturn \"target-features\"=\"+tail-call\" {\n  ret void\n}")
              "wasm32 lowering uniformly marks definitions with tail-call feature")
      (let [(gcObj (llcObject llc work "wasmGc" gc))
            (helloObj (llcObject llc work "wasmHello" hello))]
        (do (assert (= gcObj.exitCode 0) (str "llc wasm32 collector object: " gcObj.stderr))
            (assert (= helloObj.exitCode 0) (str "llc wasm32 hello object: " helloObj.stderr))
            true))))

fn driverSource -> String
  (stringJoin (list
    "#include <stdarg.h>"
    "#include <stdint.h>"
    "#include <stdio.h>"
    "#include <stdlib.h>"
    "#include <string.h>"
    "#include <sys/mman.h>"
    "typedef struct { uint32_t tag; uint32_t aux; union { int64_t i; void *o; } u; } Val;"
    "typedef struct { uint32_t size; uint8_t type, mark, perm, classIdx; Val car, cdr; } Cons;"
    "enum { T_INT = 2, T_LIST = 6, WASM_PAGE = 65536 };"
    "void gcInit(void); Cons *asl_alloc_cons(void); void asl_gc_root_push(Val *v); void asl_gc_root_pop(int n); void asl_gc_collect(void);"
    "static unsigned char *region; static int64_t reserved, grown, calls, limitPages;"
    "int32_t wasmGrowEmulated(int32_t mem, int32_t delta) {"
    "  calls++;"
    "  if (mem != 0 || delta < 0) { fprintf(stderr, \"bad memory.grow operands %d %d\\n\", mem, delta); exit(3); }"
    "  if (grown + delta > limitPages) return -1;"
    "  if (mprotect(region + grown * WASM_PAGE, (size_t)delta * WASM_PAGE, PROT_READ | PROT_WRITE) != 0) { perror(\"mprotect\"); exit(3); }"
    "  int64_t old = (int64_t)((uintptr_t)region / WASM_PAGE) + grown;"
    "  grown += delta;"
    "  return (int32_t)old;"
    "}"
    "void gcMutatorRoots(void (*mark)(Val)) { (void)mark; }"
    "const void *gcFloorGuard;"
    "void gcFloorFail(const char *code, const char *fmt, ...) {"
    "  va_list ap; va_start(ap, fmt); fprintf(stderr, \"%s: \", code); vfprintf(stderr, fmt, ap); va_end(ap); fputc('\\n', stderr); exit(1);"
    "}"
    "static Val build(int64_t n) {"
    "  Val head = {T_LIST, 0, {.o = NULL}};"
    "  asl_gc_root_push(&head);"
    "  for (int64_t i = 0; i < n; i++) { Cons *c = asl_alloc_cons(); c->car = (Val){T_INT, 0, {.i = i}}; c->cdr = head; head = (Val){T_LIST, 0, {.o = c}}; }"
    "  asl_gc_root_pop(1);"
    "  return head;"
    "}"
    "static int64_t bad(Val head, int64_t n) {"
    "  int64_t wrong = 0, i = n, steps = 0;"
    "  unsigned char *lo = region, *hi = region + grown * WASM_PAGE;"
    "  for (Val v = head; v.u.o && steps++ <= n; v = ((Cons *)v.u.o)->cdr) {"
    "    Cons *c = v.u.o; i--;"
    "    if ((unsigned char *)c < lo || (unsigned char *)c + sizeof(Cons) > hi || c->car.tag != T_INT || c->car.u.i != i) wrong++;"
    "  }"
    "  return wrong + (i != 0);"
    "}"
    "int main(int argc, char **argv) {"
    "  if (argc != 4) { fprintf(stderr, \"usage: driver run|reuse cells limitPages\\n\"); return 2; }"
    "  int64_t n = atoll(argv[2]); limitPages = atoll(argv[3]); reserved = 4096;"
    "  unsigned char *raw = mmap(NULL, (size_t)(reserved + 1) * WASM_PAGE, PROT_NONE, MAP_PRIVATE | MAP_ANON, -1, 0);"
    "  if (raw == MAP_FAILED) { perror(\"mmap\"); return 3; }"
    "  region = (unsigned char *)(((uintptr_t)raw + WASM_PAGE - 1) & ~(uintptr_t)(WASM_PAGE - 1));"
    "  if ((uintptr_t)region / WASM_PAGE + (uintptr_t)reserved > INT32_MAX) { fprintf(stderr, \"reservation above the i32 page index range\\n\"); return 3; }"
    "  if (limitPages > reserved) limitPages = reserved;"
    "  gcInit();"
    "  if (!strcmp(argv[1], \"run\")) {"
    "    Val head = build(n); asl_gc_root_push(&head);"
    "    printf(\"%lld %lld %lld\\n\", (long long)calls, (long long)grown, (long long)bad(head, n));"
    "    return 0;"
    "  }"
    "  if (!strcmp(argv[1], \"reuse\")) {"
    "    Val head = build(n); asl_gc_root_push(&head); asl_gc_collect();"
    "    int64_t first = grown, firstBad = bad(head, n);"
    "    head = (Val){T_LIST, 0, {.o = NULL}}; asl_gc_collect();"
    "    head = build(n); asl_gc_collect();"
    "    printf(\"%lld %lld %lld\\n\", (long long)first, (long long)grown, (long long)(firstBad + bad(head, n)));"
    "    return 0;"
    "  }"
    "  fprintf(stderr, \"unknown mode %s\\n\", argv[1]); return 2;"
    "}"
    "") "\n")

fn nativeGrowFacts triple: String -> target/TargetFacts
  (target/TargetFacts :triple triple :pointerWidth 64 :pageSource "memory.grow" :trapMechanism "setjmp")

fn ! buildDriver work: String -> String
  (let [(triple (gr/hostTriple (sh "uname -s -m").stdout))
        (facts (libc/libcFacts triple))
        (text (mt facts ((none) (err (list))) ((some f) (gr/collectorTextForTarget f (nativeGrowFacts triple)))))
        (gc (mt text ((ok t) t) ((err _) "")))
        (ll (str work "/growGc.ll"))
        (c (str work "/wasmGrowDriver.c"))
        (exe (str work "/wasmGrowDriver"))]
    (do
      (assert (some? facts) (str "libc.asl has facts for this host's triple '" triple "'"))
      (assert (ok? text) (str "host-triple memory.grow collector emission: " (mt text ((ok _) "ok") ((err es) (diagText es)))))
      (assert (stringContains? gc "@llvm.wasm.memory.grow.i32(") "the host-triple collector grows memory through the intrinsic")
      (refute (stringContains? gc "@mmap(") "the memory.grow page source never maps")
      (assert (ok? (fileWrite ll (stringReplace gc "@llvm.wasm.memory.grow.i32(" "@wasmGrowEmulated("))) (str "fileWrite " ll))
      (assert (ok? (fileWrite c (driverSource))) (str "fileWrite " c))
      (let [(built (sh (str "/usr/bin/clang -O1 -Wno-override-module " ll " " c " -o " exe)))]
        (do (assert (= built.exitCode 0) (str "the driver links with the collector: " built.stderr))
            exe))))

fn bounded -> String
  "perl -e 'alarm 120; exec @ARGV' "

fn numbers out: ProcessOutput -> (List Int64)
  (map (fn [(w String)] -> Int64 (optionOr (stringToInt64 w) -1)) (filter (fn [(w String)] -> Bool (not (stringEmpty? w))) (stringSplit (stringReplace out.stdout "\n" "") " ")))

fn nth xs: (List Int64) i: Int64 -> Int64
  (optionOr (listGet xs i) -1)

fn ! testGrow exe: String -> Bool
  (let [(out (sh (str (bounded) exe " run 30000 4096")))
        (ns (numbers out))]
    (do (assert (= out.exitCode 0) (str "run exits 0: " out.stderr))
        (assert (= (nth ns 0) 2) (str "two memory.grow calls serve 76 collector pages, got " out.stdout))
        (assert (= (nth ns 1) 32) (str "each grow adds 16 wasm pages, 32 in all, got " out.stdout))
        (assert (= (nth ns 2) 0) (str "every cell lies in grown memory with its value, bad cells " out.stdout))
        true))

fn ! testOom exe: String -> Bool
  (let [(out (sh (str (bounded) exe " run 30000 16")))]
    (do (assert (= out.exitCode 1) (str "a refused grow exits 1, got " out.exitCode ": " out.stderr))
        (assert (stringContains? out.stderr "ERR_OOM: out of memory allocating GC page") (str "a refused grow is ERR_OOM: " out.stderr))
        true))

fn ! testReuse exe: String -> Bool
  (let [(out (sh (str (bounded) exe " reuse 500000 4096")))
        (ns (numbers out))]
    (do (assert (= out.exitCode 0) (str "reuse exits 0: " out.stderr))
        (assert (> (nth ns 0) 128) (str "the first build grows past the cache limit of 512 collector pages (128 wasm pages), got " out.stdout))
        (assert (= (nth ns 1) (nth ns 0)) (str "the second build reuses freed pages and grows nothing, got " out.stdout))
        (assert (= (nth ns 2) 0) (str "both builds' cells intact, bad cells " out.stdout))
        true))

fn ! runTests -> Bool
  (let [(made (sh "mktemp -d"))
        (work (stringReplace made.stdout "\n" ""))]
    (do
      (assert (= made.exitCode 0) "mktemp -d makes a work directory")
      (testWasmText work)
      (let [(exe (buildDriver work))]
        (do (testGrow exe) (testOom exe) (testReuse exe) true))
      (assert (= (sh (str "rm -rf " work)).exitCode 0) "work directory removed")
      true))
