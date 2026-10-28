(module aslGateway/tests/secretsWireTest
  :x [runTests]
  :i [(chat :a ch)
      (sessions :a s)
      (cliDispatch :a cli)
      (secrets :a sc)])

; (:m :ref GW-WIRE-UP :do "credentialKey picks the provider key (secret over keyEnv, cli none) and a vendor row's NAME@id env entry puts the secret into the child env list; the secret value never appears in an error")
fn ! scratch! -> String
  (let [(d (str "/tmp/gwSecretsWire-" (procSelf) "-" (nowNs)))
        (_ (dirCreate d))]
    d)

fn vendor env: (List String) -> s/SessVendor
  (s/SessVendor :name "v" :bin "/usr/bin/true" :env env :first (list) :resume (list) :idFrom "" :replyFrom "" :wrap "" :wrapResume "" :sep "" :modelArgs (list) :fork (list))

fn ctx -> s/SessCtx
  (s/SessCtx :secretsFile "" :dir "/tmp" :vendors (list) :env (list "PATH=/usr/bin" "OTHER=x") :timeoutSec 5 :ttlSec 0 :ledger "")

fn testCredentialKey -> Bool
  (let [(env (mapFromPairs (list (pair "SOME_KEY" "envval") (pair (sc/secretEnvName "myId") "secretval"))))]
    (do
      (assert (= (ch/credentialKey "openai" env "SOME_KEY" "") "envval") "no secret falls back to keyEnv")
      (assert (= (ch/credentialKey "openai" env "SOME_KEY" "myId") "secretval") "a secret wins over keyEnv")
      (assert (= (ch/credentialKey "openai" env "SOME_KEY" "unresolved") "") "an unresolved secret gives an empty key, not the keyEnv value")
      (assert (= (ch/credentialKey "cli" env "SOME_KEY" "myId") "") "a cli entry has no key")
      true))

fn ! testVendorEnv! dir: String -> Bool
  (let [(p (str dir "/secrets.asn"))
        (_w (fileWrite p "(:secret :id tokenA :value \"sv-AAAA1111\")\n"))
        (_m (fileChmod p 384))
        (v (vendor (list "PATH" "TOKEN@tokenA")))
        (got (s/sessVendorEnvAt! (ctx) v p))
        (missing (s/sessVendorEnvAt! (ctx) (vendor (list "TOKEN@nope")) p))
        (nofile (s/sessVendorEnvAt! (ctx) v (str dir "/absent.asn")))
        (plain (s/sessVendorEnvAt! (ctx) (vendor (list "PATH")) (str dir "/absent.asn")))]
    (do
      (assert (= (listLength (s/sessSecretRows v)) 1) "one NAME@id row is read")
      (assert (= got (ok (list "PATH=/usr/bin" "TOKEN=sv-AAAA1111"))) "the secret reaches the child env list next to the allowed names")
      (assert (match missing ((err e) (and (stringContains? e "nope") (not (stringContains? e "sv-AAAA1111")))) ((ok _) false)) "a missing secret fails naming the id")
      (assert (match nofile ((err e) (not (stringContains? e "sv-AAAA1111"))) ((ok _) false)) "an unavailable store fails the turn")
      (assert (= plain (ok (list "PATH=/usr/bin"))) "a vendor without secret rows is unchanged")
      true))

fn envFrom pairs: (List (Pair String String)) -> (fn [String] -> (Option String))
  (fn [n] (mapGet (mapFromPairs pairs) n))

fn testCliEnv -> Bool
  (let [(store (resultToOptionT (sc/secretsParse "/x" "(:secret :id OPENAI_API_KEY :value \"sk-fromfile\")\n(:secret :id PATH :value \"/evil\")\n")))
        (names (list "PATH" "OPENAI_API_KEY"))
        (keys (list "OPENAI_API_KEY"))
        (lacking (cli/cliEnvAssignments names keys (envFrom (list (pair "PATH" "/usr/bin"))) store))
        (envWins (cli/cliEnvAssignments names keys (envFrom (list (pair "PATH" "/usr/bin") (pair "OPENAI_API_KEY" "fromenv"))) store))
        (noStore (cli/cliEnvAssignments names keys (envFrom (list (pair "PATH" "/usr/bin"))) none))
        (nonKey (cli/cliEnvAssignments (list "PATH") keys (envFrom (list)) store))]
    (do
      (assert (= lacking (ok "PATH=/usr/bin\nOPENAI_API_KEY=sk-fromfile")) "a key variable the env lacks comes from the secrets row")
      (assert (= envWins (ok "PATH=/usr/bin\nOPENAI_API_KEY=fromenv")) "the process env wins over the secrets row")
      (assert (= noStore (ok "PATH=/usr/bin")) "without a store nothing is added")
      (assert (= nonKey (ok "")) "a non-key variable is never taken from the secrets file")
      true))

