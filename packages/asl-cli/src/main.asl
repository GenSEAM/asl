(module asl-cli/main :x [dispatch main] :i [(cli :a c)])

fn ! dispatch args: (List Str) -> (Result Unit Str)
  (c/executeCli args)

fn ! main args: (List Str) -> (Result Unit IoError)
  (c/main args)
