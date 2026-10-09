(module asl-target-llvm/tests/wasmStackRootsTest
  :x [runTests]
  :i [(asl-ir/types :a irTy)
      (asl-ir/lower :a low)
      (asl-target-llvm :a targetLlvm)
      (asl-target-llvm/libc :a libc)
      (asl-target-llvm/target :a target)
      (asl-target-llvm/gcRoute :a gr)
      (asl-target-llvm/wasmLink :a wl)])

fn ! node -> String
  (str (optionOr (envGet "HOME") "") "/.local/bin/node")

fn llc -> String
  "/opt/homebrew/opt/llvm/bin/llc"

fn linker -> String
  "/opt/homebrew/opt/lld/bin/wasm-ld"

fn ! workRoot -> String
  (str "/tmp/asl-wasm-stack-roots-" (nowNs))

fn ! sh cmd: String -> ProcessOutput
  (processRun cmd)

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
      "try{inst.exports._start();process.exitCode=0}catch(e){if(e instanceof Exit)process.exitCode=e.code;else{fs.writeSync(2,String(e)+'\\n');process.exitCode=99}}"
      "fs.writeSync(2,'freed '+inst.exports.gcFreedObjects()+'\\n');"
      "")
    "\n")

fn churnLines -> (List String)
  (list
    ""
    "fn churn rounds: Int64 acc: Int64 -> Int64"
    "  (if (<= rounds 0)"
    "    acc"
    "    (churn (- rounds 1) (churnLoop 1000 acc)))"
    ""
    "fn churnLoop remaining: Int64 acc: Int64 -> Int64"
    "  (if (<= remaining 0)"
    "    acc"
    "    (let [(text (str \"garbage-\" remaining))"
    "          (cell (list remaining (list remaining text)))]"
    "      (churnLoop (- remaining 1) (+ acc (stringLength text)))))"
    ""
    "fn joinAll xs: (List String) acc: String fuel: Int64 -> String"
    "  (if (<= fuel 0)"
    "    (str acc \"~FUEL\")"
    "    (mt (listHead xs)"
    "      ((none) acc)"
    "      ((some h) (mt (listTail xs)"
    "                  ((none) acc)"
    "                  ((some rest) (joinAll rest (str acc h \",\") (- fuel 1)))))))"
    "")

fn program name: String body: (List String) -> String
  (stringJoin (listAppend (listAppend (list (str "(module " name " :x [main] :i [])") "") body) (churnLines)) "\n")

fn callerLocalSource -> String
  (program "rootsCallerLocal"
    (list
      "fn ! main -> Int64"
      "  (let [(kept (build 60 (list)))"
      "        (spent (churn 150 0))]"
      "    (do (println (joinAll kept \"\" 1000))"
      "        (println (> spent 0))"
      "        3))"
      ""
      "fn build n: Int64 acc: (List String) -> (List String)"
      "  (if (<= n 0)"
      "    acc"
      "    (build (- n 1) (cons (str \"kept-\" n) acc)))"))

fn callerLocalExpected -> String
  (str (stringJoin (map (fn [(i Int64)] -> String (str "kept-" i ",")) (range 1 61)) "") "\ntrue\n")

fn recursionSource -> String
  (program "rootsRecursion"
    (list
      "fn ! main -> Int64"
      "  (do (println (descend 25 \"\"))"
      "      (println (tailChain 25 \"t\"))"
      "      0)"
      ""
      "fn descend depth: Int64 acc: String -> String"
      "  (if (<= depth 0)"
      "    acc"
      "    (let [(mine (str \"<\" depth \">\"))"
      "          (spent (churn 6 0))"
      "          (below (descend (- depth 1) (str acc mine)))]"
      "      (str below \"|\" mine)))"
      ""
      "fn tailChain depth: Int64 acc: String -> String"
      "  (if (<= depth 0)"
      "    acc"
      "    (let [(spent (churn 6 0))]"
      "      (tailChain (- depth 1) (str acc \".\" depth))))"))

fn recursionExpected -> String
  (let [(down (range 0 25))
        (marks (map (fn [(i Int64)] -> String (str "<" (- 25 i) ">")) down))]
    (str (stringJoin marks "")
         (stringJoin (map (fn [(i Int64)] -> String (str "|<" (+ i 1) ">")) down) "")
         "\nt"
         (stringJoin (map (fn [(i Int64)] -> String (str "." (- 25 i))) down) "")
         "\n"))

