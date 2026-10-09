(module asl-mesh/tests/raftTest
  :x [runTests RunTests testRaftNodeInitialization testQuorumCalculation testElectionTimeoutAndCandidateTransition testRequestVoteGrantAndReject testAppendEntriesLogReplication testDualPolarityRefutations testLogFreshnessAndTermReset testLogCompactionAndSnapshot]
  :i [(asl-mesh/raft :a raft)])

fn testRaftNodeInitialization -> Bool
  (let [(peers (list "worker-1" "worker-2"))
        (node (raft/makeRaftNode "worker-0" peers))]
    (assert (= node.nodeId "worker-0") "nodeId matches worker-0")
    (refute (!= node.nodeId "worker-0") "nodeId refutes divergence")
    (assert (= node.currentTerm 0) "initial term is 0")
    (refute (!= node.currentTerm 0) "initial term refutes non-zero")
    (assert (= (listLength node.peers) 2) "peers list has 2 entries")
    (assert (listEmpty? node.logEntries) "initial log is empty")
    (refute (not (listEmpty? node.logEntries)) "initial log refutes non-empty"))
  true

fn testQuorumCalculation -> Bool
  (do
    (assert (raft/isQuorumAchieved 2 3) "2 of 3 is majority quorum")
    (refute (not (raft/isQuorumAchieved 2 3)) "2 of 3 refutes non-quorum")
    (assert (raft/isQuorumAchieved 3 5) "3 of 5 is majority quorum")
    (assert (not (raft/isQuorumAchieved 2 5)) "2 of 5 is not majority quorum")
    (refute (raft/isQuorumAchieved 2 5) "2 of 5 refutes quorum")
    (assert (not (raft/isQuorumAchieved 1 3)) "1 of 3 is not quorum")
    true)

fn testElectionTimeoutAndCandidateTransition -> Bool
  (let [(node0 (raft/makeRaftNode "node-A" (list "node-B" "node-C")))
        (node1 (raft/stepElectionTimeout node0))]
    (assert (= node1.currentTerm 1) "candidate term incremented to 1")
    (refute (!= node1.currentTerm 1) "candidate term refutes divergence")
    (assert (= node1.votedFor "node-A") "candidate self-votes")
    (refute (!= node1.votedFor "node-A") "candidate self-vote refutes divergence")
    (let [(stateStr (raft/formatRaftState node1))]
      (assert (stringContains? stateStr "candidate") "formatted state reflects candidate role")
      (refute (stringContains? stateStr "leader") "formatted state refutes leader before election")))
  true

fn testRequestVoteGrantAndReject -> Bool
  (let [(node0 (raft/makeRaftNode "follower-1" (list "cand-1")))
        (reqStale (raft/VoteRequest :term -1 :candidateId "cand-1" :lastLogIndex 0 :lastLogTerm 0))
        (resStale (raft/handleRequestVote node0 reqStale))
        (vStale (pairSecond resStale))
        (reqValid (raft/VoteRequest :term 2 :candidateId "cand-1" :lastLogIndex 1 :lastLogTerm 1))
        (resValid (raft/handleRequestVote node0 reqValid))
        (nodeVoted (pairFirst resValid))
        (vGranted (pairSecond resValid))
        (reqDup (raft/VoteRequest :term 2 :candidateId "cand-2" :lastLogIndex 1 :lastLogTerm 1))
        (resDup (raft/handleRequestVote nodeVoted reqDup))
        (vDup (pairSecond resDup))]
    (assert (not vStale.voteGranted) "stale term vote is rejected")
    (refute vStale.voteGranted "stale term vote refutes grant")
    (assert vGranted.voteGranted "valid candidate vote is granted")
    (refute (not vGranted.voteGranted) "valid candidate vote refutes reject")
    (assert (= nodeVoted.votedFor "cand-1") "votedFor recorded correctly")
    (assert (not vDup.voteGranted) "duplicate vote for different candidate in same term is rejected")
    (refute vDup.voteGranted "duplicate vote refutes grant"))
  true

