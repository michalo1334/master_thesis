# D3 Force-Directed Graph — Tips, Gotchas, and Math

Notes from building two demos in `src_demo/`:
- `src_demo/demo-svg.html` — D3 force layout with SVG (nodes as `<circle>`, edges as `<line>`, segment hulls as `<rect>`)
- `src_demo/demo-dom.html` — D3 force layout with DOM divs for nodes and an SVG layer underneath for edges and segment hulls

This document collects the math, the tips, the gotchas, and the step-by-step recipe. Read it once, then keep the demos open as reference.

---

## 1. The mental model

A D3 force simulation is a tiny physics engine. You give it:

- A list of **nodes**, each with `id`, and (after the first tick) mutable `x`, `y`, `vx`, `vy`.
- A list of **links**, each with `source`, `target` (both reference node ids; the simulation swaps them for the actual node objects on the first tick).
- A list of **forces** — small functions that read the nodes' positions and write to their velocities.

Then the simulation runs a `tick()` in a loop (driven by `d3-timer`, ~60 fps), applying each force, then integrating. Each tick you re-render the DOM/SVG from the new positions. That's the whole thing.

---

## 2. The math

### 2.1 What a tick does

For each tick, with α the current temperature and the default `alphaTarget = 0`:

$$
\alpha_{t+1} = \alpha_t + (\alpha_{target} - \alpha_t)\,\alpha_{decay}
$$

For each force $f$ (in registration order): apply the force. Force functions multiply by α. For each node $i$:

$$
v_{i,x} \leftarrow v_{i,x} \cdot (1 - \text{velocityDecay}) + \sum_f \frac{F_{f,x}(\alpha)}{m}
$$

$$
v_{i,y} \leftarrow v_{i,y} \cdot (1 - \text{velocityDecay}) + \sum_f \frac{F_{f,y}(\alpha)}{m}
$$

$$
x_i \leftarrow x_i + v_{i,x}, \qquad y_i \leftarrow y_i + v_{i,y}
$$

D3 uses unit mass $m = 1$ and unit time step $\Delta t = 1$. This is **not** textbook velocity Verlet — D3 is doing a one-step Euler with high friction, which is faster but less accurate. The high `velocityDecay = 0.4` (40% friction per tick) is what makes it converge fast and look stable.

### 2.2 The built-in forces (what each one writes to $v_x, v_y$)

| Force | Acceleration written | Notes |
|---|---|---|
| `forceCenter(x, y)` | $\Delta x = k \cdot (x_{target} - \bar{x})$ for every node, where $\bar{x}$ is the mean | Translates the whole cloud so the centroid sits at (x, y). **Direct position update** (not velocity), which is why it's not scaled by α. |
| `forceLink(links)` | Spring force per link: $k \cdot \frac{(d - d_0)}{d} \cdot (r_{tgt} - r_{src})$ | $d_0$ is the rest length. Default strength is $1 / \min(\deg(\text{src}), \deg(\text{tgt}))$. |
| `forceManyBody()` | Each pair repels with $C / r^2$ via Barnes–Hut quadtree | Default $C = -30$. `theta(0.9)` controls the approximation accuracy. |
| `forceCollide(r)` | Geometric non-overlap. Pure projection, no α scaling. | The single force that does not multiply by α. Runs `iterations(1)` times per tick. |
| `forceX(x)` / `forceY(y)` | $k \cdot (x_{target} - x_i)$ per node, per axis | Used for segment positioning. |
| `forceRadial(r, x, y)` | Pulls toward a circle of radius r around (x, y) | Useful for "perimeter" views. |

### 2.3 Cooling schedule

`alphaDecay` defaults to `1 - alphaMin^(1/300) ≈ 0.0228` and `alphaMin` defaults to `0.001`. Together that means **300 ticks of simulation before it auto-stops**. For our 34-node demo we use `alphaDecay = 0.05`, which gives ~135 ticks (ln(0.001)/ln(0.95) ≈ 134.6) — visually settled by tick 50–60.

To reheat: `sim.alpha(0.3).restart()`. To reheat without changing temperature: `sim.restart()`. The latter resets the timer but keeps α.

