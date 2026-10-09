(module asl-forms/tests/payloadApiTest :x [runTests] :i [(asl-forms/main :a m) (asl-forms/wire :a w)])

fn shellQuote s: String -> String
  (str "'" (stringReplace s "'" "'\\''") "'")

fn ! comparePayload ws: w/Workspace payload: String -> Bool
  (let [(api (m/runPayloadText! ws payload))
        (command (str "perl -e 'alarm 180; exec @ARGV' ./bin/asl " (shellQuote payload)))
        (cli (processRun command))]
    (do (assert (= (pairFirst api) cli.stdout) (str "wire text matches CLI for " payload " API=" (pairFirst api) " CLI=" cli.stdout))
        (assert (= (pairSecond api) cli.exitCode) (str "exit code matches CLI for " payload))
        true))

fn ! runTests -> Bool
  (let [(ws (m/workspaceFor! "."))
        (unbalanced (m/runPayloadText! ws "(:read"))
        (badForm (m/runPayloadText! ws "(:notAnOperation)"))]
    (do (assert (comparePayload ws "(:read :file \"asl/packages/asl-forms/src/main.asl\" :symbol \"workspaceFor!\")") "read API matches CLI")
        (assert (comparePayload ws "(:query :text \"runPayloadText!\")") "query API matches CLI")
        (assert (comparePayload ws "(:notAnOperation)") "bad form API matches CLI")
        (assert (= (pairSecond badForm) 1) "unknown operation is dispatched to drive! and rejected with exit code 1 (ERR_UNIMPLEMENTED), same as the CLI")
        (assert (comparePayload ws "(:read") "unbalanced form API matches CLI")
        (assert (and (= (pairSecond unbalanced) 2)
                     (= (pairFirst unbalanced) "(:batch :status :failed :error ERR_UNBALANCED :depth 1 :message \"Unbalanced Dyck-1 input; nothing executed\" :hint \"a paren, bracket or string in the input does not close; nothing ran\")\n"))
          "unbalanced input returns the exact error wire bytes and exit code")
        true))
