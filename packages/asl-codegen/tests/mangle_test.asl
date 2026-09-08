(module asl-codegen/mangle-test
  :d "Unit tests for asl-codegen/mangle"
  :x [test-mangle run-tests]
  :i [(mangle :a m)])

(df test-mangle [] -> Bool
  :d "Verifies identifier and module path mangling rules."
  (let [(m1 (m/mangle-ident "foo-bar"))
        (m2 (m/mangle-ident "empty?"))
        (m3 (m/mangle-ident "write!"))
        (m4 (m/mangle-ident "type"))
        (m5 (m/mangle-ident "main"))
        (p1 (m/pascal-ident "foo-bar"))
        (p2 (m/pascal-ident "my_long_name"))
        (mod1 (m/rust-mod-name "core/strings"))
        (mod2 (m/rust-mod-name "text/report"))]
    (assert (= m1 "foo_bar") "mangle foo-bar")
    (assert (= m2 "is_empty") "mangle empty?")
    (assert (= m3 "write_mut") "mangle write!")
    (assert (= m4 "type_") "mangle type")
    (assert (= m5 "main_") "mangle main")
    (assert (= p1 "FooBar") "pascal foo-bar")
    (assert (= p2 "MyLongName") "pascal my_long_name")
    (assert (= mod1 "core_strings") "rust mod core/strings")
    (assert (= mod2 "text_report") "rust mod text/report")
    true))

(df run-tests [] -> Bool
  :d "Runs mangle test suite"
  (do
    (assert (test-mangle) "test-mangle must pass")
    true))
