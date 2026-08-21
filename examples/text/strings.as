; The String section of the vocabulary, in use. Every name here is shown doing
; something a report renderer would actually need.

(module text/strings
  :doc "Normalise and inspect text for report headings and slugs."
  :export [slug shouty? headline-of measure palindrome? describe-ratio reserved?])

(defun slug [(title String)] -> String
  :doc "Lower-case a title and join its words with dashes."
  (string-replace (string-lower (string-trim title)) " " "-"))

(defun shouty? [(line String)] -> Bool
  :doc "True when a line is upper-case and ends in an exclamation mark."
  (and (= line (string-upper line))
       (string-ends-with? line "!")))

(defun headline-of [(doc String)] -> (Option String)
  :doc "The text after the first colon, when the document has one."
  (match (string-index-of doc ":")
    ((some i) (string-slice doc (+ i 1) (string-length doc)))
    ((none)   (none))))

(defun measure [(line String)] -> (Pair Int64 Bool)
  :doc "Length of a line, and whether it carries a TODO marker."
  (pair (string-length line) (string-contains? line "TODO")))

(defun palindrome? [(word String)] -> Bool
  :doc "True when a word reads the same reversed, ignoring case."
  (= (string-lower word) (string-reverse (string-lower word))))

(defun describe-ratio [(text String)] -> String
  :doc "Render a parsed decimal ratio, or report that it was not a number."
  (match (string-to-float64 (string-trim text))
    ((some r) (str "ratio " (string-from-float64 r)))
    ((none)   "not a number")))

(defun reserved? [(name String)] -> Bool
  :doc "True when a name sits in the reserved compiler namespace."
  (string-starts-with? name "as-"))