fn testAppendEntriesLogReplication -> Bool
  (let [(node0 (raft/makeRaftNode "follower-2" (list "leader-1")))
        (entry1 (raft/makeRaftLogEntry 1 1 "claim:task-101"))
        (entry2 (raft/makeRaftLogEntry 1 2 "claim:task-102"))
        (entries (list entry1 entry2))
        (appendReq (raft/AppendRequest :term 1 :leaderId "leader-1" :prevLogIndex 0 :prevLogTerm 0 :entries entries :leaderCommit 1))
        (appendRes (raft/handleAppendEntries node0 appendReq))
        (updatedNode (pairFirst appendRes))
        (resp (pairSecond appendRes))]
    (assert resp.success "append entries succeeded")
    (refute (not resp.success) "append entries refutes failure")
    (assert (= updatedNode.currentTerm 1) "follower term updated to leader term")
    (assert (= updatedNode.leaderId "leader-1") "follower tracks active leaderId")
    (assert (= (listLength updatedNode.logEntries) 2) "log contains 2 replicated entries")
    (refute (!= (listLength updatedNode.logEntries) 2) "replicated log count refutes divergence")
    (assert (= updatedNode.commitIndex 1) "commitIndex advanced to leaderCommit"))
  true

fn testDualPolarityRefutations -> Bool
  (let [(node0 (raft/makeRaftNode "node-X" (list)))
        (nodeTerm2 (raft/RaftNode :nodeId "node-X" :role (raft/roleFollower) :currentTerm 5 :votedFor "" :peers (list) :logEntries (list) :commitIndex 0 :leaderId "" :lastIncludedIndex 0 :lastIncludedTerm 0 :snapshotData "" :leaderLeaseExpiresAt 0 :leaseTtlMs 500 :readIndex 0))
        (staleAppend (raft/AppendRequest :term 3 :leaderId "old-leader" :prevLogIndex 0 :prevLogTerm 0 :entries (list) :leaderCommit 0))
        (res (raft/handleAppendEntries nodeTerm2 staleAppend))
        (resp (pairSecond res))]
    (assert (not resp.success) "append entries with term < currentTerm is rejected")
    (refute resp.success "stale append entries refutes success"))
  true

fn testLogFreshnessAndTermReset -> Bool
  (let [(entry1 (raft/makeRaftLogEntry 2 1 "op1"))
        (entry2 (raft/makeRaftLogEntry 2 2 "op2"))
        (nodeWithLogs (raft/RaftNode
                        :nodeId "follower-1"
                        :role (raft/roleFollower)
                        :currentTerm 2
                        :votedFor "cand-0"
                        :peers (list "cand-1")
                        :logEntries (list entry1 entry2)
                        :commitIndex 1
                        :leaderId ""
                        :lastIncludedIndex 0
                        :lastIncludedTerm 0
                        :snapshotData ""
                        :leaderLeaseExpiresAt 0
                        :leaseTtlMs 500
                        :readIndex 0))
        (reqStaleTerm (raft/VoteRequest :term 3 :candidateId "cand-1" :lastLogIndex 5 :lastLogTerm 1))
        (resStaleTerm (raft/handleRequestVote nodeWithLogs reqStaleTerm))
        (vStaleTerm (pairSecond resStaleTerm))
        (reqStaleIdx (raft/VoteRequest :term 3 :candidateId "cand-1" :lastLogIndex 1 :lastLogTerm 2))
        (resStaleIdx (raft/handleRequestVote nodeWithLogs reqStaleIdx))
        (vStaleIdx (pairSecond resStaleIdx))
        (reqFresh (raft/VoteRequest :term 3 :candidateId "cand-1" :lastLogIndex 2 :lastLogTerm 2))
        (resFresh (raft/handleRequestVote nodeWithLogs reqFresh))
        (vFresh (pairSecond resFresh))
        (nodeWithVote (raft/RaftNode
                        :nodeId "follower-1"
                        :role (raft/roleFollower)
                        :currentTerm 2
                        :votedFor "cand-prev"
                        :peers (list)
                        :logEntries (list)
                        :commitIndex 0
                        :leaderId ""
                        :lastIncludedIndex 0
                        :lastIncludedTerm 0
                        :snapshotData ""
                        :leaderLeaseExpiresAt 0
                        :leaseTtlMs 500
                        :readIndex 0))
        (appendHighTerm (raft/AppendRequest :term 4 :leaderId "leader-new" :prevLogIndex 0 :prevLogTerm 0 :entries (list) :leaderCommit 0))
        (resAppendTerm (raft/handleAppendEntries nodeWithVote appendHighTerm))
        (nodeAfterAppend (pairFirst resAppendTerm))
        (reqMismatch (raft/AppendRequest :term 2 :leaderId "leader-1" :prevLogIndex 5 :prevLogTerm 2 :entries (list) :leaderCommit 0))
        (resMismatch (raft/handleAppendEntries nodeWithLogs reqMismatch))
        (respMismatch (pairSecond resMismatch))]
    (do
      (assert (not vStaleTerm.voteGranted) "candidate with stale lastLogTerm must be rejected")
      (refute vStaleTerm.voteGranted "stale term refutes vote grant")
      (assert (not vStaleIdx.voteGranted) "candidate with stale lastLogIndex must be rejected")
      (refute vStaleIdx.voteGranted "stale index refutes vote grant")
      (assert vFresh.voteGranted "candidate with fresh log is granted vote")
      (refute (not vFresh.voteGranted) "fresh log refutes rejection")
      (assert (= nodeAfterAppend.votedFor "") "higher term append entries resets votedFor to empty")
      (refute (!= nodeAfterAppend.votedFor "") "higher term append entries refutes non-empty votedFor")
      (assert (not respMismatch.success) "append entries with nonexistent prevLogIndex is rejected")
      (refute respMismatch.success "prevLogIndex mismatch refutes success")
      true))

