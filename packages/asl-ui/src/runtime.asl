(module asl-ui/runtime
  :d "Pure AgentScript Elm Architecture Runtime and Immutable State Loop"
  :x [Msg
      makeMsg
      Cmd
      makeCmd
      CounterModel
      makeCounterModel
      RuntimeStepResult
      makeStepResult
      renderCounterView
      dispatchMsg
      stepRuntime]
  :i [(asl-ui/vnode :a ui)])

(dfs Msg
  (:f kind String)
  (:f value Int64))

(dfs Cmd
  (:f kind String)
  (:f payload String))

(dfs CounterModel
  (:f count Int64)
  (:f label String))

(dfs RuntimeStepResult
  (:f model CounterModel)
  (:f cmd Cmd))

(df makeMsg [(kind String) (value Int64)] -> Msg
  :d "Constructs an Elm architecture message"
  (Msg :kind kind :value value))

(df makeCmd [(kind String) (payload String)] -> Cmd
  :d "Constructs an asynchronous runtime command descriptor"
  (Cmd :kind kind :payload payload))

(df makeCounterModel [(count Int64) (label String)] -> CounterModel
  :d "Constructs a sample immutable counter model"
  (CounterModel :count count :label label))

(df makeStepResult [(model CounterModel) (cmd Cmd)] -> RuntimeStepResult
  :d "Constructs a runtime step result container"
  (RuntimeStepResult :model model :cmd cmd))

(df dispatchMsg [(model CounterModel) (msg Msg)] -> CounterModel
  :d "Dispatches message to state transition function without in-place mutation"
  (let [(k (.-kind msg))]
    (if (= k "increment")
      (let [(newCount (+ (.-count model) (.-value msg)))]
        (CounterModel :count newCount :label (str "count: " (string-from-int64 newCount))))
      (if (= k "decrement")
        (let [(newCount (- (.-count model) (.-value msg)))]
          (CounterModel :count newCount :label (str "count: " (string-from-int64 newCount))))
        model))))

(df stepRuntime [(model CounterModel) (msg Msg)] -> RuntimeStepResult
  :d "Advances runtime state and returns updated model with evaluated command"
  (let [(nextModel (dispatchMsg model msg))
        (nextCmd (makeCmd "none" ""))]
    (makeStepResult nextModel nextCmd)))

(df renderCounterView [(model CounterModel)] -> ui/VNode
  :d "Renders VNode hierarchy from immutable model state"
  (let [(lblNode (ui/makeText (.-label model) "lbl-count"))
        (btnNode (ui/makeButton "btn-inc" (map-empty) (list (ui/makeText "+" "btn-text"))))
        (containerAttrs (map-set (map-empty) "class" "counter-widget"))]
    (ui/makeContainer "counter-root" containerAttrs (list lblNode btnNode))))
