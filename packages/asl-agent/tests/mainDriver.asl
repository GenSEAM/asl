(module aslAgent/tests/mainDriver
  :x [main]
  :i [(aslAgent/main :a m)])

fn ! main args: (List String) -> (Result Int64 String)
  (ok (m/mainCli args))
