(module asl-mesh/raft
  :x [RaftRole RaftLogEntry RaftNode VoteRequest VoteResponse AppendRequest AppendResponse
      SnapshotRequest SnapshotResponse compactLog handleInstallSnapshot checkAndSendSnapshot
      makeRaftNode makeRaftLogEntry stepElectionTimeout handleRequestVote handleAppendEntries
       isQuorumAchieved becomeLeader roleFollower roleCandidate roleLeader formatRaftState isLogUpToDate?
       addPeer removePeer renewLeaderLease serveLinearizableRead jointConfigurationTransition commitJointConfiguration renewLeaderLeaseWithQuorum isJointQuorumAchieved]
   :i [])

(enum RaftRole
  (:c roleFollower [] "Follower role responding to heartbeats")
  (:c roleCandidate [] "Candidate role seeking majority election")
  (:c roleLeader [] "Active quorum leader distributing leased tasks"))

(schema RaftLogEntry
  (:f term Int64)
  (:f index Int64)
  (:f command String))

(schema RaftNode
  (:f nodeId String)
  (:f role RaftRole)
  (:f currentTerm Int64)
  (:f votedFor String)
  (:f peers (List String))
  (:f logEntries (List RaftLogEntry))
  (:f commitIndex Int64)
  (:f leaderId String)
  (:f lastIncludedIndex Int64)
  (:f lastIncludedTerm Int64)
  (:f snapshotData String)
  (:f leaderLeaseExpiresAt Int64)
  (:f leaseTtlMs Int64)
  (:f readIndex Int64))

(schema VoteRequest
  (:f term Int64)
  (:f candidateId String)
  (:f lastLogIndex Int64)
  (:f lastLogTerm Int64))

(schema VoteResponse
  (:f term Int64)
  (:f voteGranted Bool))

(schema AppendRequest
  (:f term Int64)
  (:f leaderId String)
  (:f prevLogIndex Int64)
  (:f prevLogTerm Int64)
  (:f entries (List RaftLogEntry))
  (:f leaderCommit Int64))

(schema AppendResponse
  (:f term Int64)
  (:f success Bool)
  (:f matchIndex Int64))

(schema SnapshotRequest
  (:f term Int64)
  (:f leaderId String)
  (:f lastIncludedIndex Int64)
  (:f lastIncludedTerm Int64)
  (:f snapshotData String))

(schema SnapshotResponse
  (:f term Int64)
  (:f success Bool)
  (:f lastIncludedIndex Int64))

fn makeRaftLogEntry term: Int64 index: Int64 cmd: String -> RaftLogEntry
  (RaftLogEntry :term term :index index :command cmd)

fn makeRaftNode nodeId: String peers: (List String) -> RaftNode
  (RaftNode
    :nodeId nodeId
    :role (roleFollower)
    :currentTerm 0
    :votedFor ""
    :peers peers
    :logEntries (list)
    :commitIndex 0
    :leaderId ""
    :lastIncludedIndex 0
    :lastIncludedTerm 0
    :snapshotData ""
    :leaderLeaseExpiresAt 0
    :leaseTtlMs 500
    :readIndex 0)

fn isQuorumAchieved votes: Int64 clusterSize: Int64 -> Bool
  (if (<= clusterSize 0)
    false
    (> votes (/ clusterSize 2)))

fn becomeLeader node: RaftNode -> RaftNode
  (with node :role (roleLeader) :leaderId node.nodeId :readIndex node.commitIndex)

fn stepElectionTimeout node: RaftNode -> RaftNode
  (let [(nextTerm (+ node.currentTerm 1))]
    (with node :role (roleCandidate) :currentTerm nextTerm :votedFor node.nodeId :leaderId "" :leaderLeaseExpiresAt 0))

fn isLogUpToDate? candLastTerm: Int64 candLastIndex: Int64 myLastTerm: Int64 myLastIndex: Int64 -> Bool
  (if (> candLastTerm myLastTerm)
    true
    (if (= candLastTerm myLastTerm)
      (>= candLastIndex myLastIndex)
      false))

