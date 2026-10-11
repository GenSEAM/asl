(module asl-target-llvm/tests/wasmSysValTest
  :x [runTests]
  :i [(asl-ir/types :a irTy)
      (asl-ir/lower :a low)
      (asl-target-llvm :a targetLlvm)
      (asl-target-llvm/libc :a libc)
      (asl-target-llvm/target :a target)
      (asl-target-llvm/wasmLink :a wl)])

fn allowed -> (List String)
  (list "asl.write" "asl.exit" "asl.nowNs" "asl.trap")

fn ! node -> String
  (let [(candidates (list "/usr/local/bin/node" "/opt/homebrew/bin/node"))]
    (mt (listHead (filter fileExists? candidates))
      ((some p) p)
      ((none) (stringReplace (processRun "command -v node 2>/dev/null").stdout "\n" ""))))

fn ! llc -> String
  (let [(candidates (list "/opt/homebrew/opt/llvm/bin/llc" "/opt/homebrew/bin/llc" "/usr/local/opt/llvm/bin/llc" "/usr/lib/llvm-20/bin/llc" "/usr/lib/llvm-19/bin/llc" "/usr/lib/llvm-18/bin/llc"))]
    (mt (listHead (filter fileExists? candidates))
      ((some p) p)
      ((none) (stringReplace (processRun "command -v llc 2>/dev/null").stdout "\n" ""))))

fn ! linker -> String
  (let [(candidates (list "/opt/homebrew/opt/lld/bin/wasm-ld" "/opt/homebrew/bin/wasm-ld" "/usr/local/opt/lld/bin/wasm-ld" "/usr/bin/wasm-ld"))]
    (mt (listHead (filter fileExists? candidates))
      ((some p) p)
      ((none) (stringReplace (processRun "command -v wasm-ld 2>/dev/null").stdout "\n" ""))))

fn shellQuote s: String -> String
  (str "'" (stringReplace s "'" "'\\''") "'")

fn diagText errors: (List irTy/IrDiag) -> String
  (stringJoin (map (fn [(d irTy/IrDiag)] -> String (str d.code ": " d.message)) errors) "; ")

fn textOf r: (Result String (List irTy/IrDiag)) -> String
  (mt r ((ok t) t) ((err _) ""))

fn whyOf r: (Result String (List irTy/IrDiag)) -> String
  (mt r ((ok _) "ok") ((err ds) (diagText ds)))

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
      "")
    "\n")

fn fileReadSource -> String
  (stringJoin
    (list
      "(module wasmFileRead :x [main] :i [])"
      ""
      "fn ! main -> Int64"
      "  (do (fileReadString \"dummy.txt\") 0)"
      "")
    "\n")

fn fileReadBytesSource -> String
  (stringJoin
    (list
      "(module wasmFileReadBytes :x [main] :i [])"
      ""
      "fn ! main -> Int64"
      "  (do (fileReadBytes \"dummy.txt\") 0)"
      "")
    "\n")

fn envGetSource -> String
  (stringJoin
    (list
      "(module wasmEnvGet :x [main] :i [])"
      ""
      "fn ! main -> Int64"
      "  (do (envGet \"PATH\") 0)"
      "")
    "\n")

fn nowNsSource -> String
  (stringJoin
    (list
      "(module wasmNowNs :x [main] :i [])"
      ""
      "fn ! main -> Int64"
      "  (do (nowNs) 0)"
      "")
    "\n")

fn monotonicNsSource -> String
  (stringJoin
    (list
      "(module wasmMonotonicNs :x [main] :i [])"
      ""
      "fn ! main -> Int64"
      "  (do (monotonicNs) 0)"
      "")
    "\n")

fn printSource -> String
  (stringJoin
    (list
      "(module wasmPrint :x [main] :i [])"
      ""
      "fn ! main -> Int64"
      "  (do (print \"hello wasm print\") 0)"
      "")
    "\n")

