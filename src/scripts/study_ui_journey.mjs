import { chromium } from "playwright";
import fs from "node:fs";
const root = process.env.STUDY_UI_EVIDENCE_DIR ?? "/tmp/study-ui-evidence";
const baseUrl = process.env.STUDY_UI_BASE_URL ?? "http://localhost:4031";
const input = JSON.parse(fs.readFileSync(root + "/browser-input.json", "utf8"));
const browser = await chromium.launch({
  headless: true,
  ...(process.env.CHROMIUM_EXECUTABLE_PATH
    ? { executablePath: process.env.CHROMIUM_EXECUTABLE_PATH }
    : {}),
  args: ["--no-sandbox"],
});
const context = await browser.newContext({
  viewport: { width: 1800, height: 1100 },
  permissions: ["clipboard-read", "clipboard-write"],
});
const page = await context.newPage();
const errors = [],
  events = [],
  requests = [];
page.on("pageerror", (e) => {
  errors.push(e.message);
  console.log("PAGEERROR", e.message);
});
page.on("dialog", (d) => d.accept());
page.on("websocket", (ws) => {
  const refs = new Map();
  ws.on("framesent", (frame) => {
    try {
      const a = JSON.parse(frame.payload);
      if (a[3] === "event" && a[4].event?.includes("study")) {
        refs.set(a[1], a[4].event);
        requests.push({ event: a[4].event, payload: a[4].value });
      }
    } catch {}
  });
  ws.on("framereceived", (frame) => {
    try {
      const a = JSON.parse(frame.payload);
      const payload = a[4];
      for (const pair of payload.e ?? payload.response?.diff?.e ?? []) {
        if (pair[0].startsWith("study_"))
          events.push({ event: pair[0], payload: pair[1] });
      }
      const reply =
        payload.response?.diff?.r ?? payload.response?.reply ?? payload.r;
      if (refs.has(a[1]) && reply)
        requests.push({ replyTo: refs.get(a[1]), reply });
    } catch {}
  });
});
async function select(label, value) {
  await page.getByRole("button", { name: label, exact: true }).click();
  await page.getByRole("option", { name: value, exact: true }).click();
}
async function fill(label, value) {
  await page
    .getByRole("textbox", { name: label, exact: true })
    .fill(String(value));
}
async function screenshot(name) {
  await page.screenshot({ path: root + "/" + name, fullPage: true });
}
try {
  await page.goto(baseUrl);
  await page
    .getByRole("button", { name: "Create document", exact: true })
    .click();
  await page.getByRole("menuitem", { name: "Study", exact: true }).click();
  await page
    .getByRole("button", { name: "New study revision", exact: true })
    .click();
  await page
    .getByRole("button", { name: "Freeze revision", exact: true })
    .click();
  const invalidRevision = page
    .getByRole("textbox", { name: "Revision", exact: true })
    .and(page.locator('[aria-invalid="true"]'));
  await invalidRevision.waitFor();
  const errorId = await invalidRevision.getAttribute("aria-describedby");
  if (
    !errorId ||
    !(await page.locator(`[id="${errorId}"]`).innerText()).includes(
      "Supply a valid value.",
    )
  )
    throw new Error("Backend validation was not linked to the Revision field");
  if (
    !requests.some(
      (r) =>
        r.event === "create_study_revision" &&
        r.payload.definition.revision === "" &&
        r.payload.definition.seed === "",
    )
  )
    throw new Error("Blank scientific fields did not reach backend validation");
  await fill("Study ID", input.study_id);
  await fill("Revision", input.revision);
  await fill("Master seed", input.seed);
  await fill("Family ID", input.family_id);
  await fill("Family alpha", input.family_alpha);
  await fill("Confidence level", input.confidence_level);
  await select("Feasibility", "Unrestricted");
  await page
    .getByRole("button", { name: "Choose defense actions", exact: true })
    .click();
  await page
    .getByRole("checkbox", { name: "Select patch_vulnerability", exact: true })
    .click();
  await page.getByRole("button", { name: "Select (1)", exact: true }).click();
  await fill("Iterations per run", input.iterations_per_run);
  await fill("Maximum attempts", input.max_attempts);
  await page
    .getByRole("button", { name: "Choose simulation rules", exact: true })
    .click();
  for (const rule of input.rules)
    await page
      .getByRole("checkbox", { name: "Select " + rule, exact: true })
      .click();
  await page
    .getByRole("button", {
      name: `Select (${input.rules.length})`,
      exact: true,
    })
    .click();
  for (const tier of input.tiers) {
    await page
      .getByRole("button", {
        name: `Choose ${tier.tier} graph revision`,
        exact: true,
      })
      .click();
    await page
      .locator(`[data-revision-id="${tier.graph_revision_id}"]`)
      .locator(".graph-tree-select")
      .click();
    await page
      .getByRole("button", { name: `${tier.tier} foothold Host`, exact: true })
      .click();
    await page.getByRole("option").first().click();
    await fill(`${tier.tier} budget 1`, tier.budgets[0]);
    await page
      .getByRole("button", {
        name: `Add ${tier.tier} alternative`,
        exact: true,
      })
      .click();
    await select(`${tier.tier} alternative 1`, "random");
  }
  await fill("Candidate 1 ID", input.candidates[0].id);
  await fill("Candidate 1 plans per side", input.candidates[0].plans);
  await fill("Candidate 1 attacks per plan", input.candidates[0].attacks);
  for (const [label, key] of [
    ["Extra pool plans", "extra_pool_plans"],
    ["Extra pool attacks", "extra_pool_attacks"],
    ["Outer subsamples", "outer_subsamples"],
    ["Target half-width", "target_half_width"],
    ["Guard quantile", "guard_quantile"],
  ])
    await fill(label, input[key]);
  const yaml = await page
    .getByRole("textbox", { name: "Read-only YAML", exact: true })
    .inputValue();
  if (!yaml.includes("seed: " + input.seed))
    throw new Error("Seed precision lost in generated YAML");
  fs.writeFileSync(root + "/browser-authored.yaml", yaml);
  const downloadEvent = page.waitForEvent("download");
  await page
    .getByRole("button", { name: "Download YAML", exact: true })
    .click();
  const download = await downloadEvent;
  await download.saveAs(root + "/browser-downloaded.yaml");
  if (fs.readFileSync(root + "/browser-downloaded.yaml", "utf8") !== yaml)
    throw new Error("Downloaded YAML differs from the form");
  await page.getByRole("button", { name: "Copy YAML", exact: true }).click();
  if ((await page.evaluate(() => navigator.clipboard.readText())) !== yaml)
    throw new Error("Copied YAML differs from the form");
  await page
    .locator(".study-document")
    .evaluate((node) => (node.scrollTop = 0));
  await screenshot("02-authored-draft.png");
  await page.reload();
  await page
    .getByRole("textbox", { name: "Master seed", exact: true })
    .waitFor();
  if (
    (await page
      .getByRole("textbox", { name: "Master seed", exact: true })
      .inputValue()) !== input.seed
  )
    throw new Error("Draft seed recovery failed");
  await page
    .getByRole("button", { name: "Freeze revision", exact: true })
    .click();
  await page
    .getByRole("region", { name: "Frozen study definition", exact: true })
    .waitFor({ timeout: 10000 });
  await screenshot("03-frozen-definition.png");
  await page.getByRole("tab", { name: /Executions:/ }).click();
  await page
    .getByRole("button", { name: "Start new Pilot", exact: true })
    .click();
  await page
    .getByRole("button", { name: "Continue", exact: true })
    .waitFor({ timeout: 10000 });
  await screenshot("04-pilot-started.png");
  await page.getByRole("button", { name: "Continue", exact: true }).click();
  await page
    .getByText(
      "Pilot accepted. Review the report and explicitly approve Final collection.",
      { exact: true },
    )
    .waitFor({ timeout: 45000 });
  await page.getByRole("tab", { name: "Pilot", exact: true }).click();
  await page
    .getByRole("button", { name: "Approve insufficient override", exact: true })
    .waitFor({ timeout: 10000 });
  await page
    .getByRole("radio", { name: "Select local-check", exact: true })
    .click();
  await select(
    "Insufficient override candidate",
    `local-check · ${input.candidates[0].plans} × ${input.candidates[0].attacks}`,
  );
  await page
    .getByRole("checkbox", {
      name: "I accept proceeding without meeting the Pilot precision target.",
      exact: true,
    })
    .click();
  await screenshot("05-pilot-approval.png");
  await page
    .getByRole("button", { name: "Approve insufficient override", exact: true })
    .click();
  await page.getByRole("tab", { name: "Status", exact: true }).click();
  await page.getByRole("button", { name: "Continue", exact: true }).click();
  await page
    .getByRole("button", { name: "Create document", exact: true })
    .click();
  await page.getByRole("menuitem", { name: "Runs", exact: true }).click();
  await page
    .getByRole("tab", {
      name: new RegExp("Needs attention: Study: " + input.study_id),
    })
    .waitFor({ timeout: 60000 });
  await screenshot("06a-background-attention.png");
  await page
    .getByRole("tab", { name: new RegExp("Study: " + input.study_id + " r1") })
    .click();
  await page
    .getByText(
      "Final result is stored. Review comparisons and measured timing.",
      { exact: true },
    )
    .waitFor({ timeout: 60000 });
  await page.getByRole("tab", { name: "Results", exact: true }).click();
  await page
    .getByRole("heading", { name: "Stored Final result", exact: true })
    .waitFor();
  await page.locator(".result-table").scrollIntoViewIfNeeded();
  await screenshot("06-final-comparisons.png");
  await page.locator(".result-table").getByRole("radio").first().click();
  await page
    .getByRole("region", { name: "Selected comparison", exact: true })
    .scrollIntoViewIfNeeded();
  await screenshot("07-selected-comparison.png");
  await page.getByRole("tab", { name: "Timing", exact: true }).click();
  await select("Timing tier", "large");
  await select("Display units", "Milliseconds");
  await page
    .locator(".timing-table")
    .first()
    .getByText(/ ms$/)
    .first()
    .waitFor();
  if (await page.locator(".timing-table").getByText(/ s$/).count())
    throw new Error("Timing display unit did not update");
  await page
    .getByRole("heading", { name: "Five measured replicas", exact: true })
    .scrollIntoViewIfNeeded();
  await screenshot("08-final-timing.png");
  await page.reload();
  await page
    .getByRole("heading", { name: "Five measured replicas", exact: true })
    .waitFor({ timeout: 15000 });
  if (
    (await page
      .getByRole("tab", { name: "Timing", exact: true })
      .getAttribute("aria-selected")) !== "true"
  )
    throw new Error("Timing section recovery failed");
  await page
    .getByRole("heading", { name: "Five measured replicas", exact: true })
    .scrollIntoViewIfNeeded();
  await screenshot("09-recovered-result.png");
  await page
    .getByRole("button", { name: "Create document", exact: true })
    .click();
  await page.getByRole("menuitem", { name: "Study", exact: true }).click();
  const picker = page.getByRole("dialog");
  await picker.getByPlaceholder("Search…").fill(input.study_id);
  await picker.getByRole("radio", { name: new RegExp(input.study_id) }).click();
  await picker
    .getByRole("button", { name: "Open selected", exact: true })
    .click();
  if (
    (await page
      .getByRole("tab", {
        name: new RegExp("Study: " + input.study_id + " r1"),
      })
      .count()) !== 1
  )
    throw new Error("Duplicate revision tab");
  const starts = requests.filter(
    (r) => r.event === "start_study_execution",
  ).length;
  const continues = requests.filter(
    (r) => r.event === "continue_study_execution",
  ).length;
  if (starts !== 1 || continues !== 2)
    throw new Error(
      `Unexpected progression requests: Start=${starts}, Continue=${continues}`,
    );
  const progress = events.filter((e) => e.event === "study_progress");
  if (
    !progress.some(
      (e) =>
        e.payload.progress.phase?.includes("collection") &&
        e.payload.progress.counters.some((c) => c.total > 0 && c.completed > 0),
    )
  )
    throw new Error("No meaningful collection counters captured");
  const results = requests
    .filter((r) => r.replyTo === "fetch_study_result")
    .map((r) => r.reply.result)
    .filter(Boolean);
  if (
    !results.length ||
    !results.every(
      (r) =>
        r.comparisons.length === 3 &&
        r.timing.length === 3 &&
        r.timing.every(
          (t) => t.replicas.length === 5 && t.summaries.length === 3,
        ),
    )
  )
    throw new Error("Stored comparison/timing reply coverage failed");
  fs.writeFileSync(
    root + "/browser-stored-result.json",
    JSON.stringify(results[0], null, 2),
  );
  fs.writeFileSync(
    root + "/browser-summary.json",
    JSON.stringify(
      {
        passed: true,
        starts,
        continues,
        progressEvents: progress.length,
        errors,
      },
      null,
      2,
    ),
  );
  console.log("JOURNEY PASSED", {
    starts,
    continues,
    progress: progress.length,
    errors,
  });
} catch (error) {
  await screenshot("browser-failure.png");
  console.log((await page.locator("body").innerText()).slice(-14000));
  console.error(error);
  process.exitCode = 1;
} finally {
  fs.writeFileSync(
    root + "/browser-events.json",
    JSON.stringify(events, null, 2),
  );
  fs.writeFileSync(
    root + "/browser-requests.json",
    JSON.stringify(requests, null, 2),
  );
  fs.writeFileSync(
    root + "/browser-errors.json",
    JSON.stringify(errors, null, 2),
  );
  const state = await context.storageState();
  fs.writeFileSync(
    root + "/browser-storage.json",
    JSON.stringify({ cookies: [], origins: state.origins }, null, 2),
  );
  await browser.close();
}
