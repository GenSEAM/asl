(module asl-engine/guard
  :x [RssStatus formatCriticalRssMessage evaluateRss sampleCurrentRssMb! checkRssGuard!]
  :i [])

(schema RssStatus
  (:f level String)
  (:f currentRssMb Int64)
  (:f softLimitMb Int64)
  (:f hardLimitMb Int64)
  (:f criticalMessage String))

fn formatCriticalRssMessage rssMb: Int64 maxMb: Int64 -> String
  (str "[CRITICAL] ASL Engine memory ceiling exceeded (" (stringFromInt64 rssMb) ".0 MB > " (stringFromInt64 maxMb) ".0 MB). Triggering emergency self-healing cleanup...")

fn evaluateRss rssMb: Int64 softMb: Int64 hardMb: Int64 -> RssStatus
  (cond
    ((> rssMb hardMb)
      (RssStatus :level ":critical" :currentRssMb rssMb :softLimitMb softMb :hardLimitMb hardMb :criticalMessage (formatCriticalRssMessage rssMb hardMb)))
    ((> rssMb softMb)
      (RssStatus :level ":soft-exceeded" :currentRssMb rssMb :softLimitMb softMb :hardLimitMb hardMb :criticalMessage ""))
    (else
      (RssStatus :level ":ok" :currentRssMb rssMb :softLimitMb softMb :hardLimitMb hardMb :criticalMessage "")))

fn sampleCurrentRssMb! -> Int64
  (mt (procRusage)
    ((ok u)
      (/ u.selfMaxRssKb 1024))
    ((err _)
      0))

fn checkRssGuard! softMb: Int64 hardMb: Int64 -> RssStatus
  (let [(rss (sampleCurrentRssMb!))]
    (evaluateRss rss softMb hardMb))
