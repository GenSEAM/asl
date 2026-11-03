(module asl-target-llvm/tests/llvmTools
  :x [usable? toolPath! llcPath! optPath! wasmLdPath! llvmNmPath! nodePath! clangPath!]
  :i [(asl/packages/asl-cli/src/nativeCli :a ncli) (asl/packages/asl-cli/src/system :a sys)])

; (:m :ref LLVM-NODE2-REDS :do "one lookup for every test that needs an LLVM or wasm tool: the :native row of the nearest .asl.config.asn or ~/.asl/config.asn (key llc opt wasmLd llvmNm node), then name and name-NN on PATH, then /usr/lib/llvm-NN/bin, then the Homebrew locations; none is the empty answer so the caller reports the missing tool by name")
fn versionSuffixes -> (List String)
  (list "" "-23" "-22" "-21" "-20" "-19" "-18" "-17" "-16" "-15")

fn llvmBinDirs -> (List String)
  (list "/usr/lib/llvm-23/bin" "/usr/lib/llvm-22/bin" "/usr/lib/llvm-21/bin" "/usr/lib/llvm-20/bin" "/usr/lib/llvm-19/bin" "/usr/lib/llvm-18/bin" "/usr/lib/llvm-17/bin" "/usr/lib/llvm-16/bin" "/usr/lib/llvm-15/bin"
        "/opt/homebrew/opt/llvm/bin" "/opt/homebrew/opt/lld/bin" "/opt/homebrew/bin" "/usr/local/opt/llvm/bin" "/usr/local/opt/lld/bin" "/usr/local/bin")

fn ! usable? path: String -> Bool
  (and (sys/isFile? path) (sys/executable? path))

fn ! firstUsable! paths: (List String) -> (Option String)
  (listHead (filter usable? paths))

fn ! configRow! key: String -> (Option String)
  (let [(dir (resultOr (realPath ".") "."))
        (home (optionOr (envGet "HOME") ""))
        (near (ncli/configNative (ncli/nearestConfigText! dir) key))]
    (match near
      ((some r) (some r))
      ((none) (if (stringEmpty? home) (none) (ncli/configNative (resultOr (fileReadString (str home "/.asl/config.asn")) "") key)))))

fn ! onPath! name: String -> (Option String)
  (firstUsable! (listFlatMap (fn [(d String)] -> (List String) (map (fn [(s String)] -> String (str d "/" name s)) (versionSuffixes))) (stringSplit (optionOr (envGet "PATH") "") ":")))

fn ! toolPath! name: String key: String -> String
  (match (configRow! key)
    ((some r) r)
    ((none) (match (onPath! name)
              ((some p) p)
              ((none) (optionOr (firstUsable! (map (fn [(d String)] -> String (str d "/" name)) (llvmBinDirs))) "")))))

fn ! llcPath! -> String
  (toolPath! "llc" "llc")

fn ! optPath! -> String
  (toolPath! "opt" "opt")

fn ! wasmLdPath! -> String
  (toolPath! "wasm-ld" "wasmLd")

fn ! llvmNmPath! -> String
  (toolPath! "llvm-nm" "llvmNm")

fn ! nodePath! -> String
  (toolPath! "node" "node")

fn ! clangPath! -> String
  (resultOr (ncli/clangFor! (resultOr (realPath ".") ".")) "clang")
