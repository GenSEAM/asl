(module asl-lint/rules
  :d "AgentScript native heuristic and architectural orthogonality rules enforcing the Principle of Boundary Universalism & Local Autonomy (d-0034, c-0003)."
  :x [OrthogonalityVerdict check-rational-orthogonality is-orthogonal?])

(dfs OrthogonalityVerdict
  (:f symbol-name Str "Identifier of the analyzed function or type")
  (:f occurrence-count I64 "Number of packages implementing identical identifier")
  (:f has-canonical-export Bool "True if a canonical shared package exports this symbol")
  (:f is-divergent-domain Bool "True if domains are genuinely divergent with distinct typestates")
  (:f is-violation Bool "True if this represents an unjustified ad-hoc duplication violating c-0003"))

(df is-orthogonal? [(verdict OrthogonalityVerdict)] -> Bool
  :d "Returns true if the symbol usage satisfies Boundary Universalism and orthogonality."
  (not (.-is-violation verdict)))

(df check-rational-orthogonality [(symbol-name Str) (occurrences I64) (has-canonical Bool) (is-divergent Bool)] -> OrthogonalityVerdict
  :d "Evaluates an identifier implementation against the Principle of Boundary Universalism & Local Autonomy (d-0034, c-0003). Flags unjustified duplication when 2+ packages define identical symbols without canonical export or distinct domain typestates."
  (let [(violation (if (>= occurrences 2)
                     (if has-canonical
                       true
                       (if is-divergent
                         false
                         true))
                     false))]
    (OrthogonalityVerdict
      :symbol-name symbol-name
      :occurrence-count occurrences
      :has-canonical-export has-canonical
      :is-divergent-domain is-divergent
      :is-violation violation)))
