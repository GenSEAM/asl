(module asl-checker/tests/foreignCheckTest
  :x [runTests]
  :i [(asl-parser/ast :a a) (asl-checker/check :a c) (asl-checker/types :a ty) (asl-checker/foreign :a ff)])

; (:m :ref FFI1 :do "the checker side of foreign: a well-formed declaration checks clean, and each rule (place, effect, signature, parameter and result types, library and symbol names) fails with its own code")
fn diagsOf src: String -> (List ty/Diagnostic)
  (match (a/parseForTypeCheck src)
    ((ok forms) (c/checkModuleSource forms (mapEmpty) "probe.asl" src))
    ((err e) (list (ty/Diagnostic :code "parse" :message e.msg :msg e.msg :line 1 :col 1 :path "probe.asl"))))

fn codesOf src: String -> (List String)
  (map (fn [(d ty/Diagnostic)] -> String d.code) (diagsOf src))

fn messagesOf src: String -> String
  (stringJoin (map (fn [(d ty/Diagnostic)] -> String (str d.code " " d.message)) (diagsOf src)) "; ")

fn probe decl: String -> String
  (str "(module probe :x [go] :i [])\n" decl "\nfn ! go -> Int64\n  1\n")

fn good -> String
  (probe "fn ! cbrt x: Float64 -> Float64\n  (foreign \"m\" \"cbrt\" \"f64 -> f64\")\nfn ! crc x: Int64 b: Bytes -> (Result Int64 String)\n  (foreign \"z\" \"crc32\" \"u64 bytes32 -> u64\")\nfn ! say s: String -> Unit\n  (foreign \"c\" \"puts\" \"cstr -> void\")")

fn ! expectCode label: String src: String code: String -> Bool
  (do (assert (listContains? (codesOf src) code) (str label ": wants " code ", got " (messagesOf src)))
      true)

fn ! testClean -> Bool
  (do (assert (listEmpty? (diagsOf (good))) (str "well-formed foreign fns check clean: " (messagesOf (good))))
      (assert (listEmpty? (diagsOf (probe "fn foreign a: String b: String c: String -> Int64\n  1\nfn ! use -> Int64\n  (foreign \"a\" \"b\" \"c\")")))
              (str "a module that defines its own foreign is left alone: " (messagesOf (probe "fn foreign a: String b: String c: String -> Int64\n  1\nfn ! use -> Int64\n  (foreign \"a\" \"b\" \"c\")"))))
      (assert (listEmpty? (diagsOf (probe "fn names xs: (List Int64) -> Int64\n  (let [(foreign (listLength xs))] (+ foreign 1))")))
              (str "a local binding named foreign is not a foreign call: " (messagesOf (probe "fn names xs: (List Int64) -> Int64\n  (let [(foreign (listLength xs))] (+ foreign 1))"))))
      true)

fn ! testRules -> Bool
  (do (expectCode "no !" (probe "fn cbrt x: Float64 -> Float64\n  (foreign \"m\" \"cbrt\" \"f64 -> f64\")") "ERR_FOREIGN_EFFECT")
      (expectCode "inside other code" (probe "fn ! cbrt x: Float64 -> Float64\n  (+ 1.0 (foreign \"m\" \"cbrt\" \"f64 -> f64\"))") "ERR_FOREIGN_PLACE")
      (expectCode "after another form" (probe "fn ! cbrt x: Float64 -> Float64\n  (println \"x\")\n  (foreign \"m\" \"cbrt\" \"f64 -> f64\")") "ERR_FOREIGN_PLACE")
      (expectCode "no arrow" (probe "fn ! cbrt x: Float64 -> Float64\n  (foreign \"m\" \"cbrt\" \"f64 f64\")") "ERR_FOREIGN_SIG")
      (expectCode "unknown C type" (probe "fn ! cbrt x: Float64 -> Float64\n  (foreign \"m\" \"cbrt\" \"f32 -> f64\")") "ERR_FOREIGN_SIG")
      (expectCode "param count" (probe "fn ! cbrt x: Float64 y: Float64 -> Float64\n  (foreign \"m\" \"cbrt\" \"f64 -> f64\")") "ERR_FOREIGN_SIG")
      (expectCode "param type" (probe "fn ! cbrt x: Int64 -> Float64\n  (foreign \"m\" \"cbrt\" \"f64 -> f64\")") "ERR_FOREIGN_SIG")
      (expectCode "bytes is not String" (probe "fn ! crc x: Int64 b: String -> Int64\n  (foreign \"z\" \"crc32\" \"u64 bytes32 -> u64\")") "ERR_FOREIGN_SIG")
      (expectCode "result type" (probe "fn ! cbrt x: Float64 -> Int64\n  (foreign \"m\" \"cbrt\" \"f64 -> f64\")") "ERR_FOREIGN_SIG")
      (expectCode "result error type" (probe "fn ! cbrt x: Float64 -> (Result Float64 Int64)\n  (foreign \"m\" \"cbrt\" \"f64 -> f64\")") "ERR_FOREIGN_SIG")
      (expectCode "library flag" (probe "fn ! cbrt x: Float64 -> Float64\n  (foreign \"-Wl,x\" \"cbrt\" \"f64 -> f64\")") "ERR_FOREIGN_SIG")
      (expectCode "symbol name" (probe "fn ! cbrt x: Float64 -> Float64\n  (foreign \"m\" \"cb rt\" \"f64 -> f64\")") "ERR_FOREIGN_SIG")
      (expectCode "argument count" (probe "fn ! cbrt x: Float64 -> Float64\n  (foreign \"m\" \"cbrt\")") "ERR_FOREIGN_SIG")
      (expectCode "literal arguments" (probe "fn ! cbrt x: Float64 -> Float64\n  (foreign \"m\" (str \"cb\" \"rt\") \"f64 -> f64\")") "ERR_FOREIGN_SIG")
      (expectCode "top-level expression" "(module probe :x [] :i [])\n(foreign \"m\" \"cbrt\" \"f64 -> f64\")\n" "ERR_FOREIGN_PLACE")
      true)