### 2.4 Initial positions: phyllotaxis

If a node has no `x, y` when the simulation starts, D3 places it in a phyllotaxis (sunflower) spiral:

$$
r = 10 \sqrt{0.5 + i}, \qquad \theta = i \cdot \pi \cdot (3 - \sqrt{5})
$$

$$
x = r \cos\theta, \qquad y = r \sin\theta
$$

This is **deterministic** — same `i` always lands on the same spot. Combined with D3's fixed-seed LCG for the per-tick "jiggle", the default is reproducible across runs unless you swap the RNG.

### 2.5 Pinning

At the end of every tick, after all forces have been applied, the simulation does:

```
if node.fx != null:  node.x = node.fx;  node.vx = 0
if node.fy != null:  node.y = node.fy;  node.vy = 0
```

So setting `fx`/`fy` pins a node to that coordinate, killing its velocity. Set to `null` to release. This is what makes drag-to-pin work.

**Drag container is critical.** d3-drag's default `container` is `this.parentNode` — for a circle inside `<g class="node-g" transform="translate(x, y)">`, that's the node-g. The drag handler then writes `d.fx = event.x`, but the **node-g's transform is also being updated by the tick handler** (`nodeG.attr('transform', d => translate(d.x, d.y))`). So the container's transform is moving, and `pointer(event, container)` returns the mouse position relative to the *current* (moving) container, not the simulation's frame. The node trails the mouse by the original offset, growing with the drag distance.

The fix: set the container to a stable reference frame — the root `<g>` that hosts the simulation:

```js
const drag = d3.drag()
  .container(() => gRoot.node())   // stable reference, not the moving node-g
  .clickDistance(4)
  .on('drag', (event, d) => {
    d.fx = event.x; d.fy = event.y;
    d.x  = event.x; d.y  = event.y;  // snap d.x/y to the pin (avoids 1-frame tick lag)
  });
```

This is the canonical d3-drag idiom for force layouts: the container should be the zoom root, not the dragged element's parent. Verified: a (+200, +50) drag now produces `d.fx=732, d.fy=370` (matching the root mouse position), where the buggy version produced values that trailed the mouse.

### 2.6 Pan and zoom (the transform)

`d3.zoom()` produces an `event.transform = {x, y, k}` representing a 2D affine transform:

$$
T(p) = (k \cdot p_x + t_x,\ k \cdot p_y + t_y)
$$

Inverse: $T^{-1}(p) = ((p_x - t_x)/k,\ (p_y - t_y)/k)$. With `k=1, t_x=t_y=0` you get `d3.zoomIdentity`.

For SVG: apply `g.attr("transform", event.transform)`. D3 serializes it as `translate(x,y) scale(k)`.

For DOM: apply `node.style.transform = "translate(" + t.x + "px," + t.y + "px) scale(" + t.k + ")"`. The `px` is essential because the DOM nodes use `left`/`top` in px.

**Both layers need the same transform applied every zoom event.** This is the single most important gotcha for the DOM variant — see §3.2.

### 2.7 Custom segment force (for our 3 segments)

$$
F_{i,x} = k_s \cdot (c_x(\text{seg}(i)) - x_i) \cdot \alpha
$$

$$
F_{i,y} = k_s \cdot (c_y(\text{seg}(i)) - y_i) \cdot \alpha
$$

Linear spring with constant $k_s = 0.06$, applied to both axes. The α multiplier means the force fades as the system cools — by the time the simulation is at `alphaMin = 0.001`, the segment-pinning effect is essentially off and only short-range forces (link, charge, collide) are active. Result: distinct segment clusters, with intra-segment topology still free to arrange itself.

`k_s = 0.06` is the sweet spot for our domain. Higher (0.5+) collapses the graph into 3 dots. Lower (0.01) lets the segment structure dissolve entirely.

---

## 3. Tips

### 3.1 SVG variant tips

