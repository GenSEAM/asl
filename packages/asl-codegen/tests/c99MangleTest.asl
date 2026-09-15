(module asl-codegen/c99MangleTest
  :d "Unit tests for asl-codegen/c99Mangle"
  :x [testC99Mangle
      testC99Keywords
      testC99TypeNames
      testC99ModulePrefix
      runTests]
  :i [(c99Mangle :a m)])

(df testC99Mangle [] -> Bool
  :d "Verifies C99 identifier mangling and keyword avoidance."
  (let [(m1 (m/mangleCIdent "string-contains?"))
        (m2 (m/mangleCIdent "empty?"))
        (m3 (m/mangleCIdent "is-empty?"))
        (m4 (m/mangleCIdent "write!"))
        (m5 (m/mangleCIdent "set-head!"))
        (m6 (m/mangleCIdent "foo-bar"))
        (m7 (m/mangleCIdent "user-first-name"))
        (m8 (m/mangleCIdent "int"))
        (m9 (m/mangleCIdent "return"))
        (m10 (m/mangleCIdent "struct"))
        (m11 (m/mangleCIdent "const"))
        (m12 (m/mangleCIdent "main"))
        (m13 (m/mangleCIdent "exit"))
        (m14 (m/mangleCIdent "42item"))
        (m15 (m/mangleCIdent ""))]
    (assert (= m1 "asl_is_string_contains") "predicate string-contains? mangling")
    (assert (= m2 "asl_is_empty") "predicate empty? mangling")
    (assert (= m3 "asl_is_empty") "predicate is-empty? mangling")
    (assert (= m4 "write_mut") "mutation write! mangling")
    (assert (= m5 "set_head_mut") "mutation set-head! mangling")
    (assert (= m6 "foo_bar") "kebab foo-bar mangling")
    (assert (= m7 "user_first_name") "kebab user-first-name mangling")
    (assert (= m8 "asl_int") "keyword int collision avoidance")
    (assert (= m9 "asl_return") "keyword return collision avoidance")
    (assert (= m10 "asl_struct") "keyword struct collision avoidance")
    (assert (= m11 "asl_const") "keyword const collision avoidance")
    (assert (= m12 "asl_main") "libc symbol main collision avoidance")
    (assert (= m13 "asl_exit") "libc symbol exit collision avoidance")
    (assert (= m14 "asl_42item") "leading digit identifier mangling")
    (assert (= m15 "") "empty identifier mangling")
    true))

(df testC99Keywords [] -> Bool
  :d "Verifies ISO C99 reserved keywords detection."
  (do
    (assert (m/isC99Keyword? "auto") "auto is C99 keyword")
    (assert (m/isC99Keyword? "break") "break is C99 keyword")
    (assert (m/isC99Keyword? "case") "case is C99 keyword")
    (assert (m/isC99Keyword? "char") "char is C99 keyword")
    (assert (m/isC99Keyword? "const") "const is C99 keyword")
    (assert (m/isC99Keyword? "continue") "continue is C99 keyword")
    (assert (m/isC99Keyword? "default") "default is C99 keyword")
    (assert (m/isC99Keyword? "do") "do is C99 keyword")
    (assert (m/isC99Keyword? "double") "double is C99 keyword")
    (assert (m/isC99Keyword? "else") "else is C99 keyword")
    (assert (m/isC99Keyword? "enum") "enum is C99 keyword")
    (assert (m/isC99Keyword? "extern") "extern is C99 keyword")
    (assert (m/isC99Keyword? "float") "float is C99 keyword")
    (assert (m/isC99Keyword? "for") "for is C99 keyword")
    (assert (m/isC99Keyword? "goto") "goto is C99 keyword")
    (assert (m/isC99Keyword? "if") "if is C99 keyword")
    (assert (m/isC99Keyword? "inline") "inline is C99 keyword")
    (assert (m/isC99Keyword? "int") "int is C99 keyword")
    (assert (m/isC99Keyword? "long") "long is C99 keyword")
    (assert (m/isC99Keyword? "register") "register is C99 keyword")
    (assert (m/isC99Keyword? "restrict") "restrict is C99 keyword")
    (assert (m/isC99Keyword? "return") "return is C99 keyword")
    (assert (m/isC99Keyword? "short") "short is C99 keyword")
    (assert (m/isC99Keyword? "signed") "signed is C99 keyword")
    (assert (m/isC99Keyword? "sizeof") "sizeof is C99 keyword")
    (assert (m/isC99Keyword? "static") "static is C99 keyword")
    (assert (m/isC99Keyword? "struct") "struct is C99 keyword")
    (assert (m/isC99Keyword? "switch") "switch is C99 keyword")
    (assert (m/isC99Keyword? "typedef") "typedef is C99 keyword")
    (assert (m/isC99Keyword? "union") "union is C99 keyword")
    (assert (m/isC99Keyword? "unsigned") "unsigned is C99 keyword")
    (assert (m/isC99Keyword? "void") "void is C99 keyword")
    (assert (m/isC99Keyword? "volatile") "volatile is C99 keyword")
    (assert (m/isC99Keyword? "while") "while is C99 keyword")
    (assert (m/isC99Keyword? "_Bool") "_Bool is C99 keyword")
    (assert (m/isC99Keyword? "_Complex") "_Complex is C99 keyword")
    (assert (m/isC99Keyword? "_Imaginary") "_Imaginary is C99 keyword")
    (assert (m/isC99Keyword? "main") "main is C runtime collision symbol")
    (assert (m/isC99Keyword? "exit") "exit is C runtime collision symbol")
    (assert (m/isC99Keyword? "abort") "abort is C runtime collision symbol")
    (assert (m/isC99Keyword? "index") "index is C runtime collision symbol")
    (assert (not (m/isC99Keyword? "foo")) "foo is not C99 keyword")
    (assert (not (m/isC99Keyword? "user")) "user is not C99 keyword")
    (assert (not (m/isC99Keyword? "bar_baz")) "bar_baz is not C99 keyword")
    (assert (not (m/isC99Keyword? "")) "empty string is not C99 keyword")
    true))

