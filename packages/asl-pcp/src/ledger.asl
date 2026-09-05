(module asl-pcp/ledger
  :d "ASN tabular encoder and parser for Project Constitution Protocol ledgers."
  :x [escape-string
      unescape-string
      encode-rule-row
      encode-ledger-asn
      slice-from
      is-escaped-at?
      check-quote-candidate
      find-sub-quote
      next-quote-index
      build-string-token
      locate-quote-span
      extract-one-string
      extract-all-strings
      nth-or-empty
      collect-rules-loop
      group-into-rules
      extract-rule-codes
      parse-ledger-asn]
  :i [(types :a t)])

(df escape-string [(s Str)] -> Str
  :d "Escapes backslashes and double quotes in a string literal."
  (let [(s1 (string-replace s "\\" "\\\\"))
        (s2 (string-replace s1 "\"" "\\\""))]
    (string-replace s2 "\n" "\\n")))

(df unescape-string [(s Str)] -> Str
  :d "Replaces escaped quotes and backslashes in a string literal."
  (let [(s1 (string-replace s "\\\"" "\""))
        (s2 (string-replace s1 "\\n" "\n"))]
    (string-replace s2 "\\\\" "\\")))

(df encode-rule-row [(rule t/PcpRule)] -> Str
  :d "Encodes a PcpRule as an ASN table row vector."
  (str "  [\"" (escape-string (.-code rule)) "\" \""
       (escape-string (.-title rule)) "\" \""
       (escape-string (.-why rule)) "\" \""
       (escape-string (.-status rule)) "\"]"))

(df encode-ledger-asn [(ledger t/Ledger)] -> Str
  :d "Encodes a Ledger into an ASN tabular constitution document."
  (let [(rules (.-rules ledger))
        (row-strings (map encode-rule-row rules))
        (body (string-join row-strings "\n"))]
    (str "([:code :title :why :status]\n [\n" body "\n ])\n")))

(df slice-from [(src Str) (pos I64)] -> Str
  :d "Safe substring from pos to end of string."
  (mt (string-slice src pos (string-length src))
    ((some s) s)
    ((none) "")))

(df is-escaped-at? [(src Str) (abs-idx I64)] -> Bool
  :d "Checks if character at abs-idx is preceded by a backslash escape."
  (if (> abs-idx 0)
    (mt (string-slice src (- abs-idx 1) abs-idx)
      ((some prev) (= prev "\\"))
      ((none) false))
    false))

(df check-quote-candidate [(src Str) (abs-idx I64)] -> (Option I64)
  :d "Verifies quote candidate or continues searching if escaped."
  (if (is-escaped-at? src abs-idx)
    (next-quote-index src (+ abs-idx 1))
    (some abs-idx)))

(df find-sub-quote [(src Str) (start-idx I64)] -> (Option I64)
  :d "Finds relative index of double quote in substring."
  (string-index-of (slice-from src start-idx) "\""))

(df next-quote-index [(src Str) (start-idx I64)] -> (Option I64)
  :d "Finds the next unescaped quote index starting from start-idx."
  (mt (find-sub-quote src start-idx)
    ((none) (none))
    ((some rel-idx) (check-quote-candidate src (+ start-idx rel-idx)))))

(df build-string-token [(src Str) (open-abs I64) (close-abs I64)] -> (Pair Str I64)
  :d "Extracts and unescapes string payload between open and close quote indices."
  (let [(raw (mt (string-slice src (+ open-abs 1) close-abs) ((some s) s) ((none) "")))
        (val (unescape-string raw))]
    (pair val (+ close-abs 1))))

(df locate-quote-span [(src Str) (open-abs I64)] -> (Option (Pair Str I64))
  :d "Locates closing quote for opening quote at open-abs."
  (mt (next-quote-index src (+ open-abs 1))
    ((none) (none))
    ((some close-abs) (some (build-string-token src open-abs close-abs)))))

(df extract-one-string [(src Str) (pos I64)] -> (Option (Pair Str I64))
  :d "Finds and extracts the next string literal and returns it with end position."
  (let [(tail (slice-from src pos))]
    (mt (string-index-of tail "\"")
      ((none) (none))
      ((some open-rel) (locate-quote-span src (+ pos open-rel))))))

(df extract-all-strings [(src Str) (pos I64)] -> (List Str)
  :d "Recursively extracts all double-quoted string literals from source text."
  (mt (extract-one-string src pos)
    ((none) (list))
    ((some p)
     (let [(lit (.-first p))
           (next-pos (.-second p))]
       (list-cons lit (extract-all-strings src next-pos))))))

(df nth-or-empty [(strs (List Str)) (idx I64)] -> Str
  :d "Safe list string getter returning empty string on missing index."
  (mt (list-get strs idx)
    ((some s) s)
    ((none) "")))

(df collect-rules-loop [(strs (List Str)) (acc (List t/PcpRule))] -> (List t/PcpRule)
  :d "Accumulates rules from string chunks."
  (if (< (list-length strs) 4)
    acc
    (let [(r (t/make-rule (nth-or-empty strs 0)
                          (nth-or-empty strs 1)
                          (nth-or-empty strs 2)
                          (nth-or-empty strs 3)))
          (rest (mt (list-slice strs 4 (list-length strs)) ((some sl) sl) ((none) (list))))]
      (collect-rules-loop rest (list-append acc (list r))))))

(df group-into-rules [(strs (List Str))] -> (List t/PcpRule)
  :d "Groups a flat list of strings in chunks of 4 into PcpRule records."
  (collect-rules-loop strs (list)))

(df extract-rule-codes [(rules (List t/PcpRule))] -> (List Str)
  :d "Extracts code fields from a list of rules."
  (map (fn [(r t/PcpRule)] -> Str (.-code r)) rules))

(df parse-ledger-asn [(src Str)] -> (Option t/Ledger)
  :d "Parses an ASN tabular constitution document into a Ledger."
  (let [(all-strs (extract-all-strings src 0))
        (rules (group-into-rules all-strs))]
    (if (list-empty? rules)
      (none)
      (let [(codes (extract-rule-codes rules))]
        (some (t/make-ledger rules codes))))))
