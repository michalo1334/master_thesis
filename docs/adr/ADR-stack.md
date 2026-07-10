---
document_type: adr
id: STACK
title: Technological stack
author: michalo
last_updated: 2026.07.06
status: accepted
superseded_by:
---

# Context
We need to choose tech stack that both provides rapid prototyping and provides resonable maintenance and extensibility in the long term

# Decision drivers
- master thesis deadline (~1 year)
- learn new points of view and technologies to further broaden horizons in terms of architecting efficient solutions
- seamless integration of the technologies to reduce friction

# Decision
Stack oriented around Elixir - LiveView, Svelte, LiveSvelte

# Consequences
- Good: rapid prototyping
- Bad: need to learn new technologies - reduces time spent on actual work

# Alternatives considered
- Backend: C# + ASP.NET Core - hands-on experience by the author, viable choice
- Frontend: 
    - React - too much state management, Svelte is much leaner but comes at price of smaller community and learning resources
    - Pure LiveView - complicates when more client side state or interactivity is involved (like canvas drag & drop), causing fragile split between server and client side of state juggling
# Links
