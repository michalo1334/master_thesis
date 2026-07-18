import {
  applySavedTopology as applySavedTopologyToDocuments,
  createSimulationDocument as createSimulationWorkspaceDocument,
  createTopologyDocumentFromServerGraph,
  graphNodeLabel,
  graphTypeLabel,
  nextActiveDocumentId,
  topologyEditableStateKey,
  type ServerTopologyGraph,
  type TopologyDocument,
  type TopologyEditorState,
  type WorkspaceDocument,
  type WorkspaceSnapshot,
} from "./model";

export class WorkspaceState {
  documents = $state<WorkspaceDocument[]>([]);
  topologyBaselines = $state<Record<string, string>>({});
  activeDocumentId = $state<string>();
  nextDocumentId = $state(1);

  activeDocument = $derived(
    this.documents.find((document) => document.id === this.activeDocumentId),
  );
  activeTopology = $derived(
    this.activeDocument?.type === "topology" ? this.activeDocument : undefined,
  );
  activeTopologyDirty = $derived(
    this.activeTopology
      ? this.topologyBaselines[this.activeTopology.id] !==
          topologyEditableStateKey(this.activeTopology.graph)
      : false,
  );
  selectedObject = $derived.by(() =>
    selectedTopologyObject(this.activeTopology),
  );

  snapshot(): WorkspaceSnapshot {
    return {
      documents: this.documents,
      topologyBaselines: this.topologyBaselines,
      activeDocumentId: this.activeDocumentId,
      nextDocumentId: this.nextDocumentId,
    };
  }

  restore(snapshot: WorkspaceSnapshot) {
    this.documents = snapshot.documents;
    this.topologyBaselines = snapshot.topologyBaselines;
    this.activeDocumentId = snapshot.activeDocumentId;
    this.nextDocumentId = snapshot.nextDocumentId;
  }

  createSimulationDocument() {
    const id = `simulation-${this.nextDocumentId++}`;
    const title = `Simulation result ${
      this.documents.filter((document) => document.type === "simulation")
        .length + 1
    }`;

    this.documents = [
      ...this.documents,
      createSimulationWorkspaceDocument(id, title),
    ];
    this.activeDocumentId = id;
  }

  openTopology(topology: ServerTopologyGraph) {
    const id = `topology-${this.nextDocumentId++}`;
    const document = createTopologyDocumentFromServerGraph(id, topology);

    this.documents = [...this.documents, document];
    this.topologyBaselines = {
      ...this.topologyBaselines,
      [id]: topologyEditableStateKey(document.graph),
    };
    this.activeDocumentId = id;
  }

  updateTopologyDocument(
    id: string,
    change: Pick<TopologyDocument, "graph"> | Pick<TopologyDocument, "editor">,
  ) {
    this.documents = this.documents.map((document) =>
      document.type === "topology" && document.id === id
        ? {
            ...document,
            ...change,
            title: "graph" in change ? change.graph.title : document.title,
          }
        : document,
    );
  }

  closeDocument(id: string) {
    this.activeDocumentId = nextActiveDocumentId(
      this.documents,
      this.activeDocumentId,
      id,
    );
    this.documents = this.documents.filter((document) => document.id !== id);
    this.topologyBaselines = Object.fromEntries(
      Object.entries(this.topologyBaselines).filter(
        ([documentId]) => documentId !== id,
      ),
    );
  }

  applySavedTopology(
    documentId: string,
    topology: ServerTopologyGraph,
    submittedStateKey?: string,
  ) {
    const updated = applySavedTopologyToDocuments(
      this.documents,
      this.topologyBaselines,
      documentId,
      topology,
      submittedStateKey,
    );

    this.documents = updated.documents;
    this.topologyBaselines = updated.topologyBaselines;
  }
}

function selectedTopologyObject(document?: TopologyDocument) {
  const selectedId = document?.editor.selectedId;
  if (!document || !selectedId) return undefined;

  const node = document.graph.nodes.find(
    (candidate) => candidate.id === selectedId,
  );
  if (node) return { id: node.id, name: graphNodeLabel(node) };

  const edge = document.graph.edges.find(
    (candidate) => candidate.id === selectedId,
  );
  if (!edge) return undefined;

  const source = document.graph.nodes.find((node) => node.id === edge.fromId);
  const target = document.graph.nodes.find((node) => node.id === edge.toId);
  return {
    id: edge.id,
    name:
      source && target
        ? `${graphNodeLabel(source)} → ${graphNodeLabel(target)} (${graphTypeLabel(edge.type)})`
        : graphTypeLabel(edge.type),
  };
}
