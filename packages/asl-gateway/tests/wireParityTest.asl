(module aslGateway/tests/wireParityTest
  :x [testAsnEscapeParity
      testIsBalancedAsnFormParity
      testAsnNumberParity
      testWantsAsnParity
      testChatReplyUsageParity
      testServedByParity
      testChatReplyAsnParity
      testUpstreamErrorReasonParity
      testSanitizeAsnContentParity
      testExtractOutermostSexprParity
      testFixtureCorpusVerification!
      runTests]
  :i [(wire :a wire)
      (asl-json/json :a j)])

fn parseJsonUnsafe s: String -> j/Json
  (resultOr (j/jsonParse s) (j/jnull))

fn testAsnEscapeParity -> Bool
  (do
    (assert (= (wire/asnEscape "plain text") "plain text") "esc_plain parity")
    (assert (= (wire/asnEscape "quotes: \"hello\" and 'world'") "quotes: \\\"hello\\\" and 'world'") "esc_quotes parity")
    (assert (= (wire/asnEscape "backslash: C:\\Windows\\System32") "backslash: C:\\\\Windows\\\\System32") "esc_backslash parity")
    (assert (= (wire/asnEscape "newlines\nand\ttabs\rand\rcarriage") "newlines\\nand\\ttabs\\rand\\rcarriage") "esc_newline_tab parity")
    (assert (= (wire/asnEscape "unicode: café ★ 日本語 ☃") "unicode: café ★ 日本語 ☃") "esc_unicode parity")
    (assert (= (wire/asnEscape "\"quote\" \\ \n \r \t ★") "\\\"quote\\\" \\\\ \\n \\r \\t ★") "esc_combo parity")
    (assert (= (wire/asn_escape "plain text") "plain text") "asn_escape alias parity")
    true)

fn testIsBalancedAsnFormParity -> Bool
  (do
    (assert (wire/isBalancedAsnForm? "(:test 1 2 3)") "bal_simple parity")
    (assert (wire/isBalancedAsnForm? "(:nested (:inner [1 2 3]))") "bal_nested parity")
    (assert (wire/isBalancedAsnForm? "(:string \"with (parens) inside\")") "bal_string_parens parity")
    (assert (wire/isBalancedAsnForm? "(:escaped \"with \\\" quotes\")") "bal_escaped_quote parity")
    (refute (wire/isBalancedAsnForm? "(:unbalanced (open 1 2)") "bal_unbalanced_open parity")
    (refute (wire/isBalancedAsnForm? "(:unbalanced 1 2))") "bal_unbalanced_close parity")
    (refute (wire/isBalancedAsnForm? "(:early 1) extra") "bal_early_close parity")
    (refute (wire/isBalancedAsnForm? "hello world") "bal_no_parens parity")
    (refute (wire/isBalancedAsnForm? "") "bal_empty parity")
    (refute (wire/isBalancedAsnForm? "   \n\t  ") "bal_spaces parity")
    (assert (wire/is_balanced_asn_form "(:test 1 2 3)") "is_balanced_asn_form alias parity")
    true)

fn testAsnNumberParity -> Bool
  (do
    (assert (= (wire/asnNumber (j/jint 42)) (some "42")) "num_int parity")
    (assert (= (wire/asnNumber (j/jint -999)) (some "-999")) "num_neg_int parity")
    (assert (= (wire/asnNumber (j/jfloat 3.1415)) (some "3.1415")) "num_float parity")
    (assert (= (wire/asnNumber (j/jnum 0.0)) (some "0.0")) "num_zero parity")
    (assert (none? (wire/asnNumber (j/jbool true))) "num_bool_true parity")
    (assert (none? (wire/asnNumber (j/jbool false))) "num_bool_false parity")
    (assert (none? (wire/asnNumber (j/jstr "42"))) "num_str parity")
    (assert (none? (wire/asnNumber (j/jnull))) "num_null parity")
    (assert (= (wire/asn_number (j/jint 42)) (some "42")) "asn_number alias parity")
    true)

