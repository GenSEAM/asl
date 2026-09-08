(module asl-help/registry
  :d "In-Memory Help Catalog Registry & Micro-Query Router"
  :x [lookup-help-node
      help!
      core-help-catalog
      catalog-size
      main]
  :i [(help_node :a hn)])

(df core-help-catalog [] -> (List hn/HelpNode)
  :d "Returns canonical list of HelpNode passports for core ASL primitives."
  (list
    (hn/make-help-node
      "pmap"
      "concurrency"
      "0.3.3"
      "(df {A B} pmap [(fn [A] -> B) (List A)] -> (List B))"
      "Applies pure function concurrently across list items."
      (list "Lambda MUST NOT contain effect marker '!'" "Preserves strict element ordering")
      "(pmap (fn [x] (* x 2)) '(1 2 3))"
      14)
    (hn/make-help-node
      "par-all!"
      "concurrency"
      "0.3.3"
      "(df {T} par-all! [(List (fn [] -> T))] -> (List T))"
      "Executes effectful thunks concurrently in isolated worker threads."
      (list "Allows effectful operations" "Fails if any branch fails")
      "(par-all! (list (fn [] (read-file! \"a\")) (fn [] (read-file! \"b\"))))"
      16)
    (hn/make-help-node
      "load!"
      "eval"
      "0.3.3"
      "(df load! [(Str path)] -> Any)"
      "Dynamically parses and loads external ASL module at runtime."
      (list "Path must be resolvable relative to root" "Executes top-level module forms")
      "(load! \"./math.asl\")"
      12)
    (hn/make-help-node
      "call!"
      "effect"
      "0.3.3"
      "(df {A B} call! [(fn [A] -> B) A] -> B)"
      "Invokes an effectful function with explicit caller boundary."
      (list "Demarcates effect boundary" "Propagates runtime exceptions")
      "(call! save-to-disk! data)"
      11)
    (hn/make-help-node
      "mem"
      "memory"
      "0.3.3"
      "(df mem [(Str query)] -> (List Str))"
      "Queries in-memory vector memory and perceptual knowledge chunks."
      (list "Pure query operation" "Returns relevant chunk IDs or texts")
      "(mem \"compression threshold\")"
      13)
    (hn/make-help-node
      "assert-facts-retained"
      "memory"
      "0.3.3"
      "(df assert-facts-retained [(List Str) (List Str)] -> Bool)"
      "Asserts that compressed memory chunk preserves all factual claims."
      (list "Strict equality or semantic inclusion" "Used in amnesia cascade tests")
      "(assert-facts-retained raw-facts chunk-facts)"
      15)
    (hn/make-help-node
      "help!"
      "help"
      "0.3.3"
      "(df help! [(Str sym)] -> Str)"
      "Zero-overhead on-demand query router returning compact ASN HelpNode."
      (list "Returns compact CS-expression" "Returns :ERR_UNKNOWN_SYMBOL if missing")
      "(help! \"pmap\")"
      14)))

(df catalog-size [] -> I64
  :d "Returns the count of registered core primitives."
  (list-length (core-help-catalog)))

(df lookup-help-node [(sym Str)] -> (Option hn/HelpNode)
  :d "Searches the core help catalog for a matching primitive symbol."
  (if (string-empty? sym)
      (none)
      (let [(catalog (core-help-catalog))]
        (fold (fn [(acc (Option hn/HelpNode)) (node hn/HelpNode)] -> (Option hn/HelpNode)
                (if (is-some? acc)
                    acc
                    (if (= (.-sym node) sym)
                        (some node)
                        (none))))
              (none)
              catalog))))

(df help! [(sym Str)] -> Str
  :d "Zero-overhead on-demand query router returning compact ASN HelpNode or ERR_UNKNOWN_SYMBOL."
  (let [(opt (lookup-help-node sym))]
    (if (is-some? opt)
        (hn/format-help-node (option-or opt (hn/make-empty-help-node)))
        ":ERR_UNKNOWN_SYMBOL")))

(df main [] -> Str
  :d "Default package entry point returning help passport for help!."
  (help! "help!"))
