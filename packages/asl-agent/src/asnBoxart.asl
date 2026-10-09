(module aslAgent/asnBoxart :x [BoxNode BoxEdge formatBoxBadge renderTreeBoxart renderDagBoxart] :i [])

(schema BoxNode (:f id Str) (:f title Str) (:f state Str))

(schema BoxEdge (:f from Str) (:f to Str) (:f label (Option Str)))

fn formatBoxBadge state: Str text: Str -> Str
  (let [(icon (cond ((or (= state "done") (or (= state "passed") (= state "ok"))) "[OK]") ((or (= state "running") (or (= state "active") (= state "in-progress"))) "[>]") ((or (= state "failed") (= state "error")) "[FAIL]") ((or (= state "blocked") (= state "waiting")) "[||]") (else "*")))] (str "[" icon "] " text))

fn renderTreeBoxart rootTitle: Str branches: (List Str) -> Str
  (let [(n (listLength branches))] (if (= n 0) rootTitle (let [(body (fold (fn [(acc Str) (idx I64)] -> Str (let [(branch (optionOr (listGet branches idx) "")) (isLast (= idx (- n 1))) (connector (if isLast "+-- " "|-- "))] (str acc "\n" connector branch))) rootTitle (range 0 n)))] body)))

fn renderNodeBox node: BoxNode -> Str
  (let [(badge (formatBoxBadge node.state (str node.id " : " node.title))) (padContent (str "| " badge " |")) (innerLen (+ (stringLength badge) 2)) (topBorder (str "+" (stringRepeat "-" innerLen) "+")) (botBorder (str "+" (stringRepeat "-" innerLen) "+"))] (str topBorder "\n" padContent "\n" botBorder))

fn findOutgoingEdges edges: (List BoxEdge) nodeId: Str -> (List BoxEdge)
  (fold (fn [(acc (List BoxEdge)) (e BoxEdge)] -> (List BoxEdge) (if (= e.from nodeId) (listAppend acc (list e)) acc)) (list) edges)

fn renderDagBoxart nodes: (List BoxNode) edges: (List BoxEdge) -> Str
  (let [(n (listLength nodes))] (if (= n 0) "" (fold (fn [(acc Str) (idx I64)] -> Str (let [(curNode (optionOr (listGet nodes idx) (BoxNode :id "" :title "" :state ""))) (boxStr (renderNodeBox curNode)) (isLast (= idx (- n 1))) (outEdges (findOutgoingEdges edges curNode.id)) (hasEdge (> (listLength outEdges) 0)) (edgeOpt (listGet outEdges 0)) (lblStr (mt edgeOpt ((none) "") ((some ed) (mt ed.label ((none) "") ((some l) (str " (" l ")")))))) (connector (if (not isLast) (if hasEdge (str "\n       |" lblStr "\n       [v]\n") "\n\n") ""))] (if (stringEmpty? acc) (str boxStr connector) (str acc boxStr connector)))) "" (range 0 n))))
