(module asl-target-py/emitPy
  :d "Standalone Python 3.11+ emitter backend for AgentScript under ADR D93."
  :x [emitPyType
      emitPyFn
      emitPyClass
      emitPyEnum
      emitPythonSource
      emitPythonProgram]
  :i [(ast :a a) (reader :a rd)])

(df pyMangleIdent [(id Str)] -> Str
  :d "Converts kebab-case identifiers to Python snake_case identifiers."
  (string-replace (string-replace id "/" "_") "-" "_"))

(df cleanDocstring [(ds Str)] -> Str
  :d "Normalizes a docstring by stripping wrapping quotes."
  (let [(trimmed (string-trim ds))]
    (if (and (string-starts-with? trimmed "\"")
             (string-ends-with? trimmed "\"")
             (>= (string-length trimmed) 2))
        (option-or (string-slice trimmed 1 (- (string-length trimmed) 1)) "")
        trimmed)))

(df emitPyType [(ty Str)] -> Str
  :d "Maps AgentScript type to idiomatic Python 3.11+ type annotation."
  (let [(t (string-trim ty))]
    (cond
      ((or (= t "I64") (= t "I32") (= t "Int") (= t "Int64") (= t "Int32")) "int")
      ((or (= t "F64") (= t "F32") (= t "Float") (= t "Float64")) "float")
      ((or (= t "Str") (= t "String")) "str")
      ((= t "Bool") "bool")
      ((or (= t "Unit") (= t "Void") (= t "")) "None")
      ((= t "Any") "Any")
      ((and (string-starts-with? t "(List ") (string-ends-with? t ")"))
       (let [(inner (string-slice t 6 (- (string-length t) 1)))]
         (str "list[" (emitPyType (option-or inner "")) "]")))
      ((string-starts-with? t "List ")
       (let [(inner (string-slice t 5 (string-length t)))]
         (str "list[" (emitPyType (option-or inner "")) "]")))
      ((and (string-starts-with? t "(Option ") (string-ends-with? t ")"))
       (let [(inner (string-slice t 8 (- (string-length t) 1)))]
         (str (emitPyType (option-or inner "")) " | None")))
      ((string-starts-with? t "Option ")
       (let [(inner (string-slice t 7 (string-length t)))]
         (str (emitPyType (option-or inner "")) " | None")))
      ((and (string-starts-with? t "(Map ") (string-ends-with? t ")"))
       (let [(inner (string-slice t 5 (- (string-length t) 1)))
             (parts (string-split (string-trim (option-or inner "")) " "))]
         (if (>= (list-length parts) 2)
             (str "dict[" (emitPyType (option-or (list-get parts 0) "Any")) ", "
                         (emitPyType (option-or (list-get parts 1) "Any")) "]")
             "dict[str, Any]")))
      (:else t))))

(df emitPyAtom [(s Str)] -> Str
  :d "Lowers an S-expression terminal atom to a Python expression."
  (cond
    ((= s "true") "True")
    ((= s "false") "False")
    ((or (= s "nil") (= s "none") (= s "()")) "None")
    ((string-starts-with? s "\"") s)
    ((or (string-starts-with? s "-")
         (and (>= (option-or (string-slice s 0 1) "") "0")
              (<= (option-or (string-slice s 0 1) "") "9")))
     s)
    (:else (pyMangleIdent s))))

(df emitPyBinop [(op Str) (args (List rd/SExpr))] -> Str
  :d "Lowers n-ary operator expression to Python infix expression."
  (cond
    ((list-empty? args)
     (if (or (= op "+") (= op "-")) "0" (if (or (= op "*") (= op "/")) "1" "True")))
    ((= (list-length args) 1)
     (if (= op "-")
         (str "-" (emitPyExpr (option-or (list-head args) (rd/sexprAtom ""))))
         (emitPyExpr (option-or (list-head args) (rd/sexprAtom "")))))
    (:else
     (string-join (map emitPyExpr args) (str " " op " ")))))

