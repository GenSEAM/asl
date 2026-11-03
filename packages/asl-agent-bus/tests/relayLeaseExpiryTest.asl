(module asl-agent-bus/tests/relayLeaseExpiryTest :x [runTests] :i [(aslAgentBus/cluster :a cl)])

; (:m :ref COVBATCH3 :do "isRelayLeaseExpired?: a lease expires at grantedAt plus ttlMs, not before")
fn lease granted: Int64 ttl: Int64 -> cl/RelayLease
  (cl/RelayLease :logicalPath "p" :sessionId "s" :taskId "t" :grantedAt granted :ttlMs ttl :digest "d")

fn runTests -> Bool
  (do
    (assert (not (cl/isRelayLeaseExpired? (lease 100 50) 149)) "one tick before the end is live")
    (assert (cl/isRelayLeaseExpired? (lease 100 50) 150) "at grantedAt plus ttl it is expired")
    (assert (cl/isRelayLeaseExpired? (lease 100 50) 151) "after the end it is expired")
    (assert (not (cl/isRelayLeaseExpired? (lease 100 50) 0)) "before the grant it is live")
    (assert (not (cl/isRelayLeaseExpired? (lease 100 50) 100)) "at the grant it is live")
    (assert (cl/isRelayLeaseExpired? (lease 100 0) 100) "a zero ttl is expired at once")
    (assert (not (cl/isRelayLeaseExpired? (lease 0 1000) 999)) "a lease from time zero")
    true)
