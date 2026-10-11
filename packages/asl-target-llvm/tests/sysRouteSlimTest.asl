(module asl-target-llvm/tests/sysRouteSlimTest
  :x [runTests]
  :i [(asl-ir/types :a ty)
      (asl-ir/link :a lk)
      (asl-target-llvm :a llvm)
      (asl-target-llvm/libc :a libc)])

fn host -> String
  "asl/host/out/asl-host"

fn clang -> String
  "/usr/bin/clang -Wno-override-module"

fn lib -> String
  "asl/host/out/libaslrt.a"

fn ! sh cmd: String -> ProcessOutput
  (processRun cmd)

fn ! hostTriple -> String
  (let [(k (stringReplace (sh "uname -s").stdout "\n" ""))
        (m (stringReplace (sh "uname -m").stdout "\n" ""))]
    (cond
      ((and (= k "Darwin") (= m "arm64")) "darwin-arm64")
      ((and (= k "Linux") (= m "x86_64")) "linux-x86_64")
      ((and (= k "Linux") (or (= m "aarch64") (= m "arm64"))) "linux-aarch64")
      (else "")))

fn ! hostFacts -> libc/TripleFacts
  (mt (libc/libcFacts (hostTriple))
    ((some f) f)
    ((none) (do (assert false (str "hostFacts: libc.asl has no row for this host's triple \"" (hostTriple) "\"")) (libc/emptyTripleFacts))))

fn lines xs: (List String) -> String
  (str (stringJoin xs "\n") "\n")

fn diagText ds: (List ty/IrDiag) -> String
  (stringJoin (map (fn [(d ty/IrDiag)] -> String (str d.code " " d.message)) ds) "; ")

fn ! lowered name: String src: String -> (Option ty/SsaModule)
  (let [(preludeText (resultOr (fileRead (lk/preludePath)) ""))]
    (do (assert (not (stringEmpty? preludeText)) (str (lk/preludePath) " is readable"))
        (mt (lk/lowerSourceWith src preludeText)
          ((err ds) (do (assert false (str name ": lowerSourceWith: " (diagText ds))) (none)))
          ((ok m) (some m)))))

fn ! build work: String name: String src: String -> String
  (let [(_ (assert (ok? (fileWrite (str work "/" name ".asl") src)) (str name ".asl written")))]
    (mt (lowered name src)
      ((none) "")
      ((some m)
        (mt (llvm/emitLlvmProgramFor (hostFacts) m "main")
          ((err ds) (do (assert false (str name ": emitLlvmProgramFor: " (diagText ds))) ""))
          ((ok text) (do (assert (ok? (fileWrite (str work "/" name ".ll") text)) (str name ".ll written")) text))))))

fn ! linkBin work: String name: String -> Bool
  (let [(out (sh (str (clang) " -x ir " work "/" name ".ll -x none " (lib) " -lm -o " work "/" name)))]
    (do (assert (= out.exitCode 0) (str name ": links; " out.stderr))
        (= out.exitCode 0)))

fn internalDefineMarker -> String
  "\ndefine internal tailcc "

fn internalBlocksBytes text: String -> Int64
  (let [(pieces (stringSplit text (internalDefineMarker)))
        (rest (optionOr (listTail pieces) (list)))]
    (fold (fn [(acc Int64) (piece String)] -> Int64
            (+ acc (stringLength (internalDefineMarker)) (stringLength (optionOr (listHead (stringSplit piece "\n}\n")) piece))))
          0 rest))

fn internalBlocksCount text: String -> Int64
  (- (listLength (stringSplit text (internalDefineMarker))) 1)

fn oneBuiltinSource -> String
  (lines (list
    "(module sysOneBuiltin :x [main] :i [])"
    ""
    "fn ! main args: (List String) -> (Result Int64 String)"
    "  (mt (cpuCount)"
    "    ((ok c) (ok c))"
    "    ((err e) (ok -1)))"))

fn ! testIrSizeOneBuiltin work: String -> Bool
  (let [(ll (build work "sysOneBuiltin" (oneBuiltinSource)))
        (bytes (internalBlocksBytes ll))
        (count (internalBlocksCount ll))]
    (do (assert (> count 0) (str "sysOneBuiltin: at least one routed function is internal, got " count))
        (assert (< bytes 200000)
                (str "sysOneBuiltin: " count " internal routed function(s) emit " bytes
                     " bytes of LLVM text, want < 200000 (one sys builtin must not pull the whole sysTable)"))
        true))

fn comboSource -> String
  (lines (list
    "(module sysCombo :x [main] :i [])"
    ""
    "fn ! roundTrip lfd: Int64 cfd: Int64 -> Int64"
    "  (mt (sockAccept lfd)"
    "    ((err e) (do (println \"sockAccept\" e) 1))"
    "    ((ok afd)"
    "      (do (fdWrite cfd \"hi\")"
    "          (let [(got (mt (fdRead afd 2) ((ok s) s) ((err e) (str \"err \" e))))]"
    "            (do (println \"echo\" got)"
    "                (fdClose afd) (fdClose cfd) (fdClose lfd)"
    "                (if (= got \"hi\") 0 1))))))"
    ""
    "fn ! netCheck dir: String -> Int64"
    "  (let [(path (str dir \"/combo.sock\"))]"
    "    (mt (unixListen path)"
    "      ((err e) (do (println \"unixListen\" e) 1))"
    "      ((ok lfd)"
    "        (mt (unixConnect path)"
    "          ((err e) (do (println \"unixConnect\" e) 1))"
    "          ((ok cfd) (let [(code (roundTrip lfd cfd))] (do (pathRemove path) code)))))))"
    ""
    "fn ! main args: (List String) -> (Result Int64 String)"
    "  (let [(dir (optionOr (listHead args) \".\"))"
    "        (self (procSelf))]"
    "    (do (println \"procSelf positive\" (> self 0))"
    "        (println \"procAlive self\" (procAlive? self))"
    "        (println \"fileAppend\" (fileAppend (str dir \"/log\") \"line\\n\"))"
    "        (println \"fileReadString\" (fileReadString (str dir \"/log\")))"
    "        (println \"net\" (netCheck dir))"
    "        (ok 0)))"))

fn ! testComboParity work: String -> Bool
  (let [(dn (str work "/combon"))
        (dv (str work "/combov"))
        (_ (sh (str "mkdir -p " dn " " dv)))
        (ll (build work "sysCombo" (comboSource)))
        (_ (linkBin work "sysCombo"))
        (native (sh (str work "/sysCombo " dn)))
        (vm (sh (str (host) " run " work "/sysCombo.asl " dv)))]
    (do (assert (= native.stdout vm.stdout) (str "sysCombo: native stdout equals asl-host run's; native=" native.stdout " vm=" vm.stdout " vm stderr=" vm.stderr))
        (assert (= native.exitCode vm.exitCode) (str "sysCombo: native exit " native.exitCode " equals asl-host run's " vm.exitCode "; native stderr " native.stderr))
        (assert (stringContains? native.stdout "echo hi") (str "sysCombo: the unix round trip echoes hi: " native.stdout))
        true))

fn ! runTests -> Bool
  (let [(made (sh "mktemp -d"))
        (work (stringReplace made.stdout "\n" ""))]
    (do (assert (= made.exitCode 0) "mktemp -d makes a work directory")
        (testIrSizeOneBuiltin work)
        (testComboParity work)
        (assert (= (sh (str "rm -rf " work)).exitCode 0) "work directory removed")
        true))
