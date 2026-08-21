; The first module written to be imported rather than run. `06-module.as` has
; named it since v0.2 while no such file existed, which is how cross-module
; resolution came to be untested: nothing could link, so nothing noticed.

(module core/strings
  :doc "String helpers shared across modules."
  :export [concat upper lower shout blank? initial show])

(defun concat [(a String) (b String)] -> String
  :doc "Join two strings."
  (str a b))

(defun upper [(s String)] -> String
  :doc "Upper case."
  (string-upper s))

(defun lower [(s String)] -> String
  :doc "Lower case."
  (string-lower s))

(defun shout [(s String)] -> String
  :doc "Upper case with an exclamation mark."
  (str (string-upper s) "!"))

(defun blank? [(s String)] -> Bool
  :doc "True when a string is empty once trimmed."
  (string-empty? (string-trim s)))

(defun initial [(s String)] -> (Option String)
  :doc "First character of a string, when it has one."
  (list-head (string-chars s)))

(defun show [(s String)] -> String
  :doc "Render a string for display, in quotes."
  (str "\"" s "\""))