fn ! testSig -> Bool
  (do (assert (= (ff/parseSig "u64 bytes32 -> u64") (ok (ff/ForeignSig :args (list "u64" "bytes32") :ret "u64"))) "a signature parses into C kinds")
      (assert (= (ff/parseSig "-> void") (ok (ff/ForeignSig :args (list) :ret "void"))) "a signature may take no arguments")
      (assert (err? (ff/parseSig "void -> f64")) "void is not an argument kind")
      (assert (err? (ff/parseSig "f64 -> str")) "str is not a result kind")
      (assert (= (ff/resultInner "(Result Int64 String)") (some "Int64")) "a Result return names its value type")
      (assert (= (ff/resultInner "(Result Int64 Int64)") (none)) "only String errors are a foreign Result")
      (assert (= (ff/cArgCount "bytes32") 2) "bytes32 crosses as pointer and length")
      (assert (= (ff/cArgCount "cstr") 1) "cstr crosses as one pointer")
      true)

; (:m :ref FFI2 :do "Handle kinds and C failure conventions: handle, handle:F and close:F cross as Handle, !neg goes with i32 or i64 results and !null with cstr or handle results, and a call closes at most one handle")
fn handles -> String
  (probe "fn ! openFile p: String m: String -> (Result Handle String)\n  (foreign \"c\" \"fopen\" \"cstr cstr -> handle:fclose !null\")\nfn ! closeFile f: Handle -> (Result Int64 String)\n  (foreign \"c\" \"fclose\" \"close:fclose -> i32 !neg\")\nfn ! fileNo f: Handle -> Int64\n  (foreign \"c\" \"fileno\" \"handle -> i32\")\nfn ! closeFd fd: Int64 -> Int64\n  (foreign \"c\" \"close\" \"i32 -> i32 !neg\")\nfn ! tty fd: Int64 -> (Result String String)\n  (foreign \"c\" \"ttyname\" \"i32 -> cstr !null\")")

fn ! testHandles -> Bool
  (do (assert (listEmpty? (diagsOf (handles))) (str "handle declarations check clean: " (messagesOf (handles))))
      (expectCode "Handle param type" (probe "fn ! fileNo f: Int64 -> Int64\n  (foreign \"c\" \"fileno\" \"handle -> i32\")") "ERR_FOREIGN_SIG")
      (expectCode "Handle result type" (probe "fn ! openFile p: String m: String -> (Result Int64 String)\n  (foreign \"c\" \"fopen\" \"cstr cstr -> handle:fclose\")") "ERR_FOREIGN_SIG")
      (expectCode "close needs a finaliser" (probe "fn ! closeFile f: Handle -> Int64\n  (foreign \"c\" \"fclose\" \"close -> i32\")") "ERR_FOREIGN_SIG")
      (expectCode "finaliser name" (probe "fn ! fileNo f: Handle -> Int64\n  (foreign \"c\" \"fileno\" \"handle:9x -> i32\")") "ERR_FOREIGN_SIG")
      (expectCode "marked plain kind" (probe "fn ! cbrt x: Float64 -> Float64\n  (foreign \"m\" \"cbrt\" \"f64:x -> f64\")") "ERR_FOREIGN_SIG")
      (expectCode "two closes" (probe "fn ! both a: Handle b: Handle -> Int64\n  (foreign \"c\" \"both\" \"close:fclose close:fclose -> i32\")") "ERR_FOREIGN_SIG")
      (expectCode "!neg on cstr" (probe "fn ! tty fd: Int64 -> String\n  (foreign \"c\" \"ttyname\" \"i32 -> cstr !neg\")") "ERR_FOREIGN_SIG")
      (expectCode "!null on i32" (probe "fn ! closeFd fd: Int64 -> Int64\n  (foreign \"c\" \"close\" \"i32 -> i32 !null\")") "ERR_FOREIGN_SIG")
      (expectCode "unknown convention" (probe "fn ! closeFd fd: Int64 -> Int64\n  (foreign \"c\" \"close\" \"i32 -> i32 !zero\")") "ERR_FOREIGN_SIG")
      (expectCode "two conventions" (probe "fn ! closeFd fd: Int64 -> Int64\n  (foreign \"c\" \"close\" \"i32 -> i32 !neg !neg\")") "ERR_FOREIGN_SIG")
      (assert (= (ff/parseSig "cstr -> handle:fclose !null") (ok (ff/ForeignSig :args (list "cstr") :ret "handle:fclose" :check "null"))) "a handle result keeps its finaliser and convention")
      (assert (= (ff/kindFinaliser "close:sqlite3_close") "sqlite3_close") "close:F names its finaliser")
      (assert (= (ff/kindBase "handle:fclose") "handle") "handle:F is a handle")
      (assert (= (ff/aslTypeOfKind "close:fclose") "Handle") "close:F crosses as Handle")
      true)

fn ! runTests -> Bool
  (do (assert (testClean) "clean declarations")
      (assert (testHandles) "handle kinds and conventions")
      (assert (testRules) "each rule has its code")
      (assert (testSig) "signature parsing")
      true)
