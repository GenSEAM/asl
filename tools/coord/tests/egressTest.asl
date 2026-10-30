(module asl/tools/coord/tests/egressTest
  :x [runTests]
  :i [(asl-tools/coord/egress :a e)])

fn envVals -> (List String)
  (list "hunter2-prod-value" "abc")

fn testSecrets -> Bool
  (do (assert (e/secretLike? "Authorization: Bearer abc") "bearer header")
      (assert (e/secretLike? "key sk-ant-api03-abcdefghijklmnopqrstuvwx") "anthropic key shape")
      (assert (e/secretLike? "token ghp_1234") "github token")
      (assert (e/secretLike? "AKIAIOSFODNN7EXAMPLE") "aws key id, case-insensitive")
      (assert (e/secretLike? "xoxp-123-456") "slack user token (frame needle)")
      (assert (e/secretLike? "API_KEY=1") "api_key marker")
      (assert (e/secretLike? "KEY=abcdefghijklmnop1234") "KEY= with a 20 char value")
      (assert (not (e/secretLike? "KEY=1 key=short")) "KEY= with a short value is clean")
      (assert (e/secretLike? "token=abcdefghijklmnop1234") "token= with a long value")
      (assert (not (e/secretLike? "token=abc")) "token= with a short value is clean")
      (assert (e/secretLike? "-----BEGIN PRIVATE KEY-----") "private key block")
      (assert (e/secretLike? "see .asl/mem/work/x.asn") "mem path in text")
      (assert (e/memLike? "/w/.asl/mem/x") "memLike")
      (assert (not (e/secretLike? "assert failed: half the wall budget at requests.asl:76")) "plain gate error is clean")
      (assert (not (e/memLike? "asl/tools/coord/egress.asl")) "source path is not mem")
      (assert (not (e/secretLike? "risk-high task-3 desk-lamp task-sk-1")) "sk- inside ordinary words is not a secret")
      (assert (e/secretLike? "sk-kimi-0123456789012345678901234567890123456789") "kimi key, 40 chars")
      (assert (e/secretLike? "x sk-abcdefghijklmnopqrstuvwx y") "bare sk- key of 24 chars")
      (assert (not (e/secretLike? "sk-abcdefghijklmnopqrs")) "19 chars after sk- is under the shape")
      (assert (e/secretLike? "sk-or-v1-0123456789abcdef0123456789abcdef") "openrouter key shape")
      true)

fn testEnv -> Bool
  (do (assert (e/envLeak? (envVals) "x hunter2-prod-value y") "env value found in text")
      (assert (not (e/envLeak? (envVals) "x abc y")) "values under the minimum length are ignored")
      (assert (not (e/envLeak? (list) "hunter2-prod-value")) "no env values given, none found")
      (assert (e/leaksWith? (envVals) "hunter2-prod-value") "leaksWith sees env values")
      (assert (not (e/leaks? "hunter2-prod-value")) "leaks? alone does not know env values")
      (assert (e/leaksWith? (list) "password=1") "leaksWith includes the static needles")
      true)

fn testScrub -> Bool
  (let [(text "line one\n\nTOKEN=abcdefghijklmnop1234\nsee .asl/mem/x\nhas hunter2-prod-value here\nline five is long enough to clip")
        (out (e/scrubLines (envVals) text 10 12))]
    (do (assert (= out (list "line one" "line five is")) (str "seeded lines dropped, others clipped: " (stringJoin out "|")))
        (assert (= (listLength (e/scrubLines (list) "a\nb\nc\nd" 2 5)) 2) "line count bound")
        (assert (= (e/scrubText (envVals) "ok\nsecret=1\nfine" 5 10) "ok\nfine") "scrubText joins the survivors")
        (assert (= (e/clip "abcdef" 3) "abc") "clip cuts")
        (assert (= (e/clip "ab" 3) "ab") "clip leaves short text")
        true))

fn testPaths -> Bool
  (do (assert (e/allowedPath? "/w" "asl/tools/coord/a.asl") "plain relative source path")
      (assert (e/allowedPath? "/w" "/w/asl/a.asl") "absolute path under root")
      (assert (not (e/allowedPath? "/w" ".asl/mem/work/x.asn")) "mem path")
      (assert (not (e/allowedPath? "/w" "/w/.asl/mem/x")) "absolute mem path")
      (assert (not (e/allowedPath? "/w" "config/api.env")) "env file")
      (assert (not (e/allowedPath? "/w" "home/.ssh/id_rsa")) "ssh key")
      (assert (not (e/allowedPath? "/w" "certs/server.pem")) "pem file")
      (assert (not (e/allowedPath? "/w" "/etc/passwd")) "outside root")
      (assert (not (e/allowedPath? "/w" "a/../../x")) "dotdot")
      (assert (not (e/allowedPath? "/w" "")) "empty")
      (assert (e/secretPath? "keys/my.key") "key file")
      true)

fn ! runTests -> Bool
  (do (assert (testSecrets) "secrets")
      (assert (testEnv) "env values")
      (assert (testScrub) "scrub")
      (assert (testPaths) "paths")
      true)