fn testWantsAsnParity -> Bool
  (do
    (assert (wire/wantsAsn (list "Accept: application/asn+sexpr")) "wants_accept_asn parity")
    (assert (wire/wantsAsn (list "Accept: text/html, application/asn+sexpr; q=0.9")) "wants_accept_mixed parity")
    (assert (wire/wantsAsn (list "X-ASL-Wire: asn")) "wants_wire_asn parity")
    (assert (wire/wantsAsn (list "X-ASL-Wire: ASN")) "wants_wire_upper parity")
    (assert (wire/wantsAsn (list "X-ASL-Wire:   asn  ")) "wants_wire_padded parity")
    (refute (wire/wantsAsn (list "Accept: application/json")) "wants_accept_json parity")
    (refute (wire/wantsAsn (list "Accept: text/plain" "X-ASL-Wire: json")) "wants_unrelated parity")
    (refute (wire/wantsAsn (list)) "wants_empty parity")
    (assert (wire/wantsAsnPairs? (list (pair "Accept" "application/asn+sexpr"))) "wantsAsnPairs? parity")
    (assert (wire/wants_asn (list "X-ASL-Wire: asn")) "wants_asn alias parity")
    true)

fn testChatReplyUsageParity -> Bool
  (let [(u1 (parseJsonUnsafe "{\"usage\": {\"prompt_tokens\": 100, \"completion_tokens\": 50}}"))
        (u2 (parseJsonUnsafe "{\"usage\": {\"prompt_tokens\": 200, \"cached_tokens\": 40, \"completion_tokens\": 60}}"))
        (u3 (parseJsonUnsafe "{\"usage\": {\"prompt_tokens\": 300, \"completion_tokens\": 70, \"prompt_tokens_details\": {\"cached_tokens\": 80}}}"))
        (u4 (parseJsonUnsafe "{\"asl\": {\"usage\": {\"inputTokens\": 500, \"cachedTokens\": 100, \"outputTokens\": 250}}, \"usage\": {\"prompt_tokens\": 1, \"completion_tokens\": 2}}"))
        (u5 (parseJsonUnsafe "{\"asl\": {\"usage\": {\"inputTokens\": 600, \"outputTokens\": 300}}}"))
        (u6 (parseJsonUnsafe "{\"usage\": {\"completion_tokens\": 50}}"))
        (u7 (parseJsonUnsafe "{\"usage\": {\"prompt_tokens\": 50}}"))
        (u8 (parseJsonUnsafe "{\"usage\": \"not an object\"}"))
        (u9 (parseJsonUnsafe "{\"asl\": {\"usage\": \"invalid\"}, \"usage\": {\"prompt_tokens\": 50, \"completion_tokens\": 20}}"))
        (u10 (parseJsonUnsafe "{\"asl\": {\"usage\": 999}}"))]
    (do
      (assert (= (wire/chatReplyUsage u1) (some "(:input 100 :cached 0 :output 50)")) "usage_no_cache parity")
      (assert (= (wire/chatReplyUsage u2) (some "(:input 200 :cached 40 :output 60)")) "usage_with_cached parity")
      (assert (= (wire/chatReplyUsage u3) (some "(:input 300 :cached 80 :output 70)")) "usage_with_details parity")
      (assert (= (wire/chatReplyUsage u4) (some "(:input 500 :cached 100 :output 250)")) "usage_asl_precedence parity")
      (assert (= (wire/chatReplyUsage u5) (some "(:input 600 :cached 0 :output 300)")) "usage_asl_no_cache parity")
      (assert (none? (wire/chatReplyUsage u6)) "usage_missing_prompt parity")
      (assert (none? (wire/chatReplyUsage u7)) "usage_missing_completion parity")
      (assert (none? (wire/chatReplyUsage u8)) "usage_non_dict parity")
      (assert (= (wire/chatReplyUsage u9) (some "(:input 50 :cached 0 :output 20)")) "usage_not_dict parity")
      (assert (none? (wire/chatReplyUsage u10)) "usage_not_dict_no_standard parity")
      (assert (= (wire/chat_reply_usage u1) (some "(:input 100 :cached 0 :output 50)")) "chat_reply_usage alias parity")
      true))

