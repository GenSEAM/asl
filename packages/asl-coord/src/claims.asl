(module asl-coord/claims
  :x [Lease leaseContent parseLease parseOwns pathsOverlap? pathWithin? claims! claim! release! pathAllowed!]
  :i [(asl-store/types :a ty) (asl-coord/lease :a ls) (asl-coord/paths :a pa) (asl-coord/core :a co) (asl-coord/locate :a loc)])

; (:m :ref VS-COORD :do "the public API of the old file leases, unchanged: claims are now rows of the machine's vault keyed by repository scope and the rules live in asl-coord/core over a Ctx; this module only turns a workspace into a Ctx through asl-coord/locate and an unavailable vault on a read into the same answers as no claims")
(schema Lease (:f unit String) (:f owns (List String)) (:f branch String) (:f worktree String)
  (:f agent String) (:f host String) (:f pid Int64) (:f at Int64) (:f ttl Int64))

fn leaseContent lease: Lease -> String
  (ls/leaseContent (ls/Lease :unit lease.unit :owns lease.owns :branch lease.branch :worktree lease.worktree :agent lease.agent :host lease.host :pid lease.pid :at lease.at :ttl lease.ttl))

fn parseLease raw: String -> Lease
  (let [(l (ls/parseLease raw))]
    (Lease :unit l.unit :owns l.owns :branch l.branch :worktree l.worktree :agent l.agent :host l.host :pid l.pid :at l.at :ttl l.ttl))

fn parseOwns raw: String -> (List String)
  (ls/parseOwns raw)

; (:m :ref OWNS-SYMBOL-CLAIMS :do "an :owns entry may be path#symbol (asl-tools/coord/store decides same-file clashes by symbol); a path check here is by file, so the symbol part is cut before the compare and a writer owning f.asl#sym may edit f.asl while f.asl and f.asl#B overlap")
fn pathsOverlap? left: String right: String -> Bool
  (pa/pathsOverlap? left right)

fn pathWithin? path: String root: String -> Bool
  (pa/pathWithin? path root)

fn validUnit? unit: String -> Bool
  (and (ty/nameOk? unit) (not (stringContains? unit "..")))

fn validOwnsPath? path: String -> Bool
  (and (not (stringEmpty? path))
       (not (stringStartsWith? path "/"))
       (!= path "..")
       (not (stringStartsWith? path "../"))
       (not (stringContains? path "/../"))
       (not (stringEndsWith? path "/..")))

fn claim! workspace: String unit: String owns: (List String) -> (Result String String)
  (if (or (not (validUnit? unit)) (not (listAll? validOwnsPath? owns)))
    (err (co/receipt unit "" ""))
    (match (loc/context! workspace true)
      ((err e) (err e))
      ((ok found)
        (match found
          ((some ctx) (co/claimLease ctx (loc/identity! workspace unit owns)))
          ((none) (err "claims vault unavailable"))))))

fn claims! workspace: String -> (Result String String)
  (match (loc/context! workspace false)
    ((err e) (err e))
    ((ok found)
      (match found
        ((none) (ok "(:claims)"))
        ((some ctx)
          (match (co/sweepAll ctx)
            ((err e) (err e))
            ((ok held)
              (ok (str "(:claims" (if (listEmpty? held) "" (str " " (stringJoin (map (fn [(h co/Held)] -> String (ls/leaseContent h.lease)) held) " "))) ")"))))))))

fn release! workspace: String unit: String -> (Result String String)
  (if (not (validUnit? unit))
    (err (co/receipt unit "" ""))
    (match (loc/context! workspace false)
      ((err e) (err e))
      ((ok found)
        (match found
          ((none) (ok (str "(:released :unit " (ls/q unit) " :absent true)")))
          ((some ctx)
            (co/releaseLease ctx unit (loc/callerUnit! workspace "") (loc/identity! workspace unit (list))))))))

fn pathAllowed! workspace: String unit: String rel: String -> (Result String String)
  (let [(caller (loc/callerUnit! workspace unit))]
    (match (loc/context! workspace false)
      ((err e) (if (stringContains? e "cannot resolve git common directory") (ok "") (err e)))
      ((ok found)
        (match found
          ((none) (ok ""))
          ((some ctx) (co/pathAllowedIn ctx caller rel))))))
