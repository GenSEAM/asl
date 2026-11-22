(module asl/examples/processDemo
  :x [echoOut]
  :i [(asl-tools/fleet/run :a fr)])

fn ! echoOut word: String -> String
  (let [(d (fr/runOneLimited
             (fr/job (list "/bin/echo" word) "/" (fr/childEnv (list)))
             (fr/limits 60 4)))]
    (stringTrim d.out))
