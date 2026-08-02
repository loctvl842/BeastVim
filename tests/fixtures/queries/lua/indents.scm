; Fixture copy of the upstream nvim-treesitter lua/indents.scm (MIT), vendored
; here so tests/test-treesitter-indent.lua is deterministic under `--clean`
; (no network download, no dependency on stdpath('data')/site being populated).

[
  (function_definition)
  (function_declaration)
  (field)
  (do_statement)
  (method_index_expression)
  (while_statement)
  (repeat_statement)
  (if_statement)
  "then"
  (for_statement)
  (return_statement)
  (table_constructor)
  (arguments)
] @indent.begin

[
  "end"
  "}"
  "]]"
] @indent.end

(")" @indent.end
  (#not-has-parent? @indent.end parameters))

(return_statement
  (expression_list
    (function_call))) @indent.dedent

[
  "end"
  "then"
  "until"
  "}"
  ")"
  "elseif"
  (elseif_statement)
  "else"
  (else_statement)
] @indent.branch

(comment) @indent.auto

(string) @indent.auto

(ERROR
  "function") @indent.begin
