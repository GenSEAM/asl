(module asl-text/ini :x [IniRow IniSection parseIni renderIni] :i [])

(schema IniRow (:f key String) (:f value String))

(schema IniSection (:f name String) (:f rows (List IniRow)))

(schema IniAcc (:f secs (List IniSection)) (:f cur String) (:f err (Option String)))

fn unquote v: String -> String
  (let [(t (stringTrim v)) (n (stringLength t))]
    (if (and (> n 1) (and (stringStartsWith? t "\"") (stringEndsWith? t "\"")))
      (optionOr (stringSlice t 1 (- n 1)) t)
      t))

fn splitKV line: String -> (Option (Pair String String))
  (match (stringIndexOf line "=")
    ((some i)
      (some (pair (stringTrim (optionOr (stringSlice line 0 i) ""))
                  (unquote (optionOr (stringSlice line (+ i 1) (stringLength line)) "")))))
    ((none) (none)))

fn upsertRow rows: (List IniRow) key: String value: String -> (List IniRow)
  (if (listAny? (fn [(r IniRow)] -> Bool (= r.key key)) rows)
    (map (fn [(r IniRow)] -> IniRow (if (= r.key key) (IniRow :key key :value value) r)) rows)
    (listAppend rows (cons (IniRow :key key :value value) [])))

fn ensureSection secs: (List IniSection) name: String -> (List IniSection)
  (if (listAny? (fn [(s IniSection)] -> Bool (= s.name name)) secs)
    secs
    (listAppend secs (cons (IniSection :name name :rows []) [])))

fn upsertSection secs: (List IniSection) name: String key: String value: String -> (List IniSection)
  (if (listAny? (fn [(s IniSection)] -> Bool (= s.name name)) secs)
    (map (fn [(s IniSection)] -> IniSection (if (= s.name name) (with s :rows (upsertRow s.rows key value)) s)) secs)
    (listAppend secs (cons (IniSection :name name :rows (cons (IniRow :key key :value value) [])) [])))

fn stepLine acc: IniAcc line: String -> IniAcc
  (let [(t (stringTrim line))]
    (if (some? acc.err)
      acc
      (if (or (stringEmpty? t) (or (stringStartsWith? t "#") (stringStartsWith? t ";")))
        acc
        (if (stringStartsWith? t "[")
          (if (stringEndsWith? t "]")
            (let [(nm (stringTrim (optionOr (stringSlice t 1 (- (stringLength t) 1)) "")))]
              (with acc :cur nm :secs (ensureSection acc.secs nm)))
            (with acc :err (some (str "ini: bad section header: " t))))
          (match (splitKV t)
            ((some kv)
              (if (stringEmpty? (pairFirst kv))
                (with acc :err (some (str "ini: empty key in line: " t)))
                (with acc :secs (upsertSection acc.secs acc.cur (pairFirst kv) (pairSecond kv)))))
            ((none)
              (with acc :err (some (str "ini: expected key=value: " t)))))))))

fn parseIni text: String -> (Result (List IniSection) String)
  (let [(acc (fold (fn [(a IniAcc) (l String)] -> IniAcc (stepLine a l)) (IniAcc :secs [] :cur "" :err (none)) (stringLines text)))]
    (match acc.err
      ((some e) (err e))
      ((none) (ok acc.secs))))

fn renderRow r: IniRow -> String
  (let [(v r.value)
        (q (and (= (stringTrim v) v) (not (or (stringStartsWith? v "\"") (stringEndsWith? v "\"")))))]
    (if q
      (str r.key "=" v)
      (str r.key "=" "\"" v "\"")))

fn renderSection s: IniSection -> String
  (let [(rows (listSortBy (fn [(r IniRow)] -> String r.key) s.rows))
        (body (stringJoin (map (fn [(r IniRow)] -> String (renderRow r)) rows) "\n"))]
    (if (stringEmpty? s.name)
      body
      (if (stringEmpty? body)
        (str "[" s.name "]")
        (str "[" s.name "]\n" body))))

fn renderIni secs: (List IniSection) -> String
  (let [(sorted (listSortBy (fn [(s IniSection)] -> String s.name) secs))]
    (stringJoin (map (fn [(s IniSection)] -> String (renderSection s)) sorted) "\n\n"))
