(module asl-codegen/tests/c99TypeTest
  :d "Unit tests for ISO C99 Type System Mapping, Memory Layout & Tagged Union Architecture."
  :x [testC99PrimitiveTypes
      testC99TypeStr
      testContainerTypes
      testEmitCDefschema
      testEmitCDefenum
      runTests]
  :i [(c99Type :a c99Ty) (ast :a a)])

(df testC99PrimitiveTypes [] -> Bool
  :d "Verifies mapping from ASL primitive types to C99 standard types."
  (do
    (assert (= (c99Ty/c99PrimitiveType "Int64") (some "int64_t")) "Int64 -> int64_t")
    (assert (= (c99Ty/c99PrimitiveType "I64") (some "int64_t")) "I64 -> int64_t")
    (assert (= (c99Ty/c99PrimitiveType "Int") (some "int64_t")) "Int -> int64_t")
    (assert (= (c99Ty/c99PrimitiveType "Int32") (some "int32_t")) "Int32 -> int32_t")
    (assert (= (c99Ty/c99PrimitiveType "I32") (some "int32_t")) "I32 -> int32_t")
    (assert (= (c99Ty/c99PrimitiveType "Float64") (some "double")) "Float64 -> double")
    (assert (= (c99Ty/c99PrimitiveType "F64") (some "double")) "F64 -> double")
    (assert (= (c99Ty/c99PrimitiveType "Float") (some "double")) "Float -> double")
    (assert (= (c99Ty/c99PrimitiveType "Float32") (some "float")) "Float32 -> float")
    (assert (= (c99Ty/c99PrimitiveType "F32") (some "float")) "F32 -> float")
    (assert (= (c99Ty/c99PrimitiveType "Bool") (some "bool")) "Bool -> bool")
    (assert (= (c99Ty/c99PrimitiveType "Unit") (some "void")) "Unit -> void")
    (assert (= (c99Ty/c99PrimitiveType "String") (some "asl_string_t")) "String -> asl_string_t")
    (assert (= (c99Ty/c99PrimitiveType "Str") (some "asl_string_t")) "Str -> asl_string_t")
    (refute (= (c99Ty/c99PrimitiveType "Int64") (some "int32_t")) "Int64 must not map to int32_t")
    (refute (= (c99Ty/c99PrimitiveType "Int64") (some "int")) "Int64 must not map to unadorned int")
    (refute (option-is-some? (c99Ty/c99PrimitiveType "UnknownType")) "Unknown type must return none")
    true))

(df testC99TypeStr [] -> Bool
  :d "Verifies c99TypeStr string conversion for primitives, generics, and records."
  (do
    (assert (= (c99Ty/c99TypeStr "Int64") "int64_t") "c99TypeStr Int64")
    (assert (= (c99Ty/c99TypeStr "Bool") "bool") "c99TypeStr Bool")
    (assert (= (c99Ty/c99TypeStr "int64_t") "int64_t") "c99TypeStr native int64_t")
    (assert (= (c99Ty/c99TypeStr "(Option Int64)") "AslOption_int64_t") "c99TypeStr Option Int64")
    (assert (= (c99Ty/c99TypeStr "(Option String)") "AslOption_asl_string_t") "c99TypeStr Option String")
    (assert (= (c99Ty/c99TypeStr "(List Int64)") "AslSlice_int64_t") "c99TypeStr List Int64")
    (assert (= (c99Ty/c99TypeStr "(List String)") "AslSlice_asl_string_t") "c99TypeStr List String")
    (assert (= (c99Ty/c99TypeStr "Point") "AslPoint") "c99TypeStr Point")
    (assert (= (c99Ty/c99TypeStr "my-record") "AslMyRecord") "c99TypeStr my-record")
    (refute (= (c99Ty/c99TypeStr "Int64") "int32_t") "c99TypeStr Int64 must not be int32_t")
    (refute (= (c99Ty/c99TypeStr "Int64") "int") "c99TypeStr Int64 must not be int")
    true))

(df testContainerTypes [] -> Bool
  :d "Verifies string, option, and slice container definitions."
  (let [(strDef (c99Ty/emitCStringType))
        (optDef (c99Ty/emitCOptionType "Int64"))
        (sliceDef (c99Ty/emitCSliceType "Int64"))]
    (assert (string-contains? strDef "typedef struct {") "strDef header")
    (assert (string-contains? strDef "const char* data;") "strDef data")
    (assert (string-contains? strDef "size_t len;") "strDef len")
    (assert (string-contains? strDef "asl_string_t;") "strDef name")
    (assert (string-contains? optDef "typedef struct {") "optDef header")
    (assert (string-contains? optDef "bool hasValue;") "optDef hasValue")
    (assert (string-contains? optDef "int64_t value;") "optDef value")
    (assert (string-contains? optDef "AslOption_int64_t;") "optDef name")
    (assert (string-contains? sliceDef "typedef struct {") "sliceDef header")
    (assert (string-contains? sliceDef "const int64_t* items;") "sliceDef items")
    (assert (string-contains? sliceDef "size_t count;") "sliceDef count")
    (assert (string-contains? sliceDef "AslSlice_int64_t;") "sliceDef name")
    (refute (string-contains? strDef "malloc") "strDef must not allocate")
    (refute (string-contains? optDef "malloc") "optDef must not allocate")
    (refute (string-contains? sliceDef "malloc") "sliceDef must not allocate")
    true))

