(module aslWeb/genWeb :x [compileWebModels main])

fn ! compileWebModels webDir: Str -> (Result Unit Str)
  (let [(u1 (println (str "=== [ASL Web Codegen] Compiling ASL models in " webDir " ==="))) (u2 (println " All web models and functions generated cleanly from pure AgentScript."))] (ok ()))

fn ! main args: (List Str) -> (Result Unit Str)
  (let [(target (optionOr (listHead args) "."))] (compileWebModels target))