fn closureSource -> String
  (program "rootsClosure"
    (list
      "fn ! main -> Int64"
      "  (let [(g (greeter 7))"
      "        (spent (churn 150 0))]"
      "    (do (println (g 1))"
      "        (println (g 2))"
      "        5))"
      ""
      "fn greeter n: Int64 -> (fn [Int64] -> String)"
      "  (let [(prefix (str \"hello-\" n \"-\" (+ n 35) \"-\"))]"
      "    (fn [(k Int64)] -> String (str prefix k)))"))

fn closureExpected -> String
  "hello-7-42-1\nhello-7-42-2\n"

fn variantSource -> String
  (program "rootsVariant"
    (list
      "fn ! main -> Int64"
      "  (let [(held (some (list (str \"alpha-\" 1) (str \"beta-\" 2) (str \"gamma-\" 3))))"
      "        (spent (churn 150 0))]"
      "    (do (mt held"
      "          ((some xs) (println (joinAll xs \"\" 100)))"
      "          ((none) (println \"none\")))"
      "        0))"))

fn variantExpected -> String
  "alpha-1,beta-2,gamma-3,\n"

fn phiSource -> String
  (program "rootsPhi"
    (list
      "fn ! main -> Int64"
      "  (let [(joined (if (> (churn 1 0) 0) (str \"phi-left-\" (churn 1 0)) (str \"phi-right-\" (churn 1 0))))"
      "        (spent (churn 150 0))]"
      "    (do (println joined)"
      "        (println (> spent 0))"
      "        0))"))

fn phiExpected -> String
  "phi-left-10893\ntrue\n"

fn listLiteralSource -> String
  (let [(items (stringJoin (map (fn [(i Int64)] -> String (str i)) (range 0 1000)) " "))]
    (program "rootsListLiteral"
      (list
        "fn ! main -> Int64"
        (str "  (let [(spent (churn 1 0))"
             "        (values (list " items "))]"
             "    (do (println (> spent 0))"
             "        (println (sum values 1100))"
             "        0))")
        ""
        "fn sum values: (List Int64) fuel: Int64 -> Int64"
        "  (if (<= fuel 0)"
        "    -1"
        "    (mt (listHead values)"
        "      ((none) 0)"
        "      ((some h) (mt (listTail values)"
        "        ((none) h)"
        "        ((some rest) (+ h (sum rest (- fuel 1))))))))")))

fn listLiteralExpected -> String
  "true\n499500\n"

fn phiRootStore? text: String -> Bool
  (and (stringContains? text " = phi %Val [")
       (stringContains? text "store %Val ")
       (stringContains? text ".root"))

fn ! phiEmitHasRootStore -> Bool
  (let [(facts (optionOr (libc/libcFacts "wasm32-unknown-unknown") (libc/emptyTripleFacts)))
        (text (emitFor facts (target/wasm32TargetFacts) (phiSource)))]
    (and (ok? text) (phiRootStore? (textOf text))))

fn emitFor facts: libc/TripleFacts tf: target/TargetFacts source: String -> (Result String (List irTy/IrDiag))
  (mt (low/lowerSource source)
    ((err ds) (err ds))
    ((ok m) (targetLlvm/emitLlvmProgramForTarget facts tf m "main")))

fn ! compileObject ll: String obj: String -> ProcessOutput
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

fn ! nativeRun name: String source: String work: String -> ProcessOutput
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

fn ! sharedObjects work: String -> Bool
  (let [(facts (optionOr (libc/libcFacts "wasm32-unknown-unknown") (libc/emptyTripleFacts)))
        (tf (target/wasm32TargetFacts))
        (cleared (sh (str "rm -rf " (shellQuote work))))]
    (do
      (assert (= cleared.exitCode 0) "clears the build root")
      (assert (ok? (dirCreate work)) "creates the build root")
      (assert (some? (libc/libcFacts "wasm32-unknown-unknown")) "has the wasm32 facts row")
      (assert (writeAndCompile "shared" "runtime" (targetLlvm/emitLlvmRuntimeForTarget facts tf) work) "collector object")
      (assert (writeAndCompile "shared" "support" (targetLlvm/emitLlvmSupportForTarget facts tf) work) "support object")
      (assert (ok? (fileWrite (str work "/run.js") (runnerJs))) "writes the Node runner")
      true))

