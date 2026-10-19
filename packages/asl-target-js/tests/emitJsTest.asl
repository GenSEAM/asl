(module asl-target-js/tests/emitJsTest
  :x [runTests]
  :i [(asl-ir/types :a ty) (asl-target-js/main :a js) (tools/fleet/run :a run)])

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

fn runner -> String
  (stringJoin
    ["const m = await import(process.argv[2]);"
     "m.setOutput((s) => process.stdout.write(s));"
     "try { const r = m.main(); process.exitCode = Number(r ?? 0); }"
     "catch (e) { if (e instanceof m.AslTrap) { process.stderr.write(e.message + '\\n'); process.exitCode = 1; } else throw e; }"]
    "\n")

fn errCode text: String -> String
  (mt (stringIndexOf text "ERR_")
    ((none) "")
    ((some at) (let [(rest (optionOr (stringSlice text at (stringLength text)) ""))] (optionOr (listHead (stringSplit (optionOr (listHead (stringSplit rest ":")) "") " ")) ""))))

fn ! node! -> String
  (stringTrim (sh! "." (list "/bin/sh" "-c" "command -v node") 10 8).out)

fn ! sameAsHost! name: String -> Bool
  (let [(work "/tmp/asl-target-js")
        (out (str work "/" name ".mjs"))
        (compiled (js/compileEntry! (fixture name)))]
    (do
      (assert (ok? compiled) (str name " compiles to js: " (mt compiled ((ok _) "ok") ((err ds) (js/diagText ds)))))
      (sh! "." (list "/bin/sh" "-c" (str "mkdir -p " work)) 15 8)
      (assert (ok? (fileWrite (str work "/run.mjs") (runner))) "writes the node runner")
      (assert (ok? (fileWrite out (mt compiled ((ok t) t) ((err _) "")))) (str name " writes its module"))
      (let [(viaJs (splitSh! "." (str (shellQuote (node!)) " " work "/run.mjs " (shellQuote out)) (str work "/" name ".js.stderr") 30 16))
            (viaHost (splitSh! "." (str "./bin/asl run " (shellQuote (fixture name))) (str work "/" name ".host.stderr") 60 32))]
        (do
          (assert (= viaJs.stdout viaHost.stdout) (str name " stdout matches the host; js=" viaJs.stdout " host=" viaHost.stdout))
          (assert (= viaJs.exitCode viaHost.exitCode) (str name " exit matches the host; js=" (stringFromInt64 viaJs.exitCode) " host=" (stringFromInt64 viaHost.exitCode) " " viaJs.stderr))
          (assert (= (errCode viaJs.stderr) (errCode viaHost.stderr)) (str name " trap code matches; js=" viaJs.stderr " host=" viaHost.stderr))
          true))))

fn hostCount output: String -> String
  (optionOr (listHead (stringSplit (optionOr (listLast (stringSplit (optionOr (listHead (stringSplit output " assertion")) "") " ")) "") " ")) "")

fn ! suiteUnderJs! suite: String -> Bool
  (let [(work "/tmp/asl-target-js")
        (path (str "asl/packages/asl-html/tests/" suite ".asl"))
        (out (str work "/" suite ".mjs"))
        (compiled (js/compileEntry! path))]
    (do
      (assert (ok? compiled) (str suite " compiles to js: " (mt compiled ((ok _) "ok") ((err ds) (js/diagText ds)))))
      (assert (ok? (fileWrite out (mt compiled ((ok t) t) ((err _) "")))) (str suite " writes its module"))
      (let [(viaJs (splitSh! "." (str (shellQuote (node!)) " --input-type=module -e " (shellQuote (str "const m = await import('" out "'); process.stdout.write(String(m.runTests()) + ' ' + m.counts.asserts)"))) (str work "/" suite ".js.stderr") 30 16))
            (viaHost (splitSh! "." (str "./bin/asl test " (shellQuote path)) (str work "/" suite ".host.stderr") 120 32))]
        (do
          (assert (= viaJs.stdout (str "true " (hostCount viaHost.stdout))) (str suite " passes under node with the host's assertion count; js=" viaJs.stdout viaJs.stderr " host=" viaHost.stdout))
          true))))

fn ! runTests -> Bool
  (do
    (assert (not (stringEmpty? (node!))) "node is on PATH")
    (assert (listAll? sameAsHost! ["hello" "arithmetic" "string" "list" "map" "gcLoop" "trap" "overflow" "shapes" "text" "deep" "printArgs"]) "every fixture runs the same under node as on the host")
    (assert (listAll? suiteUnderJs! ["htmlTest" "cssTest" "markdownTest"]) "asl-html's suites pass compiled to js")
    (let [(absent (js/compileEntry! (fixture "needsFile")))]
      (assert (mt absent ((ok _) false) ((err ds) (listAny? (fn [(d ty/IrDiag)] -> Bool (= d.code "ERR_CAPABILITY_ABSENT")) ds))) "a program that reads a file does not compile to js: ERR_CAPABILITY_ABSENT"))
    true)