1. **One `<g>` receives the zoom transform.** Wrap your nodes, links, segment hulls, and labels in a single inner `<g>`. Apply the transform to that. Don't apply it to each node individually — that's O(N) work per zoom event for no reason.
2. **`d3.zoomIdentity.toString()` is your friend** when binding to Svelte. Svelte 5 runes (`$state`, `$derived`) let you set `let transform = $state(zoomIdentity)` and use `transform={$state.snapshot(transform).toString()}` or just `transform={transform.toString()}` in the template. Svelte's reactivity handles the rest.
3. **Pre-warm the simulation by calling `sim.tick(80)` before showing the graph.** The first 60–80 ticks are the ugliest because nodes are flying out of the phyllotaxis spiral. Pre-warming gives a clean entrance.
4. **Bind edges to the array `forceLink` mutates, not the original input.** `d3.forceLink(links).id(d => d.id)` replaces each link's `source` and `target` strings with the actual node objects on the first tick. If you keep your edge selection bound to the original `links`, `d.source.x` is undefined and your lines all collapse to (0, 0).
5. **Use `simulation.nodes()` to detect re-init.** When the data changes, call `sim.nodes(newNodes)`. D3 re-initializes positions for any node with NaN x/y (back to phyllotaxis). To preserve user-pinned positions across data changes, save `fx, fy` in a Map keyed by `id` and rehydrate.
6. **Pre-tune the force parameters on a static layout.** Once you've picked numbers that look right with `sim.tick(300)`, write them down. Live simulation will look ~10% more chaotic.

### 3.2 DOM variant tips

1. **The zoom transform goes on a WRAPPER, not on each node.** This is the single most important DOM-variant rule. If you set `transform: scale(k) translate(tx, ty)` on each `.node` (which has `position: absolute; left: x; top: y`), the scale is applied around the node's own top-left — not around the SVG (0, 0) origin — and the nodes fly off-screen diagonally on the first zoom. The correct structure is: a `<div class="zoom-layer">` wraps all nodes, gets `transform-origin: 0 0` and the zoom transform, and each node inside uses `left/top` for graph-space position only. The wrapper's transform composes on top. This is the bug that bit me in the first version of `demo-dom.html`: nodes vanished at zoom > 1 because each node was being scaled around its own anchor.
2. **Two layers, one transform.** The DOM nodes are one layer (positioned by `left`/`top`, transformed by the wrapper). The SVG with edges and segment hulls is another layer (transformed by SVG `transform="translate(x,y) scale(k)"`). The two transforms must match. If they get out of sync — usually by 1 frame during fast scrolling — the graph looks "broken" with nodes floating off their lines.
3. **Avoid `position: absolute` with `top: 0; left: 0` for the SVG layer.** Use `position: absolute; top: 0; left: 0; width: 100%; height: 100%; pointer-events: none` and put `pointer-events: auto` on the edges/hulls you want clickable. The DOM nodes need `pointer-events: auto` too.
4. **Labels work better in DOM than in SVG.** SVG `<text>` rendering is browser-inconsistent (especially rotated text). HTML `<div>` with CSS `font-family` is the same on every browser. If labels matter, prefer DOM. **But:** under the wrapper approach, labels get scaled by the CSS transform, which renders them blurry at non-integer zoom levels (e.g. scale 0.3 or 1.7). This is a fundamental trade-off of the DOM approach. If you need crisp labels at all zoom levels, use SVG `<text>` with `vector-effect: non-scaling-stroke`, or zoom only the dot/circle and keep labels in a fixed-size overlay.
5. **Transitions are smoother in DOM** (for the geometry) **but blurrier** (for the text). Pick your poison.
6. **Caveat: hit testing on text is harder in DOM.** When a user clicks "near" a node, the click may hit the label, not the dot. Decide if the label is part of the node's hit area. (Both demos treat the entire `.node` div as the hit target.)

### 3.3 Shared tips (both variants)

