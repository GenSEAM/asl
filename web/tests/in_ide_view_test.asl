(module asl-web/in-ide-view-test
  :d "Unit and verification test suite for in-browser AI IDE and Vibe Coder workspace view."
  :x [TestInIdeViewMarkup
      TestInIdeHiddenDrawerDefault
      TestInIdeProviderAndGithubModals
      run-tests]
  :i [(asl-web/in-ide-view :a ide)])

(df TestInIdeViewMarkup [] -> Bool
  :d "Verifies presence of core vibe coder UI elements in in-ide view markup"
  (let [(html (ide/render-in-ide-view))]
    (assert (string-contains? html "in-ide-root") "Markup must contain in-ide-root")
    (assert (string-contains? html "Vibe Coder") "Markup must identify Vibe Coder mode")
    (assert (string-contains? html "ide-model-select") "Markup must include model selector")
    (assert (string-contains? html "ide-game-canvas") "Markup must render live viewport canvas")
    (assert (string-contains? html "ide-chat-container") "Markup must contain chat container")
    (refute (string-contains? html "undefined") "Markup must not contain undefined literals")
    true))

(df TestInIdeHiddenDrawerDefault [] -> Bool
  :d "Verifies code editor drawer is hidden by default in vibe coder layout"
  (let [(html (ide/render-in-ide-view))]
    (assert (string-contains? html "id=\"ide-code-drawer\" class=\"hidden") "Code drawer must be hidden by default")
    (assert (string-contains? html "Code Editor (Hidden)") "Toggle button text must indicate hidden state")
    (refute (string-contains? html "id=\"ide-code-drawer\" class=\"block") "Code drawer must not be open by default")
    true))

(df TestInIdeProviderAndGithubModals [] -> Bool
  :d "Verifies inclusion of OpenAI-compatible provider and GitHub modals"
  (let [(html (ide/render-in-ide-view))]
    (assert (string-contains? html "ide-provider-modal") "Must include provider configuration modal")
    (assert (string-contains? html "ide-github-modal") "Must include GitHub binding modal")
    (assert (string-contains? html "ide-export-modal") "Must include archive export modal")
    (refute (string-contains? html "unauthorized-eval") "Must not contain unauthorized eval")
    true))

(df run-tests [] -> Bool
  :d "Executes all in-ide view verification tests"
  (and (TestInIdeViewMarkup)
       (and (TestInIdeHiddenDrawerDefault)
            (TestInIdeProviderAndGithubModals))))
