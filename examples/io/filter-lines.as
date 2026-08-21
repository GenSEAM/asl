; Standard input, one line at a time and all at once. Both forms are here
; because they fail differently: end of input is `(none)`, not an error.

(module io/filter-lines
  :doc "Keep the input lines that mention a marker, reporting how many were read."
  :export [matching first-line])

(defun matching [(text String) (marker String)] -> (List String)
  :doc "Input lines that contain the marker."
  (filter (fn [(l String)] -> Bool (string-contains? l marker))
          (string-split text "\n")))

(defun first-line [] -> (Result (Option String) String)
  :doc "The first line of standard input, or none when the input was empty."
  :effects [stdin]
  (read-line))

(defentry [(argv (List String))] -> (Result Unit String)
  :doc "Filter standard input by the marker given as the first argument."
  :effects [console stdin]
  (let [(marker (option-or (list-head argv) "TODO"))
        (text (try (read-all)))
        (hits (matching text marker))
        (shown (try (println (string-join hits "\n"))))]
    (eprintln (str (string-from-int64 (list-length hits)) " matched"))))
