---
name: asl-mem
description: >-
  Canonical 8-tool memory matrix with dense keyword signatures, fail-open lazy loading, and staged RAM VFS.
---

(:skill
  :name "asl-mem"
  :desc "Canonical 8-tool memory matrix with dense keyword signatures, fail-open lazy loading, and staged RAM VFS."
  :rules [
    (:rule :type "mandatory" :text "Dense signatures: invoke tools using canonical dense signatures; pass '--help' to hydrate full schemas JIT.")
    (:rule :type "mandatory" :text "Fail-open discovery: missing arguments or '--help' return exit code 0 with structured ASN receipt without error.")
    (:rule :type "safety" :text "Non-destructive help guard: '--help' on discard or flush NEVER mutates staged buffers or disk.")
    (:rule :type "workflow" :text "Stage text replacements in RAM with 'asl mem edit', preview with 'asl mem diff', commit with 'asl mem flush', or drop with 'asl mem discard'.")
    (:rule :type "workflow" :text "Use 'asl mem query <text>' for vector search, 'asl mem doc <file> <sec>' for targeted reading, and 'asl mem tree' for telemetry.")
  ]
  :tools [
    (:tool :name "mem.query" :sig "query [scope] [limit]" :cmd "asl mem query <query>" :d "vector semantic search AST" :savings "90%")
    (:tool :name "mem.edit" :sig "file old new" :cmd "asl mem edit <file> <old> <new>" :d "stage atomic string replacement" :savings "85%")
    (:tool :name "mem.diff" :sig "[file]" :cmd "asl mem diff [file]" :d "inspect staged RAM diffs" :savings "90%")
    (:tool :name "mem.flush" :sig "" :cmd "asl mem flush" :d "persist staged edits disk" :savings "85%")
    (:tool :name "mem.discard" :sig "" :cmd "asl mem discard" :d "clear staged RAM buffers" :savings "90%")
    (:tool :name "mem.write" :sig "kind payload" :cmd "asl mem write <kind> <payload>" :d "append durable memory ledger" :savings "88%")
    (:tool :name "mem.doc" :sig "file section" :cmd "asl mem doc <file> <section>" :d "read section without disk" :savings "92%")
    (:tool :name "mem.tree" :sig "[path]" :cmd "asl mem tree [path]" :d "render holistic hierarchy telemetry" :savings "85%")
  ]
  :targets ["claude-code" "factory-droid" "antigravity" "cursor" "windsurf" "universal-agents"])
