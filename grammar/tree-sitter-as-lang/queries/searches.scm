; Structural search examples (axis 2). Run with:
;   tree-sitter query queries/searches.scm <file.as>
;
; These are the queries a compiler, linter, or refactoring tool would use, and
; they are why the tooling grammar carries field names: without them a query can
; match a node but cannot address its parts.
;
; The last four address §9 rules 12 and 13 — the ones a checker will have to
; enforce and which no grammar can. A query that can locate every site is the
; cheap half of that work.

; Fallible functions: every defun whose declared return type is a Result.
(defun
  name: (ident) @fallible.name
  return_type: (type_app (type_name) @_t)
  (#eq? @_t "Result"))

; Every propagation site.
(try_form body: (_) @propagated)

; Every record field read.
(field_access field: (field_ref) @read.field target: (_) @read.target)

; Every declared effect, and the declaration that carries it (§9 rule 12).
(defun name: (ident) @effectful.name (decl_opt effect: (ident) @effectful.effect))

; The entry point, which is unnamed and so can only be found structurally.
(defentry params: (params) @entry.params return_type: (_) @entry.return)

; Every foreign declaration with the ecosystem it names (§9 rule 13). A
; defextern whose :target this query cannot find is the rule's violation.
(defextern
  name: (qualified) @foreign.name
  (extern_opt target: (keyword) @foreign.target))

; The host dependency manifest: every package a module binds, without reading a
; single body.
(extern_spec package: (string) @host.package alias: (ident) @host.alias)