fn ! tightRuntime work: String facts: libc/TripleFacts tf: target/TargetFacts -> Bool
  (mt (targetLlvm/emitLlvmRuntimeForTarget facts tf)
    ((err _) false)
    ((ok text) (writeAndCompile "shared" "runtime-tight" (ok (stringReplace text "8388608" "1")) work)))

fn ! nativeCollectorText -> String
  (let [(triple (gr/hostTriple (sh "uname -s -m").stdout))
        (facts (optionOr (libc/libcFacts triple) (libc/emptyTripleFacts)))]
    (mt (gr/collectorText facts)
      ((ok text) text)
      ((err _) "")))

fn ! scenario root: String runtime: String name: String source: String expected: String -> Bool
  (let [(work (str root "/" name))
        (wasm (str work "/main.wasm"))
        (facts (optionOr (libc/libcFacts "wasm32-unknown-unknown") (libc/emptyTripleFacts)))
        (tf (target/wasm32TargetFacts))]
    (do
      (assert (ok? (dirCreate work)) (str name " creates its build directory"))
      (assert (writeAndCompile name "main" (emitFor facts tf source) work) (str name " program object"))
      (let [(linked (wl/linkWasm32 (linker) (list (str work "/main.o") runtime (str root "/support.o")) (list "gcFreedObjects") wasm))]
        (assert (= linked.exitCode 0) (str name " links: " linked.stderr)))
      (let [(ran (sh (str (shellQuote (node)) " " (shellQuote (str root "/run.js")) " " (shellQuote wasm))))
            (native (nativeRun name source work))
            (freedLine (optionOr (listLast (filter (fn [(l String)] -> Bool (stringStartsWith? l "freed ")) (stringSplit ran.stderr "\n"))) ""))
            (freed (optionOr (stringToInt64 (stringReplace freedLine "freed " "")) -1))]
        (do
          (assert (= native.stdout expected) (str name " native stdout is the expected text; native: " native.stdout))
          (assert (= ran.stdout native.stdout) (str name " wasm stdout equals native byte for byte; wasm: " ran.stdout " stderr: " ran.stderr))
          (assert (= ran.exitCode native.exitCode) (str name " wasm exit " ran.exitCode " equals native exit " native.exitCode "; " ran.stderr))
          (assert (> freed 0) (str name " collected while its values were live, freed " freed "; " ran.stderr))
          true))))

fn ! runTests -> Bool
  (let [(root (workRoot))]
    (do
      (assert (sharedObjects root) "shared wasm32 objects")
      (assert (phiRootStore? "%$4812 = phi %Val [ %$8, %bb ]\nstore %Val %$4812, ptr %$4812.root") "phi root check accepts compiler-generated SSA IDs")
      (assert (scenario root (str root "/runtime.o") "callerLocal" (callerLocalSource) (callerLocalExpected)) "caller local across an allocating call")
      (assert (scenario root (str root "/runtime.o") "recursion" (recursionSource) (recursionExpected)) "recursion and tail-call chain")
      (assert (scenario root (str root "/runtime.o") "closure" (closureSource) (closureExpected)) "closure capture")
      (assert (scenario root (str root "/runtime.o") "variant" (variantSource) (variantExpected)) "variant wrapping a list")
      (assert (phiEmitHasRootStore) "the heap-valued phi is stored in its shadow-root slot")
      (assert (scenario root (str root "/runtime.o") "phi" (phiSource) (phiExpected)) "phi-joined heap Val across an allocating call")
      (let [(facts (optionOr (libc/libcFacts "wasm32-unknown-unknown") (libc/emptyTripleFacts)))
            (tf (target/wasm32TargetFacts))]
        (do
          (assert (tightRuntime root facts tf) "compiles a tight-threshold runtime")
          (assert (scenario root (str root "/runtime-tight.o") "listLiteral" (listLiteralSource) (listLiteralExpected)) "list literal roots its partial chain during collection")))
      (assert (stringContains? (nativeCollectorText) "@gcExternalRoots = global ptr null, align 8\n@gcAsl.state = internal global") "native collector omits the wasm-only blank line")
      true))
