(module asl-target-llvm/tests/wasmTrapTest
  :x [runTests]
  :i [(asl-ir/types :a irTy)
      (asl-ir/lower :a low)
      (asl-target-llvm :a targetLlvm)
      (asl-target-llvm/libc :a libc)
      (asl-target-llvm/target :a target)])

fn trapSource name: String expression: String -> String
  (str "(module " name " :x [main] :i [])\n\nfn ! main -> (Result Int64 String)\n  " expression)

fn compiledTrap source: String -> (Result String (List irTy/IrDiag))
  (compiledTrapFor source (target/wasm32TargetFacts))

fn compiledNativeTrap source: String -> (Result String (List irTy/IrDiag))
  (compiledTrapFor source (target/nativeTargetFacts "darwin-arm64"))

fn compiledTrapFor source: String factsTarget: target/TargetFacts -> (Result String (List irTy/IrDiag))
  (let [(facts (libc/libcFacts "darwin-arm64"))]
    (mt facts
      ((none) (err (list (irTy/makeIrDiag "ERR_TEST" "native facts unavailable" "compiledTrap"))))
      ((some f) (mt (low/lowerSource source)
        ((err ds) (err ds))
        ((ok m) (targetLlvm/emitLlvmProgramForTarget f factsTarget m "main"))))))

fn ! runTests -> Bool
  (do
    (assert (wasmTrapCase "division" (trapSource "wasmDivZero" "(ok (/ 7 (- (stringLength \"a\") 1)))") "division by zero") "compiled wasm division-by-zero trap matches native")
    (assert (wasmTrapCase "explicit" (trapSource "wasmExplicit" "(trap \"ERR_RANGE\" \"chosen message\")") "chosen message") "compiled wasm explicit raise matches native")
    (assert (wasmTrapCode "wasmAssert" (trapSource "wasmAssert" "(do (assert (= (stringLength \"a\") 2) \"asserted\") (ok 0))") "ERR_ASSERT") "compiled assert-failure path lowers to the wasm host trap")
    (assert (wasmTrapCode "wasmOverflow" (trapSource "wasmOverflow" "(ok (+ 9223372036854775807 (stringLength \"a\")))") "ERR_INT_OVERFLOW") "compiled integer-overflow path lowers to the wasm host trap")
    true)

fn ! wasmTrapCode name: String source: String code: String -> Bool
  (let [(compiled (compiledTrap source))]
    (do
      (assert (ok? compiled) (str name " source compiles for wasm32"))
      (let [(text (mt compiled ((ok t) t) ((err _) "")))]
        (do
          (assert (or (stringContains? text (str "call void @rterr.raise(ptr @.rterr.c." code))
                      (or (stringContains? text (str "call void @rterr.raiseText(ptr @.rterr.c." code))
                          (stringContains? text (str "call void @rterr.raiseNumber(ptr @.rterr.c." code))))
                  (str name " emitted failure calls the central raise with " code))
          (assert (stringContains? text "@asl.trap") (str name " emitted raise calls wasm host trap"))
          (assert (not (stringContains? text "longjmp")) (str name " emitted module has no longjmp"))
          true))))

fn ! sh cmd: String -> ProcessOutput
  (processRun cmd)

fn errorLine out: ProcessOutput -> String
  (fold (fn [(acc String) (line String)] -> String (if (and (stringEmpty? acc) (not (stringEmpty? line))) line acc)) "" (stringSplit out.stderr "\n"))

fn errorCode line: String -> String
  (let [(end (optionOr (stringIndexOf line ":") (stringLength line)))]
    (optionOr (stringSlice line 0 end) ""))

fn errorMessage line: String -> String
  (let [(start (optionOr (stringIndexOf line ": ") (stringLength line)))]
    (optionOr (stringSlice line (+ start 2) (stringLength line)) ""))

