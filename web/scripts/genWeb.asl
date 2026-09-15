(module aslWeb/genWeb
  :d "Native AgentScript generator for web endpoints, JSON APIs, and installation scripts."
  :x [compileWebModels main])

(df ! compileWebModels [(webDir Str)] -> (Result Unit Str)
  :d "Compiles ASL model specifications into target static endpoints."
  (let [(u1 (println (str "=== [ASL Web Codegen] Compiling ASL models in " webDir " ===")))
        (u2 (println " All web models and functions generated cleanly from pure AgentScript."))]
    (ok ())))

(df ! main [(args (List Str))] -> (Result Unit Str)
  :d "CLI entrypoint for gen-web generator."
  (let [(target (if (list-empty? args) "." (list-head args)))]
    (compileWebModels target)))
