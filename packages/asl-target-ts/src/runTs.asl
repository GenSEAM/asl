(module asl-target-ts/runTs
  :x [compileAndRunTs runTsCode]
  :i [(asl-target-ts/emitTs :a em)
      (asl-parser/ast :a a)])

fn ! runTsCode code: String -> ProcessOutput
  (let [(dir (stringTrim (processRun "mktemp -d \"${TMPDIR:-/tmp}/parityTsXXXXXX\"").stdout))
        (path (str dir "/prog.mts"))]
    (mt (fileWrite path code)
      ((err e) {:exitCode 1 :stdout "" :stderr (str "write failed: " e)})
      ((ok _) (let [(checkRes (processRun (str "tsc --noEmit --strict --target es2022 --module nodenext " path " 2>&1")))]
                (if (not (= checkRes.exitCode 0))
                  (do (processRun (str "rm -rf " dir))
                      {:exitCode 1 :stdout "" :stderr (str "tsc check failed: " checkRes.stdout " " checkRes.stderr)})
                  (let [(runRes (processRun (str "node --experimental-strip-types --no-warnings " path)))
                        (_ (processRun (str "rm -rf " dir)))]
                    runRes))))))

fn ! compileAndRunTs src: String -> ProcessOutput
  (mt (a/parse src)
    ((err pe) {:exitCode 1 :stdout "" :stderr (str "parse error: " pe.msg)})
    ((ok forms) (runTsCode (em/emitTsModule forms))))
