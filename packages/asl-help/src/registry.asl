(module asl-help/registry :x [lookupHelpNode help! coreHelpCatalog catalogSize main] :i [(helpNode :a hn)])

fn coreHelpCatalog -> (List hn/HelpNode)
  (list (hn/makeHelpNode "pmap" "concurrency" "0.3.3" "(fn {A B} pmap [(fn [A] -> B) (List A)] -> (List B))" "Applies pure function concurrently across list items." (list "Lambda MUST NOT contain effect marker '!'" "Preserves strict element ordering") "(pmap (fn [x] (* x 2)) '(1 2 3))" 14) (hn/makeHelpNode "par-all!" "concurrency" "0.3.3" "(fn {T} par-all! [(List (fn [] -> T))] -> (List T))" "Executes effectful thunks concurrently in isolated worker threads." (list "Allows effectful operations" "Fails if any branch fails") "(par-all! (list (fn [] (read-file! \"a\")) (fn [] (read-file! \"b\"))))" 16) (hn/makeHelpNode "load!" "eval" "0.3.3" "(fn load! [(Str path)] -> Any)" "Dynamically parses and loads external ASL module at runtime." (list "Path must be resolvable relative to root" "Executes top-level module forms") "(load! \"./math.asl\")" 12) (hn/makeHelpNode "call!" "effect" "0.3.3" "(fn {A B} call! [(fn [A] -> B) A] -> B)" "Invokes an effectful function with explicit caller boundary." (list "Demarcates effect boundary" "Propagates runtime exceptions") "(call! save-to-disk! data)" 11) (hn/makeHelpNode "mem" "memory" "0.3.3" "(fn mem [(Str query)] -> (List Str))" "Queries in-memory vector memory and perceptual knowledge chunks." (list "Pure query operation" "Returns relevant chunk IDs or texts") "(mem \"compression threshold\")" 13) (hn/makeHelpNode "assert-facts-retained" "memory" "0.3.3" "(fn assert-facts-retained [(List Str) (List Str)] -> Bool)" "Asserts that compressed memory chunk preserves all factual claims." (list "Strict equality or semantic inclusion" "Used in amnesia cascade tests") "(assert-facts-retained raw-facts chunk-facts)" 15) (hn/makeHelpNode "help!" "help" "0.3.3" "(fn help! [(Str sym)] -> Str)" "Zero-overhead on-demand query router returning compact ASN HelpNode." (list "Returns compact CS-expression" "Returns :ERR_UNKNOWN_SYMBOL if missing") "(help! \"pmap\")" 14))

fn catalogSize -> I64
  (listLength (coreHelpCatalog))

fn lookupHelpNode sym: Str -> (Option hn/HelpNode)
  (if (stringEmpty? sym) (none) (let [(catalog (coreHelpCatalog))] (fold (fn [(acc (Option hn/HelpNode)) (node hn/HelpNode)] -> (Option hn/HelpNode) (if (some? acc) acc (if (= node.sym sym) (some node) (none)))) (none) catalog)))

fn help! sym: Str -> Str
  (let [(opt (lookupHelpNode sym))] (if (some? opt) (hn/formatHelpNode (optionOr opt (hn/makeEmptyHelpNode))) ":ERR_UNKNOWN_SYMBOL"))

fn ! main -> Str
  (help! "help!")