(df testC99TypeNames [] -> Bool
  :d "Verifies C99 PascalCase type name mangling with Asl prefix."
  (let [(t1 (m/mangleCTypeName "my-record"))
        (t2 (m/mangleCTypeName "user-info"))
        (t3 (m/mangleCTypeName "token"))
        (t4 (m/mangleCTypeName "AslToken"))
        (t5 (m/mangleCTypeName "empty?"))
        (t6 (m/mangleCTypeName "write!"))
        (t7 (m/mangleCTypeName ""))]
    (assert (= t1 "AslMyRecord") "my-record mangles to AslMyRecord")
    (assert (= t2 "AslUserInfo") "user-info mangles to AslUserInfo")
    (assert (= t3 "AslToken") "token mangles to AslToken")
    (assert (= t4 "AslToken") "AslToken retains single Asl prefix")
    (assert (= t5 "AslEmpty") "predicate type name strips question mark")
    (assert (= t6 "AslWrite") "mutation type name strips exclamation mark")
    (assert (= t7 "AslType") "empty type name produces fallback AslType")
    true))

(df testC99ModulePrefix [] -> Bool
  :d "Verifies C99 module path prefix derivation."
  (let [(p1 (m/mangleCModulePrefix "asl/packages/foo/bar"))
        (p2 (m/mangleCModulePrefix "packages/foo/bar"))
        (p3 (m/mangleCModulePrefix "foo/bar"))
        (p4 (m/mangleCModulePrefix "asl-codegen"))
        (p5 (m/mangleCModulePrefix "core/strings"))
        (p6 (m/mangleCModulePrefix ""))]
    (assert (= p1 "asl_foo_bar_") "asl/packages/foo/bar prefix")
    (assert (= p2 "asl_foo_bar_") "packages/foo/bar prefix")
    (assert (= p3 "asl_foo_bar_") "foo/bar prefix")
    (assert (= p4 "asl_codegen_") "asl-codegen prefix")
    (assert (= p5 "asl_core_strings_") "core/strings prefix")
    (assert (= p6 "asl_") "empty module prefix")
    true))

(df runTests [] -> Bool
  :d "Runs full C99 mangle test suite."
  (do
    (assert (testC99Mangle) "testC99Mangle must pass")
    (assert (testC99Keywords) "testC99Keywords must pass")
    (assert (testC99TypeNames) "testC99TypeNames must pass")
    (assert (testC99ModulePrefix) "testC99ModulePrefix must pass")
    true))