fn testLogCompactionAndSnapshot -> Bool
  (let [(entry1 (raft/makeRaftLogEntry 1 1 "cmd1"))
        (entry2 (raft/makeRaftLogEntry 1 2 "cmd2"))
        (entry3 (raft/makeRaftLogEntry 2 3 "cmd3"))
        (nodeWithCommitted (raft/RaftNode
                             :nodeId "follower-snap"
                             :role (raft/roleFollower)
                             :currentTerm 2
                             :votedFor ""
                             :peers (list)
                             :logEntries (list entry1 entry2 entry3)
                             :commitIndex 2
                             :leaderId "leader-1"
                             :lastIncludedIndex 0
                             :lastIncludedTerm 0
                             :snapshotData ""
                             :leaderLeaseExpiresAt 0
                             :leaseTtlMs 500
                             :readIndex 0))
        (compacted (raft/compactLog nodeWithCommitted 2 1 "state:snapshot-v1"))
        (invalidCompact (raft/compactLog compacted 3 2 "invalid-state"))
        (snapReq (raft/SnapshotRequest
                   :term 3
                   :leaderId "leader-2"
                   :lastIncludedIndex 5
                   :lastIncludedTerm 3
                   :snapshotData "state:snapshot-v2"))
        (snapResPair (raft/handleInstallSnapshot compacted snapReq))
        (nodePostInstall (pairFirst snapResPair))
        (snapRes (pairSecond snapResPair))]
    (do
      (assert (= compacted.lastIncludedIndex 2) "compacted node tracks lastIncludedIndex 2")
      (refute (!= compacted.lastIncludedIndex 2) "lastIncludedIndex refutes non-2")
      (assert (= compacted.lastIncludedTerm 1) "compacted node tracks lastIncludedTerm 1")
      (assert (= compacted.snapshotData "state:snapshot-v1") "compacted node stores snapshot data")
      (assert (= (listLength compacted.logEntries) 1) "compacted log retains only uncompacted entry 3")
      (refute (!= (listLength compacted.logEntries) 1) "compacted log count refutes non-1")
      (assert (= invalidCompact.lastIncludedIndex 2) "compaction beyond commitIndex is rejected")
      (assert snapRes.success "install snapshot response reports success")
      (refute (not snapRes.success) "install snapshot refutes failure")
      (assert (= nodePostInstall.lastIncludedIndex 5) "follower state updated to snapshot index 5")
      (assert (= nodePostInstall.commitIndex 5) "commitIndex advanced to snapshot index 5")
      (assert (= (listLength nodePostInstall.logEntries) 0) "subsumed logs discarded after snapshot install")
      true))