fn resultToOptionT r: (Result sc/SecretStore String) -> (Option sc/SecretStore)
  (match r ((ok v) (some v)) ((err _) none))

fn ! testSecretsFileOverride! dir: String -> Bool
  (let [(p (str dir "/own.asn"))
        (_w (fileWrite p "(:secret :id tokenB :value \"sv-BBBB2222\")\n"))
        (_m (fileChmod p 384))
        (text (str "(:gateway :secretsFile \"" p "\" :sessions ((:vendor v :bin \"/usr/bin/true\" :env (\"PATH\" \"TOKEN@tokenB\"))))\n"))
        (c (s/sessCtxFromText text dir (list "PATH=/usr/bin")))
        (plain (s/sessCtxFromText "(:gateway :sessions ())\n" dir (list)))
        (v (optionOr (listHead c.vendors) (vendor (list))))
        (got (s/sessVendorEnvFull! c v))]
    (do
      (assert (= c.secretsFile p) "the gateway form's :secretsFile reaches the session ctx")
      (assert (= got (ok (list "PATH=/usr/bin" "TOKEN=sv-BBBB2222"))) "the vendor secret comes from the configured file")
      (assert (not (stringEmpty? plain.secretsFile)) "without an override the default path is used")
      true))

fn errOf r: (Result String String) -> String
  (match r ((err e) e) ((ok _) ""))

fn ! testEnvRefusals! dir: String -> Bool
  (let [(bad (str dir "/loose.asn"))
        (_a (fileWrite bad "(:secret :id OPENAI_API_KEY :value \"sk-LOOSE9999\")\n"))
        (_b (fileChmod bad 420))
        (loose (cli/buildEnvStringAt! "codex" bad))
        (good (str dir "/nl.asn"))
        (_c (fileWrite good "(:secret :id OPENAI_API_KEY :value \"sk-A\\nINJECT=1\")\n"))
        (_d (fileChmod good 384))
        (nl (cli/buildEnvStringAt! "codex" good))
        (quoted (str dir "/q.asn"))
        (_e (fileWrite quoted "(:secret :id OPENAI_API_KEY :value \"\\\"wrapped\\\"\")\n"))
        (_f (fileChmod quoted 384))
        (qr (cli/buildEnvStringAt! "codex" quoted))
        (absent (cli/buildEnvStringAt! "codex" (str dir "/nothere.asn")))]
    (do
      (assert (stringContains? (errOf loose) "ERR_SECRETS_PERMS") "a store with loose permissions fails the dispatch env with its receipt")
      (assert (not (stringContains? (errOf loose) "LOOSE9999")) "that receipt carries no value")
      (assert (stringContains? (errOf nl) "ERR_SECRET_VALUE") "a value with a newline is refused")
      (assert (not (stringContains? (errOf nl) "INJECT")) "the refusal does not echo the value")
      (assert (stringContains? (errOf qr) "ERR_SECRET_VALUE") "a value wrapped in quotes is refused")
      (assert (ok? absent) "an absent store is not an error")
      true))

fn ! runTests -> Bool
  (let [(d (scratch!))]
    (do
      (assert (testCredentialKey) "testCredentialKey passed")
      (assert (testVendorEnv! d) "testVendorEnv passed")
      (assert (testCliEnv) "testCliEnv passed")
      (assert (testEnvRefusals! d) "testEnvRefusals passed")
      (assert (testSecretsFileOverride! d) "testSecretsFileOverride passed")
      (assert (ok? (pathRemove d)) "scratch removed")
      true))
