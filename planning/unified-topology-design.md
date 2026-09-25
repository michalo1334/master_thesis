# Progressive Unified Topology UX Design

## Purpose

This document defines how the unified topology looks and behaves. It does not define the server or frontend contract boundary. See `planning/grilling-topology-projection-boundary.md` for projection interfaces and request lifecycles.

## Core Experience

Use one modeless topology canvas. Do not provide separate Topology and Network views. Do not provide Overview and Detail modes.

The canvas has one stable spatial model:

- Network segments are the main spatial anchors.
- Hosts and services stay inside their segment.
- Vulnerabilities, credentials, and mission capabilities appear outside segments as attached context.
- Zoom changes visual detail, not positions or segment bounds.
- Selection reveals one temporary context neighborhood.
- A local pin keeps a neighborhood visible.

```text
[Credential]                         [Mission capability]
     │                                        ▲
┌────▼ DMZ ─────────────────┐ policy ┌────────┴ Internal ───────────┐
│ web-1 ─runs─▶ nginx       │───────▶│ app-1 ─runs─▶ application   │
│ web-2     dns             │        │ database                    │
└────────────┬──────────────┘        └──────────────────────────────┘
             │ affected-by
             ▼
       [Vulnerability]
```

## Canvas Anatomy

Keep graph actions in one compact toolbar. Keep the existing inspector on the right.

```text
┌──────────────────────────────────────────────────────────┬──────────────────┐
│ Add ▾  Search…  Arrange  Fit  Reset  Clear pins  ⚠ 3    │ Inspector        │
├──────────────────────────────────────────────────────────┤                  │
│ Navigator ▸                                              │ Selected entity  │
│                                                          │ Fields           │
│       ┌ DMZ ───────────────┐      ┌ Internal ─────────┐  │ Relationships    │
│       │ hosts and services │ ───▶ │ hosts/services   │  │ Placement status │
│       └────────────────────┘      └──────────────────┘  │ Pin action       │
│                                                          │                  │
│  ⚠ Unplaced · 3                                          │                  │
└──────────────────────────────────────────────────────────┴──────────────────┘
```

The toolbar contains:

- Add actions.
- Search.
- Arrange, Fit, and Reset.
- Clear pins, only when pins exist.
- Unplaced count, only when unplaced entities exist.
- Navigator toggle.

Do not add a density switch, context-layer switch, or presentation selector.

## Visual Grammar

### Segment zones

Render each segment as a tight rounded rectangle. Do not use ellipses or convex hulls.

The header shows:

- Segment name.
- CIDR when space permits.
- Host and service counts.
- Context count at low detail.
- A self-policy indicator when applicable.
- Selection and pin state.

Use a neutral fill and clear border. Reserve strong colors for selection, warnings, policy, and simulation state. Segment identity must not depend on color.

The segment boundary has one stable world-space footprint. It never geometrically collapses or expands because of zoom, selection, or pinning.

### Network members

Hosts and services form the in-segment structure.

- A host uses the existing typed card at high detail.
- A host uses a compact labelled glyph at medium detail.
- Services appear near their host.
- Ownership connectors appear only when their endpoints are visible.
- A segment header represents the segment node. Do not render a duplicate segment card.

Dragging a segment moves the segment, its hosts, and its services. It does not move external context.

Dragging an entity changes position only. It must not silently change segment membership, service ownership, or another authored relationship.

### Attached context

Use distinct icon and shape cues:

- Vulnerability: warning or weakness symbol.
- Credential: key or secret symbol.
- Mission capability: outcome or target symbol.

Always include a text label when detail permits. Do not rely on color alone.

Place a singly attached context node near its network anchor. Place shared context between visible anchors. Context nodes stay outside segment bounds and do not increase segment size.

### Relationships

Use a consistent visual hierarchy:

- Segment reachability: strong directed line, visible at low zoom.
- Self-segment policy: selectable indicator in the segment header.
- Containment and service ownership: thin structural line at high detail.
- Context relationship: revealed through focus or a pin.
- Operational flow: separate overlay with clear draft or saved status.

