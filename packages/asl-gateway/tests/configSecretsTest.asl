(module aslGateway/tests/configSecretsTest
  :x [runTests]
  :i [(config :a cfg)])

fn textWith provider: String -> String
  (str "(:gateway :v 2 :providers (" provider ") :models ((:model :id m :provider mac :name \"agyFlash\")) :profiles ((:profile :id default :routes ((:intent any :chain (m))))) :uses ((:use :for default :profile default)))")

fn ! parseText! text: String -> (Result cfg/GatewayTable String)
  (cfg/gatewayConfigParse! text "secretsCfg" ".asl/mem/calibration/index.asn")

fn errOf r: (Result cfg/GatewayTable String) -> String
  (match r ((err e) e) ((ok _) ""))

fn ! scratch! -> String
  (let [(d (str "/tmp/gwConfigSecretsTest-" (procSelf) "-" (nowNs)))
        (_ (dirCreate d))]
    d)

fn ! drop! dir: String -> Bool
  (let [(names (resultOr (dirList dir) (list)))
        (_ (map (fn [(n String)] -> Bool (ok? (pathRemove (str dir "/" n)))) names))]
    (ok? (pathRemove dir)))

fn ! testParse! -> Bool
  (let [(good (parseText! (textWith "(:provider :id mac :kind gateway :base \"http://127.0.0.1:18080\" :secret macToken)")))
        (noSecret (parseText! (textWith "(:provider :id mac :kind gateway :base \"http://127.0.0.1:18080\")")))
        (badId (parseText! (textWith "(:provider :id mac :kind gateway :base \"http://127.0.0.1:18080\" :secret \"two words\")")))
        (onlySecret (parseText! (textWith "(:provider :id mac :kind openai :base \"http://127.0.0.1:18080\" :secret macToken)")))
        (withEnv (parseText! (textWith "(:provider :id mac :kind openai :base \"http://127.0.0.1:18080\" :keyEnv \"MAC_KEY\" :secret macToken)")))
        (kind (parseText! (textWith "(:provider :id mac :kind weird :base \"http://127.0.0.1:18080\")")))]
    (do
      (assert (match good ((ok t) (match (mapGet t.providers "mac") ((some p) (and (= p.kind "gateway") (and (= p.secret "macToken") (= p.keyEnv "ASLSECRET_macToken")))) ((none) false))) ((err _) false)) (str "a gateway provider with :secret parses and reads its key from the injected env name: " (errOf good)))
      (assert (match onlySecret ((ok t) (match (mapGet t.providers "mac") ((some p) (= p.keyEnv "ASLSECRET_macToken")) ((none) false))) ((err _) false)) (str "a secret-only provider is accepted: " (errOf onlySecret)))
      (assert (match withEnv ((ok t) (match (mapGet t.providers "mac") ((some p) (and (= p.secret "macToken") (= p.keyEnv "ASLSECRET_macToken"))) ((none) false))) ((err _) false)) "a secret wins over a keyEnv on the same row")
      (assert (stringContains? (errOf noSecret) "needs :secret") (str "a gateway provider without :secret is refused: " (errOf noSecret)))
      (assert (stringContains? (errOf badId) ":secret must name") (str "a secret id with a space is refused: " (errOf badId)))
      (assert (stringContains? (errOf kind) "cli or gateway") "the kind error lists gateway")
      (assert (match (parseText! (textWith "(:provider :id mac :kind openai :base \"http://127.0.0.1:1\" :promptCacheKey true)")) ((ok t) (cfg/providerPromptCacheKey? t "mac")) ((err _) false)) ":promptCacheKey true is read by the accessor")
      (assert (match (parseText! (textWith "(:provider :id mac :kind openai :base \"http://127.0.0.1:1\")")) ((ok t) (not (cfg/providerPromptCacheKey? t "mac"))) ((err _) false)) "default is false")
      (assert (not (ok? (parseText! (textWith "(:provider :id mac :kind openai :base \"http://127.0.0.1:1\" :promptCacheKey 3)")))) "a non-bool is refused")
      true))

fn ! testResolve! -> Bool
  (let [(dir (scratch!))
        (p (str dir "/secrets.asn"))
        (_ (fileWrite p "(:secret :id macToken :value \"tok-CFG-91ab34cd\")\n"))
        (_2 (fileChmod p 384))
        (fromFile (cfg/resolveProviderCredential! p (list) "macToken" "GWCFG_UNSET_ENV_XYZ"))
        (missing (cfg/resolveProviderCredential! p (list) "nope" "GWCFG_UNSET_ENV_XYZ"))
        (envOnly (cfg/resolveProviderCredential! p (list) "" "GWCFG_UNSET_ENV_XYZ"))
        (_3 (fileChmod p 420))
        (loose (cfg/resolveProviderCredential! p (list) "macToken" "GWCFG_UNSET_ENV_XYZ"))
        (_4 (drop! dir))]
    (do
      (assert (match fromFile ((ok (some v)) (= v "tok-CFG-91ab34cd")) (_ false)) "a secret resolves from the file with the env var unset")
      (assert (match missing ((err e) (and (stringContains? e "ERR_SECRET_MISSING") (stringContains? e "nope"))) (_ false)) "a missing secret is ERR_SECRET_MISSING and does not fall back to env")
      (assert (match envOnly ((ok (none)) true) (_ false)) "no :secret falls back to :keyEnv, unset gives none")
      (assert (match loose ((err e) (and (stringContains? e "ERR_SECRETS_PERMS") (not (stringContains? e "tok-CFG")))) (_ false)) "a 0644 secrets file is refused without printing a value")
      true))

