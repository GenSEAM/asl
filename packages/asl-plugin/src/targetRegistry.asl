(module asl-plugin/targetRegistry :x [TargetRegistry emptyTargetRegistry registerTarget registerCodegenTarget hasTarget? lookupTarget dispatchTargetCodegen listRegisteredTargets] :i [(ast :a a) (reader :a rd)])

(schema TargetRegistry (:field targets (Map Str (fn [(List a/TopForm) (Map Str Str)] -> (Result Str Str)))) (:field docstrings (Map Str Str)))

fn emptyTargetRegistry -> TargetRegistry
  (TargetRegistry :targets (mapEmpty) :docstrings (mapEmpty))

fn registerTarget reg: TargetRegistry name: Str doc: Str emitter: (fn [(List a/TopForm) (Map Str Str)] -> (Result Str Str)) -> TargetRegistry
  (TargetRegistry :targets (mapSet reg.targets name emitter) :docstrings (mapSet reg.docstrings name doc))

fn registerCodegenTarget reg: TargetRegistry name: Str emitter: (fn [(List a/TopForm) (Map Str Str)] -> (Result Str Str)) -> TargetRegistry
  (registerTarget reg name "codegen/target provider" emitter)

fn hasTarget? reg: TargetRegistry name: Str -> Bool
  (some? (mapGet reg.targets name))

fn lookupTarget reg: TargetRegistry name: Str -> (Option (fn [(List a/TopForm) (Map Str Str)] -> (Result Str Str)))
  (mapGet reg.targets name)

fn dispatchTargetCodegen reg: TargetRegistry target: Str forms: (List a/TopForm) options: (Map Str Str) -> (Result Str Str)
  (mt (lookupTarget reg target) ((some emitter) (emitter forms options)) ((none) (err (str "unsupported-target: " target))))

fn listRegisteredTargets reg: TargetRegistry -> (List Str)
  (mapKeys reg.targets)
