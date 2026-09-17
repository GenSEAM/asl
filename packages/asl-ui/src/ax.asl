(module asl-ui/ax
  :d "Pure AgentScript Semantic Accessibility Projection and ARIA Role Mapping"
  :x [AXNode
      makeAXNode
      makeEmptyAXNode
      mapTagToAriaRole
      resolveAccessibleName
      projectAccessibilityTree
      getFocusTrappedTargets]
  :i [(asl-ui/vnode :a ui)])

(dfs AXNode
  (:f anchor String)
  (:f role String)
  (:f name String)
  (:f disabled Bool)
  (:f hidden Bool)
  (:f ariaModal Bool)
  (:f children (List AXNode)))

(df makeAXNode [(anchor String)
                (role String)
                (name String)
                (disabled Bool)
                (hidden Bool)
                (ariaModal Bool)
                (children (List AXNode))] -> AXNode
  :d "Constructs an accessibility tree node"
  (AXNode :anchor anchor
          :role role
          :name name
          :disabled disabled
          :hidden hidden
          :ariaModal ariaModal
          :children children))

(df makeEmptyAXNode [] -> AXNode
  :d "Constructs an empty sentinel accessibility node"
  (AXNode :anchor ""
          :role "generic"
          :name ""
          :disabled false
          :hidden false
          :ariaModal false
          :children (list)))

(df mapTagToAriaRole [(tag String) (attrs (Map String String))] -> String
  :d "Maps declarative UI tag and attributes to standard ARIA accessibility role"
  (if (= tag "button")
    "button"
    (if (= tag "input")
      (let [(inpType (option-or (map-get attrs "type") "text"))]
        (if (= inpType "checkbox")
          "checkbox"
          "textbox"))
      (if (= tag "list")
        "list"
        (if (= tag "modal")
          "dialog"
          (if (= tag "canvas")
            "img"
            (if (= tag "container")
              (let [(hasLabel (is-some? (map-get attrs "aria-label")))
                    (hasLabelledBy (is-some? (map-get attrs "aria-labelledby")))]
                (if (or hasLabel hasLabelledBy)
                  "region"
                  "group"))
              (if (= tag "text")
                "text"
                "generic"))))))))

(df findTargetText [(node ui/VNode) (targetId String)] -> String
  :d "Finds target node text by matching anchor key in VNode hierarchy"
  (if (= (.-key node) targetId)
    (if (> (string-length (.-text node)) 0)
      (.-text node)
      (let [(ch (.-children node))]
        (if (not (list-empty? ch))
          (let [(firstCh (option-or (list-head ch) (ui/makeText "" "")))]
            (if (= (.-tag firstCh) "text")
              (.-text firstCh)
              (.-key node)))
          (.-key node))))
    (findTargetTextChildren (.-children node) targetId)))

(df findTargetTextChildren [(children (List ui/VNode)) (targetId String)] -> String
  :d "Searches child list for target element text"
  (if (list-empty? children)
    ""
    (let [(head (option-or (list-head children) (ui/makeText "" "")))
          (found (findTargetText head targetId))]
      (if (> (string-length found) 0)
        found
        (findTargetTextChildren (option-or (list-tail children) (list)) targetId)))))

(df resolveAccessibleName [(node ui/VNode) (root ui/VNode)] -> String
  :d "Resolves accessible name following 4-tier hierarchy: aria-label > aria-labelledby > text > anchor"
  (let [(attrs (.-attrs node))
        (optAriaLabel (map-get attrs "aria-label"))]
    (if (and (is-some? optAriaLabel) (> (string-length (option-or optAriaLabel "")) 0))
      (option-or optAriaLabel "")
      (let [(optAriaLabelledBy (map-get attrs "aria-labelledby"))]
        (if (and (is-some? optAriaLabelledBy) (> (string-length (option-or optAriaLabelledBy "")) 0))
          (let [(targetText (findTargetText root (option-or optAriaLabelledBy "")))]
            (if (> (string-length targetText) 0)
              targetText
              (if (> (string-length (.-key node)) 0) (.-key node) (.-tag node))))
          (if (> (string-length (.-text node)) 0)
            (.-text node)
            (let [(children (.-children node))]
              (if (not (list-empty? children))
                (let [(firstChild (option-or (list-head children) (ui/makeText "" "")))]
                  (if (= (.-tag firstChild) "text")
                    (.-text firstChild)
                    (if (> (string-length (.-key node)) 0) (.-key node) (.-tag node))))
                (if (> (string-length (.-key node)) 0) (.-key node) (.-tag node))))))))))

(df projectAxChildren [(children (List ui/VNode)) (root ui/VNode) (acc (List AXNode))] -> (List AXNode)
  :d "Recursively projects list of child VNodes"
  (if (list-empty? children)
    (list-reverse acc)
    (let [(head (option-or (list-head children) (ui/makeText "" "")))
          (axChild (projectAxNode head root))
          (tail (option-or (list-tail children) (list)))]
      (projectAxChildren tail root (list-cons axChild acc)))))

(df projectAxNode [(node ui/VNode) (root ui/VNode)] -> AXNode
  :d "Recursively projects VNode into AXNode"
  (let [(tag (.-tag node))
        (key (.-key node))
        (attrs (.-attrs node))
        (anchor (if (> (string-length key) 0) key tag))
        (role (mapTagToAriaRole tag attrs))
        (name (resolveAccessibleName node root))
        (disabled (= (option-or (map-get attrs "disabled") "false") "true"))
        (hidden (or (not (.-visible node)) (= (option-or (map-get attrs "hidden") "false") "true")))
        (ariaModal (= tag "modal"))
        (axChildren (projectAxChildren (.-children node) root (list)))]
    (makeAXNode anchor role name disabled hidden ariaModal axChildren)))

(df projectAccessibilityTree [(rootNode ui/VNode)] -> AXNode
  :d "Projects declarative VNode tree into complete semantic AXNode tree"
  (projectAxNode rootNode rootNode))

(df isInteractiveRole [(role String)] -> Bool
  :d "Determines whether role represents an interactive control"
  (or (= role "button") (or (= role "textbox") (= role "checkbox"))))

(df collectFocusTargets [(node AXNode) (acc (List String))] -> (List String)
  :d "Traverses accessibility subtree collecting focus-trappable interactive target anchors"
  (let [(role (.-role node))
        (anchor (.-anchor node))
        (dis (.-disabled node))
        (hid (.-hidden node))
        (isInteractive (and (isInteractiveRole role) (and (not dis) (not hid))))
        (nextAcc (if isInteractive (list-cons anchor acc) acc))]
    (collectFocusTargetsChildren (.-children node) nextAcc)))

(df collectFocusTargetsChildren [(children (List AXNode)) (acc (List String))] -> (List String)
  :d "Recursively traverses child accessibility nodes collecting focus targets"
  (if (list-empty? children)
    acc
    (let [(head (option-or (list-head children) (makeEmptyAXNode)))
          (tail (option-or (list-tail children) (list)))
          (accAfterHead (collectFocusTargets head acc))]
      (collectFocusTargetsChildren tail accAfterHead))))

(df getFocusTrappedTargets [(modalNode AXNode)] -> (List String)
  :d "Returns ordered list of focusable interactive target anchors trapped within modal"
  (let [(collectedReversed (collectFocusTargetsChildren (.-children modalNode) (list)))]
    (list-reverse collectedReversed)))
