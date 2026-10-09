(module asl-ui/runtime :x [Msg makeMsg Cmd makeCmd CounterModel makeCounterModel RuntimeStepResult makeStepResult renderCounterView dispatchMsg stepRuntime] :i [(asl-ui/vnode :a ui)])

(schema Msg (:f kind String) (:f value Int64))

(schema Cmd (:f kind String) (:f payload String))

(schema CounterModel (:f count Int64) (:f label String))

(schema RuntimeStepResult (:f model CounterModel) (:f cmd Cmd))

fn makeMsg kind: String value: Int64 -> Msg
  (Msg :kind kind :value value)

fn makeCmd kind: String payload: String -> Cmd
  (Cmd :kind kind :payload payload)

fn makeCounterModel count: Int64 label: String -> CounterModel
  (CounterModel :count count :label label)

fn makeStepResult model: CounterModel cmd: Cmd -> RuntimeStepResult
  (RuntimeStepResult :model model :cmd cmd)

fn dispatchMsg model: CounterModel msg: Msg -> CounterModel
  (let [(k msg.kind)] (if (= k "increment") (let [(newCount (+ model.count msg.value))] (CounterModel :count newCount :label (str "count: " (stringFromInt64 newCount)))) (if (= k "decrement") (let [(newCount (- model.count msg.value))] (CounterModel :count newCount :label (str "count: " (stringFromInt64 newCount)))) model)))

fn stepRuntime model: CounterModel msg: Msg -> RuntimeStepResult
  (let [(nextModel (dispatchMsg model msg)) (nextCmd (makeCmd "none" ""))] (makeStepResult nextModel nextCmd))

fn renderCounterView model: CounterModel -> ui/VNode
  (let [(lblNode (ui/makeText model.label "lbl-count")) (btnNode (ui/makeButton "btn-inc" (mapEmpty) (list (ui/makeText "+" "btn-text")))) (containerAttrs (mapSet (mapEmpty) "class" "counter-widget"))] (ui/makeContainer "counter-root" containerAttrs (list lblNode btnNode)))