fn variadicPrintSource -> String
  (stringJoin
    (list
      "(module wasmVariadicPrint :x [main] :i [])"
      ""
      "fn ! main -> Int64"
      "  (do (print \"hello\" \"wasm\" \"print\") 0)"
      "")
    "\n")

fn emitFor facts: libc/TripleFacts tf: target/TargetFacts source: String -> (Result String (List irTy/IrDiag))
  (mt (low/lowerSource source)
    ((err ds) (err ds))
    ((ok m) (targetLlvm/emitLlvmProgramForTarget facts tf m "main")))

fn ! compileObject llcPath: String ll: String obj: String -> ProcessOutput
  (processRun (str (shellQuote llcPath) " -mtriple=wasm32-unknown-unknown -mattr=+bulk-memory -filetype=obj " (shellQuote ll) " -o " (shellQuote obj)))

fn ! writeAndCompile llcPath: String name: String part: String text: (Result String (List irTy/IrDiag)) work: String -> Bool
  (let [(ll (str work "/" part ".ll"))
        (obj (str work "/" part ".o"))]
    (if (not (ok? text))
      false
      (do
        (fileWrite ll (textOf text))
        (let [(compiled (compileObject llcPath ll obj))]
          (= compiled.exitCode 0)))))

fn hasCapabilityAbsent res: (Result String (List irTy/IrDiag)) name: String -> Bool
  (mt res
    ((err diags)
      (listAny? (fn [(d irTy/IrDiag)] -> Bool
                  (and (= d.code "ERR_CAPABILITY_ABSENT")
                       (stringContains? d.message name)))
                diags))
    ((ok _) false))

fn ! runsCorrectlyUnderNode name: String text: String -> Bool
  (let [(work (str "/tmp/asl-wasm-sys-val-" name))
        (wasm (str work "/main.wasm"))
        (js (str work "/run.js"))
        (facts (optionOr (libc/libcFacts "wasm32-unknown-unknown") (libc/emptyTripleFacts)))
        (tf (target/wasm32TargetFacts))
        (llcPath (llc))
        (linkerPath (linker))
        (nodePath (node))
        (cleared (processRun (str "rm -rf " (shellQuote work))))]
    (cond
      ((or (stringEmpty? llcPath) (or (stringEmpty? linkerPath) (stringEmpty? nodePath))) false)
      ((not (ok? (dirCreate work))) false)
      ((not (writeAndCompile llcPath name "main" (ok text) work)) false)
      ((not (writeAndCompile llcPath name "runtime" (targetLlvm/emitLlvmRuntimeForTarget facts tf) work)) false)
      ((not (writeAndCompile llcPath name "support" (targetLlvm/emitLlvmSupportForTarget facts tf) work)) false)
      (else
        (let [(linked (wl/linkWasm32 linkerPath (list (str work "/main.o") (str work "/runtime.o") (str work "/support.o")) (list "gcFreedObjects") wasm))]
          (if (!= linked.exitCode 0)
            false
            (do
              (fileWrite js (runnerJs))
              (let [(ran (processRun (str (shellQuote nodePath) " " (shellQuote js) " " (shellQuote wasm))))]
                (= ran.exitCode 0))))))))

fn ! testFileReadStringBuild -> Bool
  (let [(facts (optionOr (libc/libcFacts "wasm32-unknown-unknown") (libc/emptyTripleFacts)))
        (tf (target/wasm32TargetFacts))
        (res (emitFor facts tf (fileReadSource)))]
    (mt res
      ((err diags)
       (do
         (assert (hasCapabilityAbsent res "fileReadString") "compilation fails with ERR_CAPABILITY_ABSENT naming fileReadString")
         true))
      ((ok text)
       (do
         (assert (runsCorrectlyUnderNode "fileRead" text) "compilation succeeded, so wasm32 build must run correctly under node")
         true))))

