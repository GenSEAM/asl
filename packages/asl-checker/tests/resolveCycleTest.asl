(module asl-checker/resolveCycleTest :x [runTests] :i [(types :a ty) (check :a c)])

fn ! sh cmd: String -> ProcessOutput
  (processRun cmd)

fn moduleSource name: String imports: String -> String
  (str "(module " name " :x [f] :i [" imports "])\n\nfn f -> Int64\n  1\n")

fn ! writeFixture! dir: String name: String imports: String -> Bool
  (let [(res (fileWrite (str dir "/" name ".asl") (moduleSource name imports)))]
    (do (assert (ok? res) (str "fixture " name ".asl written")) true))

fn ! fixtureDir! -> String
  (let [(made (sh "d=$(mktemp -d) && cd \"$d\" && pwd -P"))
        (dir (stringReplace made.stdout "\n" ""))
        (cfg (fileWrite (str dir "/.asl.config.asn") "(:aslConfig :workspace \"fx\")\n"))]
    (do (assert (= made.exitCode 0) "mktemp -d makes a work directory")
        (assert (ok? cfg) "fixture workspace config written")
        (writeFixture! dir "cyA" "(cyB :a b)")
        (writeFixture! dir "cyB" "(cyA :a a)")
        (writeFixture! dir "cyP" "(cyQ :a q)")
        (writeFixture! dir "cyQ" "(cyR :a r)")
        (writeFixture! dir "cyR" "(cyP :a p)")
        (writeFixture! dir "cySelf" "(cySelf :a s)")
        (writeFixture! dir "cyTop" "(cyMid :a m) (cyLeaf :a l)")
        (writeFixture! dir "cyMid" "(cyLeaf :a l)")
        (writeFixture! dir "cyLeaf" "")
        dir))

fn cycleMessages diags: (List ty/Diagnostic) -> (List String)
  (map (fn [(d ty/Diagnostic)] -> String d.message) (filter (fn [(d ty/Diagnostic)] -> Bool (= d.code "rule-11")) diags))

fn ! cyclesOf! dir: String name: String -> (List String)
  (mt (c/checkFile! (str dir "/" name ".asl") (list))
    ((err _) (do (assert false (str "checkFile! reads " name ".asl")) (list)))
    ((ok diags) (cycleMessages diags)))

fn ! testTwoModuleCycle dir: String -> Bool
  (let [(a (cyclesOf! dir "cyA")) (b (cyclesOf! dir "cyB"))]
    (do (assert (= a (list "import cycle: cyA -> cyB -> cyA")) (str "cyA reports its cycle once: " (stringJoin a "; ")))
        (assert (= b (list "import cycle: cyB -> cyA -> cyB")) (str "cyB reports its cycle once: " (stringJoin b "; ")))
        true))

fn ! testThreeModuleCycle dir: String -> Bool
  (let [(p (cyclesOf! dir "cyP"))]
    (do (assert (= p (list "import cycle: cyP -> cyQ -> cyR -> cyP")) (str "a three-module cycle names every module: " (stringJoin p "; ")))
        true))

fn ! testSelfImport dir: String -> Bool
  (let [(s (cyclesOf! dir "cySelf"))]
    (do (assert (= s (list "import cycle: cySelf -> cySelf")) (str "a module importing itself is a cycle: " (stringJoin s "; ")))
        true))

fn ! testDiamondIsAcyclic dir: String -> Bool
  (do (assert (listEmpty? (cyclesOf! dir "cyTop")) "a diamond import graph has no cycle")
      (assert (listEmpty? (cyclesOf! dir "cyLeaf")) "a module without imports has no cycle")
      true)

fn ! runTests -> Bool
  (let [(dir (fixtureDir!))]
    (do (assert (testTwoModuleCycle dir) "testTwoModuleCycle")
        (assert (testThreeModuleCycle dir) "testThreeModuleCycle")
        (assert (testSelfImport dir) "testSelfImport")
        (assert (testDiamondIsAcyclic dir) "testDiamondIsAcyclic")
        (assert (= (sh (str "rm -rf " dir)).exitCode 0) "work directory removed")
        true))