Do not render every context edge at baseline. Show compact context counts instead.

Selection emphasizes direct neighbors and dims unrelated visible content. Dimming must not make unrelated content disappear completely.

## Progressive Detail

Zoom sets the baseline detail. Use hysteresis near thresholds so small wheel movements do not make content flicker.

### Far zoom

Show segment identity and policy structure.

```text
┌ DMZ ─ 18 hosts · 6 services · 4 context ┐
└──────────────────────────────────────────┘ ─────▶ [Internal · 74 hosts]
```

Show:

- Segment headers and boundaries.
- Summary counts.
- Directed segment policy.
- Self-policy indicators.
- Pinned context exceptions.

Hide individual hosts, services, and normal context edges.

### Medium zoom

Reveal hosts while preserving the same geometry.

```text
┌ DMZ ───────────────────────────┐
│ web-1  web-2  dns  mail       │
└────────────────────────────────┘
```

Show:

- Compact host glyphs or cards.
- Per-host service counts.
- Selected or pinned context.
- Segment policy.

### Near zoom

Reveal editable network detail.

```text
┌ DMZ ───────────────────────────┐
│ web-1 ─runs─▶ nginx           │
│ web-2          dns            │
└────────────────────────────────┘
```

Show:

- Full host cards.
- Service cards and labels.
- Containment and ownership relationships.
- Connection handles and edit actions.
- Selected or pinned context.

### Focus override

Selection or keyboard focus activates an adjacency lens at any zoom.

```text
Baseline:  [nginx ◇3 context links]

Focused:              [Credential]
                           │
         ┌ DMZ ────────────▼──────────────┐
         │ web-1 ─runs─▶ nginx           │
         └──────────────┬─────────────────┘
                        ├─▶ [Vulnerability]
                        └─▶ [Mission capability]
```

The lens can reveal detail above the current zoom baseline. It must not move the anchor, resize the segment, or run layout.

## Selection and Pins

Selection controls the inspector and activates a temporary adjacency lens.

A visible pin action appears on:

- The selected card.
- A selected segment header.
- The inspector.

A pin keeps that entity's adjacency lens visible after selection moves. Users can keep several pins for comparison. Each pinned entity has an unpin action. The toolbar provides Clear pins.

Pinned state uses both an icon and an outline. Pins are view state. They do not mark the graph dirty.

If a pinned entity is deleted or no longer exists after reload, remove its pin.

## Search and Navigator

Search focuses an entity. It does not filter the graph or change layout.

A search result must:

1. Pan and zoom enough to make the entity legible.
2. Select the entity.
3. Activate its adjacency lens.
4. Keep surrounding topology visible for orientation.

The Navigator is a DOM-based hierarchy:

```text
DMZ
├─ web-1
│  └─ nginx
├─ web-2
└─ dns

Attached context
├─ ordering capability
└─ deployment credential

Unplaced
└─ orphan-service
```

Navigator focus activates the same lens as canvas focus. Activation selects the entity and opens the inspector.

## Unplaced Tray

Use a view-only Unplaced tray for entities without an unambiguous topology placement.

```text
⚠ Unplaced · 3
┌─────────────────────────────────────────────────────┐
│ [host-7: no segment] [svc-3: no host] [credential] │
└─────────────────────────────────────────────────────┘
```

The tray contains:

- Hosts without a segment.
- Services without one host.
- Entities with ambiguous single-owner relationships.
- Context without a valid anchor.
- Newly changed entities while semantic projection is pending.

Use different cues for pending and placement issues. Selecting an item opens its normal inspector plus a Placement section with the typed reason.

The tray is not graph data. Moving an entity out of it requires an explicit authored relationship, not a visual drag alone.

## Add and Connect Flows

New entities use the current pointer or viewport position as an anchor, then move to a nearby free position.

