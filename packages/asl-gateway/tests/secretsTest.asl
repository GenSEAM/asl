(module aslGateway/tests/secretsTest
  :x [runTests]
  :i [(secrets :a s)])

fn ! scratch! -> String
  (let [(d (str "/tmp/gwSecretsTest-" (procSelf) "-" (nowNs)))
        (_ (dirCreate d))]
    d)

fn ! drop! dir: String -> Bool
  (let [(names (resultOr (dirList dir) (list)))
        (_ (map (fn [(n String)] -> Bool (ok? (pathRemove (str dir "/" n)))) names))]
    (ok? (pathRemove dir)))

fn ! writeSecrets! path: String mode: Int64 text: String -> Bool
  (do (fileWrite path text) (fileChmod path mode) true)

fn errText r: (Result s/SecretStore String) -> String
  (match r ((err e) e) ((ok _) ""))

fn rowsText -> String
  "; machine secrets\n(:secret :id openrouterKey :value \"sk-or-AAAA1111\")\n(:secret :id groqKey :value \"gsk_BBBB2222\")\n(:secret :id tricky :value \"q\\\"uote-CCCC3333\")\n"

fn ! testLoadAndGet! dir: String -> Bool
  (let [(p (str dir "/ok.asn"))
        (_ (writeSecrets! p 384 (rowsText)))
        (r (s/secretsLoad! p))]
    (match r
      ((err e) (do (assert false (str "a 0600 secrets file loads, got " e)) false))
      ((ok st)
        (do
          (assert (= (s/secretsIds st) (list "openrouterKey" "groqKey" "tricky")) "ids come back in file order")
          (assert (= (resultOr (s/secretsGet st "groqKey") "") "gsk_BBBB2222") "a secret resolves from the file")
          (assert (= (resultOr (s/secretsGet st "tricky") "") "q\"uote-CCCC3333") "an escaped quote survives")
          true))))

fn ! testPerms! dir: String -> Bool
  (let [(p (str dir "/perms.asn"))
        (_ (writeSecrets! p 420 (rowsText)))
        (loose (errText (s/secretsLoad! p)))
        (_2 (fileChmod p 416))
        (group (errText (s/secretsLoad! p)))
        (_3 (fileChmod p 384))
        (tight (s/secretsLoad! p))]
    (do
      (assert (stringContains? loose "ERR_SECRETS_PERMS") (str "mode 0644 is refused: " loose))
      (assert (stringContains? loose "0644") "the receipt names the mode")
      (assert (stringContains? group "ERR_SECRETS_PERMS") (str "mode 0640 is refused: " group))
      (assert (ok? tight) "the same file at 0600 loads")
      true))

fn ! testSymlink! dir: String -> Bool
  (let [(real (str dir "/real.asn"))
        (link (str dir "/link.asn"))
        (_ (writeSecrets! real 384 (rowsText)))
        (_2 (pathSymlink real link))
        (e (errText (s/secretsLoad! link)))]
    (do
      (assert (stringContains? e "ERR_SECRETS_SYMLINK") (str "a symlinked secrets file is refused: " e))
      true))

fn ! testMissingFile! dir: String -> Bool
  (let [(e (errText (s/secretsLoad! (str dir "/none.asn"))))]
    (do (assert (stringContains? e "ERR_SECRETS_FILE") (str "a missing file is a receipt: " e)) true))

fn ! testEnvInject! dir: String -> Bool
  (let [(p (str dir "/env.asn"))
        (_ (writeSecrets! p 384 (rowsText)))]
    (match (s/secretsLoad! p)
      ((err _) (do (assert false "loads") false))
      ((ok st)
        (let [(r (s/secretsEnvFor st (mapEmpty) (list (pair "OPENROUTER_API_KEY" "openrouterKey"))))
              (missing (s/secretsEnvFor st (mapEmpty) (list (pair "X" "noSuchId"))))]
          (do
            (assert (match r ((ok m) (and (= (mapSize m) 1) (= (optionOr (mapGet m "OPENROUTER_API_KEY") "") "sk-or-AAAA1111"))) ((err _) false)) "a child gets exactly the listed var and nothing else")
            (assert (match missing ((err e) (and (stringContains? e "ERR_SECRET_MISSING") (stringContains? e "noSuchId"))) ((ok _) false)) "a missing id is ERR_SECRET_MISSING naming the id")
            true)))))

