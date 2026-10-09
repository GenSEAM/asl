(module asl-target-swift/types :x [emitSwiftType swiftMangleIdent emitSwiftHeader emitSwiftBinop emitSwiftAtom isSwiftKeyword?] :i [])

fn isSwiftKeyword? s: Str -> Bool
  (or (or (or (or (or (= s "class") (= s "struct")) (or (= s "enum") (= s "protocol"))) (or (or (= s "func") (= s "let")) (or (= s "var") (= s "init")))) (or (or (or (= s "import") (= s "public")) (or (= s "private") (= s "internal"))) (or (or (= s "fileprivate") (= s "open")) (or (= s "static") (= s "typealias"))))) (or (or (or (or (= s "if") (= s "else")) (or (= s "guard") (= s "switch"))) (or (or (= s "case") (= s "default")) (or (= s "for") (= s "while")))) (or (or (or (= s "return") (= s "throw")) (or (= s "try") (= s "catch"))) (or (or (= s "break") (= s "continue")) (or (= s "where") (= s "in"))))))

fn swiftMangleIdent id: Str -> Str
  (let [(clean (stringReplace (stringReplace id "/" "_") "-" "_"))]
    (if (isSwiftKeyword? clean)
      (str "`" clean "`")
      clean))

fn emitSwiftType ty: Str -> Str
  (let [(t (stringTrim ty))]
    (cond
      ((or (or (= t "I64") (= t "Int")) (= t "Int64")) "Int")
      ((or (= t "I32") (= t "Int32")) "Int32")
      ((or (or (= t "F64") (= t "Float")) (= t "Float64")) "Double")
      ((or (= t "F32") (= t "Float32")) "Float")
      ((or (= t "Str") (= t "String")) "String")
      ((or (= t "Bool") (= t "Boolean")) "Bool")
      ((or (or (or (= t "Unit") (= t "Void")) (= t "()")) (= t "")) "Void")
      ((= t "Bytes") "Data")
      ((= t "Any") "Any")
      ((and (stringStartsWith? t "(List ") (stringEndsWith? t ")"))
        (let [(inner (stringSlice t 6 (- (stringLength t) 1)))]
          (str "[" (emitSwiftType (optionOr inner "")) "]")))
      ((stringStartsWith? t "List ")
        (let [(inner (stringSlice t 5 (stringLength t)))]
          (str "[" (emitSwiftType (optionOr inner "")) "]")))
      ((and (stringStartsWith? t "(Option ") (stringEndsWith? t ")"))
        (let [(inner (stringSlice t 8 (- (stringLength t) 1)))]
          (str (emitSwiftType (optionOr inner "")) "?")))
      ((stringStartsWith? t "Option ")
        (let [(inner (stringSlice t 7 (stringLength t)))]
          (str (emitSwiftType (optionOr inner "")) "?")))
      ((and (stringStartsWith? t "(Map ") (stringEndsWith? t ")"))
        (let [(inner (stringSlice t 5 (- (stringLength t) 1)))
              (parts (stringSplit (stringTrim (optionOr inner "")) " "))]
          (if (>= (listLength parts) 2)
            (str "[" (emitSwiftType (optionOr (listGet parts 0) "String")) ": " (emitSwiftType (optionOr (listGet parts 1) "Any")) "]")
            "[String: Any]")))
      ((stringStartsWith? t "Map ")
        (let [(inner (stringSlice t 4 (stringLength t)))
              (parts (stringSplit (stringTrim (optionOr inner "")) " "))]
          (if (>= (listLength parts) 2)
            (str "[" (emitSwiftType (optionOr (listGet parts 0) "String")) ": " (emitSwiftType (optionOr (listGet parts 1) "Any")) "]")
            "[String: Any]")))
      ((and (stringStartsWith? t "(Result ") (stringEndsWith? t ")"))
        (let [(inner (stringSlice t 8 (- (stringLength t) 1)))
              (parts (stringSplit (stringTrim (optionOr inner "")) " "))]
          (if (>= (listLength parts) 2)
            (str "Result<" (emitSwiftType (optionOr (listGet parts 0) "Void")) ", " (emitSwiftType (optionOr (listGet parts 1) "Error")) ">")
            "Result<Void, Error>")))
      ((stringStartsWith? t "Result ")
        (let [(inner (stringSlice t 7 (stringLength t)))
              (parts (stringSplit (stringTrim (optionOr inner "")) " "))]
          (if (>= (listLength parts) 2)
            (str "Result<" (emitSwiftType (optionOr (listGet parts 0) "Void")) ", " (emitSwiftType (optionOr (listGet parts 1) "Error")) ">")
            "Result<Void, Error>")))
      (else (swiftMangleIdent t))))

fn emitSwiftHeader includesUi: Bool -> Str
  (if includesUi
    (str "import Foundation\nimport SwiftUI\nimport Combine\n\n")
    (str "import Foundation\n\n"))

fn emitSwiftBinop op: Str left: Str right: Str -> Str
  (let [(cleanOp (cond
                  ((or (= op "=") (= op "==")) "==")
                  ((= op "!=") "!=")
                  ((= op "and") "&&")
                  ((= op "or") "||")
                  ((or (= op "//") (= op "idiv")) "/")
                  (else op)))]
    (str left " " cleanOp " " right))

fn emitSwiftAtom s: Str -> Str
  (cond
    ((= s "true") "true")
    ((= s "false") "false")
    ((or (or (= s "nil") (= s "none")) (= s "()")) "nil")
    ((stringStartsWith? s "\"") s)
    ((or (stringStartsWith? s "-")
         (and (>= (optionOr (stringSlice s 0 1) "") "0")
              (<= (optionOr (stringSlice s 0 1) "") "9"))) s)
    (else (swiftMangleIdent s)))
