(module asl-target-ts/tests/emitTsRunTest
  :x [emittedModule runTs testTypeChecks! testProgramOutput! runTests]
  :i [(asl-target-ts/emitTs :a em)
      (asl-parser/ast :a a)
      (asl-parser/reader :a rd)])

fn emittedModule -> String
  (let [(add (a/DefunNode :name "add-numbers" :typeVars (list) :isExported true :effect false
               :params (list (a/Param :name "a" :type "Int64") (a/Param :name "b" :type "Int64")) :retType "Int64" :docstring ""
               :body (list (rd/sexprList (list (rd/sexprAtom "+") (rd/sexprAtom "a") (rd/sexprAtom "b"))))))
        (greet (a/DefunNode :name "greet" :typeVars (list) :isExported true :effect false
                 :params (list (a/Param :name "msg" :type "Str")) :retType "Unit" :docstring ""
                 :body (list (rd/sexprList (list (rd/sexprAtom "println") (rd/sexprAtom "msg"))))))]
    (str (em/emitTsModule (list (a/topDefun add) (a/topDefun greet)))
         "\nconsole.log(String(addNumbers(40n, 2n)));\ngreet(\"hello from ts\");\n"))

fn ! runTs cmd: String -> ProcessOutput
  (let [(dir (stringTrim (processRun "mktemp -d \"${TMPDIR:-/tmp}/emitTsRunXXXXXX\"").stdout))
        (path (str dir "/emitted.mts"))]
    (mt (fileWrite path (emittedModule))
      ((err e) {:exitCode 1 :stdout "" :stderr (str "write failed: " e)})
      ((ok _) (let [(r (processRun (str cmd " " path " 2>&1")))
                    (_ (processRun (str "rm -rf " dir)))]
                r))))

fn testTypeChecks! -> Bool
  (let [(r (runTs "tsc --noEmit --strict --target es2022 --module nodenext"))]
    (do
      (assert (= r.exitCode 0) (str "tsc accepts the emitted module: " r.stdout))
      true))

fn testProgramOutput! -> Bool
  (let [(r (runTs "node --experimental-strip-types --no-warnings"))]
    (do
      (assert (= r.exitCode 0) (str "node runs the emitted module: " r.stdout))
      (assert (= r.stdout "42\nhello from ts\n") (str "stdout is what the emitted functions compute: " r.stdout))
      true))

fn ! runTests -> Bool
  (do
    (assert (testTypeChecks!) "testTypeChecks")
    (assert (testProgramOutput!) "testProgramOutput")
    true)
