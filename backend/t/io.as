; Fixture for the I/O and foreign-boundary semantics asserted by test_io.py.

(module t/io
  :doc "Exercise the effectful surface so its totality can be asserted."
  :export [read-or-message roundtrip run-echo exit-code-of missing-is-a-value])

(defun read-or-message [(path String)] -> String
  :doc "File contents, or the failure rendered as text rather than raised."
  :effects [fs]
  (match (file-read path)
    ((ok text) text)
    ((err e)   (str "failed: " e))))

(defun missing-is-a-value [(path String)] -> Bool
  :doc "True when reading a path produced a failure value instead of trapping."
  :effects [fs]
  (is-err? (file-read path)))

(defun roundtrip [(path String) (body String)] -> (Result String String)
  :doc "Write a file then read it back; both steps can fail as values."
  :effects [fs]
  (let [(written (try (file-write path body)))
        (back (try (file-read path)))]
    (ok back)))

(defun run-echo [(word String)] -> (Result String String)
  :doc "Standard output of `echo`, with its trailing newline removed."
  :effects [proc]
  (let [(r (try (process-run "echo" (list word) "")))]
    (ok (string-trim (.-stdout r)))))

(defun exit-code-of [(cmd String) (arg String)] -> (Result Int64 String)
  :doc "Exit status of a program, which is a value even when it is non-zero."
  :effects [proc]
  (let [(r (try (process-run cmd (list arg) "")))]
    (ok (.-exit-code r))))
