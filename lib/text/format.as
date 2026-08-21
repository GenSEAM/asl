; Aliases `core/numbers` as `s` — deliberately the same alias spelling that
; `09-aliases.as` binds to `core/strings`. Both call `s/show`.

(module text/format
  :doc "Render a numbered label."
  :export [render]
  :import [(core/numbers :as s)])

(defun render [(n Int64)] -> String
  :doc "A label carrying its number."
  (str "#" (s/show n)))
