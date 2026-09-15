(module asl-codegen/c99Mangle
  :d "ISO C99 identifier hygiene, keyword collision avoidance, and module prefix mangling."
  :x [mangleCIdent
      isC99Keyword?
      mangleCTypeName
      mangleCModulePrefix
      pascalIdent
      capitalizeSeg
      sliceOr
      isDigitLeading?]
  :i [])

(df isC99Keyword? [(m String)] -> Bool
  :d "Checks if identifier collides with an ISO C99 reserved keyword or libc symbol."
  (list-contains? (list "auto" "break" "case" "char" "const" "continue" "default" "do" "double" "else" "enum" "extern" "float" "for" "goto" "if" "inline" "int" "long" "register" "restrict" "return" "short" "signed" "sizeof" "static" "struct" "switch" "typedef" "union" "unsigned" "void" "volatile" "while" "_Bool" "_Complex" "_Imaginary" "main" "exit" "abort" "index") m))

(df sliceOr [(s String) (start Int64) (end Int64) (fallback String)] -> String
  :d "Safe string slice with fallback default."
  (option-or (string-slice s start end) fallback))

(df isDigitLeading? [(s String)] -> Bool
  :d "Checks if string starts with an ASCII digit."
  (if (<= (string-length s) 0)
      false
      (let [(c (sliceOr s 0 1 ""))]
        (list-contains? (list "0" "1" "2" "3" "4" "5" "6" "7" "8" "9") c))))

(df mangleCIdent [(s String)] -> String
  :d "Converts ASL kebab-case identifier to safe C snake_case identifier with keyword collision protection."
  (let [(sLen (string-length s))]
    (if (<= sLen 0)
        ""
        (let [(isPred (and (> sLen 1) (string-ends-with? s "?")))
              (withoutPred (if isPred (sliceOr s 0 (- sLen 1) "") s))
              (pLen (string-length withoutPred))
              (isMut (and (> pLen 1) (string-ends-with? withoutPred "!")))
              (withoutMut (if isMut (str (sliceOr withoutPred 0 (- pLen 1) "") "-mut") withoutPred))
              (withIs (if isPred
                          (if (or (string-starts-with? withoutMut "is-")
                                  (string-starts-with? withoutMut "is_"))
                              (str "asl-" withoutMut)
                              (str "asl-is-" withoutMut))
                          withoutMut))
              (snaked (string-replace (string-replace withIs "-" "_") "/" "_"))
              (safeIdent (if (isC99Keyword? snaked)
                             (str "asl_" snaked)
                             (if (isDigitLeading? snaked)
                                 (str "asl_" snaked)
                                 snaked)))]
          safeIdent))))

(df capitalizeSeg [(seg String)] -> String
  :d "Capitalizes a single word segment for PascalCase."
  (let [(segLen (string-length seg))]
    (if (<= segLen 0)
        ""
        (let [(head (string-upper (sliceOr seg 0 1 "")))
              (tail (string-lower (sliceOr seg 1 segLen "")))]
          (str head tail)))))

(df pascalIdent [(s String)] -> String
  :d "Converts kebab-case or snake_case identifier to PascalCase."
  (if (and (not (string-contains? s "-"))
           (not (string-contains? s "_")))
      (if (and (> (string-length s) 0)
               (= (string-upper (sliceOr s 0 1 "")) (sliceOr s 0 1 "")))
          s
          (capitalizeSeg s))
      (let [(norm (string-replace s "_" "-"))
            (segs (string-split norm "-"))
            (caps (map capitalizeSeg segs))]
        (string-join caps ""))))

(df mangleCTypeName [(s String)] -> String
  :d "Converts kebab-case identifier to PascalCase with Asl prefix."
  (let [(sLen (string-length s))]
    (if (<= sLen 0)
        "AslType"
        (let [(clean (string-replace (string-replace s "?" "") "!" ""))
              (pascal (pascalIdent clean))]
          (if (string-starts-with? pascal "Asl")
              pascal
              (str "Asl" pascal))))))

(df mangleCModulePrefix [(modPath String)] -> String
  :d "Converts an ASL module path to a safe C identifier prefix ending with underscore."
  (let [(p0 (if (string-starts-with? modPath "asl/packages/")
                (sliceOr modPath 13 (string-length modPath) "")
                (if (string-starts-with? modPath "packages/")
                    (sliceOr modPath 9 (string-length modPath) "")
                    (if (string-starts-with? modPath "asl/")
                        (sliceOr modPath 4 (string-length modPath) "")
                        modPath))))
        (p1 (string-replace (string-replace p0 "/" "_") "-" "_"))
        (p2 (if (string-starts-with? p1 "asl_")
                p1
                (str "asl_" p1)))
        (p3 (if (string-ends-with? p2 "_")
                p2
                (str p2 "_")))]
    p3))
