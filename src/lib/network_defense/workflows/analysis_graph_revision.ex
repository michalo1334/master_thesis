defmodule NetworkDefense.Workflows.AnalysisGraphRevision do
  use Ecto.Schema

  alias NetworkDefense.Graph.GraphRevision
  alias NetworkDefense.Workflows.WorkflowRun

  @primary_key false
  @foreign_key_type :binary_id

  schema "analysis_graph_revisions" do
    belongs_to :workflow_run, WorkflowRun, primary_key: true
    belongs_to :graph_revision, GraphRevision, primary_key: true
  end
end
