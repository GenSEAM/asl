(module asl-lint/rules :x [OrthogonalityVerdict checkRationalOrthogonality isOrthogonal?])

(schema OrthogonalityVerdict (:f symbolName Str) (:f occurrenceCount I64) (:f hasCanonicalExport Bool) (:f isDivergentDomain Bool) (:f isViolation Bool))

fn isOrthogonal? verdict: OrthogonalityVerdict -> Bool
  (not verdict.isViolation)

fn checkRationalOrthogonality symbolName: Str occurrences: I64 hasCanonical: Bool isDivergent: Bool -> OrthogonalityVerdict
  (let [(violation (if (>= occurrences 2) (if hasCanonical true (if isDivergent false true)) false))] (OrthogonalityVerdict :symbolName symbolName :occurrenceCount occurrences :hasCanonicalExport hasCanonical :isDivergentDomain isDivergent :isViolation violation))
