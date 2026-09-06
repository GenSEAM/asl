(module asl-codegen/emit-jsx
  :d "VNode to React 19 TSX emission logic in ASL"
  :x [VNode
      emit-vnode-jsx
      emit-jsx-attrs
      emit-component
      emit-tsx-module
      jsx-attr-key
      is-void-tag?
      is-component-tag?
      indent-spaces])

(dfe VNode
  (:c text-node [(content Str)] "Text node")
  (:c element-node [(tag Str) (attrs (Map Str Str)) (children (List VNode))] "Element node"))

(df indent-spaces [(level I64)] -> Str
  :d "Generates indentation string of 2 spaces per level"
  (if (<= level 0)
      ""
      (str "  " (indent-spaces (- level 1)))))

(df is-void-tag? [(tag Str)] -> Bool
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

(df is-component-tag? [(tag Str)] -> Bool
  :d "Checks if a tag represents a React component (uppercase first character)"
  (if (string-empty? tag)
      false
      (let [(first-ch (option-or (string-slice tag 0 1) ""))]
        (and (>= first-ch "A") (<= first-ch "Z")))))

(df jsx-attr-key [(k Str)] -> Str
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

(df emit-jsx-attrs [(attrs (Map Str Str))] -> Str
  :d "Renders an attribute map into a JSX attribute string"
  (let [(pairs (map-pairs attrs))]
    (if (= (list-length pairs) 0)
        ""
        (let [(rendered (map (fn [(p (Pair Str Str))] -> Str
                               (let [(k (jsx-attr-key (.-first p)))
                                     (v (.-second p))]
                                 (cond
                                   ((= v "true") (str " " k))
                                   ((= v "false") (str " " k "={false}"))
                                   ((string-starts-with? v "{") (str " " k "=" v))
                                   (:else (str " " k "=\"" v "\"")))))
                             pairs))]
          (string-join rendered "")))))

(df emit-vnode-jsx [(node VNode) (indent I64)] -> Str
  :d "Renders a VNode hierarchy into formatted JSX for native elements and components"
  (let [(pad (indent-spaces indent))]
    (mt node
      ((text-node content)
       (str pad content))
      ((element-node tag attrs children)
       (let [(attr-str (emit-jsx-attrs attrs))
             (ch-len (list-length children))
             (is-comp (is-component-tag? tag))]
         (if (= ch-len 0)
             (if (or (is-void-tag? tag) is-comp)
                 (str pad "<" tag attr-str " />")
                 (str pad "<" tag attr-str "></" tag ">"))
             (let [(ch-strs (map (fn [(ch VNode)] -> Str
                                   (emit-vnode-jsx ch (+ indent 1)))
                                 children))
                   (ch-joined (string-join ch-strs "\n"))]
               (str pad "<" tag attr-str ">\n" ch-joined "\n" pad "</" tag ">"))))))))

(df emit-component [(name Str) (props-type Str) (node VNode)] -> Str
  :d "Emits a React functional component definition"
  (let [(jsx (emit-vnode-jsx node 2))]
    (str "export const " name " = (props: " props-type ") => {\n"
         "  return (\n"
         jsx "\n"
         "  );\n"
         "};\n")))

(df emit-tsx-module [(component-name Str) (props-type Str) (root-node VNode)] -> Str
  :d "Emits a complete TSX module with React imports and exported component"
  (str "// @ts-nocheck\n"
       "import React from \"react\";\n\n"
       (emit-component component-name props-type root-node)))
