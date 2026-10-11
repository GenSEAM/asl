(module asl-checker/readerParityTest :x [testCurlyMap testWithForm runTests] :i [(asl-checker/check :a chk) (asl-checker/types :a ty)])

fn diagText ds: (List ty/Diagnostic) -> String
  (stringJoin (map (fn [(d ty/Diagnostic)] -> String d.message) ds) "; ")

fn ! testCurlyMap -> Bool
  (mt (chk/checkFile! "asl/packages/asl-checker/tests/fixtures/curlyMap.asl" (list "asl"))
    ((err _) (assert false "checker reads the curly-map fixture") false)
    ((ok ds) (assert (listEmpty? ds) (str "checker verdict accepts the host-valid curly map fixture: " (diagText ds))) true))

fn ! testWithForm -> Bool
  (mt (chk/checkFile! "asl/packages/asl-checker/tests/fixtures/withForm.asl" (list "asl"))
    ((err _) (assert false "checker reads the with-form fixture") false)
    ((ok ds) (assert (listEmpty? ds) "checker verdict accepts the host-valid with-form fixture") true))

fn ! runTests -> Bool
  (do (assert (testWithForm) "with form reader parity")
      (assert (testCurlyMap) "curly map reader parity")
      true)
