(module asl-shrody/ffi
  :d "Bidirectional host capability FFI declarations and contract."
  :x [HostCallRequest HostCallResponse
      make-host-request make-host-response
      is-valid-capability? is-valid-action?
      host-call]
  :i [])

(dfs HostCallRequest
  (:f capability Str "Host capability domain: fs, exec, audio, llm")
  (:f action Str "Specific capability operation")
  (:f payload Str "Serialized operation payload"))

(dfs HostCallResponse
  (:f success Bool "True if host operation succeeded")
  (:f output Str "Result data payload")
  (:f error-msg Str "Error description if failed"))

(df make-host-request [(capability Str) (action Str) (payload Str)] -> HostCallRequest
  :d "Constructs a HostCallRequest record."
  (HostCallRequest
    :capability capability
    :action action
    :payload payload))

(df make-host-response [(success Bool) (output Str) (error-msg Str)] -> HostCallResponse
  :d "Constructs a HostCallResponse record."
  (HostCallResponse
    :success success
    :output output
    :error-msg error-msg))

(df is-valid-capability? [(cap Str)] -> Bool
  :d "Checks whether capability is one of: fs, exec, audio, llm."
  (cond
    ((= cap "fs") true)
    ((= cap "exec") true)
    ((= cap "audio") true)
    ((= cap "llm") true)
    (:else false)))

(df is-valid-action? [(cap Str) (act Str)] -> Bool
  :d "Checks if action is supported by the capability."
  (cond
    ((= cap "fs")
     (cond
       ((= act "read") true)
       ((= act "write") true)
       ((= act "list") true)
       (:else false)))
    ((= cap "exec")
     (cond
       ((= act "exec") true)
       ((= act "run") true)
       (:else false)))
    ((= cap "audio")
     (cond
       ((= act "speak") true)
       ((= act "interrupt") true)
       ((= act "vad_status") true)
       (:else false)))
    ((= cap "llm")
     (cond
       ((= act "complete") true)
       ((= act "stream") true)
       (:else false)))
    (:else false)))

(df host-call [(capability Str) (action Str) (payload Str)] -> (Result Str Str)
  :d "Bidirectional host capability invocation."
  (if (not (is-valid-capability? capability))
    (err (str "Unknown capability: " capability))
    (if (not (is-valid-action? capability action))
      (err (str "Unknown action '" action "' for capability " capability))
      (ok (str "host:" capability ":" action ":" payload)))))
