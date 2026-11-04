(module aslAgent/tests/journalUsageTest
  :x [runTests]
  :i [(aslAgent/providers :a pv) (asl-tools/fleet/run :a fr)])

; (:m :ref JOURNAL-USAGE-ROWS :do "a provider reply's usage block lands in the session journal as (:usage :in :cached :out :model): the OpenAI-shaped block the gateway and hub return (prompt_tokens, prompt_tokens_details.cached_tokens, completion_tokens) and the ASN reply's own usage; a reply without usage writes nothing")
fn cfgFor temp: String -> pv/VendorConfig
  (pv/VendorConfig :vendor "agy" :mode "scout" :rootDir temp :model "m-asked" :timeout 20 :queueTimeout 20 :sessionId "s1" :intent "auto" :timeoutSet true
    :env (pv/ProviderEnv :gatewayUrl "http://127.0.0.1:1/v1/chat/completions" :inProcess false :profile "" :gatewayConfig (str temp "/.asl/gateway.asn") :tmpDir (str temp "/tmp") :childEnv (mapEmpty))
    :link none :turn 0)

fn jsonRaw body: String -> String
  (str "HTTP/1.1 200 OK\r\nContent-Type: application/json\r\nContent-Length: " (stringFromInt64 (stringLength body)) "\r\nConnection: close\r\n\r\n" body)

fn asnRaw body: String -> String
  (str "HTTP/1.1 200 OK\r\nContent-Type: application/asn+sexpr\r\nContent-Length: " (stringFromInt64 (stringLength body)) "\r\nConnection: close\r\n\r\n" body)

fn journalOf temp: String -> String
  (resultOr (fileReadString (str temp "/.asl/run/agentLoop/s1.journal")) "")

fn ! runTests -> Bool
  (let [(temp (stringTrim (resultOr (fr/shellOut "/usr/bin/mktemp -d /tmp/journalUsageTest.XXXXXX" 5000) "")))
        (p (pv/vendorProvider (cfgFor temp)))
        (usageBody "{\"model\":\"m-served\",\"choices\":[{\"message\":{\"role\":\"assistant\",\"content\":\"hi\"}}],\"usage\":{\"prompt_tokens\":120,\"prompt_tokens_details\":{\"cached_tokens\":80},\"completion_tokens\":15}}")
        (plainBody "{\"model\":\"m-served\",\"choices\":[{\"message\":{\"role\":\"assistant\",\"content\":\"hi\"}}]}")
        (none_ (pv/nextTurnReply p (jsonRaw plainBody)))
        (afterNone (journalOf temp))
        (withUsage (pv/nextTurnReply p (jsonRaw usageBody)))
        (afterJson (journalOf temp))
        (viaAsn (pv/nextTurnReply p (asnRaw "(:reply :content \"x\" :usage (:input 7 :cached 3 :output 2) :model \"m-asn\")")))
        (afterAsn (journalOf temp))
        (cleaned (fr/shellOut (str "/bin/rm -rf " temp) 5000))]
    (do (assert (not (stringContains? afterNone "(:usage")) (str "a reply without usage writes nothing: " afterNone))
        (assert (stringContains? afterJson "(:usage :in 120 :cached 80 :out 15 :model \"m-served\")") (str "the openai usage block lands in the journal with the stub's numbers: " afterJson))
        (assert (stringContains? afterAsn "(:usage :in 7 :cached 3 :out 2 :model \"m-asn\")") (str "the ASN reply's usage lands too: " afterAsn))
        (assert (match withUsage.meta.usage ((some _) true) ((none) false)) "the turn meta still carries the usage")
        true))