(df emitPyList [(items (List rd/SExpr))] -> Str
  :d "Lowers a parenthesized S-expression list to Python expression syntax."
  (if (list-empty? items)
      "None"
      (let [(head (rd/sexprHead (option-or (list-head items) (rd/sexprAtom ""))))
            (args (option-or (list-tail items) (list)))]
        (cond
          ((= head "+")    (emitPyBinop "+" args))
          ((= head "-")    (emitPyBinop "-" args))
          ((= head "*")    (emitPyBinop "*" args))
          ((= head "/")    (emitPyBinop "/" args))
          ((or (= head "mod") (= head "%")) (emitPyBinop "%" args))
          ((or (= head "=") (= head "=="))  (emitPyBinop "==" args))
          ((= head "!=")   (emitPyBinop "!=" args))
          ((= head "<")    (emitPyBinop "<" args))
          ((= head "<=")   (emitPyBinop "<=" args))
          ((= head ">")    (emitPyBinop ">" args))
          ((= head ">=")   (emitPyBinop ">=" args))
          ((= head "and")  (emitPyBinop "and" args))
          ((= head "or")   (emitPyBinop "or" args))
          ((= head "not")
           (str "not (" (emitPyExpr (option-or (list-head args) (rd/sexprAtom "False"))) ")"))
          ((= head "if")
           (let [(c (option-or (list-get args 0) (rd/sexprAtom "True")))
                 (t (option-or (list-get args 1) (rd/sexprAtom "None")))
                 (e (option-or (list-get args 2) (rd/sexprAtom "None")))]
             (str "(" (emitPyExpr t) " if " (emitPyExpr c) " else " (emitPyExpr e) ")")))
          ((= head "str")
           (if (list-empty? args)
               "\"\""
               (str "(" (string-join (map (fn [(x rd/SExpr)] -> Str (str "str(" (emitPyExpr x) ")")) args) " + ") ")")))
          ((= head "list")
           (str "[" (string-join (map emitPyExpr args) ", ") "]"))
          ((= head "tuple")
           (str "(" (string-join (map emitPyExpr args) ", ") ")"))
          ((= head "dict")
           (str "{" (string-join (map emitPyExpr args) ", ") "}"))
          (:else
           (let [(fnName (pyMangleIdent head))
                 (renderedArgs (map emitPyExpr args))]
             (str fnName "(" (string-join renderedArgs ", ") ")")))))))

(df emitPyExpr [(e rd/SExpr)] -> Str
  :d "Recursively lowers an SExpr to a Python 3.11 expression string."
  (mt e
    ((rd/sexprAtom v) (emitPyAtom v))
    ((rd/sexprList items) (emitPyList items))
    ((rd/sexprVect items)
     (str "[" (string-join (map emitPyExpr items) ", ") "]"))))

(df emitPyParam [(p a/Param)] -> Str
  :d "Emits a single typed parameter annotation for Python."
  (let [(pName (pyMangleIdent (.-name p)))
        (pType (emitPyType (.-type p)))]
    (str pName ": " pType)))

(df emitPyFn [(d a/DefunNode)] -> Str
  :d "Emits an idiomatic Python 3.11+ function definition."
  (let [(name (pyMangleIdent (.-name d)))
        (params (string-join (map emitPyParam (.-params d)) ", "))
        (ret (emitPyType (.-retType d)))
        (doc (if (string-empty? (.-docstring d))
                 ""
                 (str "    \"\"\"" (cleanDocstring (.-docstring d)) "\"\"\"\n")))
        (bodyExpr (if (list-empty? (.-body d))
                      "None"
                      (emitPyExpr (option-or (list-get (.-body d) (- (list-length (.-body d)) 1))
                                             (rd/sexprAtom "None")))))]
    (str "def " name "(" params ") -> " ret ":\n" doc "    return " bodyExpr "\n")))

(df emitPyField [(f a/AstField)] -> Str
  :d "Emits a single dataclass field annotation for Python."
  (let [(fName (pyMangleIdent (.-name f)))
        (fType (emitPyType (.-type f)))
        (defPart (mt (.-default f)
                   ((some d) (str " = " d))
                   ((none) "")))]
    (str "    " fName ": " fType defPart "\n")))

