(module asl-text/tomlLite
  :x [parse parseLine classify row flatArrayOk? ParseError]
  :i [])

(schema ParseError (:f line Int64) (:f msg String))

(schema StrScan (:f ok Bool) (:f esc Bool) (:f done Bool))

(schema ArrScan (:f cur String) (:f parts (List String)) (:f inStr Bool) (:f esc Bool))

(schema ParseState (:f table String) (:f rows (List (Result String ParseError))))

fn escape s: String -> String
  (stringReplace (stringReplace s "\\" "\\\\") "\"" "\\\"")

fn strStep a: StrScan c: String -> StrScan
  (if a.done
    (with a :ok false)
    (if a.esc
      (with a :esc false)
      (if (= c "\\")
        (with a :esc true)
        (if (= c "\"")
          (with a :done true)
          a))))

fn stringOk? s: String -> Bool
  (if (stringStartsWith? s "\"")
    (let [(rest (optionOr (stringSlice s 1 (stringLength s)) ""))
          (st (fold strStep (StrScan :ok true :esc false :done false) (stringChars rest)))]
      (and st.ok st.done (not st.esc)))
    false)

fn digitChar? c: String -> Bool
  (stringContains? "0123456789" c)

fn digits? s: String -> Bool
  (and (not (stringEmpty? s)) (listAll? digitChar? (stringChars s)))

fn stripSign s: String -> String
  (if (or (stringStartsWith? s "+") (stringStartsWith? s "-"))
    (optionOr (stringSlice s 1 (stringLength s)) "")
    s)

fn intOk? s: String -> Bool
  (digits? (stripSign s))

fn floatOk? s: String -> Bool
  (let [(parts (stringSplit s "."))]
    (and (= (listLength parts) 2)
         (digits? (stripSign (optionOr (listGet parts 0) "")))
         (digits? (optionOr (listGet parts 1) ""))))

fn scalarOk? s: String -> Bool
  (or (stringOk? s) (= s "true") (= s "false") (intOk? s) (floatOk? s))

fn arrIn2 a: ArrScan c: String -> ArrScan
  (if (= c "\\")
    (with a :cur (str a.cur c) :esc true)
    (if (= c "\"")
      (with a :cur (str a.cur c) :inStr false)
      (with a :cur (str a.cur c))))

fn arrIn a: ArrScan c: String -> ArrScan
  (if a.esc
    (with a :cur (str a.cur c) :esc false)
    (arrIn2 a c))

fn arrOut a: ArrScan c: String -> ArrScan
  (if (= c "\"")
    (with a :cur (str a.cur c) :inStr true)
    (if (= c ",")
      (with a :parts (listAppend a.parts [(stringTrim a.cur)]) :cur "")
      (with a :cur (str a.cur c))))

fn arrStep a: ArrScan c: String -> ArrScan
  (if a.inStr (arrIn a c) (arrOut a c))

fn arrayParts inner: String -> (List String)
  (let [(st (fold arrStep (ArrScan :cur "" :parts [] :inStr false :esc false) (stringChars inner)))
        (tail (stringTrim st.cur))]
    (if (and (stringEmpty? tail) (not (listEmpty? st.parts)))
      st.parts
      (listAppend st.parts [tail])))

fn arrElemOk? p: String -> Bool
  (and (not (stringEmpty? p)) (scalarOk? p))

fn flatArrayOk? inner: String -> Bool
  (if (stringEmpty? (stringTrim inner))
    true
    (listAll? arrElemOk? (arrayParts inner)))

fn arrayKind value: String -> (Result String String)
  (let [(inner (optionOr (stringSlice value 1 (- (stringLength value) 1)) ""))]
    (if (flatArrayOk? inner) (ok "array") (err "invalid array")))

fn classify4 value: String -> (Result String String)
  (if (and (stringStartsWith? value "[") (stringEndsWith? value "]"))
    (arrayKind value)
    (err "unsupported value"))

fn classify3 value: String -> (Result String String)
  (if (intOk? value)
    (ok "int")
    (if (floatOk? value)
      (ok "float")
      (classify4 value)))

fn classify2 value: String -> (Result String String)
  (if (or (= value "true") (= value "false"))
    (ok "bool")
    (classify3 value))

fn classify value: String -> (Result String String)
  (if (stringStartsWith? value "\"")
    (if (stringOk? value) (ok "string") (err "unterminated string"))
    (classify2 value))

fn row table: String key: String value: String kind: String -> String
  (str "(:row :table \"" (escape table) "\" :key \"" (escape key) "\" :value \"" (escape value) "\" :kind \"" kind "\")")

fn keyChar? c: String -> Bool
  (stringContains? "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-_." c)

fn keyOk? s: String -> Bool
  (and (not (stringEmpty? s)) (listAll? keyChar? (stringChars s)))

fn lineVal n: Int64 table: String key: String value: String -> (Result String ParseError)
  (match (classify value)
    ((ok kind) (ok (row table key value kind)))
    ((err m) (err (ParseError :line n :msg m))))

fn lineAt n: Int64 table: String text: String i: Int64 -> (Result String ParseError)
  (let [(key (stringTrim (optionOr (stringSlice text 0 i) "")))
        (value (stringTrim (optionOr (stringSlice text (+ i 1) (stringLength text)) "")))]
    (if (not (keyOk? key))
      (err (ParseError :line n :msg "invalid key"))
      (lineVal n table key value)))

fn parseLine n: Int64 table: String text: String -> (Result String ParseError)
  (match (stringIndexOf text "=")
    ((some i) (lineAt n table text i))
    ((none) (err (ParseError :line n :msg "expected key = value"))))

fn tableStep a: ParseState n: Int64 t: String -> ParseState
  (let [(name (stringTrim (optionOr (stringSlice t 1 (- (stringLength t) 1)) "")))]
    (if (and (stringEndsWith? t "]") (keyOk? name))
      (with a :table name)
      (with a :rows (listAppend a.rows [(err (ParseError :line n :msg "invalid table"))]))))

fn lineStep a: ParseState ln: (Pair Int64 String) -> ParseState
  (let [(n (+ (pairFirst ln) 1))
        (t (stringTrim (pairSecond ln)))]
    (if (or (stringEmpty? t) (stringStartsWith? t "#"))
      a
      (if (stringStartsWith? t "[")
        (tableStep a n t)
        (with a :rows (listAppend a.rows [(parseLine n a.table t)])))))

fn parse text: String -> (List (Result String ParseError))
  (let [(st (fold lineStep (ParseState :table "" :rows []) (enumerate (stringLines text))))]
    st.rows)
