(module asl-codegen/mangle
  :d "Identifier and module path mangling for Rust emission."
  :x [mangleIdent pascalIdent rustModName shortModName capitalizeSeg isRustKeyword? sliceOr]
  :i [])

(df isRustKeyword? [(m String)] -> Bool
  :d "Checks if mangled identifier collides with a Rust keyword or entry name."
  (list-contains? (list "type" "match" "fn" "let" "loop" "move" "ref" "impl" "mod" "use" "const" "static" "crate" "super" "self" "struct" "enum" "trait" "where" "for" "while" "return" "break" "continue" "as" "in" "main") m))

(df sliceOr [(s String) (start Int64) (end Int64) (fallback String)] -> String
  :d "Safe string slice with fallback default."
  (option-or (string-slice s start end) fallback))

(df mangleIdent [(s String)] -> String
  :d "Mangles an ASL kebab-case identifier into a safe Rust snake_case identifier."
  (let [(sLen (string-length s))
        (base1 (if (and (> sLen 1) (string-ends-with? s "?"))
                   (str "is-" (sliceOr s 0 (- sLen 1) ""))
                   s))
        (len1 (string-length base1))
        (base2 (if (and (> len1 1) (string-ends-with? base1 "!"))
                   (str (sliceOr base1 0 (- len1 1) "") "-mut")
                   base1))
        (snaked (string-replace base2 "-" "_"))]
    (if (isRustKeyword? snaked)
        (str snaked "_")
        snaked)))

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

(df rustModName [(modPath String)] -> String
  :d "Derives a flat Rust module name from an ASL module path."
  (let [(segs (string-split modPath "/"))
        (mangled (map mangleIdent segs))]
    (string-join mangled "_")))

(df shortModName [(modPath String)] -> String
  :d "Extracts and mangles the terminal segment of a module path."
  (if (string-contains? modPath "/")
      (let [(parts (string-split modPath "/"))
            (lastIdx (- (list-length parts) 1))
            (lastPart (option-or (list-get parts lastIdx) modPath))]
        (rustModName lastPart))
      (rustModName modPath)))
