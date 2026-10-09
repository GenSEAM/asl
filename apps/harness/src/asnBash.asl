(module aslHarness/asnBash :x [AsnExecutable AsnForm AsnScript AsnInvocationPolicy makeAsnForm makeAsnExecutable makeAsnScript appendAsnForm validateAsnScript formatAsnScript invokeAsl defaultAslInvocationPolicy rpcDeprecationNotice] :i [(asl-text/escape :a esc)])

(schema AsnExecutable (:f path Str) (:f args (List Str)) (:f cwd Str) (:f env (List (pair Str Str))) (:f allow Bool))

(schema AsnForm (:f kind Str) (:f payload Str))

(schema AsnScript (:f name Str) (:f forms (List AsnForm)) (:f executables (List AsnExecutable)))

(schema AsnInvocationPolicy (:f rpcEradicated Bool) (:f asnPrimary Bool) (:f scriptsEmbedded Bool) (:f executablesEmbedded Bool) (:f toolCallsEmbedded Bool))

fn makeAsnForm kind: Str payload: Str -> AsnForm
  (AsnForm :kind kind :payload payload)

fn makeAsnExecutable path: Str args: (List Str) cwd: Str env: (List (Pair Str Str)) allow: Bool -> AsnExecutable
  (AsnExecutable :path path :args args :cwd cwd :env env :allow allow)

fn makeAsnScript name: Str forms: (List AsnForm) executables: (List AsnExecutable) -> AsnScript
  (AsnScript :name name :forms forms :executables executables)

fn appendAsnForm script: AsnScript form: AsnForm -> AsnScript
  (with script :forms (listAppend script.forms (list form)))

fn validateAsnScript script: AsnScript -> Bool
  (and (> (stringLength script.name) 0) (> (+ (listLength script.forms) (listLength script.executables)) 0))

fn formatAsnForm form: AsnForm -> Str
  (str "(:form :kind \"" form.kind "\" :payload \"" (esc/escapeAsnStr form.payload) "\")")

fn formatAsnExecutable exe: AsnExecutable -> Str
  (let [(args (map (fn [(arg Str)] -> Str (str "\"" (esc/escapeAsnStr arg) "\"")) exe.args)) (env (map (fn [(item (pair Str Str))] -> Str (str "(:env \"" (esc/escapeAsnStr (pairFirst item)) "\" \"" (esc/escapeAsnStr (pairSecond item)) "\")")) exe.env))] (str "(:executable :path \"" (esc/escapeAsnStr exe.path) "\" :args [" (stringJoin args " ") "] :cwd \"" (esc/escapeAsnStr exe.cwd) "\" :allow " (if exe.allow "true" "false") " :env [" (stringJoin env " ") "])"))

fn formatAsnScript script: AsnScript -> Str
  (let [(forms (map (fn [(form AsnForm)] -> Str (formatAsnForm form)) script.forms)) (executables (map (fn [(exe AsnExecutable)] -> Str (formatAsnExecutable exe)) script.executables))] (str "(:script :name \"" script.name "\" :forms [" (stringJoin forms " ") "] :executables [" (stringJoin executables " ") "])"))

fn invokeAsl script: AsnScript -> Str
  (if (validateAsnScript script) (formatAsnScript script) "(:asl :status \"rejected\" :error-code \"ERR_INVALID_ASN_SCRIPT\")")

fn defaultAslInvocationPolicy -> AsnInvocationPolicy
  (AsnInvocationPolicy :rpcEradicated true :asnPrimary true :scriptsEmbedded true :executablesEmbedded true :toolCallsEmbedded true)

fn rpcDeprecationNotice -> Str
  "RPC adapter has been eradicated. All execution is direct ASN form invocation."
