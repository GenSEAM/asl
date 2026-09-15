(module asl-codegen/mangleTest
  :d "Unit tests for asl-codegen/mangle"
  :x [testMangle runTests]
  :i [(mangle :a m)])

(df testMangle [] -> Bool
  :d "Verifies identifier and module path mangling rules."
  (let [(m1 (m/mangleIdent "foo-bar"))
        (m2 (m/mangleIdent "empty?"))
        (m3 (m/mangleIdent "write!"))
        (m4 (m/mangleIdent "type"))
        (m5 (m/mangleIdent "main"))
        (p1 (m/pascalIdent "foo-bar"))
        (p2 (m/pascalIdent "my_long_name"))
        (mod1 (m/rustModName "core/strings"))
        (mod2 (m/rustModName "text/report"))]
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

(df runTests [] -> Bool
  :d "Runs mangle test suite"
  (do
    (assert (testMangle) "test-mangle must pass")
    true))
