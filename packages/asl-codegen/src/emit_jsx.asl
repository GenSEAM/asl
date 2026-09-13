(module asl-codegen/emitJsx
  :d "VNode to React 19 TSX emission logic in ASL"
  :x [VNode
      emitVnodeJsx
      emitJsxAttrs
      emitComponent
      emitTsxModule
      jsxAttrKey
      isVoidTag?
      isComponentTag?
      indentSpaces])

(dfe VNode
  (:c textNode [(content Str)] "Text node")
  (:c elementNode [(tag Str) (attrs (Map Str Str)) (children (List VNode))] "Element node"))

(df indentSpaces [(level I64)] -> Str
  :d "Generates indentation string of 2 spaces per level"
  (if (<= level 0)
      ""
      (str "  " (indentSpaces (- level 1)))))

(df isVoidTag? [(tag Str)] -> Bool
  :d "Checks if an HTML tag is a self-closing void element"
  (or (= tag "input")
      (or (= tag "img")
          (or (= tag "br")
              (or (= tag "hr")
                  (or (= tag "meta")
                      (or (= tag "link")
                          (or (= tag "source")
                              (or (= tag "col")
                                  (= tag "wbr"))))))))))

(df isComponentTag? [(tag Str)] -> Bool
  :d "Checks if a tag represents a React component (uppercase first character)"
  (if (string-empty? tag)
      false
      (let [(firstCh (option-or (string-slice tag 0 1) ""))]
        (and (>= firstCh "A") (<= firstCh "Z")))))

(df jsxAttrKey [(k Str)] -> Str
  :d "Translates HTML attribute names to React JSX property names"
  (cond
    ((= k "class") "className")
    ((= k "for") "htmlFor")
    ((= k "tabindex") "tabIndex")
    ((= k "readonly") "readOnly")
    ((= k "autocomplete") "autoComplete")
    ((= k "autofocus") "autoFocus")
    ((= k "maxlength") "maxLength")
    ((= k "minlength") "minLength")
    ((= k "onclick") "onClick")
    ((= k "onchange") "onChange")
    ((= k "onsubmit") "onSubmit")
    ((= k "onkeydown") "onKeyDown")
    ((= k "onkeyup") "onKeyUp")
    ((= k "onfocus") "onFocus")
    ((= k "onblur") "onBlur")
    (:else k)))

(df emitJsxAttrs [(attrs (Map Str Str))] -> Str
  :d "Renders an attribute map into a JSX attribute string"
  (let [(pairs (map-pairs attrs))]
    (if (= (list-length pairs) 0)
        ""
        (let [(rendered (map (fn [(p (Pair Str Str))] -> Str
                               (let [(k (jsxAttrKey (.-first p)))
                                     (v (.-second p))]
                                 (cond
                                   ((= v "true") (str " " k))
                                   ((= v "false") (str " " k "={false}"))
                                   ((string-starts-with? v "{") (str " " k "=" v))
                                   (:else (str " " k "=\"" v "\"")))))
                             pairs))]
          (string-join rendered "")))))

(df emitVnodeJsx [(node VNode) (indent I64)] -> Str
  :d "Renders a VNode hierarchy into formatted JSX for native elements and components"
  (let [(pad (indentSpaces indent))]
    (mt node
      ((textNode content)
       (str pad content))
      ((elementNode tag attrs children)
       (let [(attrStr (emitJsxAttrs attrs))
             (chLen (list-length children))
             (isComp (isComponentTag? tag))]
         (if (= chLen 0)
             (if (or (isVoidTag? tag) isComp)
                 (str pad "<" tag attrStr " />")
                 (str pad "<" tag attrStr "></" tag ">"))
             (let [(chStrs (map (fn [(ch VNode)] -> Str
                                   (emitVnodeJsx ch (+ indent 1)))
                                 children))
                   (chJoined (string-join chStrs "\n"))]
               (str pad "<" tag attrStr ">\n" chJoined "\n" pad "</" tag ">"))))))))

(df emitComponent [(name Str) (propsType Str) (node VNode)] -> Str
  :d "Emits a React functional component definition"
  (let [(jsx (emitVnodeJsx node 2))]
    (str "export const " name " = (props: " propsType ") => {\n"
         "  return (\n"
         jsx "\n"
         "  );\n"
         "};\n")))

(df emitTsxModule [(componentName Str) (propsType Str) (rootNode VNode)] -> Str
  :d "Emits a complete TSX module with React imports and exported component"
  (str "import React from \"react\";\n\n"
       (emitComponent componentName propsType rootNode)))
