(module asl-mesh/tests/swarmClusterTest
  :x [runTests RunTests testFiveNodeClusterInit testNetworkPartitionMajorityQuorum testSplitBrainResistance testPostPartitionStateConvergence testDualPolarityRefutations]
  :i [(asl-mesh/raft :a raft)
      (asl-mesh/vectorClock :a vc)])

fn testFiveNodeClusterInit -> Bool
  (let [(cluster (list "node-1" "node-2" "node-3" "node-4" "node-5"))
        (n1 (raft/makeRaftNode "node-1" (list "node-2" "node-3" "node-4" "node-5")))
        (n2 (raft/makeRaftNode "node-2" (list "node-1" "node-3" "node-4" "node-5")))
        (n3 (raft/makeRaftNode "node-3" (list "node-1" "node-2" "node-4" "node-5")))
        (n4 (raft/makeRaftNode "node-4" (list "node-1" "node-2" "node-3" "node-5")))
        (n5 (raft/makeRaftNode "node-5" (list "node-1" "node-2" "node-3" "node-4")))]
    (assert (= (listLength cluster) 5) "5-node cluster topology verified")
    (refute (!= (listLength cluster) 5) "cluster node count refutes divergence")
    (assert (= (listLength n1.peers) 4) "each node has 4 peers")
    (refute (!= (listLength n1.peers) 4) "peer count refutes divergence")
    (assert (raft/isQuorumAchieved 3 5) "majority quorum is 3 of 5")
    (refute (raft/isQuorumAchieved 2 5) "2 of 5 strictly refutes majority quorum")
    true)

fn testNetworkPartitionMajorityQuorum -> Bool
  (let [(majorityPartition (list "node-1" "node-2" "node-3"))
        (minorityPartition (list "node-4" "node-5"))]
    (assert (raft/isQuorumAchieved (listLength majorityPartition) 5) "majority partition has 3 nodes and achieves quorum")
    (refute (not (raft/isQuorumAchieved (listLength majorityPartition) 5)) "majority partition refutes lack of quorum")
    (assert (not (raft/isQuorumAchieved (listLength minorityPartition) 5)) "minority partition has 2 nodes and cannot achieve quorum")
    (refute (raft/isQuorumAchieved (listLength minorityPartition) 5) "minority partition refutes quorum achievement")
    true)

fn testSplitBrainResistance -> Bool
  (let [(candMinority (raft/stepElectionTimeout (raft/makeRaftNode "node-4" (list "node-5"))))
        (candMajority (raft/stepElectionTimeout (raft/makeRaftNode "node-1" (list "node-2" "node-3"))))
        (voteReqMinority (raft/VoteRequest :term 1 :candidateId "node-4" :lastLogIndex 0 :lastLogTerm 0))
        (voteReqMajority (raft/VoteRequest :term 1 :candidateId "node-1" :lastLogIndex 0 :lastLogTerm 0))
        (n5 (raft/makeRaftNode "node-5" (list "node-4")))
        (res5 (raft/handleRequestVote n5 voteReqMinority))
        (n2 (raft/makeRaftNode "node-2" (list "node-1" "node-3")))
        (res2 (raft/handleRequestVote n2 voteReqMajority))
        (n3 (raft/makeRaftNode "node-3" (list "node-1" "node-2")))
        (res3 (raft/handleRequestVote n3 voteReqMajority))]
    (assert (pairSecond res5).voteGranted "minority peer votes for candidate in its partition")
    (assert (not (raft/isQuorumAchieved 2 5)) "minority candidate with 2 votes (self + node-5) cannot claim leadership")
    (refute (raft/isQuorumAchieved 2 5) "minority candidate strictly refutes leader election")
    (assert (pairSecond res2).voteGranted "majority peer node-2 votes for majority candidate")
    (assert (pairSecond res3).voteGranted "majority peer node-3 votes for majority candidate")
    (assert (raft/isQuorumAchieved 3 5) "majority candidate with 3 votes (self + node-2 + node-3) achieves quorum")
    (refute (not (raft/isQuorumAchieved 3 5)) "majority candidate refutes non-quorum")
    true)

fn testPostPartitionStateConvergence -> Bool
  (let [(entry1 (raft/makeRaftLogEntry 1 1 "commit:task-55101"))
        (entry2 (raft/makeRaftLogEntry 1 2 "commit:task-55102"))
        (appendReq (raft/AppendRequest :term 1 :leaderId "node-1" :prevLogIndex 0 :prevLogTerm 0 :entries (list entry1 entry2) :leaderCommit 2))
        (staleNode4 (raft/makeRaftNode "node-4" (list "node-1" "node-2" "node-3" "node-5")))
        (convergeRes4 (raft/handleAppendEntries staleNode4 appendReq))
        (convergedNode4 (pairFirst convergeRes4))
        (resp4 (pairSecond convergeRes4))
        (staleNode5 (raft/makeRaftNode "node-5" (list "node-1" "node-2" "node-3" "node-4")))
        (convergeRes5 (raft/handleAppendEntries staleNode5 appendReq))
        (convergedNode5 (pairFirst convergeRes5))
        (resp5 (pairSecond convergeRes5))]
    (assert resp4.success "isolated node-4 successfully reconciles and appends entries from majority leader")
    (refute (not resp4.success) "node-4 reconciliation refutes failure")
    (assert resp5.success "isolated node-5 successfully reconciles and appends entries from majority leader")
    (refute (not resp5.success) "node-5 reconciliation refutes failure")
    (assert (= (listLength convergedNode4.logEntries) 2) "node-4 log converged to 2 entries")
    (refute (!= (listLength convergedNode4.logEntries) 2) "node-4 log count refutes divergence")
    (assert (= (listLength convergedNode5.logEntries) 2) "node-5 log converged to 2 entries")
    (assert (= convergedNode4.commitIndex 2) "node-4 commit index updated to 2")
    (assert (= convergedNode5.commitIndex 2) "node-5 commit index updated to 2")
    true)

fn testDualPolarityRefutations -> Bool
  (let [(singleNode (raft/makeRaftNode "solo" (list)))
        (cand (raft/stepElectionTimeout singleNode))]
    (assert (raft/isQuorumAchieved 1 1) "single node cluster quorum is 1")
    (refute (not (raft/isQuorumAchieved 1 1)) "single node quorum refutes non-quorum")
    (assert (= cand.votedFor "solo") "single node votes for self")
    (refute (!= cand.votedFor "solo") "single node refutes vote divergence")
    true)

fn runTests -> Bool
  (do
    (assert (testFiveNodeClusterInit) "testFiveNodeClusterInit passed")
    (assert (testNetworkPartitionMajorityQuorum) "testNetworkPartitionMajorityQuorum passed")
    (assert (testSplitBrainResistance) "testSplitBrainResistance passed")
    (assert (testPostPartitionStateConvergence) "testPostPartitionStateConvergence passed")
    (assert (testDualPolarityRefutations) "testDualPolarityRefutations passed")
    true)

fn RunTests -> Bool
  (runTests)
