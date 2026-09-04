(module asl-codegen/mangle-test
  :d "Unit tests for asl-codegen/mangle"
  :x [test-mangle]
  :i [(mangle :a m)])

(df test-mangle [] -> String
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
    (cond
      ((not (= m1 "foo_bar")) "fail m1")
      ((not (= m2 "is_empty")) "fail m2")
      ((not (= m3 "write_mut")) "fail m3")
      ((not (= m4 "type_")) "fail m4")
      ((not (= m5 "main_")) "fail m5")
      ((not (= p1 "FooBar")) "fail p1")
      ((not (= p2 "MyLongName")) "fail p2")
      ((not (= mod1 "core_strings")) "fail mod1")
      ((not (= mod2 "text_report")) "fail mod2")
      (:else "ok"))))
