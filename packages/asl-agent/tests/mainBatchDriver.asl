(module aslAgent/tests/mainBatchDriver
  :x [main]
  :i [(aslAgent/main :a m)])

; (:m :ref MAINPARBATCH :do "argv is the run root then one form per row; each row runs mainWithRoots in this one process and prints its stdout, a newline (as mainCli's println does) and a row-end marker carrying its exit code, so the parent test asserts per row")
fn ! rowsLoop repoRoot: String rootDir: String forms: (List String) -> Int64
  (match (listHead forms)
    ((none) 0)
    ((some form)
      (let [res (m/mainWithRoots (list form) repoRoot rootDir)]
        (do
          (print (str res.stdout "\n\u0001ROWEXIT " (stringFromInt64 res.exitCode) "\u0001\n"))
          (rowsLoop repoRoot rootDir (optionOr (listTail forms) (list)))))))

fn ! main args: (List String) -> (Result Int64 String)
  (let [repoRoot (resultOr (realPath ".") ".")
        rootArg (optionOr (listHead args) "")
        rootDir (if (stringEmpty? rootArg) repoRoot rootArg)]
    (ok (rowsLoop repoRoot rootDir (optionOr (listTail args) (list)))))
