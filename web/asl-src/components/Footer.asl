(module asl-web/footer
  :d "Declarative footer component in pure AgentScript."
  :x [footer-view]
  :i [])

(df footer-view [] -> Str
  :d "Renders global application footer with license and community links."
  "(footer (:class \"border-t border-line bg-surface/40 py-12 px-6 text-center text-sm text-ink-muted\")
    (p (:class \"mb-2\") \"AgentScript (ASL) — Native Agent-Centric Language & observably sandboxed toolchain.\")
    (p (:class \"text-xs text-ink-muted/80\") \"MIT OR Apache-2.0 License. 100% Self-Hosted & Zero Foreign Dependencies.\"))")