1. **Selection state lives in the framework, not in D3.** If you're in Svelte: `let selectedId = $state<string|null>(null)`. The tick handler reads it and applies `classed("selected", d => d.id === selectedId)`. The click handler updates it. The simulation never knows about selection.
2. **Click vs drag conflict is solved with `clickDistance`.** Both `d3-zoom` and `d3-drag` have a `clickDistance(n)` setter. Set to 4 on drag, 8 on zoom. 4 pixels of mouse-movement slop is invisible to users; 0 pixels of slop makes clicks unreliable.
3. **Drag a node to pin it.** `d3.drag().on("drag", (e, d) => { d.fx = e.x; d.fy = e.y; })` is the recipe. Releasing on `end` (setting `fx, fy` back to `null`) gives "drag-and-throw" behavior; leaving them set gives "drag-and-pin" behavior. The demos pin.
4. **Reheat during drag.** `sim.alphaTarget(0.3).restart()` on drag start, `sim.alphaTarget(0)` on drag end. This makes the *other* nodes react to the dragged one (link forces pull/push around it). Without reheating, dragging feels "stuck" because the rest of the graph doesn't move.
5. **Stop the simulation on unmount.** `return () => sim.stop();` in a Svelte `$effect` (or `onMount` cleanup). Otherwise the simulation keeps running in the background and you leak memory across page changes.
6. **Set a seed for reproducibility.** `sim.randomSource(d3.randomLcg(42))`. Same seed → same jitter → same layout. Useful for thesis figures.
7. **Use `requestAnimationFrame` for the render, not the simulation tick.** The simulation already uses `d3-timer` (which is rAF-aware). Reading `node.x, node.y` in the tick callback and writing to the DOM is fine; reading from a separate rAF loop is wasted work.

---

## 4. Gotchas (things that bit me)

### 4.1 Nodes escape the viewport at the start

**Why:** phyllotaxis starts at `r = 10·√(0.5 + i)`, so for i=149 that's already 122 px from origin. With `forceManyBody.strength = -260` over 34 nodes, things fly outward.

**Fix:** pre-warm. `sim.tick(80)` before mounting the SVG. The 80 pre-tick steps let the layout settle into something reasonable before the user sees it. Combine with `forceCenter(W/2, H/2)` to keep the centroid in the viewport.

If you can't pre-warm, clamp positions in the tick:
```js
nodes.forEach(n => {
  n.x = Math.max(20, Math.min(W-20, n.x));
  n.y = Math.max(20, Math.min(H-20, n.y));
});
```
D3's docs say "don't write to nodes from a tick handler" but in practice clamping is harmless.

### 4.1a (DOM-only) Nodes "fly diagonally" on zoom

**Why:** each DOM node has `position: absolute; left: x; top: y` and a per-node CSS `transform: translate(tx, ty) scale(k)`. The `transform-origin` defaults to `50% 50%` of the element's box. The scale is applied around the node's center, not around the SVG (0, 0) origin. So a node at graph (532, 320) with zoom (4, -2250, -1005) ends up at screen (4·(532 - 282) - 2250 + 282, 4·(320 - 332) - 1005 + 332) — diagonally offset from where the math says it should be. With more zoom, the offset grows; the node "flies" off-screen.

**Fix:** the zoom transform goes on a **wrapper** that contains all the nodes, with `transform-origin: 0 0`. Each node uses `left/top` for graph-space position only. The wrapper's transform composes correctly. This is documented in §3.2.1.

### 4.1b (Both) Drag handler fires with mouse position in the wrong coordinate frame

**Symptom:** the dragged node trails behind the mouse. The longer the drag, the bigger the gap (cumulatively).

**Why:** d3-drag's default `container` is `this.parentNode`. For a circle inside `<g class="node-g" transform="translate(x, y)">`, that's the node-g. The drag handler writes `d.fx = event.x`, but the **tick handler** is *also* writing the node-g's `transform` to `translate(d.x, d.y)`. So the container's transform is moving, and `pointer(event, container)` returns the mouse position relative to the *current* (moving) container, not the simulation's frame. The cumulative effect is d.fx trails the mouse by the original offset.

**Fix:** set `drag.container(() => gRoot.node())` to use a stable reference frame (the zoom root). See §2.7 for the full pattern. This is the canonical d3-drag idiom for force layouts.

### 4.2 The simulation never settles

**Why:** `alphaDecay` too low, `velocityDecay` too low, `alphaTarget` accidentally > 0, or `restart()` called in a hot path.

**Fix:** start with the defaults and tune one parameter at a time. Diagnostic: `sim.on('tick', () => console.log(sim.alpha()))` — should decay monotonically. If it doesn't, you have a hot `restart()` somewhere.