fn handleRequestVote node: RaftNode req: VoteRequest -> (Pair RaftNode VoteResponse)
  (let [(candTerm req.term)
        (curTerm node.currentTerm)]
    (if (< candTerm curTerm)
      (pair node (VoteResponse :term curTerm :voteGranted false))
      (let [(updatedNode (if (> candTerm curTerm)
                           (with node :role (roleFollower) :currentTerm candTerm :votedFor "" :leaderId "" :leaderLeaseExpiresAt 0)
                           node))
            (curVote updatedNode.votedFor)
            (canVoteTerm (or (stringEmpty? curVote) (= curVote req.candidateId)))
            (lastEntry (fold (fn [(acc RaftLogEntry) (e RaftLogEntry)] -> RaftLogEntry e)
                             (makeRaftLogEntry updatedNode.lastIncludedTerm updatedNode.lastIncludedIndex "")
                             updatedNode.logEntries))
            (logOk (isLogUpToDate? req.lastLogTerm req.lastLogIndex lastEntry.term lastEntry.index))
            (canVote (and canVoteTerm logOk))]
        (if canVote
          (let [(votedNode (RaftNode
                             :nodeId updatedNode.nodeId
                             :role updatedNode.role
                             :currentTerm updatedNode.currentTerm
                             :votedFor req.candidateId
                             :peers updatedNode.peers
                             :logEntries updatedNode.logEntries
                             :commitIndex updatedNode.commitIndex
                             :leaderId updatedNode.leaderId
                             :lastIncludedIndex updatedNode.lastIncludedIndex
                             :lastIncludedTerm updatedNode.lastIncludedTerm
                             :snapshotData updatedNode.snapshotData
                             :leaderLeaseExpiresAt 0
                             :leaseTtlMs updatedNode.leaseTtlMs
                             :readIndex updatedNode.readIndex))]
            (pair votedNode (VoteResponse :term votedNode.currentTerm :voteGranted true)))
          (pair updatedNode (VoteResponse :term updatedNode.currentTerm :voteGranted false))))))

fn handleAppendEntries node: RaftNode req: AppendRequest -> (Pair RaftNode AppendResponse)
  (let [(leaderTerm req.term)
        (curTerm node.currentTerm)]
    (if (< leaderTerm curTerm)
      (pair node (AppendResponse :term curTerm :success false :matchIndex node.commitIndex))
      (let [(newVotedFor (if (> leaderTerm curTerm) "" node.votedFor))
            (pIdx req.prevLogIndex)
            (pTerm req.prevLogTerm)
            (prevLogOk (if (<= pIdx 0)
                         true
                         (if (and (= pIdx node.lastIncludedIndex) (= pTerm node.lastIncludedTerm))
                           true
                           (let [(matchingEntry (fold (fn [(acc RaftLogEntry) (e RaftLogEntry)] -> RaftLogEntry
                                                         (if (= e.index pIdx) e acc))
                                                       (makeRaftLogEntry -1 -1 "")
                                                       node.logEntries))]
                             (and (= matchingEntry.index pIdx) (= matchingEntry.term pTerm))))))]
        (if (not prevLogOk)
          (let [(updatedNode (if (> leaderTerm curTerm)
                               (RaftNode
                                 :nodeId node.nodeId
                                 :role (roleFollower)
                                 :currentTerm leaderTerm
                                 :votedFor newVotedFor
                                 :peers node.peers
                                 :logEntries node.logEntries
                                 :commitIndex node.commitIndex
                                 :leaderId req.leaderId
                                 :lastIncludedIndex node.lastIncludedIndex
                                 :lastIncludedTerm node.lastIncludedTerm
                                 :snapshotData node.snapshotData
                                 :leaderLeaseExpiresAt 0
                                 :leaseTtlMs node.leaseTtlMs
                                 :readIndex node.readIndex)
                               node))]
            (pair updatedNode (AppendResponse :term leaderTerm :success false :matchIndex updatedNode.commitIndex)))
          (let [(newEntries req.entries)
                (baseLog (if (listEmpty? newEntries)
                           node.logEntries
                           (filter (fn [(e RaftLogEntry)] (<= e.index pIdx)) node.logEntries)))
                (combinedLog (if (listEmpty? newEntries)
                               baseLog
                               (listAppend baseLog newEntries)))
                (newCommit (if (> req.leaderCommit node.commitIndex)
                             (let [(lastNewIdx (+ node.lastIncludedIndex (listLength combinedLog)))]
                               (if (< req.leaderCommit lastNewIdx)
                                 req.leaderCommit
                                 lastNewIdx))
                             node.commitIndex))
                (updatedNode (RaftNode
                               :nodeId node.nodeId
                               :role (roleFollower)
                               :currentTerm leaderTerm
                               :votedFor newVotedFor
                               :peers node.peers
                               :logEntries combinedLog
                               :commitIndex newCommit
                               :leaderId req.leaderId
                               :lastIncludedIndex node.lastIncludedIndex
                               :lastIncludedTerm node.lastIncludedTerm
                               :snapshotData node.snapshotData
                               :leaderLeaseExpiresAt 0
                               :leaseTtlMs node.leaseTtlMs
                               :readIndex node.readIndex))]
            (pair updatedNode (AppendResponse
                                :term leaderTerm
                                :success true
                                :matchIndex (+ node.lastIncludedIndex (listLength combinedLog)))))))))

