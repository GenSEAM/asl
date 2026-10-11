(module asl-target-llvm/tests/wasmNoLibcTest
  :x [runTests]
  :i [(asl-ir/types :a irTy)
      (asl-ir/lower :a low)
      (asl-target-llvm :a targetLlvm)
      (asl-target-llvm/libc :a libc)
      (asl-target-llvm/target :a target)
      (asl-target-llvm/gcRoute :a gr)
      (asl-target-llvm/wasmLink :a wl)
      (tools/fleet/run :a run)])

fn ! node -> String
  (let [(candidates (list "/usr/local/bin/node" "/opt/homebrew/bin/node"))
        (pathDirs (stringSplit (optionOr (envGet "PATH") "") ":"))
        (allCandidates (listAppend candidates (map (fn [(dir String)] -> String (str dir "/node")) pathDirs)))]
    (mt (listHead (filter fileExists? allCandidates))
      ((some p) p)
      ((none) "")))

fn llc -> String
  "/opt/homebrew/opt/llvm/bin/llc"

fn linker -> String
  "/opt/homebrew/opt/lld/bin/wasm-ld"

fn allowed -> (List String)
  (list "asl.write" "asl.exit" "asl.nowNs" "asl.trap")

fn libcNames -> (List String)
  (list "malloc" "calloc" "realloc" "free" "printf" "snprintf" "dprintf" "fprintf" "strtod" "atoi" "getenv" "unsetenv" "atexit" "clock_gettime" "memcmp" "memcpy" "memset" "strchr" "strlen" "strcmp" "qsort" "fflush" "longjmp" "setjmp")

(schema Captured
  (:f exitCode Int64)
  (:f stdout String)
  (:f stderr String))