For our 34-node graph, `alphaDecay = 0.05` is fast enough that the layout visibly settles in 1–2 seconds. For 200+ nodes you might want `0.03` to give the layout more time to find a low-energy configuration.

### 4.3 Click handlers fire when they shouldn't

**Why:** a tiny mouse jitter during mousedown is enough for d3-zoom or d3-drag to eat the click.

**Fix:** `drag.clickDistance(4)`, `zoom.clickDistance(8)`. Both setters accept pixel slop. Without these, the demo is unusable.

### 4.4 Edge source/target is undefined

**Why:** the edge selection is bound to the original `links` array, where `source` is still the string id. After the first tick, `d.source` is the node object — but only on the array that `forceLink` mutated, not on your input.

**Fix:** bind to `simLinks = links` (the array you passed to `forceLink`); use the same reference everywhere.

### 4.5 d3.drag throws on the first mousedown

**Why:** `selection.data(nodes, d => d.id)` is called *after* creating the divs. The key function is called with the *existing* datum, which is `undefined` for fresh divs. If your key function then calls `d.id`, you crash.

**Fix:** always use `selectAll().data().join()` to create the data-bound elements in one pass, before attaching the drag.

### 4.6 d3.forceLink mutates the links you give it

This is intentional, but it surprises people. `forceLink` replaces `link.source` and `link.target` (strings) with the actual node objects on the first tick. If you keep the original `links` for, say, displaying a "raw" view, you've lost the original ids.

**Fix:** clone the input if you need to preserve it. `links = inputLinks.map(l => ({...l}))`. Then bind to `links` (the copy) and keep `inputLinks` for whatever else.

### 4.7 Svelte 5 reactivity + simulation positions

**Why:** if you put `node.x, node.y` in `$state`, every tick (60 fps) triggers a Svelte re-render of every node. That's hundreds of state changes per second; the framework overhead is enough to drop framerate.

**Fix:** keep positions as plain mutable object properties. The simulation mutates them. The tick handler reads them and writes to the DOM/SVG via `selectAll().attr(...)` or `selectAll().style(...)`. Svelte's reactivity is not in the hot path.

### 4.8 Edge-count blow-up

**Why:** the domain has credential pools (every pair in a pool gets an edge) and exploit applicability (every source × every target with a CVE gets an edge). With 12 user services and 4 CVEs each, that's potentially 12×12 + 12×4×4 = 192 edges before you even count network reachability.

**Fix:** in the demo, the synthetic data generator throttles:
- Credential pools: only 2-3 services per pool, not all members of a segment
- Exploits: only the 2 nearest user sources per target (not all sources)
- Network reach: only between segments, not within

Result: 59 edges for 34 nodes, which is dense enough to look "real" but sparse enough to not become a hairball.

### 4.9 Selection class lost on re-render

**Why:** D3's classed/attribute updates are local to the selection. If the data changes and the selection is rebuilt, the classed state is lost.

**Fix:** selection is *state*, owned by Svelte. The data join is idempotent (by id), so re-joining doesn't destroy DOM elements. After re-join, re-apply the classed call. Pattern:

```svelte
$effect(() => {
  nodeSel.classed("selected", d => d.id === selectedId);
});
```

When `selectedId` changes, the effect re-runs and re-applies the class. When data changes, the join is idempotent and the same effect re-runs after the join.

---

## 5. Step-by-step recipe (for the next time you build this)

1. **Set up the data.** Node = `{id, ...attrs}`. Link = `{source, target, kind}`. Don't put `x, y` on nodes yet — the simulation initializes them via phyllotaxis.
2. **Create the SVG with one inner `<g>`.** That `<g>` is the "world". All your nodes, edges, segment hulls go inside it.
3. **Define the segment centers.** Map: `{"dmz": {x, y}, "internal": {x, y}, "database": {x, y}}`. Place them in a triangle (or any non-collinear shape) so the segments don't all collapse into a line.
4. **Build the simulation.** Six forces, in this order:
   - `forceLink(links).id(d => d.id).distance(LINK_DIST)` — every edge is a spring
   - `forceManyBody().strength(CHARGE).distanceMax(DMAX)` — repulsion
   - `forceCollide().radius(d => d.r + PAD).iterations(2)` — non-overlap (this is what makes labels not stack)
   - `forceCenter(W/2, H/2)` — keeps the centroid in the viewport
   - `forceX(d => segCenters[d.segment].x).strength(SEG_STRENGTH)` — segment x
   - `forceY(d => segCenters[d.segment].y).strength(SEG_STRENGTH)` — segment y
   - `alphaDecay(0.05).randomSource(randomLcg(SEED))` — settle fast, deterministic
