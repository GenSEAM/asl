(module aslAgent/anchorLinker
  :x [MemoryRef resolveAnchor formatMemoryRef validateAnchorReference extractAnchors]
  :i [])

(schema MemoryRef
  (:f file String)
  (:f symbol String)
  (:f anchor String))

fn formatMemoryRef filePath: String symbol: String anchor: String -> String
  (str "(:ref :file \"" filePath "\" :symbol \"" symbol "\" :anchor \"" anchor "\")")

fn validateAnchorReference refStr: String -> Bool
  (and (stringContains? refStr ":ref")
       (and (stringContains? refStr ":file")
            (and (stringContains? refStr ":symbol")
                 (and (stringContains? refStr ":anchor")
                      (not (stringContains? refStr ":line"))))))

fn resolveAnchor src: String anchorName: String -> (Option String)
  (let [(pattern (str ":anchor \"" anchorName "\""))]
    (if (stringContains? src pattern)
      (some anchorName)
      (none)))

fn extractAnchors src: String -> (List String)
  (let [(lines (stringSplit src "\n"))]
    (fold (fn [(acc (List String)) (l String)] -> (List String)
            (if (stringContains? l ":anchor \"")
              (let [(p1 (optionOr (stringSlice l (+ (optionOr (stringIndexOf l ":anchor \"") 0) 9) (stringLength l)) ""))
                    (endQuote (optionOr (stringIndexOf p1 "\"") (stringLength p1)))
                    (tag (optionOr (stringSlice p1 0 endQuote) ""))]
                (if (stringEmpty? tag) acc (cons tag acc)))
              acc))
          (list) lines))