fn testLogConflictTruncation -> Bool
  (let [(e1 (raft/makeRaftLogEntry 1 1 "entry-1"))
        (e2 (raft/makeRaftLogEntry 1 2 "entry-2"))
        (e3Stale (raft/makeRaftLogEntry 1 3 "entry-3-uncommitted-stale"))
        (nodeWithStale (raft/RaftNode
                         :nodeId "follower-1"
                         :role (raft/roleFollower)
                         :currentTerm 1
                         :votedFor ""
                         :peers (list "node-2" "node-3")
                         :logEntries (list e1 e2 e3Stale)
                         :commitIndex 2
                         :leaderId "leader-1"
                         :lastIncludedIndex 0
                         :lastIncludedTerm 0
                         :snapshotData ""
                         :leaderLeaseExpiresAt 0
                         :leaseTtlMs 500
                         :readIndex 0))
        (e3New (raft/makeRaftLogEntry 2 3 "entry-3-term-2-leader"))
        (appendReq (raft/AppendRequest
                     :term 2
                     :leaderId "leader-2"
                     :prevLogIndex 2
                     :prevLogTerm 1
                     :entries (list e3New)
                     :leaderCommit 3))
        (res (raft/handleAppendEntries nodeWithStale appendReq))
        (updatedNode (pairFirst res))
        (resp (pairSecond res))
        (entries updatedNode.logEntries)
        (lastE (optionOr (listGet entries 2) (raft/makeRaftLogEntry -1 -1 "")))]
    (do
      (assert resp.success "append entries succeeded on matching prevLogIndex 2")
      (assert (= (listLength entries) 3) "conflicting uncommitted entry 3 was truncated before append")
      (assert (= lastE.term 2) "entry 3 has term 2 from new leader")
      (assert (= lastE.command "entry-3-term-2-leader") "entry 3 has new command")
      (refute (= (listLength entries) 4) "Refutation: uncommitted conflicting entries must not accumulate")
      true))

fn testCompactionIndexCalculation -> Bool
  (let [(e11 (raft/makeRaftLogEntry 2 11 "entry-11"))
        (e12 (raft/makeRaftLogEntry 2 12 "entry-12"))
        (nodeCompacted (raft/RaftNode
                         :nodeId "follower-1"
                         :role (raft/roleFollower)
                         :currentTerm 2
                         :votedFor ""
                         :peers (list "leader-1")
                         :logEntries (list)
                         :commitIndex 10
                         :leaderId "leader-1"
                         :lastIncludedIndex 10
                         :lastIncludedTerm 2
                         :snapshotData "snap-10"
                         :leaderLeaseExpiresAt 0
                         :leaseTtlMs 500
                         :readIndex 0))
        (appendReq (raft/AppendRequest
                     :term 2
                     :leaderId "leader-1"
                     :prevLogIndex 10
                     :prevLogTerm 2
                     :entries (list e11 e12)
                     :leaderCommit 12))
        (res (raft/handleAppendEntries nodeCompacted appendReq))
        (updatedNode (pairFirst res))
        (resp (pairSecond res))]
    (do
      (assert resp.success "append entries succeeded after compaction")
      (assert (= updatedNode.commitIndex 12) "commitIndex calculated as 12 (lastIncludedIndex 10 + 2)")
      (assert (= resp.matchIndex 12) "matchIndex returned as 12, not local log length 2")
      (refute (= resp.matchIndex 2) "Refutation: matchIndex must not drift to local slice length 2")
      true))