fn ! testPrintImportsAndRun name: String source: String expectedOutput: String -> Bool
  (let [(work (str "/tmp/asl-wasm-sys-val-" name))
        (wasm (str work "/main.wasm"))
        (js (str work "/run.js"))
        (facts (optionOr (libc/libcFacts "wasm32-unknown-unknown") (libc/emptyTripleFacts)))
        (tf (target/wasm32TargetFacts))
        (llcPath (llc))
        (linkerPath (linker))
        (nodePath (node))
        (text (emitFor facts tf source))]
    (do
      (assert (ok? text) (str name " emits wasm32 program: " (whyOf text)))
      (assert (ok? (dirCreate work)) (str name " creates work dir"))
      (assert (writeAndCompile llcPath name "main" text work) (str name " compiles main"))
      (assert (writeAndCompile llcPath name "runtime" (targetLlvm/emitLlvmRuntimeForTarget facts tf) work) (str name " compiles runtime"))
      (assert (writeAndCompile llcPath name "support" (targetLlvm/emitLlvmSupportForTarget facts tf) work) (str name " compiles support"))
      (let [(linked (wl/linkWasm32 linkerPath (list (str work "/main.o") (str work "/runtime.o") (str work "/support.o")) (list "gcFreedObjects") wasm))]
        (assert (= linked.exitCode 0) (str name " links: " linked.stderr)))
      (let [(read (wl/wasmImports nodePath wasm))]
        (do
          (assert (ok? read) (str name " reads imports: " (mt read ((ok _) "ok") ((err e) e))))
          (let [(imports (mt read ((ok xs) xs) ((err _) (list))))]
            (do
              (assert (listContains? imports "asl.write") (str name " imports asl.write: " (stringJoin imports " ")))
              (assert (listEmpty? (wl/importsOutside (allowed) imports)) (str name " import section contains only allowlisted imports, outside: " (stringJoin (wl/importsOutside (allowed) imports) " ")))))))
      (assert (ok? (fileWrite js (runnerJs))) (str name " writes runner js"))
      (let [(ran (processRun (str (shellQuote nodePath) " " (shellQuote js) " " (shellQuote wasm))))]
        (do
          (assert (= ran.exitCode 0) (str name " runs under node: " ran.stderr))
          (assert (= ran.stdout expectedOutput) (str name " stdout equals expected: " ran.stdout))))
      true))

fn ! testAbsentSysExtern name: String source: String -> Bool
  (let [(facts (optionOr (libc/libcFacts "wasm32-unknown-unknown") (libc/emptyTripleFacts)))
        (tf (target/wasm32TargetFacts))
        (res (emitFor facts tf source))]
    (do
      (assert (err? res) (str name " fails at compile"))
      (assert (hasCapabilityAbsent res name) (str name " fails with ERR_CAPABILITY_ABSENT naming " name))
      true))

fn ! runTests -> Bool
  (do
    (assert (testFileReadStringBuild) "fileReadString build either runs under node or fails compile with ERR_CAPABILITY_ABSENT")
    (assert (testAbsentSysExtern "fileReadBytes" (fileReadBytesSource)) "fileReadBytes rejected with ERR_CAPABILITY_ABSENT")
    (assert (testAbsentSysExtern "envGet" (envGetSource)) "envGet rejected with ERR_CAPABILITY_ABSENT")
    (assert (testAbsentSysExtern "nowNs" (nowNsSource)) "nowNs rejected with ERR_CAPABILITY_ABSENT")
    (assert (testAbsentSysExtern "monotonicNs" (monotonicNsSource)) "monotonicNs rejected with ERR_CAPABILITY_ABSENT")
    (assert (testPrintImportsAndRun "printOnly" (printSource) "hello wasm print") "print only contains allowlisted imports and runs")
    (assert (testPrintImportsAndRun "variadicPrint" (variadicPrintSource) "hello wasm print") "variadic print contains allowlisted imports and runs")
    true)
