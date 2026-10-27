defmodule NetworkDefense.Evaluation.Study.Timing.FinalReplicaSummary do
  @moduledoc false

  use Ecto.Schema

  import Ecto.Changeset

  alias NetworkDefense.Contracts

  alias NetworkDefense.Evaluation.Study.Timing.FinalReplicaSummary.{
    AttackAction,
    AttackerState,
    AttackStep,
    CanonicalGraph,
    CapabilityStatus,
    Foothold,
    Item,
    PlanAction,
    RequiredFlowStatus,
    Trial
  }

  alias NetworkDefense.Graph.Contracts.Node

  defmodule PlanAction do
    @moduledoc false

    use Ecto.Schema

    import Ecto.Changeset

    @primary_key false
    embedded_schema do
      field :position, :integer
      field :action_type, :string
      field :target_id, :string
      field :cost, :integer
    end

    @type t :: %__MODULE__{
            position: integer(),
            action_type: String.t(),
            target_id: String.t(),
            cost: non_neg_integer()
          }

    @spec changeset(t(), map()) :: Ecto.Changeset.t()
    def changeset(action, attrs) do
      action
      |> cast(attrs, [:position, :action_type, :target_id, :cost])
      |> validate_required([:position, :action_type, :target_id, :cost])
      |> validate_length(:action_type, min: 1)
      |> validate_length(:target_id, min: 1)
      |> validate_number(:position, greater_than: 0)
      |> validate_number(:cost, greater_than_or_equal_to: 0)
    end
  end

  defmodule CanonicalGraph do
    @moduledoc false

    use Ecto.Schema

    import Ecto.Changeset

    alias NetworkDefense.Graph.Contracts.{Edge, Node}

    @primary_key false
    embedded_schema do
      embeds_many :nodes, Node, on_replace: :delete
      embeds_many :edges, Edge, on_replace: :delete
    end

    @type t :: %__MODULE__{nodes: [Node.t()], edges: [Edge.t()]}

    @spec changeset(t(), map()) :: Ecto.Changeset.t()
    def changeset(graph, attrs) do
      graph
      |> cast(attrs, [])
      |> cast_embed(:nodes)
      |> cast_embed(:edges)
    end
  end

  defmodule CapabilityStatus do
    @moduledoc false

    use Ecto.Schema

    import Ecto.Changeset

    @primary_key false
    embedded_schema do
      field :capability_id, :string
      field :down?, :boolean, source: :down
    end

    @type t :: %__MODULE__{capability_id: String.t(), down?: boolean()}

    @spec changeset(t(), map()) :: Ecto.Changeset.t()
    def changeset(status, attrs) do
      status
      |> cast(attrs, [:capability_id, :down?])
      |> validate_required([:capability_id, :down?])
      |> validate_length(:capability_id, min: 1)
    end
  end

  defmodule RequiredFlowStatus do
    @moduledoc false

    use Ecto.Schema

    import Ecto.Changeset

    @primary_key false
    embedded_schema do
      field :capability_id, :string
      field :source_segment_id, :string
      field :target_service_id, :string
      field :available?, :boolean, source: :available
    end

    @type t :: %__MODULE__{
            capability_id: String.t(),
            source_segment_id: String.t(),
            target_service_id: String.t(),
            available?: boolean()
          }

    @spec changeset(t(), map()) :: Ecto.Changeset.t()
    def changeset(status, attrs) do
      status
      |> cast(attrs, [:capability_id, :source_segment_id, :target_service_id, :available?])
      |> validate_required([:capability_id, :source_segment_id, :target_service_id, :available?])
      |> validate_length(:capability_id, min: 1)
      |> validate_length(:source_segment_id, min: 1)
      |> validate_length(:target_service_id, min: 1)
    end
  end

  defmodule Foothold do
    @moduledoc false

    use Ecto.Schema

    import Ecto.Changeset

    @privileges [:none, :user, :administrator]

    @primary_key false
    embedded_schema do
      field :host_id, :string
      field :privilege, Ecto.Enum, values: @privileges
    end

    @type privilege :: :none | :user | :administrator

    @type t :: %__MODULE__{host_id: String.t(), privilege: privilege()}

    @spec changeset(t(), map()) :: Ecto.Changeset.t()
    def changeset(foothold, attrs) do
      foothold
      |> cast(attrs, [:host_id, :privilege])
      |> validate_required([:host_id, :privilege])
      |> validate_length(:host_id, min: 1)
    end
  end

  defmodule AttackerState do
    @moduledoc false

    use Ecto.Schema

    import Ecto.Changeset

    @primary_key false
    embedded_schema do
      embeds_many :footholds, Foothold, on_replace: :delete
      field :credential_ids, {:array, :string}, default: []
    end

    @type t :: %__MODULE__{footholds: [Foothold.t()], credential_ids: [String.t()]}

    @spec changeset(t(), map()) :: Ecto.Changeset.t()
    def changeset(state, attrs) do
      state
      |> cast(attrs, [:credential_ids])
      |> cast_embed(:footholds)
      |> validate_identifiers(:credential_ids)
    end

    defp validate_identifiers(changeset, field) do
      validate_change(changeset, field, fn _field, ids ->
        if Enum.all?(ids, &identifier?/1),
          do: [],
          else: [{field, "must contain identifiers"}]
      end)
    end

    defp identifier?(value), do: is_binary(value) and String.trim(value) != ""
  end

  defmodule AttackAction do
    @moduledoc false

    use Ecto.Schema

    import Ecto.Changeset

    @kinds [:exploit_vulnerability, :acquire_credential, :reuse_credential]
    @privileges [:none, :user, :administrator]
    @fields [
      :kind,
      :attempt_count,
      :source_host_id,
      :target_host_id,
      :host_id,
      :service_id,
      :vulnerability_node_id,
      :credential_id,
      :success_probability,
      :required_privilege,
      :granted_privilege,
      :supporting_edge_ids
    ]

    @primary_key false
    embedded_schema do
      field :kind, Ecto.Enum, values: @kinds
      field :attempt_count, :integer
      field :source_host_id, :string
      field :target_host_id, :string
      field :host_id, :string
      field :service_id, :string
      field :vulnerability_node_id, :string
      field :credential_id, :string
      field :success_probability, :float
      field :required_privilege, Ecto.Enum, values: @privileges
      field :granted_privilege, Ecto.Enum, values: @privileges
      field :supporting_edge_ids, {:array, :string}, default: []
    end

    @type kind :: :exploit_vulnerability | :acquire_credential | :reuse_credential
    @type privilege :: :none | :user | :administrator

    @type t :: %__MODULE__{
            kind: kind(),
            attempt_count: non_neg_integer(),
            source_host_id: String.t() | nil,
            target_host_id: String.t() | nil,
            host_id: String.t() | nil,
            service_id: String.t() | nil,
            vulnerability_node_id: String.t() | nil,
            credential_id: String.t() | nil,
            success_probability: float() | nil,
            required_privilege: privilege() | nil,
            granted_privilege: privilege() | nil,
            supporting_edge_ids: [String.t()]
          }

    @spec changeset(t(), map()) :: Ecto.Changeset.t()
    def changeset(action, attrs) do
      action
      |> cast(attrs, @fields)
      |> validate_required([:kind, :attempt_count, :supporting_edge_ids])
      |> validate_number(:attempt_count, greater_than_or_equal_to: 0)
      |> validate_identifiers(:supporting_edge_ids)
    end

    defp validate_identifiers(changeset, field) do
      validate_change(changeset, field, fn _field, ids ->
        if Enum.all?(ids, &identifier?/1),
          do: [],
          else: [{field, "must contain identifiers"}]
      end)
    end

    defp identifier?(value), do: is_binary(value) and String.trim(value) != ""
  end

  defmodule AttackStep do
    @moduledoc false

    use Ecto.Schema

    import Ecto.Changeset

    @primary_key false
    embedded_schema do
      field :index, :integer
      field :success?, :boolean, source: :success
      embeds_one :action, AttackAction, on_replace: :update
    end

    @type t :: %__MODULE__{
            index: pos_integer(),
            success?: boolean(),
            action: AttackAction.t() | nil
          }

    @spec changeset(t(), map()) :: Ecto.Changeset.t()
    def changeset(step, attrs) do
      step
      |> cast(attrs, [:index, :success?])
      |> cast_embed(:action)
      |> validate_required([:index, :success?])
      |> validate_number(:index, greater_than: 0)
    end
  end

  defmodule Trial do
    @moduledoc false

    use Ecto.Schema

    import Ecto.Changeset

    @primary_key false
    embedded_schema do
      field :position, :integer
      field :seed, :integer
      embeds_one :initial_state, AttackerState, on_replace: :update
      embeds_many :steps, AttackStep, on_replace: :delete
      embeds_one :final_state, AttackerState, on_replace: :update
      embeds_many :capability_outcomes, CapabilityStatus, on_replace: :delete
    end

    @type t :: %__MODULE__{
            position: non_neg_integer(),
            seed: non_neg_integer(),
            initial_state: AttackerState.t(),
            steps: [AttackStep.t()],
            final_state: AttackerState.t(),
            capability_outcomes: [CapabilityStatus.t()]
          }

    @spec changeset(t(), map()) :: Ecto.Changeset.t()
    def changeset(trial, attrs) do
      trial
      |> cast(attrs, [:position, :seed])
      |> cast_embed(:initial_state, required: true)
      |> cast_embed(:steps)
      |> cast_embed(:final_state, required: true)
      |> cast_embed(:capability_outcomes)
      |> validate_required([:position, :seed])
      |> validate_number(:position, greater_than_or_equal_to: 0)
      |> validate_number(:seed, greater_than_or_equal_to: 0)
    end
  end

  defmodule Item do
    @moduledoc false

    use Ecto.Schema

    import Ecto.Changeset

    @primary_key false
    embedded_schema do
      field :position, :integer
      field :used_budget, :integer
      embeds_many :selected_actions, PlanAction, on_replace: :delete
      embeds_one :output_graph, CanonicalGraph, on_replace: :update
      embeds_many :pre_attack_capability_statuses, CapabilityStatus, on_replace: :delete
      embeds_many :pre_attack_required_flow_statuses, RequiredFlowStatus, on_replace: :delete
      embeds_many :trials, Trial, on_replace: :delete
    end

    @type t :: %__MODULE__{
            position: non_neg_integer(),
            used_budget: non_neg_integer(),
            selected_actions: [PlanAction.t()],
            output_graph: CanonicalGraph.t(),
            pre_attack_capability_statuses: [CapabilityStatus.t()],
            pre_attack_required_flow_statuses: [RequiredFlowStatus.t()],
            trials: [Trial.t()]
          }

    @spec changeset(t(), map()) :: Ecto.Changeset.t()
    def changeset(item, attrs) do
      item
      |> cast(attrs, [:position, :used_budget])
      |> cast_embed(:selected_actions)
      |> cast_embed(:output_graph, required: true)
      |> cast_embed(:pre_attack_capability_statuses)
      |> cast_embed(:pre_attack_required_flow_statuses)
      |> cast_embed(:trials, required: true)
      |> validate_required([:position, :used_budget])
      |> validate_number(:position, greater_than_or_equal_to: 0)
      |> validate_number(:used_budget, greater_than_or_equal_to: 0)
      |> validate_length(:trials, min: 1)
    end
  end

  @primary_key false
  embedded_schema do
    embeds_many :items, Item, on_replace: :delete
  end

  @type t :: %__MODULE__{items: [Item.t()]}

  @type error :: :invalid_summary | :non_canonical_summary | :inconsistent_summary

  @spec changeset(t(), map()) :: Ecto.Changeset.t()
  def changeset(summary, attrs) do
    summary
    |> cast(attrs, [])
    |> cast_embed(:items, required: true)
    |> validate_length(:items, min: 1)
  end

  @spec new(map()) :: {:ok, t()} | {:error, error()}
  def new(attrs) when is_map(attrs) do
    case %__MODULE__{} |> changeset(attrs) |> apply_action(:validate) do
      {:ok, %__MODULE__{} = summary} -> validate_checked(summary)
      {:error, %Ecto.Changeset{}} -> {:error, :invalid_summary}
    end
  end

  def new(_attrs), do: {:error, :invalid_summary}

  @spec validate(t()) :: {:ok, t()} | {:error, error()}
  def validate(%__MODULE__{} = summary) do
    with {:ok, applied} <- recast(summary) do
      validate_checked(applied)
    end
  end

  def validate(_summary), do: {:error, :invalid_summary}

  # Rebuilds the changeset from an existing struct so stored values pass the same
  # shape validation as a freshly built summary. Ecto cannot cast an item list that
  # holds non-struct values, therefore that shape is rejected before conversion.
  defp recast(%__MODULE__{items: items} = summary) when is_list(items) do
    if Enum.all?(items, &match?(%Item{}, &1)),
      do: cast_existing(summary),
      else: {:error, :invalid_summary}
  end

  defp recast(_summary), do: {:error, :invalid_summary}

  defp cast_existing(summary) do
    params = Contracts.to_params(summary)

    case summary |> changeset(params) |> apply_action(:validate) do
      {:ok, %__MODULE__{} = applied} -> {:ok, applied}
      {:error, %Ecto.Changeset{}} -> {:error, :invalid_summary}
    end
  rescue
    _exception in [Ecto.CastError] -> {:error, :invalid_summary}
  end

  defp validate_checked(%__MODULE__{} = summary) do
    with :ok <- validate_items(summary),
         :ok <- validate_canonical(summary),
         :ok <- validate_consistency(summary) do
      {:ok, summary}
    end
  end

  defp validate_items(%__MODULE__{items: []}), do: {:error, :invalid_summary}
  defp validate_items(%__MODULE__{}), do: :ok

  defp validate_canonical(%__MODULE__{items: items}) do
    items
    |> Enum.with_index()
    |> Enum.all?(fn {item, index} -> canonical_item?(item, index) end)
    |> ok_or_error(:non_canonical_summary)
  end

  defp validate_consistency(%__MODULE__{items: items}) do
    items
    |> Enum.all?(&consistent_item?/1)
    |> ok_or_error(:inconsistent_summary)
  end

  defp ok_or_error(true, _error), do: :ok
  defp ok_or_error(false, error), do: {:error, error}

  defp canonical_item?(%Item{} = item, index) do
    item.position == index and
      contiguous?(Enum.map(item.selected_actions, & &1.position), 1) and
      canonical_graph?(item.output_graph) and
      sorted_unique?(Enum.map(item.pre_attack_capability_statuses, & &1.capability_id)) and
      sorted_unique?(Enum.map(item.pre_attack_required_flow_statuses, &flow_key/1)) and
      contiguous?(Enum.map(item.trials, & &1.position), 0) and
      unique?(Enum.map(item.trials, & &1.seed)) and
      Enum.all?(item.trials, &canonical_trial?/1)
  end

  defp canonical_trial?(%Trial{} = trial) do
    contiguous?(Enum.map(trial.steps, & &1.index), 1) and
      sorted_unique?(Enum.map(trial.capability_outcomes, & &1.capability_id)) and
      canonical_state?(trial.initial_state) and
      canonical_state?(trial.final_state) and
      Enum.all?(trial.steps, &canonical_step?/1)
  end

  defp canonical_step?(%AttackStep{action: nil}), do: true

  defp canonical_step?(%AttackStep{action: %AttackAction{supporting_edge_ids: edge_ids}}) do
    sorted_unique?(edge_ids)
  end

  defp canonical_state?(%AttackerState{} = state) do
    sorted_unique?(Enum.map(state.footholds, & &1.host_id)) and
      sorted_unique?(state.credential_ids)
  end

  defp canonical_graph?(%CanonicalGraph{} = graph) do
    sorted_unique?(Enum.map(graph.nodes, & &1.id)) and
      sorted_unique?(Enum.map(graph.edges, & &1.id)) and
      Enum.all?(graph.nodes, &canonical_view?/1)
  end

  defp canonical_view?(%Node{view_data: %{x_pos: x_pos, y_pos: y_pos, radius: radius}}) do
    x_pos == 0.0 and y_pos == 0.0 and is_nil(radius)
  end

  defp canonical_view?(_node), do: false

  defp consistent_item?(%Item{} = item) do
    selected_cost(item.selected_actions) == item.used_budget and
      Enum.all?(item.trials, &consistent_trial?/1)
  end

  defp consistent_trial?(%Trial{} = trial), do: Enum.all?(trial.steps, &consistent_step?/1)

  defp consistent_step?(%AttackStep{action: nil}), do: true

  defp consistent_step?(%AttackStep{action: %AttackAction{} = action}) do
    consistent_action?(action)
  end

  defp consistent_action?(%AttackAction{kind: :exploit_vulnerability} = action) do
    present?(action, [
      :source_host_id,
      :service_id,
      :vulnerability_node_id,
      :success_probability,
      :required_privilege,
      :granted_privilege
    ]) and blank?(action, [:credential_id, :host_id])
  end

  defp consistent_action?(%AttackAction{kind: :acquire_credential} = action) do
    present?(action, [:credential_id, :host_id]) and
      blank?(action, [
        :source_host_id,
        :target_host_id,
        :service_id,
        :vulnerability_node_id,
        :success_probability,
        :required_privilege,
        :granted_privilege
      ])
  end

  defp consistent_action?(%AttackAction{kind: :reuse_credential} = action) do
    present?(action, [
      :credential_id,
      :source_host_id,
      :target_host_id,
      :service_id,
      :granted_privilege
    ]) and
      blank?(action, [:host_id, :vulnerability_node_id, :success_probability, :required_privilege])
  end

  defp consistent_action?(%AttackAction{}), do: false

  defp present?(action, fields), do: Enum.all?(fields, &present_field?(action, &1))

  defp present_field?(action, field) do
    case Map.get(action, field) do
      nil -> false
      value when is_binary(value) -> String.trim(value) != ""
      _value -> true
    end
  end

  defp blank?(action, fields), do: Enum.all?(fields, &is_nil(Map.get(action, &1)))

  defp selected_cost(actions), do: actions |> Enum.map(& &1.cost) |> Enum.sum()

  defp flow_key(%RequiredFlowStatus{} = status) do
    {status.capability_id, status.source_segment_id, status.target_service_id}
  end

  defp contiguous?([], _next), do: true
  defp contiguous?([next | rest], next), do: contiguous?(rest, next + 1)
  defp contiguous?(_values, _next), do: false

  defp unique?(values), do: length(Enum.uniq(values)) == length(values)

  defp sorted_unique?(values), do: Enum.sort(Enum.uniq(values)) == values
end
