(module asl-target-go/tests/ssaGoTest
  :x [runTests]
  :i [(asl-ir/types :a ty) (asl-target-go/main :a go)])

fn shellQuote s: String -> String
  (str "'" (stringReplace s "'" "'\\''") "'")

fn fixture name: String -> String
  (str "asl/packages/asl-target-js/tests/fixtures/" name ".asl")

fn errCode text: String -> String
  (mt (stringIndexOf text "ERR_")
    ((none) "")
    ((some at) (let [(rest (optionOr (stringSlice text at (stringLength text)) ""))] (optionOr (listHead (stringSplit (optionOr (listHead (stringSplit rest ":")) "") " ")) ""))))

fn ! goTool! -> String
  (stringTrim (processRun "command -v go").stdout)

fn ! build! dir: String files: (List (Pair String String)) -> (Result String String)
  (do
    (processRun (str "mkdir -p " (shellQuote dir)))
    (fileWrite (str dir "/go.mod") "module aslrun\n\ngo 1.21\n")
    (listAll? (fn [(p (Pair String String))] -> Bool (ok? (fileWrite (str dir "/" (pairFirst p)) (pairSecond p)))) files)
    (let [(r (processRun (str "cd " (shellQuote dir) " && " (shellQuote (goTool!)) " build -o prog . 2>&1")))]
      (if (= r.exitCode 0) (ok (str dir "/prog")) (err r.stdout))))

fn ! sameAsHost! name: String -> Bool
  (let [(compiled (go/compileEntry! (fixture name)))]
    (do
      (assert (ok? compiled) (str name " compiles to go: " (mt compiled ((ok _) "ok") ((err ds) (go/diagText ds)))))
      (let [(built (build! (str "/tmp/asl-target-go/" name) [(pair "main.go" (mt compiled ((ok t) t) ((err _) "")))]))]
        (do
          (assert (ok? built) (str name " builds with go: " (mt built ((ok _) "ok") ((err e) e))))
          (let [(viaGo (processRun (shellQuote (resultOr built "false"))))
                (viaHost (processRun (str "asl/host/out/asl-host run " (shellQuote (fixture name)))))]
            (do
              (assert (= viaGo.stdout viaHost.stdout) (str name " stdout matches the host; go=" viaGo.stdout " host=" viaHost.stdout))
              (assert (= viaGo.exitCode viaHost.exitCode) (str name " exit matches the host; go=" (stringFromInt64 viaGo.exitCode) " host=" (stringFromInt64 viaHost.exitCode) " " viaGo.stderr))
              (assert (= (errCode viaGo.stderr) (errCode viaHost.stderr)) (str name " trap code matches; go=" viaGo.stderr " host=" viaHost.stderr))
              true))))))

fn hostCount output: String -> String
  (optionOr (listHead (stringSplit (optionOr (listLast (stringSplit (optionOr (listHead (stringSplit output " assertion")) "") " ")) "") " ")) "")

fn suiteRunner -> String
  "package main\n\nimport \"fmt\"\n\nfunc main() {\n\tr := RunTests()\n\tfmt.Printf(\"%v %d\", r, Counts.Asserts)\n}\n"

fn ! suiteUnderGo! suite: String -> Bool
  (let [(path (str "asl/packages/asl-html/tests/" suite ".asl"))
        (compiled (go/compileEntry! path))]
    (do
      (assert (ok? compiled) (str suite " compiles to go: " (mt compiled ((ok _) "ok") ((err ds) (go/diagText ds)))))
      (let [(built (build! (str "/tmp/asl-target-go/" suite) [(pair "suite.go" (mt compiled ((ok t) t) ((err _) ""))) (pair "runner.go" (suiteRunner))]))]
        (do
          (assert (ok? built) (str suite " builds with go: " (mt built ((ok _) "ok") ((err e) e))))
          (let [(viaGo (processRun (shellQuote (resultOr built "false"))))
                (viaHost (processRun (str "asl/host/out/asl-host test " (shellQuote path))))]
            (do
              (assert (= viaGo.stdout (str "true " (hostCount viaHost.stdout))) (str suite " passes under go with the host's assertion count; go=" viaGo.stdout viaGo.stderr " host=" viaHost.stdout))
              true))))))

fn ! runTests -> Bool
  (do
    (assert (not (stringEmpty? (goTool!))) "go is on PATH")
    (assert (listAll? sameAsHost! ["hello" "arithmetic" "string" "list" "map" "gcLoop" "trap" "overflow" "shapes" "text" "deep" "printArgs"]) "every fixture runs the same compiled with go as on the host")
    (assert (listAll? suiteUnderGo! ["htmlTest" "cssTest" "markdownTest"]) "asl-html's suites pass compiled to go")
    (let [(absent (go/compileEntry! (fixture "needsFile")))]
      (assert (mt absent ((ok _) false) ((err ds) (listAny? (fn [(d ty/IrDiag)] -> Bool (= d.code "ERR_CAPABILITY_ABSENT")) ds))) "a program that reads a file does not compile to go: ERR_CAPABILITY_ABSENT"))
    true)
