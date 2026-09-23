# Generated Inspector Execution

## Chunk 1: Runtime Contract Metadata

Add a separate metadata generation pass. Keep the existing generated type file type-only. Generate a runtime metadata file from raw typespec fields and existing enum metadata. Generate discriminant mappings that resolve node and edge variants to their data contracts. Re-export runtime values through the generated alias modules. Add generator and synchronization tests. Add missing enum metadata to CVSS by reusing its existing enum values in validation.

## Chunk 2: Shared Inspector

Add one shared field renderer that consumes generated metadata. It must support strings, numbers, enums, nested objects, and nullable values. Add a small frontend presentation overlay for label overrides, hidden fields, and custom controls. Extract mission required-flow editing into a custom field component. Replace the heuristic and mission scalar forms with one selection inspector. Remove inspector component references from the graph presentation registry.

## Chunk 3: Backend Validation Errors

Define a generated wire contract for graph validation errors. Convert nested save changeset errors into entity-scoped errors with field paths. Return them from the existing save event without changing successful saves. Store errors in the editable graph document, expose selected-entity errors to the inspector, and clear stale errors when the corresponding entity changes.

## Chunk 4: Integration and Verification

Review the combined implementation for type, validation, accessibility, and persistence regressions. Run focused tests after fixes. Then run the complete frontend test, type, format, and style checks and `mix precommit`. Verify the inspector manually with a valid edit and an invalid edit followed by Save.