fn testCheckAndSendSnapshot -> Bool
  (let [(leader (raft/RaftNode
                  :nodeId "leader-0"
                  :role (raft/roleLeader)
                  :currentTerm 3
                  :votedFor "leader-0"
                  :peers (list "worker-1")
                  :logEntries (list)
                  :commitIndex 50
                  :leaderId "leader-0"
                  :lastIncludedIndex 50
                  :lastIncludedTerm 2
                  :snapshotData "snapshot-50"))
        (reqBehind (raft/checkAndSendSnapshot leader 40))
        (reqCurrent (raft/checkAndSendSnapshot leader 55))]
    (do
      (assert (some? reqBehind) "behind follower triggers snapshot request")
      (refute (none? reqBehind) "refute missing snapshot request for behind follower")
      (mt reqBehind
        ((some snap)
          (do
            (assert (= snap.lastIncludedIndex 50) "snapshot lastIncludedIndex matches leader 50")
            (assert (= snap.term 3) "snapshot term matches leader term 3")
            true))
        ((none) false))
      (assert (none? reqCurrent) "up-to-date follower does not trigger snapshot request")
      true))

fn testDynamicClusterReconfiguration -> Bool
  (let [(node0 (raft/makeRaftNode "node-0" (list "node-1" "node-2")))
        (nodeAdded (raft/addPeer node0 "node-3"))
        (nodeDup (raft/addPeer nodeAdded "node-3"))
        (nodeRemoved (raft/removePeer nodeAdded "node-2"))]
    (do
      (assert (= (listLength nodeAdded.peers) 3) "peer node-3 added to cluster")
      (refute (!= (listLength nodeAdded.peers) 3) "peer count refutes divergence after addition")
      (assert (= (listLength nodeDup.peers) 3) "duplicate addPeer is idempotent")
      (assert (= (listLength nodeRemoved.peers) 2) "node-2 successfully removed from cluster")
      (assert (not (listContains? nodeRemoved.peers "node-2")) "removed peer absent from peer list")
      (refute (listContains? nodeRemoved.peers "node-2") "removed peer refutes presence")
      (assert (listContains? nodeRemoved.peers "node-3") "node-3 remains in reconfigured cluster")
      true))

fn testLeaderLeaseAndLinearizableRead -> Bool
  (let [(node0 (raft/makeRaftNode "leader-0" (list "worker-1" "worker-2")))
        (leader0 (raft/becomeLeader node0))
        (leaderWithCommit (raft/RaftNode
                            :nodeId leader0.nodeId
                            :role leader0.role
                            :currentTerm 1
                            :votedFor leader0.votedFor
                            :peers leader0.peers
                            :logEntries (list)
                            :commitIndex 42
                            :leaderId leader0.leaderId
                            :lastIncludedIndex 0
                            :lastIncludedTerm 0
                            :snapshotData ""
                            :leaderLeaseExpiresAt 0
                            :leaseTtlMs 500
                            :readIndex 0))
        (leasedLeader (raft/renewLeaderLease leaderWithCommit 1000))
        (followerRenewed (raft/renewLeaderLease node0 1000))
        (readActive (raft/serveLinearizableRead leasedLeader 1200))
        (readExpired (raft/serveLinearizableRead leasedLeader 1600))
        (readFollower (raft/serveLinearizableRead node0 1200))]
    (do
      (assert (= leasedLeader.leaderLeaseExpiresAt 1500) "lease expires at nowMs + ttl (1000 + 500)")
      (refute (!= leasedLeader.leaderLeaseExpiresAt 1500) "lease expiry refutes divergence")
      (assert (= followerRenewed.leaderLeaseExpiresAt 0) "follower cannot renew leader lease")
      (refute (!= followerRenewed.leaderLeaseExpiresAt 0) "follower lease refutes non-zero")
      (assert (= leasedLeader.readIndex 42) "readIndex pinned to commitIndex 42")
      (assert (= (optionOr readActive -1) 42) "linearizable read served within active lease")
      (refute (!= (optionOr readActive -1) 42) "active read refutes non-42")
      (assert (none? readExpired) "linearizable read rejected after lease expiry")
      (refute (some? readExpired) "expired read refutes success")
      (assert (none? readFollower) "follower rejects linearizable read")
      true))

