(module asl-cli/tests/standaloneCliTest
  :x [runTests]
  :i [(asl/packages/asl-cli/src/system :a sys)])

fn okSource -> String
  "(module standaloneOk :x [f] :i [])\nfn f -> Int64 1\n"

fn unbalancedSource -> String
  "(module standaloneUnbalanced :x [f] :i [])\nfn f -> Int64 (+ 1 2\n"

fn unknownSource -> String
  "(module standaloneUnknown :x [f] :i [])\nfn f -> Int64 (nope 1)\n"

fn passedReceipt -> String
  "(:audit :sub check :status :passed (:check :id balance :status :passed) (:check :id hostCheck :status :passed :exit 0))"

fn unbalancedReceipt -> String
  "(:audit :sub check :status :failed (:check :id balance :status :failed :err ERR_UNBALANCED) (:check :id hostCheck :status :skipped))"

fn unknownReceipt -> String
  "(:audit :sub check :status :failed (:check :id balance :status :passed) (:check :id hostCheck :status :failed :exit 1))"

fn ! makeDir! path: String -> (Result String String)
  (mt (dirCreate path) ((err e) (err (str "mkdir " path ": " e))) ((ok _) (ok path)))

fn ! writeFile! path: String text: String -> (Result String String)
  (mt (fileWrite path text) ((err e) (err (str "write " path ": " e))) ((ok _) (ok path)))

fn ! build! root: String binary: String -> (Result String String)
  (mt (sys/capture! (list (str root "/bin/asl") "build" (str root "/asl/packages/asl-cli/src/command.asl") "-o" binary) (some root))
    ((err e) (err (str "asl build: " e)))
    ((ok got)
      (if (and (= got.exitCode 0) (sys/executable? binary))
        (ok binary)
        (err (str "asl build exited " (stringFromInt64 got.exitCode) ": " got.stdout got.stderr)))))

fn ! setupOutside! base: String binary: String -> (Result String String)
  (mt (makeDir! base)
    ((err e) (err e))
    ((ok _)
      (mt (makeDir! (str base "/cwd"))
        ((err e) (err e))
        ((ok cwd)
          (mt (makeDir! (str base "/bin"))
            ((err e) (err e))
            ((ok binDir)
              (mt (pathSymlink binary (str binDir "/asl"))
                ((err e) (err (str "symlink: " e)))
                ((ok _)
                  (mt (writeFile! (str cwd "/ok.asl") (okSource))
                    ((err e) (err e))
                    ((ok _)
                      (mt (writeFile! (str cwd "/unbalanced.asl") (unbalancedSource))
                        ((err e) (err e))
                        ((ok _)
                          (mt (writeFile! (str cwd "/unknown.asl") (unknownSource))
                            ((err e) (err e))
                            ((ok _) (ok cwd)))))))))))))))

fn ! runClean! cwd: String path: String program: String file: String -> (Result sys/Captured String)
  (sys/capture! (list "/usr/bin/env" "-i" (str "PATH=" path) program "check" file) (some cwd))

fn ! runCleanHelp! cwd: String path: String program: String -> (Result sys/Captured String)
  (sys/capture! (list "/usr/bin/env" "-i" (str "PATH=" path) program "help") (some cwd))

fn lastLine text: String -> String
  (optionOr (listLast (filter (fn [(l String)] -> Bool (not (stringEmpty? l))) (stringSplit text "\n"))) "")

fn describe got: sys/Captured -> String
  (str "exit " (stringFromInt64 got.exitCode) " stdout " got.stdout " stderr " got.stderr)

(schema Outcome
  (:f label String)
  (:f got (Result sys/Captured String))
  (:f exitCode Int64)
  (:f receipt String)
  (:f stderrHas String))

fn ! expectCheck! o: Outcome -> Bool
  (mt o.got
    ((err e) (do (assert false (str o.label ": spawn failed: " e)) false))
    ((ok got)
      (do
        (assert (= got.exitCode o.exitCode) (str o.label ": want exit " (stringFromInt64 o.exitCode) ", got " (describe got)))
        (assert (= (lastLine got.stdout) o.receipt) (str o.label ": want receipt " o.receipt ", got " (describe got)))
        (assert (stringContains? got.stderr o.stderrHas) (str o.label ": want stderr holding " o.stderrHas ", got " (describe got)))
        true)))

fn ! runCases! cwd: String binary: String binDir: String -> (List Outcome)
  (let [(plain "/usr/bin:/bin")
        (viaPath (str binDir ":/usr/bin:/bin"))]
    (list
      (Outcome :label "absolute exe, good file" :got (runClean! cwd plain binary "ok.asl") :exitCode 0 :receipt (passedReceipt) :stderrHas "")
      (Outcome :label "PATH symlink named asl, good file" :got (runClean! cwd viaPath "asl" "ok.asl") :exitCode 0 :receipt (passedReceipt) :stderrHas "")
      (Outcome :label "absolute exe, unbalanced file" :got (runClean! cwd plain binary "unbalanced.asl") :exitCode 1 :receipt (unbalancedReceipt) :stderrHas "")
      (Outcome :label "PATH symlink named asl, unknown symbol" :got (runClean! cwd viaPath "asl" "unknown.asl") :exitCode 1 :receipt (unknownReceipt) :stderrHas "ERR_UNKNOWN_SYMBOL nope")))

fn ! runTests -> Bool
  (let [(root (resultOr (realPath ".") "."))
        (tag (stringFromInt64 (monotonicNs)))
        (buildDir (str root "/.asl/tmp/standaloneCli_" tag))
        (outside (str "/tmp/standaloneCli_" tag))
        (binary (str buildDir "/asl"))
        (built (makeDir! buildDir))
        (compiled (mt built ((err e) (err e)) ((ok _) (build! root binary))))
        (cwdR (mt compiled ((err e) (err e)) ((ok _) (setupOutside! outside binary))))
        (outcomes (mt cwdR ((err _) (list)) ((ok cwd) (runCases! cwd binary (str outside "/bin")))))
        (helpOut (mt cwdR ((err e) (err e)) ((ok cwd) (runCleanHelp! cwd (str outside "/bin:/usr/bin:/bin") binary))))
        (removedBuild (pathRemove buildDir))
        (removedOutside (pathRemove outside))]
    (do
      (assert (fileExists? (str root "/asl/grammar/rules.asn")) "run from the workspace root")
      (assert (ok? built) (mt built ((err e) e) ((ok _) "build dir")))
      (assert (ok? compiled) (mt compiled ((err e) e) ((ok _) "built")))
      (assert (ok? cwdR) (mt cwdR ((err e) e) ((ok _) "outside cwd")))
      (assert (= (listLength outcomes) 4) "four cases ran")
      (map expectCheck! outcomes)
      (assert (and (ok? helpOut) (mt helpOut ((err _) false) ((ok got) (= got.exitCode 0)))) "clean standalone help exits successfully")
      (assert (mt helpOut ((err _) false) ((ok got) (and (stringContains? got.stdout "Host evaluates expressions and echoes (:keyword ...) as ASN data")
                                                         (stringContains? got.stdout "--native evaluates a single Int64 expression only"))))
              "help distinguishes host ASN echo from native single-Int64 evaluation")
      (assert (and (ok? removedBuild) (not (fileExists? buildDir))) "build dir removed")
      (assert (and (ok? removedOutside) (not (fileExists? outside))) "outside dir removed")
      true))