fn testServedByParity -> Bool
  (let [(s1 (wire/servedBy (parseJsonUnsafe "{\"alias\": \"fast-model\"}") true "default" none none))
        (s2 (wire/servedBy (j/jstr "string-model") true "default" none none))
        (s3 (wire/servedBy (parseJsonUnsafe "{\"alias\": \"ignored\"}") false "v1-model" none none))
        (s4 (wire/servedBy (j/jstr "fast") true "fast" none (some "high")))
        (s5 (wire/servedBy (j/jstr "fast") true "fast" (some (parseJsonUnsafe "{\"temperature\": 0.7}")) none))
        (s6 (wire/servedBy (parseJsonUnsafe "{\"alias\": \"pro\"}") true "fallback" (some (parseJsonUnsafe "{\"temperature\": 0.0}")) (some "medium")))]
    (do
      (assert (= (j/jsonGet s1 "alias") (some (j/jstr "fast-model"))) "served_v2_dict alias")
      (assert (= (j/jsonGet s2 "alias") (some (j/jstr "string-model"))) "served_v2_string alias")
      (assert (= (j/jsonGet s3 "alias") (some (j/jstr "v1-model"))) "served_v1_fallback alias")
      (assert (= (j/jsonGet s4 "alias") (some (j/jstr "fast"))) "served_effort alias")
      (assert (= (j/jsonGet s4 "effort") (some (j/jstr "high"))) "served_effort value")
      (assert (= (j/jsonGet s5 "alias") (some (j/jstr "fast"))) "served_temperature alias")
      (assert (= (j/jsonGet s5 "temperature") (some (j/jfloat 0.7))) "served_temperature value")
      (assert (= (j/jsonGet s6 "alias") (some (j/jstr "pro"))) "served_full alias")
      (assert (= (j/jsonGet s6 "effort") (some (j/jstr "medium"))) "served_full effort")
      (assert (= (j/jsonGet s6 "temperature") (some (j/jfloat 0.0))) "served_full temperature")
      (let [(s1Alias (wire/served_by (parseJsonUnsafe "{\"alias\": \"fast-model\"}") true "default" none none))]
        (assert (= (j/jsonGet s1Alias "alias") (some (j/jstr "fast-model"))) "served_by alias parity"))
      true))

