(module asl-target-go/tests/ssaGoTest
  :x [runTests]
  :i [(asl-ir/types :a ty) (asl-target-go/main :a go) (asl-tools/fleet/run :a run)])

(schema SplitOut (:f exitCode Int64) (:f stdout String) (:f stderr String))

fn shellQuote s: String -> String
  (str "'" (stringReplace s "'" "'\\''") "'")

fn fixture name: String -> String
  (str "asl/packages/asl-target-js/tests/fixtures/" name ".asl")

fn errCode text: String -> String
  (match (stringIndexOf text "ERR_")
    ((none) "")
    ((some at) (let [(rest (optionOr (stringSlice text at (stringLength text)) ""))] (optionOr (listHead (stringSplit (optionOr (listHead (stringSplit rest ":")) "") " ")) ""))))

fn ! sh! root: String argv: (List String) timeoutS: Int64 maxDesc: Int64 -> run/Done
  (run/runOneLimited (run/job argv root (run/childEnv (list))) (run/limits timeoutS maxDesc))

fn ! splitSh! root: String cmd: String errFile: String timeoutS: Int64 maxDesc: Int64 -> SplitOut
  (let [(d (sh! root (list "/bin/sh" "-c" (str cmd " 2>" (shellQuote errFile))) timeoutS maxDesc))
        (e (resultOr (fileReadString errFile) ""))]
    (SplitOut :exitCode d.exit :stdout d.out :stderr e))

fn ! goTool! -> String
  (stringTrim (sh! "." (list "/bin/sh" "-c" "command -v go") 10 8).out)

fn ! build! dir: String files: (List (Pair String String)) -> (Result String String)
  (do
    (sh! "." (list "/bin/sh" "-c" (str "mkdir -p " (shellQuote dir))) 15 8)
    (fileWrite (str dir "/go.mod") "module aslrun\n\ngo 1.21\n")
    (listAll? (fn [(p (Pair String String))] -> Bool (ok? (fileWrite (str dir "/" (pairFirst p)) (pairSecond p)))) files)
    (let [(r (sh! "." (list "/bin/sh" "-c" (str "cd " (shellQuote dir) " && " (shellQuote (goTool!)) " build -o prog . 2>&1")) 180 32))]
      (if (= r.exit 0) (ok (str dir "/prog")) (err r.out))))

fn ! sameAsHost! name: String -> Bool
  (let [(compiled (go/compileEntry! (fixture name)))]
    (do
      (assert (ok? compiled) (str name " compiles to go: " (match compiled ((ok _) "ok") ((err ds) (go/diagText ds)))))
      (let [(built (build! (str "/tmp/asl-target-go/" name) [(pair "main.go" (match compiled ((ok t) t) ((err _) "")))]))]
        (do
          (assert (ok? built) (str name " builds with go: " (match built ((ok _) "ok") ((err e) e))))
          (let [(errBase (str "/tmp/asl-target-go/" name))
                (viaGo (splitSh! "." (shellQuote (resultOr built "false")) (str errBase "/go.stderr") 30 16))
                (viaHost (splitSh! "." (str "./bin/asl run " (shellQuote (fixture name))) (str errBase "/host.stderr") 60 32))]
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
      (assert (ok? compiled) (str suite " compiles to go: " (match compiled ((ok _) "ok") ((err ds) (go/diagText ds)))))
      (let [(built (build! (str "/tmp/asl-target-go/" suite) [(pair "suite.go" (match compiled ((ok t) t) ((err _) ""))) (pair "runner.go" (suiteRunner))]))]
        (do
          (assert (ok? built) (str suite " builds with go: " (match built ((ok _) "ok") ((err e) e))))
          (let [(errBase (str "/tmp/asl-target-go/" suite))
                (viaGo (splitSh! "." (shellQuote (resultOr built "false")) (str errBase "/go.stderr") 30 16))
                (viaHost (splitSh! "." (str "./bin/asl test " (shellQuote path)) (str errBase "/host.stderr") 120 32))]
            (do
              (assert (= viaGo.stdout (str "true " (hostCount viaHost.stdout))) (str suite " passes under go with the host's assertion count; go=" viaGo.stdout viaGo.stderr " host=" viaHost.stdout))
              true))))))

fn ! runTests -> Bool
  (do
    (assert (not (stringEmpty? (goTool!))) "go is on PATH")
    (assert (listAll? sameAsHost! ["hello" "arithmetic" "string" "list" "map" "gcLoop" "trap" "overflow" "shapes" "text" "deep" "printArgs"]) "every fixture runs the same compiled with go as on the host")
    (assert (listAll? suiteUnderGo! ["htmlTest" "cssTest" "markdownTest"]) "asl-html's suites pass compiled to go")
    (let [(absent (go/compileEntry! (fixture "needsFile")))]
      (assert (match absent ((ok _) false) ((err ds) (listAny? (fn [(d ty/IrDiag)] -> Bool (= d.code "ERR_CAPABILITY_ABSENT")) ds))) "a program that reads a file does not compile to go: ERR_CAPABILITY_ABSENT"))
    true)
