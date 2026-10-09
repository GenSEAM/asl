(module asl-target-llvm/wasmLink
  :x [! linkWasm32 ! wasmImports importsOutside])

fn shellQuote s: String -> String
  (str "'" (stringReplace s "'" "'\\''") "'")

fn joinQuoted xs: (List String) -> String
  (stringJoin (map shellQuote xs) " ")

fn ! linkWasm32 linker: String objects: (List String) exports: (List String) output: String -> ProcessOutput
  (processRun (str (shellQuote linker) " --fatal-warnings --export-memory -z stack-size=1048576"
                   (stringJoin (map (fn [(name String)] -> String (str " " (shellQuote (str "--export=" name)))) exports) "")
                   " " (joinQuoted objects) " -o " (shellQuote output)))

fn ! wasmImports node: String wasm: String -> (Result (List String) String)
  (let [(script "const fs=require('fs');const m=new WebAssembly.Module(fs.readFileSync(process.argv[1]));for(const x of WebAssembly.Module.imports(m))console.log(x.module+'.'+x.name);")
        (out (processRun (str (shellQuote node) " -e " (shellQuote script) " " (shellQuote wasm))))]
    (if (= out.exitCode 0)
      (ok (filter (fn [(line String)] -> Bool (not (stringEmpty? line))) (stringSplit out.stdout "\n")))
      (err (str "node could not read the import section of " wasm ": " out.stderr))))

fn importsOutside allowed: (List String) imports: (List String) -> (List String)
  (filter (fn [(name String)] -> Bool (not (listContains? allowed name))) imports)
