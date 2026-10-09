(module aslAgent/omniIntent
  :x [OmniDomain OmniIntent
      domainCodeTask domainResearch domainBrowserAction domainIdeaCapture domainCrossProjectSync domainSystemControl
      classifyOmniIntent formatOmniIntentAsn isCodeTask? isResearch? isBrowserAction? domainToString]
  :i [])

(enum OmniDomain
  (:c domainCodeTask [] "Code edits, test suites, gate executions, refactors -> Worker Jail (:owns + Red-Green Gate)")
  (:c domainResearch [] "Codebase search, symbol lookups, web docs, API exploration -> In-Process Cognitive Fiber")
  (:c domainBrowserAction [] "Headless browser automation, forms, web navigation -> asl-gateway (/api/asl/browser/exec)")
  (:c domainIdeaCapture [] "Unstructured developer thoughts, notes, discoveries -> mem/notes.asl")
  (:c domainCrossProjectSync [] "Schema, contract, or AST synchronization (asex <-> stonefish) -> sync.asl")
  (:c domainSystemControl [] "Daemon lifecycle, worker pool inspect, cache flush -> Daemon Control Loop"))

(schema OmniIntent
  (:f intentId Str)
  (:f domain OmniDomain)
  (:f rawDirective Str)
  (:f targetSubstrate Str)
  (:f requiresGate Bool)
  (:f requiresWorktree Bool)
  (:f declaredOwns (List Str)))

fn isCodeDirective? text: Str -> Bool
  (or (stringContains? text "refactor")
    (or (stringContains? text "compiler")
      (or (stringContains? text "edit")
        (or (stringContains? text "modify")
          (or (stringContains? text "fix")
            (or (stringContains? text "implement")
              (or (stringContains? text "gate")
                (or (stringContains? text "поправь")
                  (or (stringContains? text "исправь")
                    (or (stringContains? text "сделай")
                      (stringContains? text "напиши")))))))))))

fn isBrowserDirective? text: Str -> Bool
  (or (stringContains? text "browser")
    (or (stringContains? text "github.com")
      (or (stringContains? text "http://")
        (or (stringContains? text "https://")
          (or (stringContains? text "cart")
            (or (stringContains? text "salad")
              (or (stringContains? text "click")
                (or (stringContains? text "открой браузер")
                  (or (stringContains? text "вкладку")
                    (or (stringContains? text "корзину")
                      (or (stringContains? text "салат")
                        (stringContains? text "продуктов"))))))))))))

fn isIdeaDirective? text: Str -> Bool
  (or (stringContains? text "note:")
    (or (stringContains? text "idea:")
      (or (stringContains? text "remember")
        (or (stringContains? text "запиши идею")
          (or (stringContains? text "заметка")
            (stringContains? text "идея"))))))

fn isSyncDirective? text: Str -> Bool
  (or (stringContains? text "sync")
    (or (stringContains? text "stonefish")
      (or (stringContains? text "cross-project")
        (or (stringContains? text "синхронизировать")
          (stringContains? text "между проектами")))))

fn isSystemDirective? text: Str -> Bool
  (or (stringContains? text "asl daemon")
    (or (stringContains? text "daemon status")
      (or (stringContains? text "worker count")
        (or (stringContains? text "mesh status")
          (stringContains? text "статус демона")))))

fn isResearchDirective? text: Str -> Bool
  (or (stringContains? text "find")
    (or (stringContains? text "search")
      (or (stringContains? text "where")
        (or (stringContains? text "lookup")
          (or (stringContains? text "explore")
            (or (stringContains? text "проведи ресерч")
              (or (stringContains? text "найди")
                (stringContains? text "как работает"))))))))

fn classifyOmniIntent raw: Str -> OmniIntent
  (let [(lower (stringLower raw))
        (id (str "intent-" (stringFromInt64 (stringLength raw))))]
    (cond
      ((isSystemDirective? lower)
       (OmniIntent :intentId id :domain (domainSystemControl) :rawDirective raw :targetSubstrate "daemon-loop" :requiresGate false :requiresWorktree false :declaredOwns (list)))
      ((isSyncDirective? lower)
       (OmniIntent :intentId id :domain (domainCrossProjectSync) :rawDirective raw :targetSubstrate "sync-nexus" :requiresGate false :requiresWorktree false :declaredOwns (list)))
      ((isIdeaDirective? lower)
       (OmniIntent :intentId id :domain (domainIdeaCapture) :rawDirective raw :targetSubstrate "notes-ledger" :requiresGate false :requiresWorktree false :declaredOwns (list)))
      ((isBrowserDirective? lower)
       (OmniIntent :intentId id :domain (domainBrowserAction) :rawDirective raw :targetSubstrate "gateway-browser" :requiresGate false :requiresWorktree false :declaredOwns (list)))
      ((isResearchDirective? lower)
       (OmniIntent :intentId id :domain (domainResearch) :rawDirective raw :targetSubstrate "cognitive-fiber" :requiresGate false :requiresWorktree false :declaredOwns (list)))
      ((isCodeDirective? lower)
       (OmniIntent :intentId id :domain (domainCodeTask) :rawDirective raw :targetSubstrate "worker-jail" :requiresGate true :requiresWorktree true :declaredOwns (list "src/")))
      (else
       (OmniIntent :intentId id :domain (domainResearch) :rawDirective raw :targetSubstrate "cognitive-fiber" :requiresGate false :requiresWorktree false :declaredOwns (list)))))

fn isCodeTask? intent: OmniIntent -> Bool
  (mt intent.domain
    ((domainCodeTask) true)
    (_ false))

fn isResearch? intent: OmniIntent -> Bool
  (mt intent.domain
    ((domainResearch) true)
    (_ false))

fn isBrowserAction? intent: OmniIntent -> Bool
  (mt intent.domain
    ((domainBrowserAction) true)
    (_ false))

fn formatOmniIntentAsn intent: OmniIntent -> Str
  (let [(dStr (mt intent.domain
                ((domainCodeTask) ":codeTask")
                ((domainResearch) ":research")
                ((domainBrowserAction) ":browserAction")
                ((domainIdeaCapture) ":ideaCapture")
                ((domainCrossProjectSync) ":crossProjectSync")
                ((domainSystemControl) ":systemControl")))]
    (str "(:omni-intent :id \"" intent.intentId "\""
         " :domain " dStr
         " :target \"" intent.targetSubstrate "\""
         " :requires-gate " (if intent.requiresGate "true" "false")
         " :requires-worktree " (if intent.requiresWorktree "true" "false") ")"))

fn domainToString domain: OmniDomain -> Str
  (mt domain
    ((domainCodeTask) ":codeTask")
    ((domainResearch) ":research")
    ((domainBrowserAction) ":browserAction")
    ((domainIdeaCapture) ":ideaCapture")
    ((domainCrossProjectSync) ":crossProjectSync")
    ((domainSystemControl) ":systemControl"))
