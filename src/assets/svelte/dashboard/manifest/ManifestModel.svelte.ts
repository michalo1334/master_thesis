import type { DashboardApi } from "../dashboard-api";
import type { ManifestError, ManifestSummary } from "../contract";

const DEFAULT_MANIFEST = `{
  "schema_version": 2,
  "model_version": "current-model-version",
  "id": "fixed-enterprise-v1",
  "source": { "type": "topology", "generator": "enterprise", "hosts": 50, "seed": 42 },
  "attacker": { "entry_host": { "type": "semantic_key", "value": "internet" }, "max_attempts": 1 },
  "model": { "objective": "mission_then_blast_radius", "require_pre_attack_feasibility": true },
  "strategy_runs": [
    { "strategy": "cvss", "budget": 1, "selection_seeds": [101] },
    { "strategy": "simulation_informed", "budget": 1, "selection_seeds": [201, 202] }
  ],
  "analysis": { "primary_comparisons": [{ "strategy": "simulation_informed", "baseline": "cvss", "budget": 1, "outcome": "blast_radius" }], "confidence_level": 0.95, "bootstrap_resamples": 10000, "permutation_resamples": 10000, "multiplicity_correction": "holm", "seed": 7001, "pilot": { "ci_half_width": 0.25 } },
  "evaluation": { "trials": 1000, "seed": 9001 }
}`;
const DEFAULT_MANIFEST_ID = "fixed-enterprise-v1";

export class ManifestModel {
  open = $state(false);
  manifests = $state<ManifestSummary[]>([]);
  selectedId = $state<string | null>(null);
  title = $state("");
  editorText = $state("");
  errors = $state<ManifestError[]>([]);
  statusMessage = $state("");
  isLoading = $state(false);
  isSaving = $state(false);
  isStarting = $state(false);
  onStarted: ((runId: string, manifest: ManifestSummary) => void) | undefined;
  private savedSelectionId = $state<string | null>(null);
  private savedTitle = $state("");
  private savedEditorText = $state("");

  constructor(readonly api: DashboardApi) {}

  get isBusy(): boolean {
    return this.isLoading || this.isSaving || this.isStarting;
  }

  get selectedManifest(): ManifestSummary | undefined {
    return this.manifests.find((manifest) => manifest.id === this.selectedId);
  }

  get canSave(): boolean {
    return (
      this.title.trim() !== "" && this.editorText.trim() !== "" && !this.isBusy
    );
  }

  get canStart(): boolean {
    return (
      this.selectedManifest !== undefined &&
      !this.hasUnsavedChanges &&
      !this.isBusy
    );
  }

  get hasUnsavedChanges(): boolean {
    return (
      this.selectedId === this.savedSelectionId &&
      (this.title !== this.savedTitle ||
        this.editorText !== this.savedEditorText)
    );
  }

  async openDialog(): Promise<void> {
    this.open = true;
    await this.loadManifests();
  }

  closeDialog(): void {
    if (this.isBusy) return;
    this.open = false;
  }

  async loadManifests(): Promise<void> {
    this.isLoading = true;
    try {
      const reply = await this.api.listManifests();
      this.manifests = reply.manifests;
      if (
        this.selectedId &&
        !this.manifests.some((manifest) => manifest.id === this.selectedId)
      ) {
        this.selectedId = null;
        this.savedSelectionId = null;
      }
    } catch {
      this.statusMessage = "Unable to load saved manifests.";
    } finally {
      this.isLoading = false;
    }
  }

  async selectManifest(id: string): Promise<void> {
    if (this.isBusy) return;
    this.errors = [];
    this.statusMessage = "";
    this.isLoading = true;
    try {
      const reply = await this.api.getManifest(id);
      if (!reply.manifest) {
        this.statusMessage = "The selected manifest is no longer available.";
        return;
      }
      if (
        reply.manifest.content === null ||
        typeof reply.manifest.content !== "object" ||
        Array.isArray(reply.manifest.content)
      ) {
        this.statusMessage = "Unable to load the selected manifest.";
        return;
      }
      this.selectedId = reply.manifest.id;
      this.title = reply.manifest.title;
      this.editorText = JSON.stringify(reply.manifest.content, null, 2);
      this.savedSelectionId = this.selectedId;
      this.savedTitle = this.title;
      this.savedEditorText = this.editorText;
    } catch {
      this.statusMessage = "Unable to load the selected manifest.";
    } finally {
      this.isLoading = false;
    }
  }

  addManifest(): void {
    if (this.isBusy) return;
    this.selectedId = null;
    this.savedSelectionId = null;
    this.title = "";
    this.editorText = DEFAULT_MANIFEST.replace(
      `"id": "${DEFAULT_MANIFEST_ID}"`,
      `"id": "${crypto.randomUUID()}"`,
    );
    this.errors = [];
    this.statusMessage = "";
  }

  async save(): Promise<boolean> {
    if (!this.canSave) return false;
    const parsed = this.parseEditor();
    if (!parsed) return false;

    const manifestId = parsed.id;
    if (typeof manifestId !== "string" || manifestId === "") {
      this.errors = [{ path: "id", message: "must be a non-empty string" }];
      return false;
    }
    if (
      this.selectedId === null &&
      this.manifests.some((manifest) => manifest.manifest_id === manifestId)
    ) {
      this.errors = [{ path: "id", message: "already exists" }];
      return false;
    }

    this.isSaving = true;
    this.errors = [];
    this.statusMessage = "";
    try {
      const reply = await this.api.saveManifest({
        manifest_id: manifestId,
        title: this.title.trim(),
        content: parsed,
      });
      if (reply.status === "ok" && reply.manifest) {
        await this.loadManifests();
        this.selectedId = reply.manifest.id;
        this.savedSelectionId = this.selectedId;
        this.savedTitle = this.title;
        this.savedEditorText = this.editorText;
        this.statusMessage = "Manifest saved.";
        return true;
      }
      this.errors = reply.errors ?? [];
      if (this.errors.length === 0) {
        this.statusMessage = "Unable to save the manifest.";
      }
      return false;
    } catch {
      this.statusMessage = "Unable to save the manifest.";
      return false;
    } finally {
      this.isSaving = false;
    }
  }

  async start(): Promise<boolean> {
    if (!this.canStart || !this.selectedId) return false;
    const manifest = this.selectedManifest;
    if (!manifest) return false;

    this.isStarting = true;
    this.errors = [];
    this.statusMessage = "";
    try {
      const reply = await this.api.startEvaluation(manifest.manifest_id);
      if (reply.status === "accepted" && reply.run_id) {
        this.statusMessage = "Evaluation started.";
        this.onStarted?.(reply.run_id, manifest);
        return true;
      }
      this.errors = reply.errors ?? [];
      if (this.errors.length === 0) {
        this.statusMessage =
          reply.status === "not_found"
            ? "The selected manifest was not found."
            : "Unable to start the evaluation.";
      }
      return false;
    } catch {
      this.statusMessage = "Unable to start the evaluation.";
      return false;
    } finally {
      this.isStarting = false;
    }
  }

  private parseEditor(): Record<string, unknown> | null {
    try {
      const parsed: unknown = JSON.parse(this.editorText);
      if (
        typeof parsed !== "object" ||
        parsed === null ||
        Array.isArray(parsed)
      ) {
        this.errors = [
          { path: "$", message: "manifest must be a JSON object" },
        ];
        return null;
      }
      return parsed as Record<string, unknown>;
    } catch {
      this.errors = [{ path: "$", message: "invalid JSON" }];
      return null;
    }
  }
}
