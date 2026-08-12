; Structural search examples (axis 2). Run with:
;   tree-sitter query queries/searches.scm <file.agents>
;
; These are the queries a compiler, linter, or refactoring tool would use, and
; they are why the tooling grammar carries field names: without them a query can
; match a node but cannot address its parts.

; Fallible functions: every defun whose declared return type is a Result.
(defun
  name: (ident) @fallible.name
  return_type: (type_app (type_name) @_t)
  (#eq? @_t "Result"))

; Every propagation site.
(try_form body: (_) @propagated)

; Every record field read.
(field_access field: (field_ref) @read.field target: (_) @read.target)
