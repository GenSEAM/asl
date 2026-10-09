(module aslVdom/emitJsx :x [emitVnodeJsx emitJsxAttrs emitComponent emitTsxModule jsxAttrKey isComponentTag? indentSpaces] :i [(aslVdom/vdom :a v) (aslVdom/html :a html)])

fn indentSpaces level: Int64 -> String
  (if (<= level 0) "" (str "  " (indentSpaces (- level 1))))

fn isComponentTag? tag: String -> Bool
  (if (stringEmpty? tag) false (let [(firstCh (optionOr (stringSlice tag 0 1) ""))] (and (>= firstCh "A") (<= firstCh "Z"))))

fn jsxAttrKey k: String -> String
  (cond ((= k "class") "className") ((= k "for") "htmlFor") ((= k "tabindex") "tabIndex") ((= k "readonly") "readOnly") ((= k "autocomplete") "autoComplete") ((= k "autofocus") "autoFocus") ((= k "maxlength") "maxLength") ((= k "minlength") "minLength") ((= k "onclick") "onClick") ((= k "onchange") "onChange") ((= k "onsubmit") "onSubmit") ((= k "onkeydown") "onKeyDown") ((= k "onkeyup") "onKeyUp") ((= k "onfocus") "onFocus") ((= k "onblur") "onBlur") (else k))

fn emitJsxAttrs attrs: (Map String String) -> String
  (let [(pairs (mapPairs attrs))] (if (= (listLength pairs) 0) "" (let [(rendered (map (fn [(p (pair String String))] -> String (let [(k (jsxAttrKey (pairFirst p))) (v (pairSecond p))] (cond ((= v "true") (str " " k)) ((= v "false") (str " " k "={false}")) ((stringStartsWith? v "{") (str " " k "=" v)) (else (str " " k "=\"" (html/escapeHtml v) "\""))))) pairs))] (stringJoin rendered ""))))

fn emitVnodeJsx node: v/VNode indent: Int64 -> String
  (let [(pad (indentSpaces indent))] (mt node ((v/textNode content) (let [(safeContent (stringReplace (html/escapeHtml content) "{" "&#123;"))] (str pad safeContent))) ((v/elementNode tag attrs children) (let [(attrStr (emitJsxAttrs attrs)) (chLen (listLength children)) (isComp (isComponentTag? tag))] (if (= chLen 0) (if (or (html/isVoidTag? tag) isComp) (str pad "<" tag attrStr " />") (str pad "<" tag attrStr "></" tag ">")) (let [(chStrs (map (fn [(ch v/VNode)] -> String (emitVnodeJsx ch (+ indent 1))) children)) (chJoined (stringJoin chStrs "\n"))] (str pad "<" tag attrStr ">\n" chJoined "\n" pad "</" tag ">")))))))

fn emitComponent name: String propsType: String node: v/VNode -> String
  (let [(jsx (emitVnodeJsx node 2))] (str "export const " name " = (props: " propsType ") => {\n" "  return (\n" jsx "\n" "  );\n" "};\n"))

fn emitTsxModule componentName: String propsType: String rootNode: v/VNode -> String
  (str "// @ts-nocheck\n" "import React from \"react\";\n\n" (emitComponent componentName propsType rootNode))
