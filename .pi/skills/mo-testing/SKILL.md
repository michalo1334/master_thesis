---
name: mo-testing
description: Use when writing, reviewing, or running tests. Covers manual testing, EARS, TDD, and coverage.
---

# Test design principles

- **Requirements:** Write test cases in EARS notation. Capitalize EARS keywords (`WHEN`, `WHILE`, `IF`, `THEN`, `SHALL`)
  and give each case a feature-scoped ID (for example, `AUTH-01`).
- **Test first:** Use TDD for implementation changes: write a failing test before the code. Have an independent subagent
  author tests when available to reduce implementation bias.
- **Priority:** For user-facing products, start with user journeys. Focus on likely failures in daily use; cover rare
  cases when their impact justifies the cost.
- **Assertions:** Test observable behavior and contracts, not implementation details. Mock dependencies when isolation
  helps; do not test the mocks themselves.
- **Scope:** Use unit tests for isolated logic, integration tests for interactions with real dependencies, and E2E tests
  for cross-component journeys. Backend E2E tests exercise real service-to-database flows without a UI.
- **Other checks:** Use architecture tests for module boundaries and static analysis for enforceable code rules. Use
  manual testing for fast feedback, exploration, or cases where automation costs more than it helps.
- **Maintenance:** Keep tests repeatable and independent. Reuse fixtures and helpers, use consistent names, and avoid
  duplicate cases.
- **Traceability:** Tag automated tests with their type (`Unit`, `Integration`, `E2E`) and case ID when the framework
  supports it.
- **Tools:** Use `playwright-cli` to explore browser flows or perform manual UI checks before encoding repeatable tests.

## Test case template

```text
ID: <feature>-<number>
Type: <Unit | Integration | E2E | Backend E2E | Architecture | Static | Manual>
Requirement: WHEN <trigger>, THE <system> SHALL <observable outcome>.
Preconditions: <required state>
Action: <trigger or operation>
Expected: <observable assertion>
```

Use the EARS form that fits the requirement; the `WHEN ... SHALL ...` line is one example.
