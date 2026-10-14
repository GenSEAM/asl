(module asl-target-py/tests/ssaPyTest
  :x [runTests]
  :i [(asl-ir/types :a ty) (asl-target-py/main :a py)])

fn shellQuote s: String -> String
  (str "'" (stringReplace s "'" "'\\''") "'")

fn fixture name: String -> String
  (str "asl/packages/asl-target-js/tests/fixtures/" name ".asl")

fn errCode text: String -> String
  (mt (stringIndexOf text "ERR_")
    ((none) "")
    ((some at) (let [(rest (optionOr (stringSlice text at (stringLength text)) ""))] (optionOr (listHead (stringSplit (optionOr (listHead (stringSplit rest ":")) "") " ")) ""))))

fn ! python! -> String
  (stringTrim (processRun "command -v python3").stdout)

fn ! sameAsHost! name: String -> Bool
  (let [(work "/tmp/asl-target-py")
        (out (str work "/" name ".py"))
        (compiled (py/compileEntry! (fixture name)))]
    (do
      (assert (ok? compiled) (str name " compiles to python: " (mt compiled ((ok _) "ok") ((err ds) (py/diagText ds)))))
      (processRun (str "mkdir -p " work))
      (assert (ok? (fileWrite out (mt compiled ((ok t) t) ((err _) "")))) (str name " writes its module"))
      (let [(viaPy (processRun (str (shellQuote (python!)) " " (shellQuote out))))
            (viaHost (processRun (str "asl/host/out/asl-host run " (shellQuote (fixture name)))))]
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
      (assert (ok? compiled) (str suite " compiles to python: " (mt compiled ((ok _) "ok") ((err ds) (py/diagText ds)))))
      (assert (ok? (fileWrite out (mt compiled ((ok t) t) ((err _) "")))) (str suite " writes its module"))
      (let [(viaPy (processRun (str (shellQuote (python!)) " -c " (shellQuote (loader out)))))
            (viaHost (processRun (str "asl/host/out/asl-host test " (shellQuote path))))]
        (do
          (assert (= viaPy.stdout (str "true " (hostCount viaHost.stdout))) (str suite " passes under python with the host's assertion count; py=" viaPy.stdout viaPy.stderr " host=" viaHost.stdout))
          true))))

fn ! runTests -> Bool
  (do
    (assert (not (stringEmpty? (python!))) "python3 is on PATH")
    (assert (listAll? sameAsHost! ["hello" "arithmetic" "string" "list" "map" "gcLoop" "trap" "overflow" "shapes" "text" "deep" "printArgs"]) "every fixture runs the same under python as on the host")
    (assert (listAll? suiteUnderPy! ["htmlTest" "cssTest" "markdownTest"]) "asl-html's suites pass compiled to python")
    (let [(absent (py/compileEntry! (fixture "needsFile")))]
      (assert (mt absent ((ok _) false) ((err ds) (listAny? (fn [(d ty/IrDiag)] -> Bool (= d.code "ERR_CAPABILITY_ABSENT")) ds))) "a program that reads a file does not compile to python: ERR_CAPABILITY_ABSENT"))
    true)
