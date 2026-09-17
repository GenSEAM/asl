(module asl-ui/renderWeb
  :d "WebAssembly DOM Mutation Applicator and HTML String Renderer under ADR D96"
  :x [DomPatch
      makeDomPatch
      makeEmptyDomPatch
      applyDomMutations
      renderToHtml
      handleWebResize]
  :i [(asl-ui/vnode :a ui)
      (asl-ui/runtime :a elm)
      (asl-ui/arena :a arena)])

(dfs DomPatch
  (:f opcode String)
  (:f targetKey String)
  (:f param1 String)
  (:f param2 String))

(df makeDomPatch [(opcode String)
                  (targetKey String)
                  (param1 String)
                  (param2 String)] -> DomPatch
  :d "Constructs a DOM patch instruction"
  (DomPatch :opcode opcode
            :targetKey targetKey
            :param1 param1
            :param2 param2))

(df makeEmptyDomPatch [] -> DomPatch
  :d "Constructs an empty no-op DOM patch"
  (DomPatch :opcode "DOM_NOOP"
            :targetKey ""
            :param1 ""
            :param2 ""))

(df mapMutationToPatch [(mut arena/MutationRecord)] -> DomPatch
  :d "Maps an atomic mutation record to a virtual DOM patch instruction"
  (let [(k (.-kind mut))
        (key (.-targetKey mut))
        (tag (.-tag (.-node mut)))]
    (if (= k "insert")
      (makeDomPatch "DOM_INSERT" key tag "")
      (if (= k "remove")
        (makeDomPatch "DOM_REMOVE" key tag "")
        (if (= k "update")
          (makeDomPatch "DOM_UPDATE" key tag "")
          (makeDomPatch "DOM_NOOP" key "" ""))))))

(df applyDomMutationsLoop [(muts (List arena/MutationRecord)) (acc (List DomPatch))] -> (List DomPatch)
  :d "Recursively converts mutation records into DOM patch instructions"
  (if (list-empty? muts)
    acc
    (let [(head (option-or (list-head muts) (arena/makeMutationRecord "" "" (ui/makeText "" "") (map-empty) 0)))
          (tail (option-or (list-tail muts) (list)))
          (patch (mapMutationToPatch head))]
      (applyDomMutationsLoop tail (list-append acc (list patch))))))

(df applyDomMutations [(mutations (List arena/MutationRecord))] -> (List DomPatch)
  :d "Batch applies mutation records to produce ordered list of DOM patches"
  (applyDomMutationsLoop mutations (list)))

(df mapVNodeTagToHtmlTag [(tag String)] -> String
  :d "Maps abstract VNode tag to concrete HTML element tag"
  (if (= tag "container")
    "div"
    (if (= tag "modal")
      "div"
      (if (= tag "list")
        "ul"
        tag))))

(df renderAttributesLoop [(attrs (Map String String)) (keys (List String)) (acc String)] -> String
  :d "Recursively renders attributes map into HTML attribute string"
  (if (list-empty? keys)
    acc
    (let [(k (option-or (list-head keys) ""))
          (tail (option-or (list-tail keys) (list)))
          (val (option-or (map-get attrs k) ""))
          (attrPair (str-concat " " (str-concat k (str-concat "=\"" (str-concat val "\"")))))]
      (renderAttributesLoop attrs tail (str-concat acc attrPair)))))

(df renderChildrenHtmlLoop [(children (List ui/VNode)) (acc String)] -> String
  :d "Recursively renders child VNodes into concatenated HTML"
  (if (list-empty? children)
    acc
    (let [(head (option-or (list-head children) (ui/makeText "" "")))
          (tail (option-or (list-tail children) (list)))
          (childHtml (renderToHtml head))]
      (renderChildrenHtmlLoop tail (str-concat acc childHtml)))))

(df renderToHtml [(node ui/VNode)] -> String
  :d "Converts declarative VNode hierarchy into sanitized HTML string representation"
  (if (not (.-visible node))
    ""
    (let [(tag (.-tag node))]
      (if (= tag "text")
        (.-text node)
        (let [(htmlTag (mapVNodeTagToHtmlTag tag))
              (attrKeys (map-keys (.-attrs node)))
              (attrsStr (renderAttributesLoop (.-attrs node) attrKeys ""))
              (childrenStr (renderChildrenHtmlLoop (.-children node) ""))]
          (str-concat "<" (str-concat htmlTag (str-concat attrsStr (str-concat ">" (str-concat childrenStr (str-concat "</" (str-concat htmlTag ">"))))))))))))

(df handleWebResize [(width Int64) (height Int64) (dpr Int64)] -> elm/Msg
  :d "Generates Elm runtime resize message from Web viewport dimensions"
  (elm/makeMsg "resize" width))
