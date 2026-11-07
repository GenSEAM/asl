(module aslAgent/tests/contextAliasTest
  :x [runTests]
  :i [(aslAgent/context :a x) (asl-json/json :a j)])

; (:m :ref LEON-CTX-ALIAS :do "a gateway alias with no family word (synDs41Flash) sized its context by smallContextTokens; contextTokensForIn resolves it through the alias row: row :contextTokens, then the family of the row :name; an unknown alias, a prefix of a known one and a row whose name has no family word stay small; an explicit value still wins; contextTokensAt! reads the config file it is given")
fn gatewayText -> String
  (str "(:gateway :version 1\n"
       "  :models ((:model :id synDs41Flash :provider synthetic :name \"hf:deepseek-ai/DeepSeek-V4.1-Flash-1017\" :maxTokens 32768)\n"
       "           (:model :id plainAlias :provider synthetic :name \"hf:acme/Widget-7B\" :maxTokens 32768)\n"
       "           (:model :id sizedAlias :provider synthetic :name \"hf:acme/Widget-9B\" :contextTokens 64000 :maxTokens 32768)\n"
       "           (:model :id \"quotedAlias\" :provider synthetic :name \"hf:moonshotai/Kimi-K3.1-Pro\")))\n")

fn ! scratch -> String
  (str (optionOr (envGet "TMPDIR") "/tmp") "/contextAliasTest-" (stringFromInt64 (procSelf)) "-" (stringFromInt64 (nowNs)) ".asn")

fn ! runTests -> Bool
  (let [(text (gatewayText))
        (alias (x/contextTokensForIn (some "synDs41Flash") (j/jnull) false text))
        (pureAlias (x/contextTokensFor (some "synDs41Flash") (j/jnull) false))
        (unknown (x/contextTokensForIn (some "noSuchAlias") (j/jnull) false text))
        (prefix (x/contextTokensForIn (some "synDs41") (j/jnull) false text))
        (plain (x/contextTokensForIn (some "plainAlias") (j/jnull) false text))
        (sized (x/contextTokensForIn (some "sizedAlias") (j/jnull) false text))
        (quoted (x/contextTokensForIn (some "quotedAlias") (j/jnull) false text))
        (explicit (x/contextTokensForIn (some "synDs41Flash") (j/jint 5000) false text))
        (family (x/contextTokensForIn (some "deepseek-v4-flash") (j/jnull) false ""))
        (path (scratch))
        (wrote (fileWrite path text))
        (fromFile (x/contextTokensAt! (some "synDs41Flash") (j/jnull) false path))
        (_ (pathRemove path))
        (missing (x/contextTokensAt! (some "synDs41Flash") (j/jnull) false path))]
    (do (assert (= alias 120000) (str "an alias whose row name holds deepseek gets the deepseek budget: " (stringFromInt64 alias)))
        (assert (= pureAlias 8000) (str "the pure family match on the bare alias alone stays small: " (stringFromInt64 pureAlias)))
        (assert (= unknown 8000) (str "an alias with no row stays small: " (stringFromInt64 unknown)))
        (assert (= prefix 8000) (str "a prefix of a known alias does not take its row: " (stringFromInt64 prefix)))
        (assert (= plain 8000) (str "a row whose name has no family word stays small: " (stringFromInt64 plain)))
        (assert (= sized 64000) (str "a row :contextTokens is honoured: " (stringFromInt64 sized)))
        (assert (= quoted 120000) (str "a quoted row id resolves too (kimi): " (stringFromInt64 quoted)))
        (assert (= explicit 5000) (str "an explicit contextTokens still wins: " (stringFromInt64 explicit)))
        (assert (= family 120000) (str "a model id with a family word needs no config: " (stringFromInt64 family)))
        (assert (and (ok? wrote) (= fromFile 120000)) (str "contextTokensAt! resolves through the config file: " (stringFromInt64 fromFile)))
        (assert (= missing 8000) (str "an unreadable config leaves the alias small: " (stringFromInt64 missing)))
        (assert (= (x/gatewayConfigPathFrom (none) (some "/h")) "/h/.asl/gateway.asn") "the config defaults to HOME/.asl/gateway.asn")
        (assert (= (x/gatewayConfigPathFrom (some "/c/g.asn") (some "/h")) "/c/g.asn") "ASL_GATEWAY_CONFIG names the config")
        (assert (= (x/gatewayConfigPathFrom (some "") (some "/h")) "/h/.asl/gateway.asn") "an empty ASL_GATEWAY_CONFIG falls back to HOME")
        true))
