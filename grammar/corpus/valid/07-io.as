; v0.3: the I/O surface and the single entry point. Everything that touches the
; outside is a Result, so a program cannot ignore a failed read.

(module tool/wc
  :doc "Count the lines and words of a file named on the command line."
  :export [count-lines count-words report])

(defun count-lines [(text String)] -> Int64
  :doc "Number of newline-separated lines."
  (list-length (string-split text "\n")))

(defun count-words [(text String)] -> Int64
  :doc "Number of space-separated words, ignoring empty runs."
  (list-length (filter (fn [(w String)] -> Bool (not (string-empty? w)))
                       (string-split text " "))))

(defun report [(path String)] -> (Result String String)
  :doc "One summary line for a file, or the read failure as a value."
  :effects [fs]
  (let [(text (try (file-read path)))]
    (ok (str (string-from-int64 (count-lines text))
             " "
             (string-from-int64 (count-words text))
             " "
             path))))

(defentry [(argv (List String))] -> (Result Unit String)
  :doc "Summarise the file named by the first argument."
  :effects [console fs]
  (let [(path (option-or (list-head argv) ""))
        (line (try (report path)))]
    (println line)))
