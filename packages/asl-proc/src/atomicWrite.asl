(module asl-proc/atomicWrite
  :x [tmpNameFor fileWriteAtomic!]
  :i [])

; (:m :ref FILEWRITE-ATOMIC :do "fileWriteAtomic! writes text to a sibling <path>.tmp-<pid>-<ns> and pathRenames it onto path: rename on one filesystem is atomic, so a concurrent reader that polls path sees either the old file or the whole new one, never the truncated or half-written state plain fileWrite exposes; a failed write or rename removes the tmp and returns the error")
fn tmpNameFor path: String pid: Int64 ns: Int64 -> String
  (str path ".tmp-" (stringFromInt64 pid) "-" (stringFromInt64 ns))

fn ! fileWriteAtomic! path: String text: String -> (Result Unit String)
  (let [(tmp (tmpNameFor path (procSelf) (nowNs)))]
    (match (fileWrite tmp text)
      ((err e) (let [(_ (pathRemove tmp))] (err e)))
      ((ok _) (match (pathRename tmp path)
                ((ok _) (ok ()))
                ((err e) (let [(_ (pathRemove tmp))] (err e)))))))