fn ! wasmTrapCase name: String source: String expectedMessage: String -> Bool
  (let [(work (str "/tmp/asl-wasm-trap-" name))
        (src (str work "/main.asl"))
        (ll (str work "/main.ll"))
        (nativeLl (str work "/native.ll"))
        (nativeBin (str work "/native"))
        (obj (str work "/main.o"))
        (wasm (str work "/main.wasm"))
        (node (str (optionOr (envGet "HOME") "") "/.local/bin/node"))
        (llc "/opt/homebrew/opt/llvm/bin/llc")
        (nm "/opt/homebrew/opt/llvm/bin/llvm-nm")
        (ld "/opt/homebrew/opt/lld/bin/wasm-ld")
        (clang "/usr/bin/clang -Wno-override-module")
        (nodeCode "const fs=require(\"fs\");let i,got=\"\",next=65536;const alloc=n=>{const p=next;next=(next+Math.max(Number(n),1)+7)&~7;while(next>i.exports.memory.buffer.byteLength)i.exports.memory.grow(1);return p};const mod=new WebAssembly.Module(fs.readFileSync(process.argv[1]));const imports={};for(const x of WebAssembly.Module.imports(mod)){imports[x.module] ||= {};imports[x.module][x.name]=(...a)=>{if(x.module===\"asl\"&&x.name===\"trap\"){const b=new Uint8Array(i.exports.memory.buffer);const z=b.indexOf(0,a[0]);const d=new TextDecoder();got=d.decode(b.subarray(a[0],z))+\"|\"+d.decode(b.subarray(a[1],a[1]+Number(a[2])));throw new Error(\"trap\")}if(x.name===\"asl_alloc\")return alloc(a[1]);if(x.name===\"malloc\")return alloc(a[0]);if(x.name===\"calloc\")return alloc(Number(a[0])*Number(a[1]));if(x.name===\"realloc\"){const p=alloc(a[1]);new Uint8Array(i.exports.memory.buffer).set(new Uint8Array(i.exports.memory.buffer,a[0],Number(a[1])),p);return p}return 0}}i=new WebAssembly.Instance(mod,imports);try{i.exports.main()}catch(e){}if(got)process.stdout.write(got);else process.exit(1);")]
    (do
      (assert (ok? (dirCreate work)) "creates the wasm trap test directory")
      (let [(ir (compiledTrap source))]
        (do
          (assert (ok? ir) (str "compiles real ASL source for wasm32: " (mt ir ((ok _) "ok") ((err ds) (stringJoin (map (fn [(d irTy/IrDiag)] -> String d.message) ds) "; ")))))
          (let [(nativeIr (compiledNativeTrap source))]
            (assert (ok? nativeIr) (str "compiles same ASL source for native: " (mt nativeIr ((ok _) "ok") ((err ds) (stringJoin (map (fn [(d irTy/IrDiag)] -> String d.message) ds) "; ")))))
            (let [(text (mt ir ((ok t) t) ((err _) "")))
                (writeSource (fileWrite src source))
                (writeIr (fileWrite ll (mt ir ((ok t) t) ((err _) ""))))
                (writeNativeIr (fileWrite nativeLl (mt nativeIr ((ok t) t) ((err _) ""))))
                (nativeLinked (sh (str clang " -x ir " nativeLl " -x none asl/host/out/libaslrt.a -lm -o " nativeBin)))
                (native (sh nativeBin))
                (nativeLine (errorLine native))
                (code (errorCode nativeLine))
                (compiled (sh (str llc " -mtriple=wasm32-unknown-unknown -filetype=obj " ll " -o " obj)))
                (symbols (sh (str nm " " obj)))]
            (do
              (assert (ok? writeSource) "writes the same source for native execution")
              (assert (ok? writeIr) "writes compiler-emitted wasm LLVM IR")
              (assert (ok? writeNativeIr) "writes compiler-emitted native LLVM IR")
              (assert (= nativeLinked.exitCode 0) (str "clang links compiler-emitted native program: " nativeLinked.stderr))
              (assert (= native.exitCode 1) (str "native emitted program traps: " native.stderr))
              (assert (not (stringEmpty? code)) (str "extracts native emitted error code: " native.stderr))
              (assert (stringContains? text "wasm-import-module") "compiler output imports the asl trap callback")
              (assert (not (stringContains? text "longjmp")) "compiler output has no longjmp")
              (assert (= compiled.exitCode 0) (str "llc compiles wasm32 object: " compiled.stderr))
              (assert (stringContains? symbols.stdout "U asl.trap") (str "wasm object imports asl.trap: " symbols.stdout))
              (refute (stringContains? symbols.stdout "setjmp") "wasm object has no setjmp import")
              (refute (stringContains? symbols.stdout "longjmp") "wasm object has no longjmp import")
              (refute (stringContains? symbols.stdout "_setjmp") "wasm object has no _setjmp import")
              (let [(linked (sh (str ld " --no-entry --export-dynamic --export-memory --allow-undefined " obj " -o " wasm)))]
                (do
                  (assert (= linked.exitCode 0) (str "wasm-ld links compiler-emitted module: " linked.stderr))
                  (let [(ran (sh (str node " -e '" nodeCode "' " wasm)))]
                    (and (= ran.exitCode 0)
                         (= (optionOr (stringSlice ran.stdout 0 (optionOr (stringIndexOf ran.stdout "|") 0)) "") code)
                         (= (optionOr (stringSlice ran.stdout (+ (optionOr (stringIndexOf ran.stdout "|") 0) 1) (stringLength ran.stdout)) "") (errorMessage nativeLine))
                         (= (errorMessage nativeLine) expectedMessage))))))))))))
