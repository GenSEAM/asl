(module asl-target-py/tests/emitPyTest
  :d "Unit tests for standalone Python platform leaf code generator with dual-polarity D77 refutations."
  :x [runTests]
  :i [(asl-target-py/emitPy :a py) (ast :a a) (reader :a rd)])

(df testPyType [] -> Bool
  :d "Verifies AgentScript to Python type mapping with positive assertions and D77 refutations."
  (let [(t1 (py/emitPyType "I64"))
        (t2 (py/emitPyType "I32"))
        (t3 (py/emitPyType "Int"))
        (t4 (py/emitPyType "Bool"))
        (t5 (py/emitPyType "Str"))
        (t6 (py/emitPyType "F64"))
        (t7 (py/emitPyType "Float"))
        (t8 (py/emitPyType "Unit"))
        (t9 (py/emitPyType "CustomType"))
        (t10 (py/emitPyType "(List I64)"))
        (t11 (py/emitPyType "(Option Str)"))]
    (assert (= t1 "int") "I64 must map to int")
    (assert (= t2 "int") "I32 must map to int")
    (assert (= t3 "int") "Int must map to int")
    (assert (= t4 "bool") "Bool must map to bool")
    (assert (= t5 "str") "Str must map to str")
    (assert (= t6 "float") "F64 must map to float")
    (assert (= t7 "float") "Float must map to float")
    (assert (= t8 "None") "Unit must map to None")
    (assert (= t9 "CustomType") "CustomType must be preserved")
    (assert (= t10 "list[int]") "(List I64) must map to list[int]")
    (assert (= t11 "str | None") "(Option Str) must map to str | None")
    (refute (= t1 "int64") "Must refute Go-style int64")
    (refute (= t1 "i64") "Must refute Rust-style i64")
    (refute (= t4 "boolean") "Must refute Java-style boolean")
    (refute (= t5 "string") "Must refute Go-style string")
    (refute (= t6 "float64") "Must refute Go-style float64")
    (refute (= t8 "void") "Must refute C-style void")
    (refute (= t8 "") "Must refute empty return for Unit in Python")
    (refute (string-contains? t10 "List[") "Must refute deprecated typing.List in Python 3.11+")
    (refute (string-contains? t11 "Optional[") "Must refute typing.Optional in favor of PEP 604 | None")
    true))

(df testPyFn [] -> Bool
  :d "Verifies Python function emission with docstrings and return types under D77."
  (let [(fnNode (a/DefunNode :name "add-numbers"
                             :typeVars (list)
                             :isExported true
                             :effect false
                             :params (list (a/Param :name "first-num" :type "I64")
                                           (a/Param :name "second-num" :type "I64"))
                             :retType "I64"
                             :docstring "\"Adds two integers.\""
                             :body (list (rd/sexprList (list (rd/sexprAtom "+")
                                                             (rd/sexprAtom "first-num")
                                                             (rd/sexprAtom "second-num"))))))
        (fnCode (py/emitPyFn fnNode))]
    (assert (string-contains? fnCode "def add_numbers(first_num: int, second_num: int) -> int:") "Function signature must use snake_case and type annotations")
    (assert (string-contains? fnCode "\"\"\"Adds two integers.\"\"\"") "Docstring must be wrapped in PEP 257 triple quotes")
    (assert (string-contains? fnCode "return first_num + second_num") "Body must emit return statement with infix expression")
    (refute (string-contains? fnCode "func ") "Must refute Go function syntax")
    (refute (string-contains? fnCode "pub fn") "Must refute Rust function syntax")
    (refute (string-contains? fnCode "add-numbers") "Must refute kebab-case in Python identifiers")
    (refute (string-contains? fnCode "first-num") "Must refute kebab-case in Python parameter identifiers")
    (refute (string-contains? fnCode "{") "Must refute curly braces in Python function body")
    true))

(df testPyClass [] -> Bool
  :d "Verifies Python dataclass class generation for SchemaNode under D77."
  (let [(sNode (a/SchemaNode :name "UserData"
                             :typeVars (list)
                             :fields (list (a/AstField :name "user-id" :type "I64" :docstring "" :default (none) :json (none))
                                           (a/AstField :name "user-name" :type "Str" :docstring "" :default (none) :json (none))
                                           (a/AstField :name "is-active" :type "Bool" :docstring "" :default (some "True") :json (none)))
                             :jsonCase (none)))
        (clsCode (py/emitPyClass sNode))]
    (assert (string-contains? clsCode "@dataclass") "Class must carry @dataclass decorator")
    (assert (string-contains? clsCode "class UserData:") "Class header must match class <name>:")
    (assert (string-contains? clsCode "user_id: int") "Field user_id must be annotated with int")
    (assert (string-contains? clsCode "user_name: str") "Field user_name must be annotated with str")
    (assert (string-contains? clsCode "is_active: bool = True") "Field is_active must include default value")
    (refute (string-contains? clsCode "type UserData struct") "Must refute Go struct syntax")
    (refute (string-contains? clsCode "pub struct") "Must refute Rust struct syntax")
    (refute (string-contains? clsCode "user-id") "Must refute kebab-case in field names")
    (refute (string-contains? clsCode "interface UserData") "Must refute TypeScript interface syntax")
    true))

