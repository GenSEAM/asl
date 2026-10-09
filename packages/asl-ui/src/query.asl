(module asl-ui/query :x [SemanticReceipt makeSemanticReceipt queryAxNodeByAnchor queryAllAxNodesByRole describeAxNode dispatchSemanticAction] :i [(asl-ui/ax :a ax) (asl-ui/runtime :a elm)])

(schema SemanticReceipt (:f status String) (:f reason String) (:f anchor String) (:f msg (Option elm/Msg)))

fn makeSemanticReceipt status: String reason: String anchor: String msg: (Option elm/Msg) -> SemanticReceipt
  (SemanticReceipt :status status :reason reason :anchor anchor :msg msg)

fn queryAxNodeByAnchor root: ax/AXNode anchor: String -> (Option ax/AXNode)
  (if (= root.anchor anchor) (some root) (queryAxChildrenByAnchor root.children anchor))

fn queryAxChildrenByAnchor children: (List ax/AXNode) anchor: String -> (Option ax/AXNode)
  (if (listEmpty? children) (none) (let [(head (optionOr (listHead children) (ax/makeEmptyAXNode))) (found (queryAxNodeByAnchor head anchor))] (if (some? found) found (queryAxChildrenByAnchor (optionOr (listTail children) (list)) anchor))))

fn collectNodesByRole node: ax/AXNode role: String acc: (List ax/AXNode) -> (List ax/AXNode)
  (let [(matches (= node.role role)) (nextAcc (if matches (cons node acc) acc))] (collectChildrenByRole node.children role nextAcc))

fn collectChildrenByRole children: (List ax/AXNode) role: String acc: (List ax/AXNode) -> (List ax/AXNode)
  (if (listEmpty? children) acc (let [(head (optionOr (listHead children) (ax/makeEmptyAXNode))) (tail (optionOr (listTail children) (list))) (accAfterHead (collectNodesByRole head role acc))] (collectChildrenByRole tail role accAfterHead)))

fn queryAllAxNodesByRole root: ax/AXNode role: String -> (List ax/AXNode)
  (listReverse (collectNodesByRole root role (list)))

fn describeAxNode node: ax/AXNode -> String
  (let [(anchorStr (stringConcat "(:axNode :anchor \"" (stringConcat node.anchor "\""))) (roleStr (stringConcat " :role \"" (stringConcat node.role "\""))) (nameStr (stringConcat " :name \"" (stringConcat node.name "\""))) (disStr (stringConcat " :disabled " (if node.disabled "true" "false"))) (hidStr (stringConcat " :hidden " (if node.hidden "true" "false"))) (modalStr (stringConcat " :ariaModal " (if node.ariaModal "true)" "false)")))] (stringConcat anchorStr (stringConcat roleStr (stringConcat nameStr (stringConcat disStr (stringConcat hidStr modalStr))))))

fn dispatchSemanticAction root: ax/AXNode action: String anchor: String param: String -> SemanticReceipt
  (let [(optNode (queryAxNodeByAnchor root anchor))] (if (none? optNode) (makeSemanticReceipt "error" "NOT_FOUND" anchor (none)) (let [(node (optionOr optNode (ax/makeEmptyAXNode)))] (if node.disabled (makeSemanticReceipt "error" "DISABLED" anchor (none)) (if node.hidden (makeSemanticReceipt "error" "HIDDEN" anchor (none)) (if (= action "click") (makeSemanticReceipt "ok" "SUCCESS" anchor (some (elm/makeMsg "click" 1))) (if (= action "input") (makeSemanticReceipt "ok" "SUCCESS" anchor (some (elm/makeMsg "input" (stringLength param)))) (makeSemanticReceipt "error" "UNSUPPORTED_ACTION" anchor (none)))))))))