5. **Pre-warm.** `sim.tick(80)` before mounting. This hides the phyllotaxis explosion.
6. **Build the data joins.** Edges first (they're simpler — just source/target), then nodes. Use `selectAll().data().join()` and bind drag/click on the joined elements.
7. **Attach zoom to the SVG.** `select(svg).call(zoom().on("zoom", e => g.attr("transform", e.transform)))`. The `<g>` is the world. The zoom transform composes on top of the simulation's positions. **For DOM-variant demos:** also apply the same transform to a wrapper element around the DOM nodes (with `transform-origin: 0 0`). Do NOT apply it to each individual node.
8. **Tick handler.** Read positions, write to the DOM. Don't re-bind data. Don't compute anything heavy per node.
9. **Click handler.** Update Svelte state, not D3 state. Re-apply classed.
10. **Drag handler.** Set `fx, fy` to the event coords. On `end`, leave them set (pin) or clear them (release). Reheat the simulation during drag.
11. **Reset button.** Re-initialize the simulation, restore original positions, re-heat.
12. **Test in headless Chrome** (Playwright). The static smoke test won't catch the edge-source/target mutation bug — only a real browser will. **Critically: test zoom IN and zoom OUT, and pan, and verify the nodes still align with the edges.** Misalignment on zoom is the most common bug; see §4.1a.

---

## 6. Parameter cheat sheet

For a 30-50 node graph on a 1440×600 canvas, these are the values that work in the demos:

```
W = 1440, H = 600
CHARGE       = -260          // d3 default is -30, but at 30+ nodes that's too weak
LINK_DIST    = 70            // average spring rest length
COLLIDE_R    = 28            // node radius (12) + 16px label padding
SEG_STRENGTH = 0.06          // segment force, weak so layout has freedom
ALPHA_DECAY  = 0.05          // ~135 ticks to settle
ALPHA_MIN    = 0.001         // default, don't change
VEL_DECAY    = 0.4           // default, don't change
ZOOM_MIN     = 0.2           // hard lower limit on scale
ZOOM_MAX     = 4             // hard upper limit on scale
SEED         = 42            // or any int, for reproducibility
```

For a 200-host production graph, scale up to:
```
CHARGE       = -350
LINK_DIST    = 35            // tighter, because you have more nodes per area
COLLIDE_R    = 15
SEG_STRENGTH = 0.04          // weaker, so the simulation has more freedom
ALPHA_DECAY  = 0.03          // slower cooling, more time to find low-energy layout
```

Tune from there.

---

## 7. When to abandon D3 and use something else

- **> 1000 nodes:** switch to Canvas rendering. The d3-force simulation is renderer-agnostic; the bottleneck is the SVG DOM, not the simulation. D3 + Canvas is a few lines: `nodes.forEach(n => ctx.arc(n.x, n.y, n.r, 0, 2*Math.PI))`. There's an [Observable pattern for d3-force + web worker](https://observablehq.com/@d3/force-directed-web-worker) that offloads the simulation itself.
- **Need built-in graph algorithms (shortest path, BFS, centrality):** [Cytoscape.js](https://js.cytoscape.org/). 400KB minified; you pay for a kitchen you don't need at 150 nodes.
- **WebGL at any size:** [Sigma.js](https://www.sigmajs.org/). Their own homepage says "if you have small graphs, use D3." At 150 nodes you're firmly in the "use D3" zone.
- **Editing a node graph (DAG editor, workflow):** [svelte-flow](https://svelteflow.dev/). Wrong tool for attack-graph visualization.

For our 150-node attack graph, D3 + SVG is the right pick. The DOM variant trades some complexity for better text rendering and slightly smoother animation.
