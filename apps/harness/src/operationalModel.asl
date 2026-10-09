(module aslHarness/operationalModel :x [OperationalModel makeOperationalModel formatOperationalModel] :i [])

(schema OperationalModel (:f targetFiles (List Str)) (:f requiredSymbols (List Str)) (:f expectedExitBehavior Str) (:f forbiddenSideEffects (List Str)))

fn makeOperationalModel targetFiles: (List Str) requiredSymbols: (List Str) expectedExitBehavior: Str forbiddenSideEffects: (List Str) -> OperationalModel
  (OperationalModel :targetFiles targetFiles :requiredSymbols requiredSymbols :expectedExitBehavior expectedExitBehavior :forbiddenSideEffects forbiddenSideEffects)

fn formatOperationalModel model: OperationalModel -> Str
  (str "(:operational-model" " :target-files [" (stringJoin model.targetFiles " ") "]" " :required-symbols [" (stringJoin model.requiredSymbols " ") "]" " :expected-exit-behavior \"" model.expectedExitBehavior "\"" " :forbidden-side-effects [" (stringJoin model.forbiddenSideEffects " ") "]" ")")
