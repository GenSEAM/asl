(module asl-port/astUtil
  :x [getType getLineno getEndLineno getStringProp getListProp getObjProp isType?]
  :i [(asl-json/json :a json)])

fn getType j: json/Json -> String
  (mt (json/jsonGet j "_type")
    ((some v) (mt v ((json/jstr s) s) (_ "")))
    ((none) ""))

fn isType? j: json/Json expected: String -> Bool
  (= (getType j) expected)

fn getLineno j: json/Json -> Int64
  (mt (json/jsonGet j "lineno")
    ((some v) (mt v ((json/jint i) i) (_ 0)))
    ((none) 0))

fn getEndLineno j: json/Json -> Int64
  (mt (json/jsonGet j "end_lineno")
    ((some v) (mt v ((json/jint i) i) (_ 0)))
    ((none) 0))

fn getStringProp j: json/Json key: String -> String
  (mt (json/jsonGet j key)
    ((some v) (mt v ((json/jstr s) s) (_ "")))
    ((none) ""))

fn getListProp j: json/Json key: String -> (List json/Json)
  (mt (json/jsonGet j key)
    ((some v) (mt v ((json/jarr xs) xs) (_ (list))))
    ((none) (list)))

fn getObjProp j: json/Json key: String -> (Option json/Json)
  (json/jsonGet j key)
