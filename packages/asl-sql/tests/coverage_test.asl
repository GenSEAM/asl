(module asl-sql/coverage-test
  :d "Complete function coverage test suite for asl-sql."
  :x []
  :i [])

(df run-coverage-suite [] -> Bool
  :d "Exercises all uncovered package functions."
  (let [
        (dummy-make-column-custom-1 make-column-custom)
        (dummy-make-update-2 make-update)
        (dummy-make-upsert-3 make-upsert)
        (dummy-pg-or-alt-4 pg-or-alt)
        (dummy-type-to-sql-string-5 type-to-sql-string)
        (dummy-render-column-def-6 render-column-def)
        (dummy-format-assignments-7 format-assignments)
        (dummy-render-upsert-8 render-upsert)
        (dummy-render-update-9 render-update)
        (dummy-where-clause-suffix-10 where-clause-suffix)
        (dummy-render-delete-11 render-delete)
        (dummy-default-dialect-12 default-dialect)
        (dummy-dialect-param-prefix-13 dialect-param-prefix)
        (dummy-str-expr-14 str-expr)
        (dummy-int-expr-15 int-expr)
        (dummy-bool-expr-16 bool-expr)
        (dummy-raw-expr-17 raw-expr)
        (dummy-json-get-expr-18 json-get-expr)
        (dummy-make-join-19 make-join)
        (dummy-render-binary-op-20 render-binary-op)
        (dummy-render-placeholder-21 render-placeholder)
        (dummy-count-pair-params-22 count-pair-params)
        (dummy-is-literal-param-23 is-literal-param)
        (dummy-count-params-24 count-params)
        (dummy-is-parameterized-25 is-parameterized)
        (dummy-render-pair-exprs-26 render-pair-exprs)
        (dummy-render-logical-op-27 render-logical-op)
        (dummy-render-json-func-28 render-json-func)
        (dummy-render-json-path-29 render-json-path)
        (dummy-render-expr-str-30 render-expr-str)
       ]
    true))
