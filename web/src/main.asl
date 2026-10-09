(module aslWeb/main :x [mainInit main] :i [(App :a app)])

fn mainInit -> Str
  "(app-mount :target \"#root\")"

fn main -> Str
  (mainInit)
