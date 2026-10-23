# Frontmatter library research

## Decision

Use `yaml` as a direct dependency in `pi-interactive-subagents`. Use `parseDocument()` for reads and updates.

## Evidence

- Pi uses `yaml` for frontmatter parsing.
- Pi's subagent example uses its YAML-backed `parseFrontmatter()` helper.
- No active workspace extension uses `gray-matter`, `front-matter`, or `js-yaml`.
- The target lock file already contains `yaml@2.8.3` through `@mariozechner/pi-coding-agent`.
- A production package must declare `yaml` directly. It must not import a transitive dependency.

## Required update behavior

1. Detect LF or CRLF.
2. Extract the first frontmatter block without changing the Markdown body.
3. Parse the block with `yaml.parseDocument()`.
4. Reject malformed YAML and duplicate `model` or `thinking` keys.
5. Update only `model` and `thinking`.
6. Serialize the YAML document.
7. Restore the original line-ending style.
8. Reattach the original Markdown body exactly.
9. Replace the file atomically.

## Preservation contract

Preserve:

- Markdown body bytes
- unknown fields
- key order where the YAML document model supports it
- separate-line comments
- LF or CRLF style
- atomic replacement behavior

Do not promise byte-for-byte frontmatter preservation. YAML serialization can normalize whitespace, quoting, and
indentation.

## Tests

Cover LF, CRLF, body delimiters, comments, unknown fields, quoted scalars, lists, maps, multiline values, missing keys,
duplicate target keys, malformed YAML, missing delimiters, exact body preservation, atomic success, and atomic failure.
