# Progressive Topology Grilling

Progressive Topology
├─ Spatial grammar
│  ├─ Backbone: segment anchors [#](#backbone)
│  └─ Segment boundary: stable tight rectangle [#](#large-segments)
├─ Progressive disclosure
│  ├─ Detail trigger: zoom, focus, manual [#](#detail-trigger)
│  ├─ Manual disclosure: local sticky pin [#](#manual-disclosure)
│  └─ Layout stability: stable positions
├─ Context graph
│  ├─ Placement: attached outside zones [#](#placement)
│  └─ Relationship visibility: adjacency lens [#](#relationship-visibility)
├─ Editing
│  ├─ Creation target: anchored free slot
│  └─ Selection focus: adjacency lens
└─ Scale
   ├─ Large segments: stable footprint [#](#large-segments)
   └─ Edge density: adjacency lens [#](#relationship-visibility)

# Spatial grammar

## Backbone

### Question

What remains spatially stable while the canvas progressively reveals network and context detail?

### Decision

Use network segments as stable spatial anchors. Keep contextual entities outside the segment boundary and attach them to the relevant host, service, or segment. Progressive disclosure must not replace this spatial structure.

This approach keeps network policy readable without hiding mission, credential, vulnerability, or ownership relationships in another view.

### Rejected alternatives

- An equal-entity force graph. Segment identity would remain too weak.
- A context-first tree. It would obscure network policy and hosts that serve several contexts.

# Progressive disclosure

## Detail trigger

### Decision

Use three compatible triggers:

- Zoom sets the baseline detail level.
- Focus promotes the selected neighborhood.
- Manual controls let the user reveal or retain detail on demand.

The triggers change representation. They do not replace the scene or run a new layout. The remaining decision is how manual disclosure behaves.

## Manual disclosure

### Decision

Let users pin detail for a segment or entity. A pin overrides zoom-based simplification until the user removes it. Pinning remains local and does not become a global detail mode.

Pinned detail changes representation only. It does not move the selected anchor or unrelated zones.

# Context graph

## Placement

### Decision

Keep segments, hosts, and services in the network structure. Show vulnerabilities, credentials, and mission capabilities as attached context.

Context nodes do not enlarge segment boundaries. Place a singly attached context node near its network anchor. Place shared context between its visible anchors. Keep the related network anchors stable.

## Relationship visibility

### Decision

Use an adjacency lens. At baseline, show compact context indicators and counts. Selection or a sticky pin reveals the exact context nodes and relationships around that anchor. Keep segment-policy relationships visible at low detail because they define the network structure.

This is progressive disclosure, not a global context layer. Several anchors can remain pinned when the user needs a comparison.

# Scale

## Large segments

### Decision

Give each segment one tightly packed world-space footprint. Do not geometrically collapse it. At low zoom, replace child rendering with a segment summary. At higher zoom, reveal the already-positioned hosts and services.

A large segment remains larger than a small segment in proportion to its packed contents. Progressive rendering does not change bounds or member positions. This removes the old Network-view expansion model and prevents layout jumps.

# Editing

## Creation target

Keep the current pointer or viewport anchor, then find a nearby free slot. Node creation must not move existing anchors.

## Selection focus

Selection activates the adjacency lens. A sticky pin keeps that local lens active after focus moves.

# Result

The canvas has one spatial model and no presentation mode:

```text
[Credential]                         [Mission capability]
     │                                        ▲
     │                         supports       │
┌────▼ DMZ ─────────────────┐ policy ┌────────┴ Internal ───────────┐
│ web-1 ─runs─▶ nginx       │───────▶│ app-1 ─runs─▶ application   │
│ web-2     dns             │        │ database                    │
└────────────┬──────────────┘        └──────────────────────────────┘
             │ affected-by
             ▼
       [Vulnerability]
```

At low zoom, each stable zone renders as a summary. At higher zoom, the same geometry reveals hosts and services. Focus or a local sticky pin reveals attached context through the adjacency lens.
