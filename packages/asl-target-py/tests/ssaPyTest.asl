(module asl-target-py/tests/ssaPyTest
  :x [runTests]
  :i [(asl-ir/types :a ty) (asl-target-py/main :a py) (tools/fleet/run :a run)])

(schema SplitOut (:f exitCode Int64) (:f stdout String) (:f stderr String))

fn shellQuote s: String -> String
  (str "'" (stringReplace s "'" "'\\''") "'")

fn ! sh! root: String argv: (List String) timeoutS: Int64 maxDesc: Int64 -> run/Done
  (run/runOneLimited (run/job argv root (run/childEnv (list))) (run/limits timeoutS maxDesc))

fn ! splitSh! root: String cmd: String errFile: String timeoutS: Int64 maxDesc: Int64 -> SplitOut
  (let [(d (sh! root (list "/bin/sh" "-c" (str cmd " 2>" (shellQuote errFile))) timeoutS maxDesc))
        (e (resultOr (fileReadString errFile) ""))]
    (SplitOut :exitCode d.exit :stdout d.out :stderr e))

fn fixture name: String -> String
  (str "asl/packages/asl-target-js/tests/fixtures/" name ".asl")

fn errCode text: String -> String
  (match (stringIndexOf text "ERR_")
    ((none) "")
    ((some at) (let [(rest (optionOr (stringSlice text at (stringLength text)) ""))] (optionOr (listHead (stringSplit (optionOr (listHead (stringSplit rest ":")) "") " ")) ""))))

fn ! python! -> String
  (stringTrim (sh! "." (list "/bin/sh" "-c" "command -v python3") 10 8).out)

fn ! sameAsHost! name: String -> Bool
  (let [(work "/tmp/asl-target-py")
        (out (str work "/" name ".py"))
        (compiled (py/compileEntry! (fixture name)))]
    (do
      (assert (ok? compiled) (str name " compiles to python: " (match compiled ((ok _) "ok") ((err ds) (py/diagText ds)))))
      (sh! "." (list "/bin/sh" "-c" (str "mkdir -p " work)) 15 8)
      (assert (ok? (fileWrite out (match compiled ((ok t) t) ((err _) "")))) (str name " writes its module"))
      (let [(viaPy (splitSh! "." (str (shellQuote (python!)) " " (shellQuote out)) (str work "/" name ".py.stderr") 30 16))
            (viaHost (splitSh! "." (str "./bin/asl run " (shellQuote (fixture name))) (str work "/" name ".host.stderr") 60 32))]
        (do
          (assert (= viaPy.stdout viaHost.stdout) (str name " stdout matches the host; py=" viaPy.stdout " host=" viaHost.stdout))
          (assert (= viaPy.exitCode viaHost.exitCode) (str name " exit matches the host; py=" (stringFromInt64 viaPy.exitCode) " host=" (stringFromInt64 viaHost.exitCode) " " viaPy.stderr))
          (assert (= (errCode viaPy.stderr) (errCode viaHost.stderr)) (str name " trap code matches; py=" viaPy.stderr " host=" viaHost.stderr))
          true))))

fn hostCount output: String -> String
  (optionOr (listHead (stringSplit (optionOr (listLast (stringSplit (optionOr (listHead (stringSplit output " assertion")) "") " ")) "") " ")) "")

fn loader out: String -> String
  (str "import importlib.util as u, sys; sys.setrecursionlimit(10**7); s = u.spec_from_file_location('m', " (shellQuote out) "); m = u.module_from_spec(s); s.loader.exec_module(m); "
       "r = m.runTests(); print(('true' if r is True else repr(r)) + ' ' + str(m.counts['asserts']), end='')")

fn ! suiteUnderPy! suite: String -> Bool
  (let [(work "/tmp/asl-target-py")
        (path (str "asl/packages/asl-html/tests/" suite ".asl"))
        (out (str work "/" suite ".py"))
        (compiled (py/compileEntry! path))]
    (do
      (assert (ok? compiled) (str suite " compiles to python: " (match compiled ((ok _) "ok") ((err ds) (py/diagText ds)))))
      (assert (ok? (fileWrite out (match compiled ((ok t) t) ((err _) "")))) (str suite " writes its module"))
      (let [(viaPy (splitSh! "." (str (shellQuote (python!)) " -c " (shellQuote (loader out))) (str work "/" suite ".py.stderr") 30 16))
            (viaHost (splitSh! "." (str "./bin/asl test " (shellQuote path)) (str work "/" suite ".host.stderr") 120 32))]
        (do
          (assert (= viaPy.stdout (str "true " (hostCount viaHost.stdout))) (str suite " passes under python with the host's assertion count; py=" viaPy.stdout viaPy.stderr " host=" viaHost.stdout))
          true))))

fn ! runTests -> Bool
  (do
    (assert (not (stringEmpty? (python!))) "python3 is on PATH")
    (assert (listAll? sameAsHost! ["hello" "arithmetic" "string" "list" "map" "gcLoop" "trap" "overflow" "shapes" "text" "deep" "printArgs"]) "every fixture runs the same under python as on the host")
    (assert (listAll? suiteUnderPy! ["htmlTest" "cssTest" "markdownTest"]) "asl-html's suites pass compiled to python")
    (let [(absent (py/compileEntry! (fixture "needsFile")))]
      (assert (match absent ((ok _) false) ((err ds) (listAny? (fn [(d ty/IrDiag)] -> Bool (= d.code "ERR_CAPABILITY_ABSENT")) ds))) "a program that reads a file does not compile to python: ERR_CAPABILITY_ABSENT"))
    true)