fn testChatReplyAsnParity -> Bool
  (let [(r1 (parseJsonUnsafe "{\"model\": \"gpt-4o\", \"choices\": [{\"message\": {\"content\": \"(:solution :code 42)\"}, \"finish_reason\": \"stop\"}]}"))
        (r2 (parseJsonUnsafe "{\"model\": \"claude-3-haiku\", \"choices\": [{\"message\": {\"content\": \"Hello! How can I help you?\"}, \"finish_reason\": \"stop\"}]}"))
        (r3 (parseJsonUnsafe "{\"model\": \"test-model\", \"choices\": [{\"message\": {\"content\": \"Path: C:\\\\test\\n\\\"quoted\\\" ★\"}, \"finish_reason\": \"stop\"}], \"usage\": {\"prompt_tokens\": 12, \"completion_tokens\": 34}}"))
        (r4 (parseJsonUnsafe "{\"model\": \"deepseek-r1\", \"choices\": [{\"message\": {\"content\": \"(:thought 1)\"}, \"finish_reason\": \"stop\"}], \"asl\": {\"alias\": \"r1\", \"effort\": \"high\", \"temperature\": 0.6, \"pool\": \"cluster-a\", \"queueWaitSec\": 0.12, \"execSec\": 4.56}}"))
        (r5 (parseJsonUnsafe "{\"model\": \"gemini-2\", \"choices\": [{\"message\": {\"content\": null}}], \"usage\": {\"prompt_tokens\": 10, \"completion_tokens\": 0}}"))
        (r6 (parseJsonUnsafe "{\"model\": \"empty-model\", \"choices\": []}"))
        (rObj (parseJsonUnsafe "{\"choices\": [{\"message\": {\"content\": {\"role\": \"assistant\", \"code\": 100}}}]}"))
        (rArr (parseJsonUnsafe "{\"choices\": [{\"message\": {\"content\": [\"item1\", 42, false]}}]}"))
        (rNest (parseJsonUnsafe "{\"choices\": [{\"message\": {\"content\": {\"data\": {\"items\": [1, 2], \"valid\": true}}}}]}"))
        (rNonAscii (parseJsonUnsafe "{\"choices\": [{\"message\": {\"content\": {\"greeting\": \"café\", \"chinese\": \"中文\"}}}]}"))
        (rUsageNotDict (parseJsonUnsafe "{\"choices\": [{\"message\": {\"content\": \"ok\"}}], \"asl\": {\"usage\": \"invalid\"}, \"usage\": {\"prompt_tokens\": 50, \"completion_tokens\": 20}}"))
        (rPool (parseJsonUnsafe "{\"choices\": [{\"message\": {\"content\": \"ok\"}}], \"asl\": {\"pool\": 101}}"))]
    (do
      (assert (= (wire/chatReplyAsn r1) "(:reply :model \"gpt-4o\" :content (:solution :code 42) :finish \"stop\")\n") "reply_balanced parity")
      (assert (= (wire/chatReplyAsn r2) "(:reply :model \"claude-3-haiku\" :content \"Hello! How can I help you?\" :finish \"stop\")\n") "reply_raw_text parity")
      (assert (= (wire/chatReplyAsn r3) "(:reply :model \"test-model\" :content \"Path: C:\\\\test\\n\\\"quoted\\\" ★\" :finish \"stop\" :usage (:input 12 :cached 0 :output 34))\n") "reply_escapes_unicode parity")
      (assert (= (wire/chatReplyAsn r4) "(:reply :model \"deepseek-r1\" :content (:thought 1) :alias \"r1\" :effort \"high\" :temperature 0.6 :finish \"stop\" :asl (:pool \"cluster-a\" :queueWaitSec 0.12 :execSec 4.56))\n") "reply_asl_metadata parity")
      (assert (= (wire/chatReplyAsn r5) "(:reply :model \"gemini-2\" :content \"\" :finish \"stop\" :usage (:input 10 :cached 0 :output 0))\n") "reply_none_content parity")
      (assert (= (wire/chatReplyAsn r6) "(:reply :model \"empty-model\" :content \"\" :finish \"stop\")\n") "reply_empty_choices parity")
      (assert (= (wire/chatReplyAsn rObj) "(:reply :model \"\" :content \"{\\\"role\\\": \\\"assistant\\\", \\\"code\\\": 100}\" :finish \"stop\")\n") "reply_content_object parity")
      (assert (= (wire/chatReplyAsn rArr) "(:reply :model \"\" :content \"[\\\"item1\\\", 42, false]\" :finish \"stop\")\n") "reply_content_array parity")
      (assert (= (wire/chatReplyAsn rNest) "(:reply :model \"\" :content \"{\\\"data\\\": {\\\"items\\\": [1, 2], \\\"valid\\\": true}}\" :finish \"stop\")\n") "reply_content_nested parity")
      (assert (= (wire/chatReplyAsn rNonAscii) "(:reply :model \"\" :content \"{\\\"greeting\\\": \\\"caf\\\\u00e9\\\", \\\"chinese\\\": \\\"\\\\u4e2d\\\\u6587\\\"}\" :finish \"stop\")\n") "reply_content_non_ascii parity")
      (assert (= (wire/chatReplyAsn rUsageNotDict) "(:reply :model \"\" :content \"ok\" :finish \"stop\" :usage (:input 50 :cached 0 :output 20))\n") "reply_usage_not_dict parity")
      (assert (= (wire/chatReplyAsn rPool) "(:reply :model \"\" :content \"ok\" :finish \"stop\" :asl (:pool \"101\"))\n") "reply_pool_non_string parity")
      (assert (= (wire/chat_reply_asn r1) "(:reply :model \"gpt-4o\" :content (:solution :code 42) :finish \"stop\")\n") "chat_reply_asn alias parity")
      true))

fn testUpstreamErrorReasonParity -> Bool
  (let [(longInput (stringRepeat "A" 600))
        (longExpected (stringConcat "Error log: " (stringRepeat "A" 489)))]
    (do
      (assert (= (wire/upstreamErrorReason "{\"error\": {\"message\": \"Context window exceeded\", \"type\": \"invalid_request\"}}" "Unknown error")
                 "Context window exceeded") "err_json_message parity")
      (assert (= (wire/upstreamErrorReason "{\"error\": \"Invalid API key provided\"}" "Unknown error")
                 "Invalid API key provided") "err_json_string parity")
      (assert (= (wire/upstreamErrorReason "{\"error\": {\"code\": 503, \"status\": \"unavailable\"}}" "Unknown error")
                 "{\"error\": {\"code\": 503, \"status\": \"unavailable\"}}") "err_json_no_message parity")
      (assert (= (wire/upstreamErrorReason "<html><head><title>504 Gateway Timeout</title></head><body><h1>504 Gateway Timeout</h1></body></html>" "Unknown error")
                 "<html><head><title>504 Gateway Timeout</title></head><body><h1>504 Gateway Timeout</h1></body></html>") "err_html_body parity")
      (assert (= (wire/upstreamErrorReason "" "Network connection failed")
                 "Network connection failed") "err_empty_fallback parity")
      (assert (= (wire/upstreamErrorReason (str "Error log: " longInput) "fallback")
                 longExpected) "err_long_body_500 parity")
      (assert (= (wire/upstream_error_reason "{\"error\": \"Unauthorized\"}" "fallback") "Unauthorized") "upstream_error_reason alias parity")
      true))

