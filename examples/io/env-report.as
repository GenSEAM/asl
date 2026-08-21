; The I/O surface, in use: read the environment and the filesystem, shell out,
; and write a report. Nothing here can fail silently — every outside call is a
; Result, and `try` is what unwraps one.

(module io/env-report
  :doc "Write a short report about the checkout and the environment."
  :export [describe-commit report verbose?])

(defun describe-commit [] -> (Result String String)
  :doc "Short commit id of the checkout, or why git could not tell us."
  :effects [proc]
  (let [(r (try (process-run "git" (list "rev-parse" "--short" "HEAD") "")))]
    (if (= (.-exit-code r) 0)
      (ok (string-trim (.-stdout r)))
      (err (string-trim (.-stderr r))))))

(defun home-or-unknown [] -> String
  :doc "The user's home directory, or a placeholder when it is unset."
  :effects [env]
  (option-or (env-get "HOME") "<unset>"))

(defun verbose? [] -> Bool
  :doc "True when --verbose was passed.

  This reads the arguments directly rather than having argv threaded down to it:
  a helper that needs one flag should not change every signature above it."
  :effects [env]
  (list-contains? (args) "--verbose"))

(defun report [(path String)] -> (Result String String)
  :doc "Build the report text, noting whether the target path already exists."
  :effects [env fs proc]
  (let [(commit (try (describe-commit)))
        (state (if (file-exists? path) "present" "absent"))
        (detail (if (verbose?) (str "\nhome " (home-or-unknown)) ""))]
    (ok (str "commit " commit "\ntarget " state detail))))

(defentry [(argv (List String))] -> (Result Unit String)
  :doc "Write the report to the path given, or to standard output with no path."
  :effects [console env fs proc]
  (let [(text (try (report (option-or (list-head argv) ""))))]
    (match (list-head argv)
      ((some path) (let [(written (try (file-write path text)))]
                     (eprintln (str "wrote " path))))
      ((none)      (let [(shown (try (print text)))]
                     (println ""))))))