; (:m :ref GW-SECRETS-FILE-OVERRIDE-server :do "the server reads the same top-level :secretsFile as config check; absent, malformed or non-string text is none and a leading ~ expands to HOME")
fn testSecretsFileOverride -> Bool
  (let [(withPath (cfg/gatewaySecretsFileOverride "(:gateway :v 2 :secretsFile \"/custom/s.asn\")"))
        (without (cfg/gatewaySecretsFileOverride "(:gateway :v 2)"))
        (malformed (cfg/gatewaySecretsFileOverride "not even a gateway form"))
        (nonString (cfg/gatewaySecretsFileOverride "(:gateway :v 2 :secretsFile 42)"))]
    (do
      (assert (= withPath (some "/custom/s.asn")) "a :secretsFile string is read back exactly")
      (assert (= without none) "an absent :secretsFile is none")
      (assert (= malformed none) "unparseable text is none")
      (assert (= nonString none) "a non-string :secretsFile is none")
      (assert (match (cfg/gatewaySecretsFileChoice "(:gateway :v 2 :secretsFile 42)") ((err e) (stringContains? e "ERR_SECRETS_CONFIG")) (_ false)) "the strict choice refuses a non-string :secretsFile")
      (assert (match (cfg/gatewaySecretsFileChoice "(:gateway :v 2") ((err e) (stringContains? e "ERR_SECRETS_CONFIG")) (_ false)) "the strict choice refuses text that does not parse")
      (assert (match (cfg/gatewaySecretsFileChoice "(:gateway :v 2)") ((ok (none)) true) (_ false)) "an absent key is ok none")
      (assert (match (cfg/gatewaySecretsFileChoice "") ((ok (none)) true) (_ false)) "empty text is ok none")
      true))

; (:m :ref GW-CONFIGCHECK-SECRET-BLIND :do "the warnings a config check and the start log print consult the secrets file for :secret providers and the keyFiles for :keyEnv providers; a secret-only provider needs no :keyEnv; a key found nowhere still warns, naming the env and the files and never a value")
fn ! testWarnings! -> Bool
  (let [(dir (scratch!))
        (sp (str dir "/secrets.asn"))
        (kf (str dir "/keys.env"))
        (_ (do (fileWrite sp "(:secret :id wTok :value \"tok-WARN-7788aabb\")\n") (fileChmod sp 384) true))
        (_2 (fileWrite kf "export WARN_FILE_KEY=kf-WARN-99ccdd\n"))
        (text (fn [(extra String)] -> String
                (str "(:gateway :v 2 :secretsFile \"" sp "\" :keyFiles (\"" kf "\") :providers ((:provider :id ps :kind openai :base \"http://127.0.0.1:1\" :secret wTok) (:provider :id pk :kind openai :base \"http://127.0.0.1:1\" :keyEnv WARN_FILE_KEY)" extra ")"
                     " :models ((:model :id m1 :provider ps :name \"a\") (:model :id m2 :provider pk :name \"b\")" (if (stringEmpty? extra) "" " (:model :id m3 :provider pn :name \"c\")") ")"
                     " :profiles ((:profile :id default :routes ((:intent any :chain (m1 m2))))) :uses ((:use :for default :profile default)))")))
        (clean (parseText! (text "")))
        (lost (parseText! (text " (:provider :id pn :kind openai :base \"http://127.0.0.1:1\" :keyEnv WARN_NOWHERE_KEY)")))
        (warnsOf (fn [(r (Result cfg/GatewayTable String))] -> String (match r ((ok t) (stringJoin t.warnings " | ")) ((err e) e))))
        (_3 (drop! dir))]
    (do
      (assert (= (warnsOf clean) "") (str "a secret-only provider and a keyFiles-only key give no warning: " (warnsOf clean)))
      (assert (and (stringContains? (warnsOf lost) "WARN_NOWHERE_KEY is not set") (stringContains? (warnsOf lost) "keys.env")) (str "a key found nowhere still warns and names the files: " (warnsOf lost)))
      (assert (not (stringContains? (str (warnsOf clean) (warnsOf lost)) "tok-WARN-7788aabb")) "no warning prints a value")
      true))

fn ! runTests -> Bool
  (let [(a (testParse!))
        (b (testResolve!))
        (c (testSecretsFileOverride))
        (d (testWarnings!))]
    (and a (and b (and c d))))
