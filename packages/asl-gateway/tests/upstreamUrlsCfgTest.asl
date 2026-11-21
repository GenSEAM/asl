(module asl-gateway/tests/upstreamUrlsCfgTest
  :x [runTests]
  :i [(upstream :a u)])

; (:m :ref GW-UPSTREAM-URLS-CFG :do "config provider bases override every built-in URL (gemini included), env URL vars are only the fallback below config, and empty bases reproduce the old upstreamSettings result exactly")

fn settingsOf r: (Result u/UpstreamSettings String) -> (Option u/UpstreamSettings)
  (match r
    ((ok st) (some st))
    ((err _) none))

fn fieldOf r: (Result u/UpstreamSettings String) which: String -> String
  (match (settingsOf r)
    ((none) (str "ERR " which))
    ((some st)
     (if (= which "geminiUrl") st.geminiUrl
       (if (= which "groqUrl") st.groqUrl
         (if (= which "ollamaUrl") st.ollamaUrl
           (if (= which "url") st.url
             (if (= which "key") st.key st.geminiKey)))))))

fn runTests -> Bool
  (let [(env (mapFromPairs
               (list (pair "GROQ_BASE_URL" "https://env.example/openai/v1")
                     (pair "OLLAMA_BASE_URL" "https://env-ollama.example")
                     (pair "OPENROUTER_API_KEY" "k-or")
                     (pair "GEMINI_API_KEY" "k-gem"))))
        (bases (mapFromPairs
                 (list (pair "gemini" "https://gemini.example/v1beta/openai")
                       (pair "groq" "https://cfg.example/openai/v1") (pair "ollama" "https://cfg-ollama.example/v1") (pair "openrouter" "https://cfg-or.example/api/v1"))))
        (cfg (u/upstreamSettingsFrom env bases))
        (plain (u/upstreamSettings env))
        (empty (u/upstreamSettingsFrom env (mapEmpty)))]
    (do (assert (= (fieldOf cfg "geminiUrl") "https://gemini.example/v1beta/openai")
                "a gemini base from bases wins over the built-in URL")
        (assert (= (fieldOf cfg "groqUrl") "https://cfg.example/openai/v1")
                "config beats env for groq") (assert (= (fieldOf cfg "ollamaUrl") "https://cfg-ollama.example/v1") "a config ollama base wins over the env URL var") (assert (= (fieldOf cfg "url") "https://cfg-or.example/api/v1") "a config openrouter base wins over the env URL var")
        (assert (= (fieldOf empty "geminiUrl") (fieldOf plain "geminiUrl"))
                "empty bases keep the built-in gemini URL")
        (assert (= (fieldOf empty "groqUrl") (fieldOf plain "groqUrl"))
                "empty bases keep the env groq URL")
        (assert (= (fieldOf empty "ollamaUrl") (fieldOf plain "ollamaUrl"))
                "empty bases keep the env ollama URL")
        (assert (= (fieldOf empty "url") (fieldOf plain "url"))
                "empty bases keep the openrouter URL")
        (assert (= (fieldOf empty "key") (fieldOf plain "key"))
                "empty bases keep the key")
        (assert (= (fieldOf empty "geminiKey") (fieldOf plain "geminiKey"))
                "empty bases keep the gemini key")
        (assert (= (fieldOf (u/upstreamSettingsFrom (mapEmpty) (mapEmpty)) "geminiUrl")
                   "https://generativelanguage.googleapis.com/v1beta/openai")
                "with no env and no bases the built-in gemini URL is the default")
        true))
