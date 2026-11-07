(module asl-proc/atomicWrite
  :x [tmpNameFor fileWriteAtomic!]
  :i [])

fn tmpNameFor path: String pid: Int64 ns: Int64 -> String
  (str path ".tmp-" (stringFromInt64 pid) "-" (stringFromInt64 ns))

fn ! fileWriteAtomic! path: String text: String -> (Result Unit String)
  (let [(tmp (tmpNameFor path (procSelf) (nowNs)))]
    (match (fileWrite tmp text)
      ((err e) (let [(_ (pathRemove tmp))] (err e)))
      ((ok _) (match (pathRename tmp path)
                ((ok _) (ok ()))
                ((err e) (let [(_ (pathRemove tmp))] (err e)))))))
