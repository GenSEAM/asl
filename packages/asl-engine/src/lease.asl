(module asl-engine/lease
  :x [LeaseLock lockPathFor formatLeaseBusyMessage acquireLease! releaseLease!]
  :i [])

(schema LeaseLock
  (:f acquired Bool)
  (:f fd Int64)
  (:f lockPath String)
  (:f error String))

fn lockPathFor socketPath: String -> String
  (str socketPath ".lock")

fn formatLeaseBusyMessage socketPath: String -> String
  (str "[Engine] Engine already active for socket " socketPath " (lock held).")

fn acquireLease! socketPath: String -> (Result LeaseLock String)
  (let [(lPath (lockPathFor socketPath))]
    (mt (fileLock lPath true)
      ((ok fd)
        (ok (LeaseLock :acquired true :fd fd :lockPath lPath :error "")))
      ((err e)
        (if (= e "busy")
          (err (formatLeaseBusyMessage socketPath))
          (err (str "fileLock error: " e))))))

fn releaseLease! lease: LeaseLock -> (Result Unit String)
  (if lease.acquired
    (let [(_ (fdClose lease.fd))
          (_ (pathRemove lease.lockPath))]
      (ok ()))
    (ok ()))
