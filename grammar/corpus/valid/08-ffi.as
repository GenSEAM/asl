; v0.3: the total foreign boundary. The declared return type is the SUCCESS
; type — every call site sees (Result T String), so a host exception cannot
; arrive as anything but a value.

(module data/frames
  :doc "Typed total boundary over the host dataframe library."
  :export [row-count describe]
  :extern [(py "polars" :as pl)])

(defopaque DataFrame
  :doc "A host dataframe: passed across the boundary, never inspected here.")

(defextern pl/read-csv [(path String)] -> DataFrame
  :doc "Read a CSV file into a dataframe."
  :target :py
  :symbol "read_csv")

(defextern pl/height [(df DataFrame)] -> Int64
  :doc "Number of rows in a dataframe."
  :target :py)

(defun row-count [(path String)] -> (Result Int64 String)
  :doc "Rows in a CSV, or the host failure as a value."
  (let [(df (try (pl/read-csv path)))]
    (ok (try (pl/height df)))))

(defun describe [(path String)] -> (Result String String)
  :doc "Human-readable row count for a CSV."
  (let [(n (try (row-count path)))]
    (ok (str (string-from-int64 n) " rows"))))
