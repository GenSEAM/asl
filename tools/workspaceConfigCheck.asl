(module ws/asl/tools/workspaceConfigCheck
  :x [main]
  :i [(asl/packages/asl-cli/src/configSchema :a cs)])

; (:m :ref WS-CONFIG-SCHEMA :do "asl run asl/tools/workspaceConfigCheck.asl check FILE [SCHEMA]: checks a .asl.config.asn or ~/.asl/config.asn against asl/grammar/workspaceConfig.asn, prints the receipt, exit 1 on any error")
fn ! main args: (List String) -> (Result Int64 String)
  (cs/cli! args)
