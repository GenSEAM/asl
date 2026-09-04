(module asl-compiler/test
  :d "Unit tests for 100% self-hosted compiler pipeline"
  :x [run-tests]
  :i [(compiler :a comp)])

(df test-compile-clean-function [] -> Bool
  :d "Verifies end-to-end compilation of a valid arithmetic function."
  (let [(src "(df add [(a I64) (b I64)] -> I64 (+ a b))")
        (res (comp/compile-standalone-source src "math.asl"))]
    (and (.-ok res)
         (and (string-contains? (.-code res) "pub fn add")
              (list-empty? (.-diagnostics res))))))

(df test-compile-clean-schema [] -> Bool
  :d "Verifies end-to-end compilation of a valid schema definition."
  (let [(src "(dfs Point (:f x I64 \"x coord\") (:f y I64 \"y coord\"))")
        (res (comp/compile-standalone-source src "point.asl"))]
    (and (.-ok res)
         (string-contains? (.-code res) "pub struct Point"))))

(df test-compile-parse-error [] -> Bool
  :d "Verifies rejection of syntactically malformed code."
  (let [(src "(df broken [)")
        (res (comp/compile-standalone-source src "syntax_err.asl"))]
    (and (not (.-ok res))
         (> (list-length (.-diagnostics res)) 0))))

(df test-compile-type-error [] -> Bool
  :d "Verifies rejection of type-mismatched code."
  (let [(src "(df type-err [] -> I64 \"not-an-int\")")
        (res (comp/compile-standalone-source src "type_err.asl"))]
    (and (not (.-ok res))
         (> (list-length (.-diagnostics res)) 0))))

(df run-tests [] -> Bool
  :d "Runs all compiler pipeline tests."
  (and (test-compile-clean-function)
       (and (test-compile-clean-schema)
            (and (test-compile-parse-error)
                 (test-compile-type-error)))))
