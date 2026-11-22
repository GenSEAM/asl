(module asl-vault/graph
  :x [edgeProblem outgoingOf incomingOf contradictionsOf neighbours contradictsPair?]
  :i [(asl-vault/model :a m) (asl-vault/codec :a cd)])

; (:m :ref VS-VAULT :do "an edge joins two different entries by one of the four relations with a weight of 1 to 10000 basis points; existence of the endpoints is the caller's check against the store")
fn edgeProblem e: m/Edge -> (Option String)
  (cd/firstFailure
    (list (cd/check (cd/validId? e.fromId) (str "invalid fromId " e.fromId))
          (cd/check (cd/validId? e.toId) (str "invalid toId " e.toId))
          (cd/check (!= e.fromId e.toId) "self-edge not allowed")
          (cd/check (m/validRelation? e.relation) (str "invalid relation " e.relation))
          (cd/check (and (>= e.weightBp 1) (<= e.weightBp 10000)) "weightBp must be 1..10000")))

fn outgoingOf edges: (List m/Edge) id: String -> (List m/Edge)
  (filter (fn [(e m/Edge)] -> Bool (= e.fromId id)) edges)

fn incomingOf edges: (List m/Edge) id: String -> (List m/Edge)
  (filter (fn [(e m/Edge)] -> Bool (= e.toId id)) edges)

fn contradictsPair? e: m/Edge a: String b: String -> Bool
  (and (= e.relation "contradicts") (m/pairMatches? a b e.fromId e.toId))

; (:m :ref VS-VAULT :do "ids joined to id by a contradicts edge in either direction, once each in edge order")
fn contradictionsOf edges: (List m/Edge) id: String -> (List String)
  (cd/dedupStrings (map (fn [(e m/Edge)] -> String (if (= e.fromId id) e.toId e.fromId))
                   (filter (fn [(e m/Edge)] -> Bool (and (= e.relation "contradicts") (or (= e.fromId id) (= e.toId id)))) edges)))

fn neighbours edges: (List m/Edge) id: String -> (List String)
  (cd/dedupStrings (listAppend (map (fn [(e m/Edge)] -> String e.toId) (outgoingOf edges id)) (map (fn [(e m/Edge)] -> String e.fromId) (incomingOf edges id))))
