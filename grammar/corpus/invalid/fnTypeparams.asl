"A lambda takes neither type parameters nor :doc (asl/agentSpecCore.md 4.3):"
"the host reads `fn` followed by anything but a parameter vector as a bad lambda."
fn f -> Int64
  ((fn {A} [(x A)] -> A x) 1)
