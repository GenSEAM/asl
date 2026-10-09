(module aslWeb/inIdeViewTest :x [TestInIdeViewMarkup TestInIdeHiddenDrawerDefault TestInIdeProviderAndGithubModals runTests] :i [(aslWeb/inIdeView :a ide)])

fn TestInIdeViewMarkup -> Bool
  (let [(html (ide/renderInIdeView))] (assert (stringContains? html "in-ide-root") "Markup must contain in-ide-root") (assert (stringContains? html "Vibe Coder") "Markup must identify Vibe Coder mode") (assert (stringContains? html "ide-model-select") "Markup must include model selector") (assert (stringContains? html "ide-game-canvas") "Markup must render live viewport canvas") (assert (stringContains? html "ide-chat-container") "Markup must contain chat container") (refute (stringContains? html "undefined") "Markup must not contain undefined literals") true)

fn TestInIdeHiddenDrawerDefault -> Bool
  (let [(html (ide/renderInIdeView))] (assert (stringContains? html "id=\"ide-code-drawer\" class=\"hidden") "Code drawer must be hidden by default") (assert (stringContains? html "Code Editor (Hidden)") "Toggle button text must indicate hidden state") (refute (stringContains? html "id=\"ide-code-drawer\" class=\"block") "Code drawer must not be open by default") true)

fn TestInIdeProviderAndGithubModals -> Bool
  (let [(html (ide/renderInIdeView))] (assert (stringContains? html "ide-provider-modal") "Must include provider configuration modal") (assert (stringContains? html "ide-github-modal") "Must include GitHub binding modal") (assert (stringContains? html "ide-export-modal") "Must include archive export modal") (refute (stringContains? html "unauthorized-eval") "Must not contain unauthorized eval") true)

fn runTests -> Bool
  (and (TestInIdeViewMarkup) (and (TestInIdeHiddenDrawerDefault) (TestInIdeProviderAndGithubModals)))
