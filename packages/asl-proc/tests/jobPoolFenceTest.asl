(module asl-proc/jobPoolFenceTest :x [runTests] :i [(jobPool :a jp)])

; (:m :ref NODE2-SIGSTOP-RC :do "the package copy of the tree killer under the node2 snapshot of 2026-10-30 in miniature: user manager 19144, sshd 500/501, login shell 600, a job wrapper 700 whose group holds the killer 720 and its parent 710, the killer's job 740 with 741 and 742 (742 in the conductor's group 800), and a foreign sleeper 900 with ppid 1")
fn nodeSnapshot -> String
  "    1     0     1 S launchd\n19144     1 19144 S systemd\n  500     1   500 S sshd\n  501   500   501 S sshd-session\n  600   501   600 S bash\n  700 19144   700 S perl\n  710   700   700 S sh\n  720   710   700 S test\n  730   720   700 S sleep\n  740   720   740 S sh\n  741   740   740 S sleep\n  742   741   800 S sleep\n  800 19144   800 S conductor\n  810   800   800 S writer\n  900     1   900 S sleep\n  910   900   900 S sleep\n"

fn testFence -> Bool
  (let [(procs (jp/procsOf (nodeSnapshot)))
        (pids (map (fn [(p jp/Proc)] -> Int64 p.pid) procs))
        (zero (jp/treeOf procs 0 (list) (list) 720))
        (init (jp/treeOf procs 1 (list) (list) 720))
        (parent (jp/treeOf procs 710 (list 700) (list 720 730) 720))
        (job (jp/treeOf procs 740 (list 900 19144 600 700 800 740) (list 900 910 19144 600 710 800) 720))
        (members (pairFirst job))
        (groups (pairSecond job))]
    (do (refute (listContains? pids 19144) "the user manager (comm systemd) is never a snapshot row")
        (refute (listContains? pids 501) "an sshd session process is never a snapshot row")
        (assert (listEmpty? (pairFirst zero)) (str "a root of 0 has an empty tree, not every process: " (pairFirst zero)))
        (assert (listEmpty? (pairFirst init)) (str "a root of 1 has an empty tree, not every orphan of init: " (pairFirst init)))
        (assert (listEmpty? (pairFirst parent)) (str "the killer's own parent as root gives an empty tree: " (pairFirst parent)))
        (assert (and (= (listLength members) 2) (and (listContains? members 741) (listContains? members 742))) (str "the job's tree is its two children and nothing else: " members))
        (refute (listContains? members 900) "a foreign sleeper with ppid 1 in known is not stopped")
        (refute (listContains? members 810) "a member in the conductor's group does not pull the conductor's writer in")
        (assert (and (= (listLength groups) 1) (listContains? groups 740)) (str "only the job's own group is signalled: " groups))
        true))

fn ! runTests -> Bool
  (do (assert (testFence) "the package tree killer never reaches pid 0, itself, its ancestors, a foreign group or a user manager")
      true)
