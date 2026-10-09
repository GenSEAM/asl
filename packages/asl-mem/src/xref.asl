(module aslMem/xref :x [XRefEdge XRefGraph makeXrefGraph listAddUnique xrefAddEdge findDependents findPrerequisites findProvenance xrefForwardEdges xrefBackwardEdges xrefHasNode?] :i [])

(schema XRefEdge (:f source Str) (:f target Str) (:f relation Str))

(schema XRefGraph (:f nodes (List Str)) (:f edges (List XRefEdge)) (:f forward (Map Str (List Str))) (:f backward (Map Str (List Str))) (:f provenanceMap (Map Str (List Str))) (:f prereqMap (Map Str (List Str))) (:f depMap (Map Str (List Str))))

fn makeXrefGraph -> XRefGraph
  (XRefGraph :nodes (list) :edges (list) :forward (mapEmpty) :backward (mapEmpty) :provenanceMap (mapEmpty) :prereqMap (mapEmpty) :depMap (mapEmpty))

fn listAddUnique lst: (List Str) item: Str -> (List Str)
  (if (listContains? lst item) lst (listAppend lst (list item)))

fn xrefHasNode? g: XRefGraph id: Str -> Bool
  (listContains? g.nodes id)

fn xrefForwardEdges g: XRefGraph nodeId: Str -> (List Str)
  (optionOr (mapGet g.forward nodeId) (list))

fn xrefBackwardEdges g: XRefGraph nodeId: Str -> (List Str)
  (optionOr (mapGet g.backward nodeId) (list))

fn xrefAddEdge g: XRefGraph source: Str target: Str relation: Str -> XRefGraph
  (let [(edge (XRefEdge :source source :target target :relation relation)) (n1 (listAddUnique g.nodes source)) (newNodes (listAddUnique n1 target)) (newEdges (listAppend g.edges (list edge))) (fwdList (optionOr (mapGet g.forward source) (list))) (newFwd (mapSet g.forward source (listAddUnique fwdList target))) (bwdList (optionOr (mapGet g.backward target) (list))) (newBwd (mapSet g.backward target (listAddUnique bwdList source))) (isDep (= relation "depends-on")) (isPrereq (or (= relation "prerequisite") (= relation "requires"))) (isProv (or (= relation "provenance") (or (= relation "derives-from") (or (= relation "justified-by") (and (or (= relation "ref") (= relation "references")) (or (stringStartsWith? target "adr:") (or (stringStartsWith? target "d:") (or (stringStartsWith? target "c:") (stringStartsWith? target "task:"))))))))) (pList (optionOr (mapGet g.prereqMap source) (list))) (newPrereq (if isPrereq (mapSet g.prereqMap source (listAddUnique pList target)) g.prereqMap)) (dList (optionOr (mapGet g.depMap target) (list))) (newDep (if isDep (mapSet g.depMap target (listAddUnique dList source)) g.depMap)) (provList (optionOr (mapGet g.provenanceMap source) (list))) (newProv (if isProv (mapSet g.provenanceMap source (listAddUnique provList target)) g.provenanceMap))] (XRefGraph :nodes newNodes :edges newEdges :forward newFwd :backward newBwd :provenanceMap newProv :prereqMap newPrereq :depMap newDep))

fn findDependents g: XRefGraph nodeId: Str -> (List Str)
  (optionOr (mapGet g.depMap nodeId) (list))

fn findPrerequisites g: XRefGraph nodeId: Str -> (List Str)
  (optionOr (mapGet g.prereqMap nodeId) (list))

fn findProvenance g: XRefGraph nodeId: Str -> (List Str)
  (optionOr (mapGet g.provenanceMap nodeId) (list))