fn testJointConfigurationTransition -> Bool
  (let [(node0 (raft/makeRaftNode "node-0" (list "node-1" "node-2")))
        (newPeers (list "node-3" "node-4"))
        (nodeJoint (raft/jointConfigurationTransition node0 newPeers))
        (nodeFinal (raft/commitJointConfiguration nodeJoint))]
    (assert (> (listLength nodeJoint.peers) 2) "joint configuration adds new peers")
    (assert (listContains? nodeJoint.peers "node-3") "node-3 present in joint configuration")
    (assert (listContains? nodeJoint.peers "node-1") "node-1 retained in joint configuration")
    (assert (= (listLength nodeFinal.peers) 2) "final configuration has exactly newPeers count")
    (assert (listContains? nodeFinal.peers "node-3") "node-3 in final configuration")
    (assert (listContains? nodeFinal.peers "node-4") "node-4 in final configuration")
    (assert (not (listContains? nodeFinal.peers "node-1")) "retired peer node-1 absent from final configuration")
    (refute (listContains? nodeFinal.peers "node-1") "retired peer refutes presence in final config")
    (assert (raft/isJointQuorumAchieved 2 3 2 3) "joint quorum achieved when both quorums pass")
    (refute (raft/isJointQuorumAchieved 1 3 2 3) "joint quorum fails if C_old lacks quorum")
    (refute (raft/isJointQuorumAchieved 2 3 1 3) "joint quorum fails if C_new lacks quorum")
    true)

fn testRenewLeaderLeaseWithQuorum -> Bool
  (let [(leader0 (raft/becomeLeader (raft/makeRaftNode "leader" (list "p1" "p2" "p3" "p4"))))
        (renewedWithQuorum (raft/renewLeaderLeaseWithQuorum leader0 3 1000))
        (staleWithoutQuorum (raft/renewLeaderLeaseWithQuorum leader0 1 1000))
        (followerNode (raft/makeRaftNode "follower" (list "p1" "p2")))
        (followerQuorum (raft/renewLeaderLeaseWithQuorum followerNode 2 1000))]
    (assert (> renewedWithQuorum.leaderLeaseExpiresAt 1000) "lease renewed with majority quorum")
    (assert (= staleWithoutQuorum.leaderLeaseExpiresAt 0) "lease rejected without majority quorum")
    (assert (= followerQuorum.leaderLeaseExpiresAt 0) "follower cannot renew lease with quorum")
    (refute (!= followerQuorum.leaderLeaseExpiresAt 0) "follower quorum refutes non-zero")
    true)

fn runTests -> Bool
  (do
    (assert (testRaftNodeInitialization) "testRaftNodeInitialization passed")
    (assert (testQuorumCalculation) "testQuorumCalculation passed")
    (assert (testElectionTimeoutAndCandidateTransition) "testElectionTimeoutAndCandidateTransition passed")
    (assert (testRequestVoteGrantAndReject) "testRequestVoteGrantAndReject passed")
    (assert (testAppendEntriesLogReplication) "testAppendEntriesLogReplication passed")
    (assert (testDualPolarityRefutations) "testDualPolarityRefutations passed")
    (assert (testLogFreshnessAndTermReset) "testLogFreshnessAndTermReset passed")
    (assert (testLogCompactionAndSnapshot) "testLogCompactionAndSnapshot passed")
    (assert (testLogConflictTruncation) "testLogConflictTruncation passed")
    (assert (testCompactionIndexCalculation) "testCompactionIndexCalculation passed")
    (assert (testCheckAndSendSnapshot) "testCheckAndSendSnapshot passed")
    (assert (testDynamicClusterReconfiguration) "testDynamicClusterReconfiguration passed")
    (assert (testLeaderLeaseAndLinearizableRead) "testLeaderLeaseAndLinearizableRead passed")
    (assert (testJointConfigurationTransition) "testJointConfigurationTransition passed")
    (assert (testRenewLeaderLeaseWithQuorum) "testRenewLeaderLeaseWithQuorum passed")
    true)

fn RunTests -> Bool
  (runTests)
