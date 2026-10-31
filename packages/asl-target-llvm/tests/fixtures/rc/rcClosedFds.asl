(module rcClosedFds
  :x [main]
  :i [])

fn verdict out: ProcessOutput -> Int64
  (if (!= out.exitCode 0) 5 (if (= out.stdout "x\n") 0 6))

fn ! viaSpawn -> Int64
  (match (processSpawn "/bin/echo x")
    ((err e) 2)
    ((ok h) (match (processWait h 5000)
              ((err e) 3)
              ((ok out) (verdict out)))))

fn ! viaRun -> Int64
  (verdict (processRun "/bin/echo x"))

fn ! main args: (List String) -> (Result Int64 String)
  (ok (if (= (optionOr (listHead args) "") "run") (viaRun) (viaSpawn)))
