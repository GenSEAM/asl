(module asl-tools/hub/preflight
  :x [hubPreflight]
  :i [])

; (:m :ref ORCH-NODE2-CUTOVER-BUG :do "a unit worktree whose agentLoop predates the hub client would give its Leon an in-process gateway with its own buckets; when HOME/.asl/hub.asn names a :sock the worktree's providers.asl must carry hubAsnPath, else the write stage must not start: (ok hubClient) with a hub and a client, (ok noHub) without hub.asn, (err ERR_HUB_CLIENT_MISSING ...) otherwise")
fn ! hubPreflight home: String root: String -> (Result String String)
  (let [(hub (resultOr (fileReadString (str home "/.asl/hub.asn")) ""))]
    (if (not (stringContains? hub ":sock \"")) (ok "noHub")
      (if (stringContains? (resultOr (fileReadString (str root "/asl/packages/asl-agent/src/providers.asl")) "") "hubAsnPath")
        (ok "hubClient")
        (err (str "ERR_HUB_CLIENT_MISSING: " root " has no hub client in asl/packages/asl-agent/src/providers.asl while " home "/.asl/hub.asn names a hub; rebase the unit on a main that has it")))))
