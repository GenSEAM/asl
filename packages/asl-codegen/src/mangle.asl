(module asl-codegen/mangle
  :d "Identifier and module path mangling for Rust emission."
  :x [mangle-ident pascal-ident rust-mod-name capitalize-seg is-rust-keyword? slice-or]
  :i [])

(df is-rust-keyword? [(m String)] -> Bool
  :d "Checks if mangled identifier collides with a Rust keyword or entry name."
  (or (= m "type")
      (or (= m "match")
          (or (= m "fn")
              (or (= m "let")
                  (or (= m "loop")
                      (or (= m "move")
                          (or (= m "ref")
                              (or (= m "impl")
                                  (= m "main"))))))))))

(df slice-or [(s String) (start Int64) (end Int64) (def String)] -> String
  :d "Safe string slice with fallback default."
  (option-or (string-slice s start end) def))

(df mangle-ident [(s String)] -> String
  :d "Mangles an ASL kebab-case identifier into a safe Rust snake_case identifier."
  (let [(s-len (string-length s))
        (base1 (if (and (> s-len 1) (string-ends-with? s "?"))
                   (str "is-" (slice-or s 0 (- s-len 1) ""))
                   s))
        (len1 (string-length base1))
        (base2 (if (and (> len1 1) (string-ends-with? base1 "!"))
                   (str (slice-or base1 0 (- len1 1) "") "-mut")
                   base1))
        (snaked (string-replace base2 "-" "_"))]
    (if (is-rust-keyword? snaked)
        (str snaked "_")
        snaked)))

(df capitalize-seg [(seg String)] -> String
  :d "Capitalizes a single word segment for PascalCase."
  (let [(seg-len (string-length seg))]
    (if (<= seg-len 0)
        ""
        (let [(head (string-upper (slice-or seg 0 1 "")))
              (tail (string-lower (slice-or seg 1 seg-len "")))]
          (str head tail)))))

(df pascal-ident [(s String)] -> String
  :d "Converts kebab-case or snake_case identifier to PascalCase."
  (let [(norm (string-replace s "_" "-"))
        (segs (string-split norm "-"))
        (caps (map capitalize-seg segs))]
    (string-join caps "")))

(df rust-mod-name [(mod-path String)] -> String
  :d "Derives a flat Rust module name from an ASL module path."
  (let [(segs (string-split mod-path "/"))
        (mangled (map mangle-ident segs))]
    (string-join mangled "_")))
