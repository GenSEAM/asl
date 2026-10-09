(module asl-checker/untypedParamTest :x [runTests] :i [(check :a c) (types :a ty)])

fn checkerProbe src: String -> (List ty/Diagnostic)
  (c/checkSource src (mapEmpty) "untypedParamProbe.asl")

fn diagnosticText ds: (List ty/Diagnostic) -> String
  (stringJoin (map (fn [(d ty/Diagnostic)] -> String (str d.code " " d.message)) ds) "; ")

fn ! hostProbe! source: String -> (Pair String ProcessOutput)
  (let [(made (processRun "mktemp -d /tmp/asl-untyped-param-XXXXXX"))
        (dir (stringTrim made.stdout))
        (owned (and (= made.exitCode 0) (stringStartsWith? dir "/tmp/asl-untyped-param-")))
        (path (str dir "/probe.asl"))
        (written (if owned (fileWrite path source) (err (str "mktemp failed: " made.stderr))))
        (result (processRun (str "./bin/asl check " path)))
        (removed (if owned (processRun (str "rm -rf " dir)).exitCode 1))]
    (do
      (assert owned (str "host probe gets its own temporary directory: " dir made.stderr))
      (assert (mt written ((ok _) true) ((err _) false)) "host probe source is written")
      (assert (and (= removed 0) (not (fileExists? path))) "host probe directory is removed")
      (pair dir result)))

fn hostOutput result: ProcessOutput -> String
  (str result.stdout result.stderr)

fn ! runTests -> Bool
  (let [(checkerBad (checkerProbe "(module probe :x [bad]) (fn bad [(item)] -> Int64 7)"))
        (checkerTyped (checkerProbe "(module probe :x [good]) (fn good [(item Int64)] -> Int64 7)"))
        (checkerLambda (checkerProbe "(module probe :x [good]) (fn good [] -> Int64 ((fn [item] 7) 7))"))
        (hostBadRun (hostProbe! "(module probe :x [bad])

fn bad item -> Int64
  item
"))
        (hostTypedRun (hostProbe! "(module probe :x [good])

fn good item: Int64 -> Int64
  item
"))
        (hostLambdaRun (hostProbe! "(module probe :x [good])

fn good -> Int64
  ((fn [item] item) 7)
"))
        (checkerPlaced (checkerProbe "(module probe :x [bad])\n\n(fn bad [(item)] -> Int64\n    7)"))
        (probeDirs (list (pairFirst hostBadRun) (pairFirst hostTypedRun) (pairFirst hostLambdaRun)))
        (hostBad (pairSecond hostBadRun))
        (hostTyped (pairSecond hostTypedRun))
        (hostLambda (pairSecond hostLambdaRun))
        (badCheckerText (diagnosticText checkerBad))
        (badHostText (hostOutput hostBad))]
    (do
      (assert (and (stringContains? badCheckerText "ERR_UNTYPED_PARAM") (stringContains? badCheckerText "item") (stringContains? badCheckerText "bad")) (str "checker rejects an untyped top-level parameter and names it and its function: " badCheckerText))
      (assert (= (listLength checkerBad) 1) (str "checker emits one missing-parameter diagnostic: " badCheckerText))
      (assert (mt (listHead checkerPlaced) ((some d) (and (= d.code "ERR_UNTYPED_PARAM") (= d.line 4) (= d.col 5))) ((none) false)) (str "checker places the diagnostic at the function's first body form, line 4 col 5: " (stringJoin (map (fn [(d ty/Diagnostic)] -> String (str d.code "@" d.line ":" d.col)) checkerPlaced) "; ")))
      (assert (= (listLength (mapKeys (fold (fn [(seen (Map String Bool)) (dir String)] -> (Map String Bool) (mapSet seen dir true)) (mapEmpty) probeDirs))) 3) (str "each host probe uses a distinct temporary directory: " (stringJoin probeDirs " ")))
      (assert (listEmpty? checkerTyped) (str "checker accepts typed top-level params: " (diagnosticText checkerTyped)))
      (assert (listEmpty? checkerLambda) (str "checker exempts untyped lambda params: " (diagnosticText checkerLambda)))
      (assert (and (not (= hostBad.exitCode 0)) (stringContains? badHostText "ERR_UNTYPED_PARAM") (stringContains? badHostText "item") (stringContains? badHostText "bad")) (str "host rejects an untyped top-level parameter and names it and its function: " badHostText))
      (assert (= hostTyped.exitCode 0) (str "host accepts typed top-level params: " (hostOutput hostTyped)))
      (assert (= hostLambda.exitCode 0) (str "host exempts untyped lambda params: " (hostOutput hostLambda)))
      true))