(df testPyEnum [] -> Bool
  :d "Verifies Python Enum and tagged union emission under D77."
  (let [(simpleEnum (a/EnumNode :name "Status"
                                :typeVars (list)
                                :cases (list (a/EnumCase :name "Pending" :fields (list) :docstring "")
                                             (a/EnumCase :name "Active" :fields (list) :docstring "")
                                             (a/EnumCase :name "Completed" :fields (list) :docstring ""))))
        (eCode (py/emitPyEnum simpleEnum))]
    (assert (string-contains? eCode "class Status(Enum):") "Simple enum must inherit from Enum")
    (assert (string-contains? eCode "Pending = auto()") "Case Pending must use auto()")
    (assert (string-contains? eCode "Active = auto()") "Case Active must use auto()")
    (assert (string-contains? eCode "Completed = auto()") "Case Completed must use auto()")
    (refute (string-contains? eCode "type Status int") "Must refute Go enum type")
    (refute (string-contains? eCode "iota") "Must refute Go iota")
    (refute (string-contains? eCode "pub enum") "Must refute Rust enum syntax")
    (let [(unionEnum (a/EnumNode :name "Shape"
                                 :typeVars (list)
                                 :cases (list (a/EnumCase :name "Circle" :fields (list (a/Param :name "radius" :type "F64")) :docstring "")
                                              (a/EnumCase :name "Square" :fields (list (a/Param :name "side" :type "F64")) :docstring ""))))
          (uCode (py/emitPyEnum unionEnum))]
      (assert (string-contains? uCode "@dataclass\nclass ShapeCircle:") "Tagged union case Circle must emit dataclass")
      (assert (string-contains? uCode "radius: float") "Tagged union case Circle must contain typed field")
      (assert (string-contains? uCode "Shape = ShapeCircle | ShapeSquare") "Tagged union must emit type alias")
      (refute (string-contains? uCode "class Shape(Enum):") "Tagged union must refute simple Enum inheritance")
      true)))

(df testPythonSourceAndProgram [] -> Bool
  :d "Verifies full module source and program emission with targetRegistry integration."
  (let [(src (str "(dfs Coordinate\n"
                  "  (:f lat F64 \"latitude\")\n"
                  "  (:f lon F64 \"longitude\"))\n\n"
                  "(df calculate-distance [(p1 Coordinate) (p2 Coordinate)] -> F64\n"
                  "  :d \"Calculates distance.\"\n"
                  "  0.0)\n"))
        (parseRes (a/parse src))]
    (assert (is-ok? parseRes) "Source parses successfully")
    (refute (is-err? parseRes) "Source refutes parse error")
    (mt parseRes
      ((err _) false)
      ((ok forms)
       (let [(pySource (py/emitPythonSource forms))
             (progRes (py/emitPythonProgram forms (map-empty)))]
         (assert (string-contains? pySource "from __future__ import annotations") "Source contains __future__ annotations")
         (assert (string-contains? pySource "from dataclasses import dataclass") "Source contains dataclass import")
         (assert (string-contains? pySource "class Coordinate:") "Source contains Coordinate class")
         (assert (string-contains? pySource "def calculate_distance") "Source contains calculate_distance function")
         (refute (string-contains? pySource "calculate-distance") "Source refutes kebab-case in function name")
         (assert (is-ok? progRes) "emitPythonProgram returns ok")
         (refute (is-err? progRes) "emitPythonProgram refutes err")
         (mt progRes
           ((err _) false)
           ((ok code)
            (do
              (assert (string-contains? code "@dataclass") "Program code contains dataclass")
              (assert (string-contains? code "lat: float") "Program code contains lat field")
              (refute (string-empty? code) "Program code refutes empty string under D77")
              true))))))))

(df testDualPolarityRefutations [] -> Bool
  :d "Verifies dual-polarity D77 refutations against malformed inputs and invalid patterns."
  (let [(emptyProg (py/emitPythonProgram (list) (map-empty)))]
    (assert (is-ok? emptyProg) "Empty forms list still produces valid module envelope")
    (refute (is-err? emptyProg) "Empty forms list refutes error")
    (mt emptyProg
      ((err _) false)
      ((ok code)
       (do
         (assert (string-contains? code "from dataclasses import dataclass") "Empty module has standard imports")
         (refute (string-contains? code "def ") "Empty module refutes function definitions")
         (refute (string-contains? code "class ") "Empty module refutes class definitions")
         true))))
  (let [(emptyFn (py/emitPyFn (a/DefunNode :name "noop" :typeVars (list) :isExported false :effect false :params (list) :retType "Unit" :docstring "" :body (list))))]
    (assert (string-contains? emptyFn "def noop() -> None:") "Empty body defun emits -> None")
    (assert (string-contains? emptyFn "return None") "Empty body defun returns None")
    (refute (string-contains? emptyFn "return 0") "Empty body defun refutes return 0 under D77")
    true))

(df runTests [] -> Bool
  :d "Runs all Python target unit tests."
  (do
    (assert (testPyType) "testPyType must pass")
    (assert (testPyFn) "testPyFn must pass")
    (assert (testPyClass) "testPyClass must pass")
    (assert (testPyEnum) "testPyEnum must pass")
    (assert (testPythonSourceAndProgram) "testPythonSourceAndProgram must pass")
    (assert (testDualPolarityRefutations) "testDualPolarityRefutations must pass")
    true))