- A host created from a selected segment uses a free slot in that segment.
- A service created from a selected host uses a free slot near that host.
- A host or service created without an owner appears in Unplaced.
- Context appears near its anchor after the relationship exists.

Connection handles remain available at near detail or through focus override. The segment header exposes valid segment relationships.

Adding, dragging, or connecting one entity must not move unrelated entities.

## Layout Behavior

Arrange is explicit. Do not run continuous physics or automatic relayout after zoom, focus, pinning, search, or projection refresh.

Arrangement must:

1. Pack hosts and services inside each segment.
2. Produce tight rectangular segment bounds.
3. Prevent segment overlap.
4. Place context outside segments near its anchors.
5. Keep shared context between anchors when space permits.
6. Preserve deterministic output for the same graph.

A large segment is larger than a small segment in proportion to packed content. It must not contain empty area caused by old scattered coordinates.

Opening an existing graph must not silently rearrange valid saved positions. If positions cause collisions or excessive spread, show an Arrange topology suggestion.

## Projection Feedback

### Pending

Keep the last accepted topology visible. Mark new or semantically changed entities as pending in the Unplaced tray. Show a small Updating topology status. Do not block editing.

### Placement issue

Show an entity warning and its reason in the inspector. Keep the entity editable.

### Projection error

Show a non-blocking error banner:

> Topology grouping is unavailable. Graph editing remains available.

Keep flat graph editing available. Do not show a second legacy Network view.

### Draft reachability

When operational flows come from unsaved edits, label the overlay:

> Draft reachability · Save before simulation

Simulation and optimization continue to use saved revisions.

## Inspector

Keep the existing inspector structure. Add only contextual sections:

- Pin or unpin action.
- Placement status and typed issue.
- Visible relationship summary.
- Draft reachability status when relevant.

Do not duplicate editable graph fields in a separate topology panel.

## Accessibility

- Provide keyboard access through the canvas and Navigator.
- Make keyboard focus activate the same adjacency lens as pointer selection.
- Keep focus visible at every zoom level.
- Use text, shape, icon, and line style with color.
- Do not make hover the only disclosure mechanism.
- Respect reduced-motion settings.
- Keep pinned or focused content available even when zoom would normally summarize it.
- Give toolbar, pin, policy, and Unplaced controls explicit accessible names.

## UX Test Cases

- When the user changes zoom, the workspace shall change detail without changing world coordinates or segment bounds.
- When zoom stays near a threshold, the workspace shall not repeatedly switch detail.
- When the user selects or focuses an entity, the workspace shall reveal its adjacent context.
- When the user pins an entity, the workspace shall keep its context visible after selection moves.
- When the user clears a pin, the entity shall return to zoom-derived detail.
- When a segment renders at low detail, it shall show identity and summary counts over its stable footprint.
- When the graph has an unplaced entity, the workspace shall show it in the Unplaced tray with a reason.
- When semantic projection is pending, the workspace shall keep the last accepted topology visible and editing available.
- When semantic projection fails, the workspace shall show a non-blocking error and keep flat editing available.
- When draft operational flows are visible, the workspace shall identify them as unsaved.
- When the user searches for an entity, the workspace shall focus it without hiding the surrounding topology.
- When the user arranges the graph, the workspace shall produce tight non-overlapping segment bounds.
- When the user drags a segment, the workspace shall move its hosts and services but not external context.
- When the user drags an entity, the workspace shall not change authored membership or ownership.
- When the user saves and reloads positions, the workspace shall restore them.
- When reduced motion is active, detail changes shall not use unnecessary animation.

## Boundaries

Do not add:

- Separate Topology and Network views.
- Overview or Detail modes.
- Geometric segment collapse.
- Global context-layer toggles.
- Automatic hover expansion.
- Continuous force simulation.
- Automatic layout after projection refresh.
- Color-only meaning.
- A legacy Network fallback.

This document does not define projection contracts, server modules, request freshness, or migration mechanics. Those decisions are in `planning/grilling-topology-projection-boundary.md`.