fn ! testBadRows! dir: String -> Bool
  (let [(p (str dir "/bad.asn"))
        (_ (writeSecrets! p 384 "(:secret :id a :value \"topsecretDDDD\")\n(:secret :id b :value topsecretEEEE)\n"))
        (bad (errText (s/secretsLoad! p)))
        (_2 (writeSecrets! p 384 "(:secret :id a :value \"dupvalFFFF\")\n(:secret :id a :value \"dupvalGGGG\")\n"))
        (dup (errText (s/secretsLoad! p)))]
    (do
      (assert (stringContains? bad "ERR_SECRET_ROW") (str "a malformed row is refused: " bad))
      (assert (stringContains? bad ":line 2") "it names the line")
      (assert (stringContains? dup "ERR_SECRET_DUPLICATE") (str "a duplicate id is refused: " dup))
      (assert (not (stringContains? (str bad dup) "topsecret")) "errors never print a value")
      (assert (not (stringContains? (str bad dup) "dupval")) "errors never print a duplicate's value")
      true))

fn ! testLeak! dir: String -> Bool
  (let [(p (str dir "/leak.asn"))
        (_ (writeSecrets! p 384 (rowsText)))]
    (match (s/secretsLoad! p)
      ((err _) (do (assert false "loads") false))
      ((ok st)
        (let [(values (list "sk-or-AAAA1111" "gsk_BBBB2222" "q\"uote-CCCC3333"))
              (outputs (str (s/secretsMissingReceipt "groqKey") (errText (s/secretsLoad! (str dir "/none.asn")))
                            (s/secretsRedact st "auth sk-or-AAAA1111 and gsk_BBBB2222 and q\"uote-CCCC3333 end")))]
          (do
            (assert (stringContains? outputs "<secret:groqKey>") "redaction names the id")
            (assert (listAll? (fn [(v String)] -> Bool (not (stringContains? outputs v))) values) "no secret value appears in any receipt or redacted log text")
            true)))))

fn ! testJsonEscaped! dir: String -> Bool
  (let [(p (str dir "/json.asn"))
        (_ (writeSecrets! p 384 (rowsText)))]
    (match (s/secretsLoad! p)
      ((err _) (do (assert false "loads") false))
      ((ok st)
        (let [(out (s/secretsRedact st "{\"auth\":\"q\\\"uote-CCCC3333\"}"))]
          (do (assert (not (stringContains? out "CCCC3333")) (str "the JSON-escaped form of a value is redacted too: " out))
              true)))))

fn ! testRedactForms! -> Bool
  (match (s/secretsParse "/x" "(:secret :id odd :value \"p@ss w/\u00e9\u20acx\")\n")
    ((err e) (do (assert false (str "parses: " e)) false))
    ((ok st)
      (let [(forms (list "p%40ss%20w%2F%C3%A9%E2%82%ACx" "p%40ss%20w%2f%c3%a9%e2%82%acx"
                         "p@ss w/\\u00e9\\u20acx" "p@ss w/\\u00E9\\u20ACx"
                         "\\u0070\\u0040\\u0073\\u0073\\u0020\\u0077\\u002f\\u00e9\\u20ac\\u0078"))
            (leaks (filter (fn [(f String)] -> Bool (let [(out (s/secretsRedact st (str "a " f " b")))] (or (stringContains? out f) (not (stringContains? out "<secret:odd>"))))) forms))]
        (do
          (assert (listEmpty? leaks) (str "forms not redacted: " (stringJoin leaks " | ")))
          true))))

fn ! testEqual! -> Bool
  (do
    (assert (s/secretsEqual? "abc" "abc") "equal strings are equal")
    (assert (not (s/secretsEqual? "abc" "abd")) "a differing byte is unequal")
    (assert (not (s/secretsEqual? "abc" "abcd")) "a longer string is unequal")
    (assert (not (s/secretsEqual? "abcd" "abc")) "a shorter string is unequal")
    (assert (s/secretsEqual? "" "") "empty strings are equal")
    true)

fn ! runTests -> Bool
  (let [(dir (scratch!))
        (ok1 (testLoadAndGet! dir))
        (ok2 (testPerms! dir))
        (ok3 (testSymlink! dir))
        (ok4 (testMissingFile! dir))
        (ok5 (testEnvInject! dir))
        (ok6 (testBadRows! dir))
        (ok7 (testLeak! dir))
        (ok8 (testJsonEscaped! dir))
        (ok9 (testRedactForms!))
        (ok10 (testEqual!))
        (_ (drop! dir))]
    (and ok1 (and ok2 (and ok3 (and ok4 (and ok5 (and ok6 (and ok7 (and ok8 (and ok9 ok10))))))))))
