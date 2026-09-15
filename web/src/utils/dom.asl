(module aslWeb/dom
  :d "Pure AgentScript DOM and WASM AST manipulation utilities"
  :x [domElement domQuery formatVdomNode]
  :i [])

(df domElement [(tag Str) (attrs (List Any)) (children (List Any))] -> Any
  :d "Constructs structured DOM element node record with tag, attribute key-value pairs, and child nodes"
  (:tag tag :attrs attrs :children children))

(df formatAttr [(attr Any)] -> Str
  :d "Serializes a single attribute pair or record into key-value string format"
  (if (> (listLen attr) 1)
      (let [(k (option-unwrap (list-get attr 0)))
            (v (option-unwrap (list-get attr 1)))]
        (str " " k "=\"" v "\""))
      (str " " (.-name attr) "=\"" (.-value attr) "\"")))

(df formatAttrs [(attrs (List Any))] -> Str
  :d "Serializes a list of attributes into formatted space-prefixed string"
  (fold (fn [(acc Str) (attr Any)] -> Str
          (str acc (formatAttr attr)))
        ""
        attrs))

(df formatVdomNode [(node Any)] -> Str
  :d "Serializes an element node and its nested children into a canonical formatted tag string representation"
  (if (= node nil)
      ""
      (if (= (.-tag node) nil)
          (str node)
          (let [(tag (.-tag node))
                (attrs (.-attrs node))
                (children (.-children node))]
            (let [(attrStr (if (= attrs nil) "" (formatAttrs attrs)))
                  (childStr (if (= children nil)
                                 ""
                                 (fold (fn [(acc Str) (child Any)] -> Str
                                         (str acc (formatVdomNode child)))
                                       ""
                                       children)))]
              (str "<" tag attrStr ">" childStr "</" tag ">"))))))

(df domQuery [(root Any) (tagName Str)] -> (Option Any)
  :d "Recursively traverses node tree and returns the first element matching tag-name, or nil if not found"
  (if (= root nil)
      nil
      (if (= (.-tag root) tagName)
          root
          (let [(children (.-children root))]
            (if (= children nil)
                nil
                (fold (fn [(found Any) (child Any)] -> Any
                        (if (!= found nil)
                            found
                            (domQuery child tagName)))
                      nil
                      children))))))