(df emitPyClass [(s a/SchemaNode)] -> Str
  :d "Emits an idiomatic Python 3.11+ dataclass definition."
  (let [(name (.-name s))
        (fields (if (list-empty? (.-fields s))
                    "    pass\n"
                    (string-join (map emitPyField (.-fields s)) "")))]
    (str "@dataclass\nclass " name ":\n" fields)))

(df emitPyCase [(c a/EnumCase)] -> Str
  :d "Emits a single Enum member variant with auto() value."
  (let [(cName (.-name c))]
    (str "    " cName " = auto()\n")))

(df enumHasFields? [(cases (List a/EnumCase))] -> Bool
  :d "Returns true if any enum case contains payload fields."
  (fold (fn [(acc Bool) (c a/EnumCase)] -> Bool
          (or acc (> (list-length (.-fields c)) 0)))
        false
        cases))

(df emitPyEnumCaseClass [(enumName Str) (c a/EnumCase)] -> Str
  :d "Emits a dataclass for an enum case with payload fields."
  (let [(cName (str enumName (.-name c)))
        (fields (if (list-empty? (.-fields c))
                    "    pass\n"
                    (string-join (map (fn [(p a/Param)] -> Str
                                        (str "    " (pyMangleIdent (.-name p)) ": " (emitPyType (.-type p)) "\n"))
                                      (.-fields c)) "")))]
    (str "@dataclass\nclass " cName ":\n" fields)))

(df emitPyEnum [(e a/EnumNode)] -> Str
  :d "Emits an idiomatic Python 3.11+ Enum or tagged union representation."
  (let [(name (.-name e))
        (cases (.-cases e))]
    (if (enumHasFields? cases)
        (let [(classes (string-join (map (fn [(c a/EnumCase)] -> Str (emitPyEnumCaseClass name c)) cases) "\n"))
              (typeUnion (string-join (map (fn [(c a/EnumCase)] -> Str (str name (.-name c))) cases) " | "))]
          (str classes "\n" name " = " typeUnion "\n"))
        (let [(body (if (list-empty? cases)
                        "    pass\n"
                        (string-join (map emitPyCase cases) "")))]
          (str "class " name "(Enum):\n" body)))))

(df emitPythonHeader [] -> Str
  :d "Emits standard Python 3.11+ preamble and imports."
  (str "from __future__ import annotations\n"
       "from dataclasses import dataclass\n"
       "from enum import Enum, auto\n"
       "from typing import Any, Optional, Union\n\n"))

(df emitTopForm [(tf a/TopForm)] -> Str
  :d "Emits a single top-level ASL form in Python."
  (mt tf
    ((a/topSchema s) (emitPyClass s))
    ((a/topEnum e)   (emitPyEnum e))
    ((a/topDefun d)  (emitPyFn d))
    ((a/topModule _) "")))

(df unpackForms [(forms (List a/TopForm))] -> (List a/TopForm)
  :d "Unpacks topModule forms if declarations are nested inside."
  (if (and (= (list-length forms) 1)
           (mt (list-head forms)
             ((some (a/topModule _)) true)
             (:else false)))
      (mt (list-head forms)
        ((some (a/topModule m)) (.-defs m))
        (:else forms))
      forms))

(df emitPythonSource [(forms (List a/TopForm))] -> Str
  :d "Generates a complete Python 3.11+ module with dataclass imports and definitions."
  (let [(effForms (unpackForms forms))
        (hdr (emitPythonHeader))
        (rendered (filter (fn [(s Str)] -> Bool (not (string-empty? s)))
                          (map emitTopForm effForms)))
        (body (string-join rendered "\n"))]
    (str hdr body)))

(df emitPythonProgram [(forms (List a/TopForm)) (opts (Map Str Str))] -> (Result Str Str)
  :d "Program emitter for targetRegistry integration."
  (ok (emitPythonSource forms)))
