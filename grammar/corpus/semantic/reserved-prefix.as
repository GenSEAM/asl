; as- is a reserved compiler-internal prefix (AGENT_SPEC_CORE 2).
; This name is lexically well-formed, so rejection must come from the reserved
; rule itself and not from an unrelated character-class violation.
(defun as-internal [] -> Int64
  1)
