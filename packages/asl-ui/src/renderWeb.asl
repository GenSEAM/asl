(module asl-ui/renderWeb :x [DomPatch makeDomPatch makeEmptyDomPatch applyDomMutations renderToHtml handleWebResize] :i [(asl-ui/vnode :a ui) (asl-ui/runtime :a elm) (asl-ui/arena :a arena)])

(schema DomPatch (:f opcode String) (:f targetKey String) (:f param1 String) (:f param2 String))

fn makeDomPatch opcode: String targetKey: String param1: String param2: String -> DomPatch
  (DomPatch :opcode opcode :targetKey targetKey :param1 param1 :param2 param2)

fn makeEmptyDomPatch -> DomPatch
  (DomPatch :opcode "DOM_NOOP" :targetKey "" :param1 "" :param2 "")

fn mapMutationToPatch mut: arena/MutationRecord -> DomPatch
  (let [(k mut.kind) (key mut.targetKey) (tag mut.node.tag)] (if (= k "insert") (makeDomPatch "DOM_INSERT" key tag "") (if (= k "remove") (makeDomPatch "DOM_REMOVE" key tag "") (if (= k "update") (makeDomPatch "DOM_UPDATE" key tag "") (makeDomPatch "DOM_NOOP" key "" "")))))

fn applyDomMutationsLoop muts: (List arena/MutationRecord) acc: (List DomPatch) -> (List DomPatch)
  (if (listEmpty? muts) acc (let [(head (optionOr (listHead muts) (arena/makeMutationRecord "" "" (ui/makeText "" "") (mapEmpty) 0))) (tail (optionOr (listTail muts) (list))) (patch (mapMutationToPatch head))] (applyDomMutationsLoop tail (listAppend acc (list patch)))))

fn applyDomMutations mutations: (List arena/MutationRecord) -> (List DomPatch)
  (applyDomMutationsLoop mutations (list))

fn mapVNodeTagToHtmlTag tag: String -> String
  (if (= tag "container") "div" (if (= tag "modal") "div" (if (= tag "list") "ul" tag)))

fn renderAttributesLoop attrs: (Map String String) keys: (List String) acc: String -> String
  (if (listEmpty? keys) acc (let [(k (optionOr (listHead keys) "")) (tail (optionOr (listTail keys) (list))) (val (optionOr (mapGet attrs k) "")) (attrPair (stringConcat " " (stringConcat k (stringConcat "=\"" (stringConcat val "\"")))))] (renderAttributesLoop attrs tail (stringConcat acc attrPair))))

fn renderChildrenHtmlLoop children: (List ui/VNode) acc: String -> String
  (if (listEmpty? children) acc (let [(head (optionOr (listHead children) (ui/makeText "" ""))) (tail (optionOr (listTail children) (list))) (childHtml (renderToHtml head))] (renderChildrenHtmlLoop tail (stringConcat acc childHtml))))

fn renderToHtml node: ui/VNode -> String
  (if (not node.visible) "" (let [(tag node.tag)] (if (= tag "text") node.text (let [(htmlTag (mapVNodeTagToHtmlTag tag)) (attrKeys (mapKeys node.attrs)) (attrsStr (renderAttributesLoop node.attrs attrKeys "")) (childrenStr (renderChildrenHtmlLoop node.children ""))] (stringConcat "<" (stringConcat htmlTag (stringConcat attrsStr (stringConcat ">" (stringConcat childrenStr (stringConcat "</" (stringConcat htmlTag ">")))))))))))

fn handleWebResize width: Int64 height: Int64 dpr: Int64 -> elm/Msg
  (elm/makeMsg "resize" width)