fn testSanitizeAsnContentParity -> Bool
  (let [(longInput (stringRepeat "X" 250))
        (longExpected (str "(:error :reason \"unbalanced_non_asn\" :raw \"Notice: " (stringRepeat "X" 189) "...\")"))]
    (do
      (assert (= (wire/sanitizeAsnContent "(:status :ok :items [1 2 3])") "(:status :ok :items [1 2 3])") "san_clean_sexp parity")
      (assert (= (wire/sanitizeAsnContent "```asn\n(:response :val 100)\n```") "(:response :val 100)") "san_fence_asn parity")
      (assert (= (wire/sanitizeAsnContent "Here is the response:\n```lisp\n(:agent-plan :step 1)\n```\nLet me know!") "(:agent-plan :step 1)") "san_fence_lisp parity")
      (assert (= (wire/sanitizeAsnContent "```\n(:cmd :name \"build\")\n```") "(:cmd :name \"build\")") "san_fence_no_lang parity")
      (assert (= (wire/sanitizeAsnContent "I cannot complete this task.") "(:error :reason \"unbalanced_non_asn\" :raw \"I cannot complete this task.\")") "san_conversational parity")
      (assert (= (wire/sanitizeAsnContent "Error: \"failed\"\nNext line") "(:error :reason \"unbalanced_non_asn\" :raw \"Error: \\\"failed\\\" Next line\")") "san_quotes_newline parity")
      (assert (= (wire/sanitizeAsnContent (str "Notice: " longInput)) longExpected) "san_long_non_asn parity")
      (assert (= (wire/sanitize_asn_content "(:status :ok)") "(:status :ok)") "sanitize_asn_content alias parity")
      true))

fn testExtractOutermostSexprParity -> Bool
  (do
    (assert (= (wire/extractOutermostSexpr "Research summary follows:\n(:researchReport :topic \"quantum\" :confidence \"high\")\nEnd of report.")
               (some "(:researchReport :topic \"quantum\" :confidence \"high\")")) "ext_research_report parity")
    (assert (= (wire/extractOutermostSexpr "```\n(:searchResults [(:url \"https://asl.dev\" :title \"ASL\")])\n```")
               (some "(:searchResults [(:url \"https://asl.dev\" :title \"ASL\")])")) "ext_search_results parity")
    (assert (= (wire/extractOutermostSexpr "Computed: (:result 42)")
               (some "(:result 42)")) "ext_generic_asn parity")
    (assert (= (wire/extractOutermostSexpr "(:msg \"brackets [here] and (parens)\")")
               (some "(:msg \"brackets [here] and (parens)\")")) "ext_nested_brackets parity")
    (assert (none? (wire/extractOutermostSexpr "(:bad [1 2 3))")) "ext_unbalanced parity")
    (assert (none? (wire/extractOutermostSexpr "Plain prose with no sexprs at all.")) "ext_none parity")
    (assert (= (wire/extract_outermost_sexpr "Computed: (:ok)") (some "(:ok)")) "extract_outermost_sexpr alias parity")
    true)

fn testFixtureCorpusVerification! -> Bool
  (let [(readRes (fileReadString "asl/packages/asl-gateway/tests/wireParityFixtures.asn"))]
    (do
      (assert (ok? readRes) "wireParityFixtures.asn must exist and be readable")
      (let [(content (resultOr readRes ""))
            (lines (filter (fn [(l String)] -> Bool (stringStartsWith? l "(:case ")) (stringSplit content "\n")))
            (n (listLength lines))]
        (assert (>= n 30) "Corpus must have at least 30 fixtures")
        (assert (= n 79) "Corpus holds exactly 79 recorded fixtures from Python")
        true)))

fn ! runTests -> Bool
  (and (testAsnEscapeParity)
  (and (testIsBalancedAsnFormParity)
  (and (testAsnNumberParity)
  (and (testWantsAsnParity)
  (and (testChatReplyUsageParity)
  (and (testServedByParity)
  (and (testChatReplyAsnParity)
  (and (testUpstreamErrorReasonParity)
  (and (testSanitizeAsnContentParity)
  (and (testExtractOutermostSexprParity)
       (testFixtureCorpusVerification!)))))))))))
