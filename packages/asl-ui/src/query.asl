(module asl-ui/query
  :d "Pure AgentScript Symbolic Agent Perception Query Engine and Semantic Action Dispatch"
  :x [SemanticReceipt
      makeSemanticReceipt
      queryAxNodeByAnchor
      queryAllAxNodesByRole
      describeAxNode
      dispatchSemanticAction]
  :i [(asl-ui/ax :a ax)
      (asl-ui/runtime :a elm)])

(dfs SemanticReceipt
  (:f status String)
  (:f reason String)
  (:f anchor String)
  (:f msg (Option elm/Msg)))

(df makeSemanticReceipt [(status String)
                         (reason String)
                         (anchor String)
                         (msg (Option elm/Msg))] -> SemanticReceipt
  :d "Constructs a semantic action dispatch receipt"
  (SemanticReceipt :status status
                   :reason reason
                   :anchor anchor
                   :msg msg))

(df queryAxNodeByAnchor [(root ax/AXNode) (anchor String)] -> (Option ax/AXNode)
  :d "Searches accessibility tree for node matching anchor identifier"
  (if (= (.-anchor root) anchor)
    (some root)
    (queryAxChildrenByAnchor (.-children root) anchor)))

(df queryAxChildrenByAnchor [(children (List ax/AXNode)) (anchor String)] -> (Option ax/AXNode)
  :d "Recursively traverses children searching for matching anchor"
  (if (list-empty? children)
    (none)
    (let [(head (option-or (list-head children) (ax/makeEmptyAXNode)))
          (found (queryAxNodeByAnchor head anchor))]
      (if (is-some? found)
        found
        (queryAxChildrenByAnchor (option-or (list-tail children) (list)) anchor)))))

(df collectNodesByRole [(node ax/AXNode) (role String) (acc (List ax/AXNode))] -> (List ax/AXNode)
  :d "Helper collecting nodes matching role in traversal order"
  (let [(matches (= (.-role node) role))
        (nextAcc (if matches (list-cons node acc) acc))]
    (collectChildrenByRole (.-children node) role nextAcc)))

(df collectChildrenByRole [(children (List ax/AXNode)) (role String) (acc (List ax/AXNode))] -> (List ax/AXNode)
  :d "Helper traversing children collecting nodes matching role"
  (if (list-empty? children)
    acc
    (let [(head (option-or (list-head children) (ax/makeEmptyAXNode)))
          (tail (option-or (list-tail children) (list)))
          (accAfterHead (collectNodesByRole head role acc))]
      (collectChildrenByRole tail role accAfterHead))))

(df queryAllAxNodesByRole [(root ax/AXNode) (role String)] -> (List ax/AXNode)
  :d "Queries all accessibility nodes matching specified ARIA role"
  (list-reverse (collectNodesByRole root role (list))))

(df describeAxNode [(node ax/AXNode)] -> String
  :d "Renders a high-SNR symbolic S-expression representation of an AXNode"
  (let [(anchorStr (str-concat "(:axNode :anchor \"" (str-concat (.-anchor node) "\"")))
        (roleStr (str-concat " :role \"" (str-concat (.-role node) "\"")))
        (nameStr (str-concat " :name \"" (str-concat (.-name node) "\"")))
        (disStr (str-concat " :disabled " (if (.-disabled node) "true" "false")))
        (hidStr (str-concat " :hidden " (if (.-hidden node) "true" "false")))
        (modalStr (str-concat " :ariaModal " (if (.-ariaModal node) "true)" "false)")))]
    (str-concat anchorStr (str-concat roleStr (str-concat nameStr (str-concat disStr (str-concat hidStr modalStr)))))))

(df dispatchSemanticAction [(root ax/AXNode)
                            (action String)
                            (anchor String)
                            (param String)] -> SemanticReceipt
  :d "Dispatches a simulated semantic user action to target anchor returning structured typed receipt"
  (let [(optNode (queryAxNodeByAnchor root anchor))]
    (if (is-none? optNode)
      (makeSemanticReceipt "error" "NOT_FOUND" anchor (none))
      (let [(node (option-or optNode (ax/makeEmptyAXNode)))]
        (if (.-disabled node)
          (makeSemanticReceipt "error" "DISABLED" anchor (none))
          (if (.-hidden node)
            (makeSemanticReceipt "error" "HIDDEN" anchor (none))
            (if (= action "click")
              (makeSemanticReceipt "ok" "SUCCESS" anchor (some (elm/makeMsg "click" 1)))
              (if (= action "input")
                (makeSemanticReceipt "ok" "SUCCESS" anchor (some (elm/makeMsg "input" (string-length param))))
                (makeSemanticReceipt "error" "UNSUPPORTED_ACTION" anchor (none))))))))))
