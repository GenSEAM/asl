(module aslVdom/perception :x [AXFrame makeAxFrame downsampleTree] :i [])

(schema AXFrame (:f nodeId I64) (:f role Str) (:f name Str))

fn makeAxFrame id: I64 role: Str name: Str -> AXFrame
  (AXFrame :nodeId id :role role :name name)

fn downsampleTree raw: Str -> Str
  (let [(clean (stringTrim raw))] (if (stringEmpty? clean) "(:ax-root)" (str "(:ax-root (:node :content \"" clean "\"))")))
