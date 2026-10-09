(module asl-cli/tests/commandEmptyPathTest
  :x [testEmptyPathRejected runTests]
  :i [(asl-cli/command :a cmd)])

fn checkRejected res: (Result (List String) Int64) label: String -> Bool
  (mt res
    ((ok _) (do (assert false (str label ": must be rejected, not resolved to a file list")) false))
    ((err code) (do (assert (= code 2) (str label ": exits 2")) true)))

fn checkRealPathOk res: (Result (List String) Int64) -> Bool
  (mt res
    ((ok found) (do (assert (= (listLength found) 1) "a real, non-empty path still resolves normally") true))
    ((err _) (do (assert false "a real path must not be rejected") false)))

fn ! testEmptyPathRejected -> Bool
  (let [(r1 (checkRejected (cmd/testFiles! (list "") (list)) "sole empty-string path"))
        (r2 (checkRejected (cmd/testFiles! (list "asl/packages/asl-cli/src/main.asl" "") (list)) "trailing empty-string path"))
        (r3 (checkRealPathOk (cmd/testFiles! (list "asl/packages/asl-cli/src/main.asl") (list))))]
    (and r1 (and r2 r3)))

fn ! runTests -> Bool
  (testEmptyPathRejected)
