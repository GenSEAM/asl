; Two modules bind the alias `s` to different modules, and both call `s/show`.
;
; Under the alias-based flattening this replaced, both lowered to `s_show` — two
; different functions, one name, no error. Mangling from the resolved module path
; keeps them apart, and `backend/modules.py` fails loudly if any two ever do
; collide, which §8 requires and a silent rename would violate.

(module app/labels
  :doc "Label rendering that reaches two modules through the same alias name."
  :export [quoted numbered]
  :import [(core/strings :as s)
           (text/format  :as f)])

(defun quoted [(x String)] -> String
  :doc "A quoted string; `s` here is core/strings."
  (s/show x))

(defun numbered [(n Int64)] -> String
  :doc "A numbered label; the `s` inside text/format is core/numbers."
  (f/render n))