fn checkAndSendSnapshot leader: RaftNode followerNextIndex: Int64 -> (Option SnapshotRequest)
  (if (and (> leader.lastIncludedIndex 0) (<= followerNextIndex leader.lastIncludedIndex))
    (some (SnapshotRequest
            :term leader.currentTerm
            :leaderId leader.nodeId
            :lastIncludedIndex leader.lastIncludedIndex
            :lastIncludedTerm leader.lastIncludedTerm
            :snapshotData leader.snapshotData))
    (none))

fn compactLog node: RaftNode snapshotIndex: Int64 snapshotTerm: Int64 data: String -> RaftNode
  (if (or (> snapshotIndex node.commitIndex) (<= snapshotIndex node.lastIncludedIndex))
    node
    (let [(retainedEntries (filter (fn [(e RaftLogEntry)] (> e.index snapshotIndex)) node.logEntries))]
      (with node :logEntries retainedEntries :lastIncludedIndex snapshotIndex :lastIncludedTerm snapshotTerm :snapshotData data)))

fn handleInstallSnapshot node: RaftNode req: SnapshotRequest -> (Pair RaftNode SnapshotResponse)
  (let [(leaderTerm req.term)
        (curTerm node.currentTerm)]
    (if (< leaderTerm curTerm)
      (pair node (SnapshotResponse :term curTerm :success false :lastIncludedIndex node.lastIncludedIndex))
      (let [(sIndex req.lastIncludedIndex)
            (sTerm req.lastIncludedTerm)
            (newVotedFor (if (> leaderTerm curTerm) "" node.votedFor))
            (matchingEntry (fold (fn [(acc RaftLogEntry) (e RaftLogEntry)] -> RaftLogEntry
                                   (if (and (= e.index sIndex) (= e.term sTerm)) e acc))
                                 (makeRaftLogEntry -1 -1 "")
                                 node.logEntries))
            (retainedEntries (if (= matchingEntry.index sIndex)
                               (filter (fn [(e RaftLogEntry)] (> e.index sIndex)) node.logEntries)
                               (list)))
            (newCommit (if (> sIndex node.commitIndex) sIndex node.commitIndex))
            (updatedNode (RaftNode
                           :nodeId node.nodeId
                           :role (roleFollower)
                           :currentTerm leaderTerm
                           :votedFor newVotedFor
                           :peers node.peers
                           :logEntries retainedEntries
                           :commitIndex newCommit
                           :leaderId req.leaderId
                           :lastIncludedIndex sIndex
                           :lastIncludedTerm sTerm
                           :snapshotData req.snapshotData
                           :leaderLeaseExpiresAt 0
                           :leaseTtlMs node.leaseTtlMs
                           :readIndex node.readIndex))]
        (pair updatedNode (SnapshotResponse :term leaderTerm :success true :lastIncludedIndex sIndex)))))

