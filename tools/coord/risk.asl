(module asl-tools/coord/risk
  :x [RiskInput Signal Risk packageOf signalsOf tierOf assess]
  :i [])

(schema RiskInput
  (:f names (List String))
  (:f deleted (List String))
  (:f lines Int)
  (:f added (List String))
  (:f closure (List String))
  (:f gateKind String)
  (:f priorSigs Int)
  (:f mutantHistory Bool)
  (:f publicSurface Bool))

(schema Signal
  (:f name String)
  (:f weight Int))

(schema Risk
  (:f score Int)
  (:f tier String)
  (:f signals (List Signal)))

; (:m :ref RISK-HOTPACKAGES-AGENT :do "hot package keys as packageOf derives them, bare of the asl- prefix: the agent code is agentLoop while it lives in asl/agentLoop/ (packageOf names that directory, which would otherwise key as asl) and agent once it is the package asl/packages/asl-agent")
fn hotPackages -> (List String)
  (list "host" "runtime" "llvm" "seed" "gateway" "coord" "agentLoop" "agent")

fn spawnMarkers -> (List String)
  (list "spawn" "procExePath" "fileDelete" "~/.asl" "/.asl/")

fn anyStr? xs: (List String) p: (fn [String] -> Bool) -> Bool
  (some? (listHead (filter p xs)))

fn segment path: String n: Int -> String
  (let [(parts (stringSplit path "/"))]
    (if (< n (listLength parts)) (optionOr (listGet parts n) "") ""))

fn packageOf path: String -> String
  (cond
    ((stringStartsWith? path "asl/host/") "asl-host")
    ((stringStartsWith? path "asl/packages/") (segment path 2))
    ((stringStartsWith? path "asl/tools/") (segment path 2))
    ((stringStartsWith? path "asl/agentLoop/") "agentLoop")
    (else (segment path 0)))

fn bare pkg: String -> String
  (if (stringStartsWith? pkg "asl-") (optionOr (stringSlice pkg 4 (stringLength pkg)) pkg) pkg)

fn distinctPackages names: (List String) -> (List String)
  (fold (fn [(acc (List String)) (n String)] -> (List String)
          (if (listContains? acc (packageOf n)) acc (listAppend acc (list (packageOf n)))))
        (list) names)

fn inClosure? input: RiskInput -> Bool
  (anyStr? input.names (fn [(n String)] -> Bool
    (anyStr? input.closure (fn [(c String)] -> Bool (stringStartsWith? n c)))))

fn hot? input: RiskInput -> Bool
  (anyStr? (distinctPackages input.names) (fn [(p String)] -> Bool (listContains? (hotPackages) (bare p))))

fn spread? input: RiskInput -> Bool
  (or (> (listLength input.names) 4)
      (> (listLength (distinctPackages input.names)) 1)
      (> input.lines 300))

fn spawnOrFs? input: RiskInput -> Bool
  (anyStr? input.added (fn [(l String)] -> Bool
    (anyStr? (spawnMarkers) (fn [(m String)] -> Bool (stringContains? l m)))))

fn gateWeight kind: String -> Int
  (cond
    ((= kind "none") 3)
    ((= kind "checkOnly") 2)
    ((= kind "corpus") 1)
    ((= kind "native") 1)
    (else 0))

fn add name: String weight: Int on: Bool acc: (List Signal) -> (List Signal)
  (if (and on (> weight 0)) (listAppend acc (list (Signal :name name :weight weight))) acc)

fn signalsOf input: RiskInput -> (List Signal)
  (let [(a (add "closureChanged" 3 (inClosure? input) (list)))
        (b (add "hotPackage" 2 (hot? input) a))
        (c (add "spread" 1 (spread? input) b))
        (d (add "deletes" 2 (not (listEmpty? input.deleted)) c))
        (e (add "spawnOrFs" 3 (spawnOrFs? input) d))
        (f (add "gateKind" (gateWeight input.gateKind) true e))
        (g (add "priorSigs" 1 (>= input.priorSigs 2) f))
        (h (add "mutantHistory" 1 input.mutantHistory g))]
    (add "publicSurface" 1 input.publicSurface h))

fn tierOf score: Int -> String
  (cond
    ((>= score 5) "high")
    ((>= score 2) "med")
    (else "low"))

fn assess input: RiskInput -> Risk
  (let [(sigs (signalsOf input))
        (score (fold (fn [(a Int) (s Signal)] -> Int (+ a s.weight)) 0 sigs))]
    (Risk :score score :tier (tierOf score) :signals sigs))
