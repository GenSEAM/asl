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

fn ! runTests -> Bool
  (do (assert (testClean) "clean declarations")
      (assert (testRules) "each rule has its code")
      (assert (testSig) "signature parsing")
      true)
