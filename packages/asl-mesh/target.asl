(:targetAdapter
  :package "asl-mesh"
  :authority "ADR0081"
  :substrate "pure-asl"
  :projections (
    (:projection
      :id "native"
      :backend "llvm"
      :outputArtifact "dist/asl-mesh"
      :options (list "-O3"))
    (:projection
      :id "wasm"
      :backend "wat"
      :outputArtifact "dist/mesh.wasm"
      :options (list "-Os"))
  )
)
