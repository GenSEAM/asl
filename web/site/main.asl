(module aslSite/main
  :x [! main ! update ! render ! measured]
  :i [(aslSite/ui/html :a h) (aslSite/ui/bridge :a b) (aslSite/app/msg :a m) (aslSite/app/home :a home) (aslSite/app/update :a u)])

fn ! main -> Int64
  0

fn ! update code: Int64 model: Int64 -> Int64
  (let [(r (u/step (m/msgOf code) model))]
    (do (print (b/encodeOps (pairSecond r))) (pairFirst r)))

fn ! render -> Int64
  (stringLength (h/renderDocument (home/homePage (home/placeholderStats))))

fn ! measured cold: Int64 warm: Int64 bytes: Int64 -> Int64
  (do (print (b/encodeOps (u/measuredOps cold warm bytes))) 0)
