(module aslAgentCore/tests/promptTreeTest :x [runTests TestPromptTreeInitAndRoot TestPromptTreeBranching TestPromptTreeAssemblyAndTokenRatio TestPromptTreeSavingsCalculation] :i [(promptTree :a pt)])

fn TestPromptTreeInitAndRoot -> Bool
  (let [(shared "SYSTEM INVARIANTS: Zero foreign code C1 C2 C3 C4 C5. All tools available.") (tree (pt/promptTreeInit "root" shared))] (assert (= tree.rootId "root") "Root ID must be root") (assert (= (listLength tree.nodes) 1) "Tree must contain exactly 1 node initially") true)

fn TestPromptTreeBranching -> Bool
  (let [(shared "SYSTEM INVARIANTS: Root context.") (tree0 (pt/promptTreeInit "root" shared)) (tree1 (pt/promptTreeBranch tree0 "scout-branch" "root" "ROLE: Scout. Discover files.")) (tree2 (pt/promptTreeBranch tree1 "implementer-branch" "root" "ROLE: Implementer. Write code."))] (assert (= (listLength tree2.nodes) 3) "Tree must contain 3 total nodes after branching") true)

fn TestPromptTreeAssemblyAndTokenRatio -> Bool
  (let [(shared (str "SYSTEM CONTEXT: Large invariant prompt text explaining architecture, " "tools, grammar rules, invariants C1 C2 C3 C4 C5, and repository topology. " "This constitutes the bulk of tokens shared across all swarm agents.")) (delta "ROLE: Architect. Plan Phase 431 DAG.") (tree0 (pt/promptTreeInit "root" shared)) (tree1 (pt/promptTreeBranch tree0 "arch-node" "root" delta)) (resOpt (pt/promptTreeAssemble tree1 "arch-node"))] (mt resOpt ((none) (assert false "Prompt must assemble successfully")) ((some p) (assert (stringContains? p.fullText "SYSTEM CONTEXT") "Must contain root prefix") (assert (stringContains? p.fullText "ROLE: Architect") "Must contain leaf delta") (assert (> p.sharedTokens 0) "Shared tokens must be positive") (assert (> p.sharingRatioPct 70) "Sharing ratio must exceed 70%"))) true)

fn TestPromptTreeSavingsCalculation -> Bool
  (let [(shared "Shared 100-token system prompt prefix.") (tree0 (pt/promptTreeInit "root" shared)) (tree1 (pt/promptTreeBranch tree0 "sub-1" "root" "task 1")) (tree2 (pt/promptTreeBranch tree1 "sub-2" "root" "task 2")) (tree3 (pt/promptTreeBranch tree2 "sub-3" "root" "task 3")) (savings (pt/promptTreeCalcSavings tree3 (list "sub-1" "sub-2" "sub-3")))] (assert (> savings 0) "Token savings must be greater than zero for multi-agent swarm") true)

fn runTests -> Bool
  (and (TestPromptTreeInitAndRoot) (and (TestPromptTreeBranching) (and (TestPromptTreeAssemblyAndTokenRatio) (TestPromptTreeSavingsCalculation))))