fn addPeer node: RaftNode newPeerId: String -> RaftNode
  (if (or (= newPeerId node.nodeId) (listContains? node.peers newPeerId))
    node
    (with node :peers (listAppend node.peers (list newPeerId))))

fn removePeer node: RaftNode peerIdToRemove: String -> RaftNode
  (let [(updatedPeers (filter (fn [(p String)] (not (= p peerIdToRemove))) node.peers))]
    (with node :peers updatedPeers))

fn renewLeaderLease node: RaftNode nowMs: Int64 -> RaftNode
  (mt node.role
    ((roleLeader)
      (with node :leaderLeaseExpiresAt (+ nowMs node.leaseTtlMs) :readIndex node.commitIndex))
    (_ node))

fn serveLinearizableRead node: RaftNode nowMs: Int64 -> (Option Int64)
  (mt node.role
    ((roleLeader)
      (if (< nowMs node.leaderLeaseExpiresAt)
        (some node.readIndex)
        (none)))
    (_ (none)))

fn formatRaftState node: RaftNode -> String
  (let [(roleStr (mt node.role
                   ((roleFollower) "follower")
                   ((roleCandidate) "candidate")
                   ((roleLeader) "leader")))]
    (str "(:raft-node :id \"" node.nodeId "\" :role \"" roleStr "\" :term " (stringFromInt64 node.currentTerm) " :commitIndex " (stringFromInt64 node.commitIndex) ")"))

fn jointConfigurationTransition node: RaftNode newPeers: (List String) -> RaftNode
  (let [(combinedPeers (fold (fn [(acc (List String)) (p String)]
                               (if (or (= p node.nodeId) (listContains? acc p))
                                 acc
                                 (listAppend acc (list p))))
                             node.peers
                             newPeers))
        (nextIdx (+ (listLength node.logEntries) 1))
        (jointCmd (str "config:joint:" (stringJoin newPeers ",")))
        (jointEntry (makeRaftLogEntry node.currentTerm nextIdx jointCmd))
        (updatedLog (listAppend node.logEntries (list jointEntry)))]
    (with node :peers combinedPeers :logEntries updatedLog))

fn commitJointConfiguration node: RaftNode -> RaftNode
  (let [(jointEntryOpt (fold (fn [(found (Option RaftLogEntry)) (entry RaftLogEntry)]
                               (if (stringStartsWith? entry.command "config:joint:")
                                 (some entry)
                                 found))
                             (none)
                             node.logEntries))]
    (mt jointEntryOpt
      ((some entry)
        (let [(cmd entry.command)
              (newPeersStr (optionOr (stringSlice cmd 13 (stringLength cmd)) ""))
              (rawPeers (if (stringEmpty? newPeersStr) (list) (stringSplit newPeersStr ",")))
              (finalPeers (fold (fn [(acc (List String)) (p String)]
                                  (if (or (= p node.nodeId) (stringEmpty? p) (listContains? acc p))
                                    acc
                                    (listAppend acc (list p))))
                                (list)
                                rawPeers))
              (nextIdx (+ (listLength node.logEntries) 1))
              (finalCmd (str "config:final:" newPeersStr))
              (finalEntry (makeRaftLogEntry node.currentTerm nextIdx finalCmd))
              (updatedLog (listAppend node.logEntries (list finalEntry)))]
          (with node :peers finalPeers :logEntries updatedLog :commitIndex nextIdx)))
      ((none) node)))

fn renewLeaderLeaseWithQuorum node: RaftNode acks: Int64 nowMs: Int64 -> RaftNode
  (mt node.role
    ((roleLeader)
      (let [(totalClusterSize (+ (listLength node.peers) 1))]
        (if (isQuorumAchieved acks totalClusterSize)
          (with node :leaderLeaseExpiresAt (+ nowMs node.leaseTtlMs) :readIndex node.commitIndex)
          (with node :leaderLeaseExpiresAt 0))))
    (_ node))

fn isJointQuorumAchieved votesOld: Int64 clusterSizeOld: Int64 votesNew: Int64 clusterSizeNew: Int64 -> Bool
  (and (isQuorumAchieved votesOld clusterSizeOld)
       (isQuorumAchieved votesNew clusterSizeNew))