fn ! shWithin cmd: String timeoutS: Int64 -> Captured
  (let [(root (optionOr (envGet "ASL_ROOT") "."))
        (prelude (optionOr (envGet "ASL_PRELUDE") (str root "/asl/prelude/prelude.asl")))
        (path (optionOr (envGet "PATH") "/usr/bin:/bin"))
        (base (str (optionOr (envGet "TMPDIR") "/tmp") "/wasmNoLibcTest." (monotonicNs)))
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

fn shellQuote s: String -> String
  (str "'" (stringReplace s "'" "'\\''") "'")

fn diagText errors: (List irTy/IrDiag) -> String
  (stringJoin (map (fn [(d irTy/IrDiag)] -> String (str d.code ": " d.message)) errors) "; ")

fn textOf r: (Result String (List irTy/IrDiag)) -> String
  (mt r ((ok t) t) ((err _) ""))

fn whyOf r: (Result String (List irTy/IrDiag)) -> String
  (mt r ((ok _) "ok") ((err ds) (diagText ds)))

fn importName entry: String -> String
  (mt (stringIndexOf entry ".")
    ((some at) (optionOr (stringSlice entry (+ at 1) (stringLength entry)) ""))
    ((none) entry))

fn envImports imports: (List String) -> (List String)
  (filter (fn [(entry String)] -> Bool (stringStartsWith? entry "env.")) imports)

fn libcImports imports: (List String) -> (List String)
  (filter (fn [(entry String)] -> Bool (listContains? (libcNames) (importName entry))) imports)

fn runnerJs -> String
  (stringJoin
    (list
      "const fs=require('fs');"
      "const mod=new WebAssembly.Module(fs.readFileSync(process.argv[2]));"
      "let inst;"
      "class Exit{constructor(c){this.code=c}}"
      "const mem=()=>new Uint8Array(inst.exports.memory.buffer);"
      "const text=(p,n)=>Buffer.from(mem().subarray(p,p+n));"
      "const imports={asl:{"
      "  write:(fd,p,n)=>{if(fd!==1&&fd!==2)return -1n;fs.writeSync(fd,text(p,Number(n)));return n},"
      "  exit:c=>{throw new Exit(c)},"
      "  nowNs:()=>process.hrtime.bigint(),"
      "  trap:(c,m,n)=>{const b=mem();let e=c;while(b[e])e++;fs.writeSync(2,Buffer.concat([text(c,e-c),Buffer.from(': '),text(m,n),Buffer.from('\\n')]));throw new Exit(1)}}};"
      "for(const x of WebAssembly.Module.imports(mod)) if(!(imports[x.module]&&imports[x.module][x.name])) throw new Error('unexpected import '+x.module+'.'+x.name);"
      "inst=new WebAssembly.Instance(mod,imports);"
      "try{inst.exports._start();process.exitCode=0}catch(e){if(e instanceof Exit)process.exitCode=e.code;else throw e}"
      "if(process.argv[3]==='stats')fs.writeSync(2,'freed '+inst.exports.gcFreedObjects()+'\\n');"
      "")
    "\n")

fn helloSource -> String
  "(module wasmHello :x [main] :i [])\n\nfn ! main -> Int64\n  (do (print \"hello from wasm\") 0)\n"

fn allocationSource -> String
  (stringJoin
    (list
      "(module wasmAllocation :x [main] :i [])"
      ""
      "fn ! main -> Int64"
      "  (do (println (rounds 300 0)) 0)"
      ""
      "fn rounds left: Int64 acc: Int64 -> Int64"
      "  (if (<= left 0)"
      "    acc"
      "    (rounds (- left 1) (allocateLoop 1000 acc)))"
      ""
      "fn allocateLoop remaining: Int64 acc: Int64 -> Int64"
      "  (if (<= remaining 0)"
      "    acc"
      "    (let [(text (str remaining))"
      "          (cell (list remaining (list remaining text)))]"
      "      (allocateLoop (- remaining 1) (+ acc (stringLength text)))))"
      "")
    "\n")

fn stringSource -> String
  (stringJoin
    (list
      "(module wasmStringBuild :x [main] :i [])"
      ""
      "fn ! main -> Int64"
      "  (do (println (buildString 2000 \"\"))"
      "      (println (str 42 \" \" -7 \" \" 9223372036854775807 \" \" (- -9223372036854775807 1) \" \" 0))"
      "      (println (str 3.5 \" \" 0.1 \" \" -2.25e-7 \" \" 1e300 \" \" (/ 1.0 3.0) \" \" 5e-324 \" \" 1.7976931348623157e308 \" \" 123456.789 \" \" 1e16 \" \" 1e21 \" \" -0.0 \" \" 100.0 \" \" 2.5 \" \" 0.30000000000000004))"
      "      (println (stringToFloat64 \"2.5e-3\") (stringToFloat64 \" 17\") (stringToFloat64 \"abc\") (stringToFloat64 \"1e400\") (stringToFloat64 \"-inf\") (stringToFloat64 \"0x10\"))"
      "      (println (stringFromFloat64 (* 0.1 3.0)) (stringFromInt64 -12345))"
      "      3)"
      ""
      "fn buildString remaining: Int64 acc: String -> String"
      "  (if (<= remaining 0)"
      "    acc"
      "    (buildString (- remaining 1) (str acc remaining \",\")))"
      "")
    "\n")

fn emitFor facts: libc/TripleFacts tf: target/TargetFacts source: String -> (Result String (List irTy/IrDiag))
  (mt (low/lowerSource source)
    ((err ds) (err ds))
    ((ok m) (targetLlvm/emitLlvmProgramForTarget facts tf m "main")))

fn ! compileObject ll: String obj: String -> Captured
  (sh (str (shellQuote (llc)) " -mtriple=wasm32-unknown-unknown -mattr=+bulk-memory -filetype=obj " (shellQuote ll) " -o " (shellQuote obj)))

fn ! writeAndCompile name: String part: String text: (Result String (List irTy/IrDiag)) work: String -> Bool
  (let [(ll (str work "/" part ".ll"))
        (obj (str work "/" part ".o"))]
    (do
      (assert (ok? text) (str name " emits its wasm32 " part " module: " (whyOf text)))
      (assert (ok? (fileWrite ll (textOf text))) (str name " writes " ll))
      (let [(compiled (compileObject ll obj))]
        (assert (= compiled.exitCode 0) (str name " llc compiles " part ": " compiled.stderr)))
      true))

fn ! nativeRun name: String source: String work: String -> Captured
  (let [(un (sh "uname -s -m"))
        (triple (gr/hostTriple un.stdout))
        (facts (libc/libcFacts triple))
        (ll (str work "/native.ll"))
        (bin (str work "/native"))]
    (do
      (assert (some? facts) (str name " host '" un.stdout "' has a libc facts row"))
      (let [(text (emitFor (optionOr facts (libc/emptyTripleFacts)) (target/nativeTargetFacts triple) source))]
        (do
          (assert (ok? text) (str name " emits native IR: " (whyOf text)))
          (assert (ok? (fileWrite ll (textOf text))) (str name " writes native IR"))
          (let [(linked (sh (str "/usr/bin/cc -Wno-override-module -x ir " (shellQuote ll) " -x none asl/host/out/libaslrt.a -lm -o " (shellQuote bin))))]
            (do
              (assert (= linked.exitCode 0) (str name " links natively: " linked.stderr))
              (sh (shellQuote bin))))))))

fn ! wasmCase name: String source: String -> Bool
  (let [(work (str "/tmp/asl-wasm-no-libc-" name))
        (wasm (str work "/main.wasm"))
        (js (str work "/run.js"))
        (facts (libc/libcFacts "wasm32-unknown-unknown"))
        (wf (optionOr facts (libc/emptyTripleFacts)))
        (tf (target/wasm32TargetFacts))
        (cleared (sh (str "rm -rf " (shellQuote work))))]
    (do
      (assert (= cleared.exitCode 0) (str name " clears its build directory"))
      (assert (ok? (dirCreate work)) (str name " creates its build directory"))
      (assert (some? facts) (str name " has the wasm32 facts row"))
      (assert (writeAndCompile name "main" (emitFor wf tf source) work) (str name " program object"))
      (assert (writeAndCompile name "runtime" (targetLlvm/emitLlvmRuntimeForTarget wf tf) work) (str name " collector object"))
      (assert (writeAndCompile name "support" (targetLlvm/emitLlvmSupportForTarget wf tf) work) (str name " support object"))
      (let [(linked (wl/linkWasm32 (linker) (list (str work "/main.o") (str work "/runtime.o") (str work "/support.o")) (list "gcFreedObjects") wasm))]
        (assert (= linked.exitCode 0) (str name " links without --allow-undefined: " linked.stderr)))
      (let [(read (wl/wasmImports (node) wasm))
            (imports (mt read ((ok xs) xs) ((err _) (list))))]
        (do
          (assert (ok? read) (str name " import section reads: " (mt read ((ok _) "ok") ((err e) e))))
          (assert (listContains? imports "asl.write") (str name " imports asl.write: " (stringJoin imports " ")))
          (assert (listEmpty? (wl/importsOutside (allowed) imports)) (str name " imports only the allowlist, outside: " (stringJoin (wl/importsOutside (allowed) imports) " ")))
          (assert (listEmpty? (envImports imports)) (str name " has no env import: " (stringJoin (envImports imports) " ")))
          (assert (listEmpty? (libcImports imports)) (str name " imports no libc name: " (stringJoin (libcImports imports) " ")))))
      (assert (ok? (fileWrite js (runnerJs))) (str name " writes its Node runner"))
      (let [(ran (sh (str (shellQuote (node)) " " (shellQuote js) " " (shellQuote wasm) " stats")))
            (native (nativeRun name source work))
            (freedLine (optionOr (listLast (filter (fn [(l String)] -> Bool (stringStartsWith? l "freed ")) (stringSplit ran.stderr "\n"))) ""))
            (freed (optionOr (stringToInt64 (stringReplace freedLine "freed " "")) -1))]
        (do
          (assert (not (stringEmpty? native.stdout)) (str name " native run prints"))
          (assert (= ran.stdout native.stdout) (str name " wasm stdout equals native byte for byte; wasm: " ran.stdout " stderr " ran.stderr " native: " native.stdout))
          (assert (= ran.exitCode native.exitCode) (str name " wasm exit " ran.exitCode " equals native exit " native.exitCode "; " ran.stderr))
          (assert (>= freed 0) (str name " reports gcFreedObjects: " ran.stderr))
          (assert (or (!= name "allocation") (> freed 0)) (str name " forces collections when it is the allocation loop, freed " freed))
          true))))

fn controlLl -> String
  (stringJoin
    (list
      "target triple = \"wasm32-unknown-unknown\""
      "declare i32 @snprintf(ptr, i64, ptr, ...) #0"
      "declare ptr @malloc(i64) #1"
      "define void @_start() {"
      "entry:"
      "  %p = call ptr @malloc(i64 8)"
      "  %n = call i32 (ptr, i64, ptr, ...) @snprintf(ptr %p, i64 8, ptr %p)"
      "  ret void"
      "}"
      "attributes #0 = { \"wasm-import-module\"=\"asl\" \"wasm-import-name\"=\"snprintf\" }"
      "attributes #1 = { \"wasm-import-module\"=\"env\" \"wasm-import-name\"=\"malloc\" }"
      "")
    "\n")

fn ! controlCase -> Bool
  (let [(work "/tmp/asl-wasm-no-libc-control")
        (ll (str work "/control.ll"))
        (obj (str work "/control.o"))
        (wasm (str work "/control.wasm"))]
    (do
      (assert (= (sh (str "rm -rf " work)).exitCode 0) "control clears its build directory")
      (assert (ok? (dirCreate work)) "control creates its build directory")
      (assert (ok? (fileWrite ll (controlLl))) "control writes its module")
      (let [(compiled (compileObject ll obj))]
        (assert (= compiled.exitCode 0) (str "control compiles: " compiled.stderr)))
      (let [(linked (wl/linkWasm32 (linker) (list obj) (list) wasm))]
        (assert (= linked.exitCode 0) (str "control links: " linked.stderr)))
      (let [(read (wl/wasmImports (node) wasm))
            (imports (mt read ((ok xs) xs) ((err _) (list))))]
        (do
          (assert (= (wl/importsOutside (allowed) imports) (list "env.malloc" "asl.snprintf")) (str "control's renamed libc imports are outside the allowlist: " (stringJoin imports " ")))
          (assert (= (envImports imports) (list "env.malloc")) "control's env import is flagged")
          (assert (= (libcImports imports) (list "env.malloc" "asl.snprintf")) "control's libc names are flagged")))
      true))

fn ! runTests -> Bool
  (let [(row (libc/libcFacts "wasm32-unknown-unknown"))
        (abi (libc/runtimeAbi "wasm32-unknown-unknown"))
        (services (mt abi ((some a) (list a.output a.exit a.clock a.trap)) ((none) (list))))]
    (do
      (assert (listContains? (libc/libcTriples) "wasm32-unknown-unknown") "wasm32 is a libc.asl triple")
      (assert (some? row) "wasm32 has a facts row")
      (let [(facts (optionOr row (libc/emptyTripleFacts)))]
        (do
          (assert (stringEmpty? facts.errnoAccessor) "wasm32 has no errno accessor")
          (assert (listEmpty? facts.consts) "wasm32 declares no libc constants")
          (assert (listEmpty? facts.structs) "wasm32 declares no libc struct layouts")))
      (assert (none? (libc/runtimeAbi "darwin-arm64")) "a libc triple has no host runtime ABI")
      (assert (= services (allowed)) (str "wasm32 runtime services are exactly the allowlist: " (stringJoin services " ")))
      (assert (= (mt abi ((some a) a.memory) ((none) "")) "memory.grow") "wasm32 memory is memory.grow")
      (assert (= (libc/hostImport "asl.nowNs") (pair "asl" "nowNs")) "a service splits into import module and name")
      (assert (controlCase) "the import check flags a renamed libc")
      (assert (wasmCase "hello" (helloSource)) "hello")
      (assert (wasmCase "allocation" (allocationSource)) "allocation")
      (assert (wasmCase "string" (stringSource)) "string")
      true))
