(module aslAgent/ffi :x [HostCallRequest HostCallResponse makeHostRequest makeHostResponse isValidCapability? isValidAction? hostCall!] :i [])

(schema HostCallRequest (:f capability Str) (:f action Str) (:f payload Str))

(schema HostCallResponse (:f success Bool) (:f output Str) (:f errorMsg Str))

fn makeHostRequest capability: Str action: Str payload: Str -> HostCallRequest
  (HostCallRequest :capability capability :action action :payload payload)

fn makeHostResponse success: Bool output: Str errorMsg: Str -> HostCallResponse
  (HostCallResponse :success success :output output :errorMsg errorMsg)

fn isValidCapability? cap: Str -> Bool
  (cond ((= cap "fs") true) ((= cap "exec") true) ((= cap "audio") true) ((= cap "llm") true) (else false))

fn isValidAction? cap: Str act: Str -> Bool
  (cond ((= cap "fs") (cond ((= act "read") true) ((= act "write") true) ((= act "list") true) (else false))) ((= cap "exec") (cond ((= act "exec") true) ((= act "run") true) (else false))) ((= cap "audio") (cond ((= act "speak") true) ((= act "interrupt") true) ((= act "vad_status") true) (else false))) ((= cap "llm") (cond ((= act "complete") true) ((= act "stream") true) (else false))) (else false))

fn hostCall! capability: Str action: Str payload: Str -> (Result Str Str)
  (if (not (isValidCapability? capability))
    (err (str "Unknown capability: " capability))
    (if (not (isValidAction? capability action))
      (err (str "Unknown action '" action "' for capability " capability))
      (cond
        ((= capability "fs")
          (cond
            ((= action "read") (mt (fileRead payload) ((ok c) (ok c)) ((err _) (err (str "file not found: " payload)))))
            (else (err (str "unsupported fs action in stage-0 sandbox: " action)))))
        ((= capability "exec")
          (err "unsupported exec capability in stage-0 sandbox: native subprocess required"))
        (else
          (err (str "unsupported capability in stage-0 sandbox: " capability))))))