(df testEmitCDefschema [] -> Bool
  :d "Verifies lowering of AST SchemaNode to C99 struct typedef."
  (let [(f1 (a/AstField :name "x" :type "Int64" :docstring "" :default (none) :json (none)))
        (f2 (a/AstField :name "y" :type "Int64" :docstring "" :default (none) :json (none)))
        (sNode (a/SchemaNode :name "Point" :typeVars (list) :fields (list f1 f2) :jsonCase (none)))
        (sOut (c99Ty/emitCDefschema sNode))
        (f3 (a/AstField :name "is-empty?" :type "Bool" :docstring "" :default (none) :json (none)))
        (f4 (a/AstField :name "default" :type "Int64" :docstring "" :default (none) :json (none)))
        (sNode2 (a/SchemaNode :name "user-status" :typeVars (list) :fields (list f3 f4) :jsonCase (none)))
        (sOut2 (c99Ty/emitCDefschema sNode2))
        (badField (a/AstField :name "" :type "Int64" :docstring "" :default (none) :json (none)))
        (badNode (a/SchemaNode :name "Bad" :typeVars (list) :fields (list badField) :jsonCase (none)))
        (badOut (c99Ty/emitCDefschema badNode))]
    (assert (string-contains? sOut "typedef struct AslPoint_s {") "Point struct header")
    (assert (string-contains? sOut "int64_t x;") "Point field x")
    (assert (string-contains? sOut "int64_t y;") "Point field y")
    (assert (string-contains? sOut "} AslPoint;") "Point struct footer")
    (assert (string-contains? sOut2 "typedef struct AslUserStatus_s {") "UserStatus struct header")
    (assert (string-contains? sOut2 "bool is_empty;") "UserStatus field is_empty")
    (assert (string-contains? sOut2 "int64_t asl_default;") "UserStatus keyword mangling")
    (assert (string-contains? sOut2 "} AslUserStatus;") "UserStatus struct footer")
    (refute (string-contains? badOut "typedef struct") "emitCDefschema must reject empty field names")
    (refute (string-contains? sOut "-") "emitted struct must not contain dashes")
    (assert (= badOut "") "bad schema produces empty string")
    true))

(df testEmitCDefenum [] -> Bool
  :d "Verifies lowering of AST EnumNode to C99 tagged union."
  (let [(c1 (a/EnumCase :name "active" :fields (list) :docstring ""))
        (c2 (a/EnumCase :name "inactive" :fields (list) :docstring ""))
        (en (a/EnumNode :name "Status" :typeVars (list) :cases (list c1 c2)))
        (eOut (c99Ty/emitCDefenum en))
        (p1 (a/Param :name "radius" :type "Float64"))
        (c3 (a/EnumCase :name "circle" :fields (list p1) :docstring ""))
        (p2 (a/Param :name "w" :type "Float64"))
        (p3 (a/Param :name "h" :type "Float64"))
        (c4 (a/EnumCase :name "rectangle" :fields (list p2 p3) :docstring ""))
        (en2 (a/EnumNode :name "Shape" :typeVars (list) :cases (list c3 c4)))
        (eOut2 (c99Ty/emitCDefenum en2))
        (badCase (a/EnumCase :name "" :fields (list) :docstring ""))
        (badNode (a/EnumNode :name "BadEnum" :typeVars (list) :cases (list badCase)))
        (badOut (c99Ty/emitCDefenum badNode))]
    (assert (string-contains? eOut "typedef enum {") "Status tag enum header")
    (assert (string-contains? eOut "ASL_STATUS_ACTIVE") "Status active constant")
    (assert (string-contains? eOut "ASL_STATUS_INACTIVE") "Status inactive constant")
    (assert (string-contains? eOut "} AslStatusTag;") "Status tag enum footer")
    (assert (string-contains? eOut "typedef union {") "Status data union header")
    (assert (string-contains? eOut "} AslStatusData;") "Status data union footer")
    (assert (string-contains? eOut "typedef struct AslStatus_s {") "Status struct header")
    (assert (string-contains? eOut "AslStatusTag tag;") "Status tag member")
    (assert (string-contains? eOut "AslStatusData data;") "Status data member")
    (assert (string-contains? eOut "} AslStatus;") "Status struct footer")
    (assert (string-contains? eOut2 "ASL_SHAPE_CIRCLE") "Shape circle constant")
    (assert (string-contains? eOut2 "ASL_SHAPE_RECTANGLE") "Shape rectangle constant")
    (assert (string-contains? eOut2 "double radius;") "Shape circle payload field")
    (assert (string-contains? eOut2 "} circle;") "Shape circle payload struct")
    (assert (string-contains? eOut2 "double w;") "Shape rectangle payload field w")
    (assert (string-contains? eOut2 "double h;") "Shape rectangle payload field h")
    (assert (string-contains? eOut2 "} rectangle;") "Shape rectangle payload struct")
    (refute (string-contains? badOut "typedef struct") "emitCDefenum must reject empty case names")
    (refute (string-contains? eOut "-") "emitted enum must not contain dashes")
    (assert (= badOut "") "bad enum produces empty string")
    true))

(df runTests [] -> Bool
  :d "Executes all c99Type test suites."
  (do
    (assert (testC99PrimitiveTypes) "testC99PrimitiveTypes must pass")
    (assert (testC99TypeStr) "testC99TypeStr must pass")
    (assert (testContainerTypes) "testContainerTypes must pass")
    (assert (testEmitCDefschema) "testEmitCDefschema must pass")
    (assert (testEmitCDefenum) "testEmitCDefenum must pass")
    true))
