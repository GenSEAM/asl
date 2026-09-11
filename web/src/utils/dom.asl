(module asl-web/dom
  :d "Pure AgentScript DOM and WASM AST manipulation utilities"
  :x [dom-element dom-query format-vdom-node]
  :i [])

(df dom-element [(tag Str) (attrs (List Any)) (children (List Any))] -> Any
  :d "Constructs structured DOM element node record with tag, attribute key-value pairs, and child nodes"
  (:tag tag :attrs attrs :children children))

(df format-attr [(attr Any)] -> Str
  :d "Serializes a single attribute pair or record into key-value string format"
  (if (> (list-len attr) 1)
      (let [(k (option-unwrap (list-get attr 0)))
            (v (option-unwrap (list-get attr 1)))]
        (str " " k "=\"" v "\""))
      (str " " (.-name attr) "=\"" (.-value attr) "\"")))

(df format-attrs [(attrs (List Any))] -> Str
  :d "Serializes a list of attributes into formatted space-prefixed string"
  (fold (fn [(acc Str) (attr Any)] -> Str
          (str acc (format-attr attr)))
        ""
        attrs))

(df format-vdom-node [(node Any)] -> Str
  :d "Serializes an element node and its nested children into a canonical formatted tag string representation"
  (if (= node nil)
      ""
      (if (= (.-tag node) nil)
          (str node)
          (let [(tag (.-tag node))
                (attrs (.-attrs node))
                (children (.-children node))]
            (let [(attr-str (if (= attrs nil) "" (format-attrs attrs)))
                  (child-str (if (= children nil)
                                 ""
                                 (fold (fn [(acc Str) (child Any)] -> Str
                                         (str acc (format-vdom-node child)))
                                       ""
                                       children)))]
              (str "<" tag attr-str ">" child-str "</" tag ">"))))))

(df dom-query [(root Any) (tag-name Str)] -> (Option Any)
  :d "Recursively traverses node tree and returns the first element matching tag-name, or nil if not found"
  (if (= root nil)
      nil
      (if (= (.-tag root) tag-name)
          root
          (let [(children (.-children root))]
            (if (= children nil)
                nil
                (fold (fn [(found Any) (child Any)] -> Any
                        (if (!= found nil)
                            found
                            (dom-query child tag-name)))
                      nil
                      children))))))
