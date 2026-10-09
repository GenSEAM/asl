(module asl-target-c/tests/runParityCTest
  :x [runTests]
  :i [(asl-target-c/emit :a em)])

fn corpusFiles -> (List String)
  (list "tests/acceptance/targetParity/corpus/sample.asl"
        "tests/acceptance/targetParity/corpus/strings.asl"
        "tests/acceptance/targetParity/corpus/records.asl"
        "tests/acceptance/targetParity/corpus/lists.asl"
        "tests/acceptance/targetParity/corpus/result.asl"
        "tests/acceptance/targetParity/corpus/errors.asl")

fn workName path: String -> String
  (stringReplace (stringReplace path "/" "_") "." "_")

fn ! emitAndCheckSyntax work: String path: String -> (Result ProcessOutput String)
  (mt (fileRead path)
    ((err e) (err (str path ": read failed: " e)))
    ((ok src)
      (mt (mt (fileRead "asl/prelude/prelude.asl") ((err e) (err (str "prelude read failed: " e))) ((ok preludeText) (em/emitC11SourceWith src preludeText path)))
        ((err m) (err (str path ": emit failed: " m)))
        ((ok code)
          (let [(cFile (str work "/" (workName path) ".c"))]
            (mt (fileWrite cFile code)
              ((err e) (err (str path ": write failed: " e)))
              ((ok _) (ok (processRun (str "/usr/bin/cc -fsyntax-only " cFile))))))))))

fn ! testCorpusFile work: String path: String -> Bool
  (mt (emitAndCheckSyntax work path)
    ((err m) (do (assert false m) false))
    ((ok checked)
      (let [(passed (= checked.exitCode 0))]
        (do (assert passed (str path ": emits and type-checks as C11 (cc -fsyntax-only exit " checked.exitCode "; stderr: " checked.stderr ")")) passed))))

fn ! testMathBuiltinsC work: String -> Bool
  (testCorpusFile work "tests/acceptance/targetParity/corpus/math.asl")

fn ! runTests -> Bool
  (let [(ccCheck (processRun "which /usr/bin/cc"))]
    (if (not (= ccCheck.exitCode 0))
      (do (assert false "/usr/bin/cc is required by this gate and is reported missing, not silently skipped") false)
      (let [(mkt (processRun "mktemp -d"))]
        (if (not (= mkt.exitCode 0))
          (do (assert false "mktemp -d failed") false)
          (let [(work (stringReplace mkt.stdout "\n" ""))
                (results (map (fn [(p String)] -> Bool (testCorpusFile work p)) (corpusFiles)))
                (allOk (fold (fn [(acc Bool) (r Bool)] -> Bool (and acc r)) true results))
                (mathOk (testMathBuiltinsC work))
                (_ (processRun (str "rm -rf " work)))]
            (and allOk mathOk))))))
