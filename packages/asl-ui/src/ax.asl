(module asl-ui/ax :x [AXNode makeAXNode makeEmptyAXNode mapTagToAriaRole resolveAccessibleName projectAccessibilityTree getFocusTrappedTargets] :i [(asl-ui/vnode :a ui)])

(schema AXNode (:f anchor String) (:f role String) (:f name String) (:f disabled Bool) (:f hidden Bool) (:f ariaModal Bool) (:f children (List AXNode)))

fn makeAXNode anchor: String role: String name: String disabled: Bool hidden: Bool ariaModal: Bool children: (List AXNode) -> AXNode
  (AXNode :anchor anchor :role role :name name :disabled disabled :hidden hidden :ariaModal ariaModal :children children)

fn makeEmptyAXNode -> AXNode
  (AXNode :anchor "" :role "generic" :name "" :disabled false :hidden false :ariaModal false :children (list))

fn mapTagToAriaRole tag: String attrs: (Map String String) -> String
  (if (= tag "button") "button" (if (= tag "input") (let [(inpType (optionOr (mapGet attrs "type") "text"))] (if (= inpType "checkbox") "checkbox" "textbox")) (if (= tag "list") "list" (if (= tag "modal") "dialog" (if (= tag "canvas") "img" (if (= tag "container") (let [(hasLabel (some? (mapGet attrs "aria-label"))) (hasLabelledBy (some? (mapGet attrs "aria-labelledby")))] (if (or hasLabel hasLabelledBy) "region" "group")) (if (= tag "text") "text" "generic")))))))

fn findTargetText node: ui/VNode targetId: String -> String
  (if (= node.key targetId) (if (> (stringLength node.text) 0) node.text (let [(ch node.children)] (if (not (listEmpty? ch)) (let [(firstCh (optionOr (listHead ch) (ui/makeText "" "")))] (if (= firstCh.tag "text") firstCh.text node.key)) node.key))) (findTargetTextChildren node.children targetId))

fn findTargetTextChildren children: (List ui/VNode) targetId: String -> String
  (if (listEmpty? children) "" (let [(head (optionOr (listHead children) (ui/makeText "" ""))) (found (findTargetText head targetId))] (if (> (stringLength found) 0) found (findTargetTextChildren (optionOr (listTail children) (list)) targetId))))

fn resolveAccessibleName node: ui/VNode root: ui/VNode -> String
  (let [(attrs node.attrs) (optAriaLabel (mapGet attrs "aria-label"))] (if (and (some? optAriaLabel) (> (stringLength (optionOr optAriaLabel "")) 0)) (optionOr optAriaLabel "") (let [(optAriaLabelledBy (mapGet attrs "aria-labelledby"))] (if (and (some? optAriaLabelledBy) (> (stringLength (optionOr optAriaLabelledBy "")) 0)) (let [(targetText (findTargetText root (optionOr optAriaLabelledBy "")))] (if (> (stringLength targetText) 0) targetText (if (> (stringLength node.key) 0) node.key node.tag))) (if (> (stringLength node.text) 0) node.text (let [(children node.children)] (if (not (listEmpty? children)) (let [(firstChild (optionOr (listHead children) (ui/makeText "" "")))] (if (= firstChild.tag "text") firstChild.text (if (> (stringLength node.key) 0) node.key node.tag))) (if (> (stringLength node.key) 0) node.key node.tag))))))))

fn projectAxChildren children: (List ui/VNode) root: ui/VNode acc: (List AXNode) -> (List AXNode)
  (if (listEmpty? children) (listReverse acc) (let [(head (optionOr (listHead children) (ui/makeText "" ""))) (axChild (projectAxNode head root)) (tail (optionOr (listTail children) (list)))] (projectAxChildren tail root (cons axChild acc))))

fn projectAxNode node: ui/VNode root: ui/VNode -> AXNode
  (let [(tag node.tag) (key node.key) (attrs node.attrs) (anchor (if (> (stringLength key) 0) key tag)) (role (mapTagToAriaRole tag attrs)) (name (resolveAccessibleName node root)) (disabled (= (optionOr (mapGet attrs "disabled") "false") "true")) (hidden (or (not node.visible) (= (optionOr (mapGet attrs "hidden") "false") "true"))) (ariaModal (= tag "modal")) (axChildren (projectAxChildren node.children root (list)))] (makeAXNode anchor role name disabled hidden ariaModal axChildren))

fn projectAccessibilityTree rootNode: ui/VNode -> AXNode
  (projectAxNode rootNode rootNode)

fn isInteractiveRole role: String -> Bool
  (or (= role "button") (or (= role "textbox") (= role "checkbox")))

fn collectFocusTargets node: AXNode acc: (List String) -> (List String)
  (let [(role node.role) (anchor node.anchor) (dis node.disabled) (hid node.hidden) (isInteractive (and (isInteractiveRole role) (and (not dis) (not hid)))) (nextAcc (if isInteractive (cons anchor acc) acc))] (collectFocusTargetsChildren node.children nextAcc))

fn collectFocusTargetsChildren children: (List AXNode) acc: (List String) -> (List String)
  (if (listEmpty? children) acc (let [(head (optionOr (listHead children) (makeEmptyAXNode))) (tail (optionOr (listTail children) (list))) (accAfterHead (collectFocusTargets head acc))] (collectFocusTargetsChildren tail accAfterHead)))

fn getFocusTrappedTargets modalNode: AXNode -> (List String)
  (let [(collectedReversed (collectFocusTargetsChildren modalNode.children (list)))] (listReverse collectedReversed))
