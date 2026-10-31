(module rcSpawnLeak
  :x [main]
  :i [])

fn ! main args: (List String) -> (Result Int64 String)
  (match (processSpawn "/bin/true")
    ((err e) (err e))
    ((ok h) (match (processWait h 5000)
              ((err e) (err e))
              ((ok _) (ok 0)))))
