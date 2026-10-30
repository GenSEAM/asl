(module asl/agentLoop/tests/mainDriver
  :x [main]
  :i [(asl/agentLoop/main :a m)])

fn ! main args: (List String) -> (Result Int64 String)
  (ok (m/mainCli args))
