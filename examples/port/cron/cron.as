; A cron-expression parser and describer, written once.
;
; Why this library: it is one of the clearest cases of the duplicated effort this
; language exists to remove. The same logic has been hand-ported down a chain —
; a C# describer to JavaScript to Go — and each port re-derives the same field
; grammar, the same bounds and the same English rendering, then maintains them
; separately. Here it is written once and every backend gets it.
;
; Why it is expressible today: pure logic, no bytes and no regular expressions,
; and its behaviour is pinned by test vectors that can be lifted verbatim rather
; than judged. It is also Option- and Result-dense, which is what the language is
; actually for.

(module port/cron
  :doc "Parse a five-field cron expression and describe it in English."
  :export [parse describe describe-or-error matches-minute?])

(defenum Field
  (:case every    []                  "Every value in the field's range")
  (:case exact    [(value Int64)]      "One value")
  (:case span     [(lo Int64) (hi Int64)] "An inclusive range of values")
  (:case every-nth [(step Int64)]      "Every nth value from the range's start")
  (:case one-of   [(values (List Int64))] "An explicit set of values"))

(defschema Cron
  (:field minute  Field "Minute of the hour, 0-59")
  (:field hour    Field "Hour of the day, 0-23")
  (:field day     Field "Day of the month, 1-31")
  (:field month   Field "Month of the year, 1-12")
  (:field weekday Field "Day of the week, 0-6 with 0 as Sunday"))

; ---------- parsing ----------

(defun bounded [(n Int64) (lo Int64) (hi Int64)] -> (Result Int64 String)
  :doc "A value inside an inclusive range, or a message naming the bound broken."
  (if (and (>= n lo) (<= n hi))
    (ok n)
    (err (str "value " (string-from-int64 n) " is outside "
              (string-from-int64 lo) "-" (string-from-int64 hi)))))

(defun to-number [(text String) (lo Int64) (hi Int64)] -> (Result Int64 String)
  :doc "Parse one in-range integer, or say why it is not one."
  (match (string-to-int64 text)
    ((some n) (bounded n lo hi))
    ((none)   (err (str "not a number: " text)))))

(defun parse-list [(parts (List String)) (lo Int64) (hi Int64)] -> (Result (List Int64) String)
  :doc "Parse every comma-separated member of a set, failing on the first bad one."
  (fold (fn [(acc (Result (List Int64) String)) (part String)] -> (Result (List Int64) String)
          (match acc
            ((err e) (err e))
            ((ok ns) (match (string-to-int64 part)
                       ((none)   (err (str "not a number: " part)))
                       ((some n) (if (and (>= n lo) (<= n hi))
                                   (ok (list-append ns (list n)))
                                   (err (str "value " (string-from-int64 n)
                                             " is outside " (string-from-int64 lo)
                                             "-" (string-from-int64 hi)))))))))
        (ok (list))
        parts))

(defun parse-field [(text String) (lo Int64) (hi Int64)] -> (Result Field String)
  :doc "Parse one cron field: a wildcard, a step, a range, a set, or a value."
  (cond
    ((= text "*") (ok (every)))
    ((string-starts-with? text "*/")
     (match (string-slice text 2 (string-length text))
       ((none)     (err "empty step"))
       ((some rest)
        (match (string-to-int64 rest)
          ((none)   (err (str "not a number: " rest)))
          ((some n) (if (> n 0)
                      (ok (every-nth n))
                      (err "step must be positive")))))))
    ((string-contains? text "-")
     (let [(ends (string-split text "-"))]
       (if (!= (list-length ends) 2)
         (err (str "malformed range: " text))
         (match (to-number (option-or (list-get ends 0) "") lo hi)
           ((err e)  (err e))
           ((ok a)   (match (to-number (option-or (list-get ends 1) "") lo hi)
                       ((err e) (err e))
                       ((ok b)  (if (<= a b)
                                  (ok (span a b))
                                  (err (str "range runs backwards: " text))))))))))
    ((string-contains? text ",")
     (match (parse-list (string-split text ",") lo hi)
       ((err e)  (err e))
       ((ok ns)  (ok (one-of (list-sort ns))))))
    (:else
     (match (to-number text lo hi)
       ((err e) (err e))
       ((ok n)  (ok (exact n)))))))

(defun parse [(expression String)] -> (Result Cron String)
  :doc "Parse a whole five-field expression, or report the first field that failed."
  (let [(fields (filter (fn [(f String)] -> Bool (not (string-empty? f)))
                        (string-split (string-trim expression) " ")))]
    (if (!= (list-length fields) 5)
      (err (str "expected 5 fields, got " (string-from-int64 (list-length fields))))
      (match (parse-field (option-or (list-get fields 0) "") 0 59)
        ((err e) (err (str "minute: " e)))
        ((ok mi)
         (match (parse-field (option-or (list-get fields 1) "") 0 23)
           ((err e) (err (str "hour: " e)))
           ((ok ho)
            (match (parse-field (option-or (list-get fields 2) "") 1 31)
              ((err e) (err (str "day: " e)))
              ((ok da)
               (match (parse-field (option-or (list-get fields 3) "") 1 12)
                 ((err e) (err (str "month: " e)))
                 ((ok mo)
                  (match (parse-field (option-or (list-get fields 4) "") 0 6)
                    ((err e) (err (str "weekday: " e)))
                    ((ok wd) (ok (Cron :minute mi :hour ho :day da
                                       :month mo :weekday wd)))))))))))))))

; ---------- matching ----------

(defun field-matches? [(f Field) (n Int64)] -> Bool
  :doc "Whether a field admits a given value."
  (match f
    ((every)      true)
    ((exact v)    (= v n))
    ((span lo hi) (and (>= n lo) (<= n hi)))
    ((every-nth s) (= (mod n s) 0))
    ((one-of vs)  (list-contains? vs n))))

(defun matches-minute? [(expression String) (minute Int64)] -> (Result Bool String)
  :doc "Whether an expression's minute field admits a given minute."
  (match (parse expression)
    ((err e) (err e))
    ((ok c)  (ok (field-matches? (.-minute c) minute)))))

; ---------- describing ----------

(defun field-text [(f Field) (unit String)] -> String
  :doc "One field in English, with its unit named."
  (match f
    ((every)       (str "every " unit))
    ((exact v)     (str unit " " (string-from-int64 v)))
    ((span lo hi)  (str unit " " (string-from-int64 lo) " through " (string-from-int64 hi)))
    ((every-nth s) (str "every " (string-from-int64 s) " " unit "s"))
    ((one-of vs)   (str unit " " (string-join (map (fn [(v Int64)] -> String
                                                     (string-from-int64 v)) vs) ", ")))))

(defun describe [(expression String)] -> (Result String String)
  :doc "A whole expression in English, or the parse failure."
  (match (parse expression)
    ((err e) (err e))
    ((ok c)  (ok (string-join
                   (list (field-text (.-minute c) "minute")
                         (field-text (.-hour c) "hour")
                         (field-text (.-day c) "day")
                         (field-text (.-month c) "month")
                         (field-text (.-weekday c) "weekday"))
                   "; ")))))

(defun describe-or-error [(expression String)] -> String
  :doc "The description, or the failure rendered as text.

  The flattened form is what a command line wants, and it is what the
  differential gate compares across backends: one string per input, so a
  disagreement is visible without the harness knowing about Result."
  (match (describe expression)
    ((ok text) text)
    ((err e)   (str "error: " e))))
