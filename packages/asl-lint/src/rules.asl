(module asl-lint/rules
  :d "AgentScript native heuristic and architectural orthogonality rules enforcing the Principle of Boundary Universalism & Local Autonomy (D0034, C0003)."
  :x [OrthogonalityVerdict checkRationalOrthogonality isOrthogonal?])

(dfs OrthogonalityVerdict
  (:f symbolName Str "Identifier of the analyzed function or type")
  (:f occurrenceCount I64 "Number of packages implementing identical identifier")
  (:f hasCanonicalExport Bool "True if a canonical shared package exports this symbol")
  (:f isDivergentDomain Bool "True if domains are genuinely divergent with distinct typestates")
  (:f isViolation Bool "True if this represents an unjustified ad-hoc duplication violating C0003"))

(df isOrthogonal? [(verdict OrthogonalityVerdict)] -> Bool
  :d "Returns true if the symbol usage satisfies Boundary Universalism and orthogonality."
  (not (.-isViolation verdict)))

(df checkRationalOrthogonality [(symbolName Str) (occurrences I64) (hasCanonical Bool) (isDivergent Bool)] -> OrthogonalityVerdict
  :d "Evaluates an identifier implementation against the Principle of Boundary Universalism & Local Autonomy (D0034, C0003). Flags unjustified duplication when 2+ packages define identical symbols without canonical export or distinct domain typestates."
  (let [(violation (if (>= occurrences 2)
                     (if hasCanonical
                       true
                       (if isDivergent
                         false
                         true))
                     false))]
    (OrthogonalityVerdict
      :symbolName symbolName
      :occurrenceCount occurrences
      :hasCanonicalExport hasCanonical
      :isDivergentDomain isDivergent
      :isViolation violation)))
