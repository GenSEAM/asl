(:package "asl-coord"
  :version "0.2.0"
  :public true
  :entry "src/claims.asl"
  :doc "Shared scope claim leases, needs and presence over the asl-store vault"
  :modules (
    "asl-coord/paths"
    "asl-coord/lease"
    "asl-coord/core"
    "asl-coord/needs"
    "asl-coord/presence"
    "asl-coord/locate"
    "asl-coord/claims"
  )
  :dependencies ("asl-store" "asl-store-fs")
)
