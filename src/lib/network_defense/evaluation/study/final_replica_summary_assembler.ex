defmodule NetworkDefense.Evaluation.Study.FinalReplicaSummaryAssembler do
  @moduledoc false

  import Ecto.Query

  alias NetworkDefense.Actions.{AcquireCredential, AttemptedAction, ExploitVulnerability}
  alias NetworkDefense.Actions.ReuseCredential
  alias NetworkDefense.AttackerState.AttackerState
  alias NetworkDefense.Evaluation.Study.{Collection, RunIdentity}
  alias NetworkDefense.Evaluation.Study.Contracts.CollectionWorkItem
  alias NetworkDefense.Evaluation.Study.Contracts.Definition
  alias NetworkDefense.Evaluation.Study.Contracts.StudyError
  alias NetworkDefense.Evaluation.Study.Timing.FinalReplicaSummary
  alias NetworkDefense.Evaluation.{StudyCollectionItem, StudyExecution, StudyPhase}
  alias NetworkDefense.Graph.Contracts.{Edge, Node, NodeViewData}
  alias NetworkDefense.Graph.Graph
  alias NetworkDefense.Graph.Graphs
  alias NetworkDefense.Optimization.Contracts.OptimizationParams
  alias NetworkDefense.Optimization.ExecutionConfig
  alias NetworkDefense.Optimization.{OptimizationAction, OptimizationRun}
  alias NetworkDefense.Repo
  alias NetworkDefense.Simulation.{Experiment, Experiments, MissionImpact, Run}

  @measured_positions 0..4

  # Builds one complete-family scientific summary for one measured replica
  # position.
  #
  # Scientific equality must not depend on Gust task payloads or runtime record
  # identifiers, so this boundary reads the authoritative PostgreSQL rows and
  # converts them into the typed summary contract. One stored collection item
  # row carries one canonical work item, so the number of rows, their positions,
  # and their identity all follow from the immutable definition and the frozen
  # selection.

  @spec assemble(StudyPhase.t(), Definition.t(), 0..4) ::
          {:ok, FinalReplicaSummary.t(), [StudyCollectionItem.t()]}
          | {:error, StudyError.t()}
  def assemble(%StudyPhase{} = phase, %Definition{} = definition, position)
      when position in @measured_positions do
    with {:ok, stored} <- stored_phase(phase),
         {:ok, work} <- canonical_work(stored, definition, position),
         {:ok, pairs} <- ordered_items(stored, work, position),
         {:ok, summary} <- summary(pairs, definition) do
      {:ok, summary, Enum.map(pairs, &elem(&1, 1))}
    end
  end

  def assemble(_phase, _definition, _position),
    do: {:error, StudyError.final_replica_summary_invalid()}

  defp stored_phase(%StudyPhase{id: phase_id}) do
    with {:ok, id} <- Ecto.UUID.cast(phase_id),
         %StudyPhase{phase: :final_collection} = stored <- Repo.get(StudyPhase, id) do
      {:ok, stored}
    else
      _invalid -> {:error, StudyError.invalid_study_phase()}
    end
  end

  defp canonical_work(%StudyPhase{} = phase, %Definition{} = definition, position) do
    case Repo.get(StudyExecution, phase.execution_id) do
      %StudyExecution{} = execution ->
        Collection.build_collection_work(execution, phase, definition, position)

      nil ->
        {:error, StudyError.invalid_study_phase()}
    end
  end

  defp ordered_items(%StudyPhase{id: phase_id} = phase, work, position) do
    rows =
      Repo.all(
        from item in StudyCollectionItem,
          where: item.study_phase_id == ^phase_id and item.replica_position == ^position,
          order_by: item.item_position
      )

    expected = Enum.map(work, & &1.item_position)

    cond do
      Enum.map(rows, & &1.item_position) != expected -> incomplete()
      not Enum.all?(rows, &canonical_item?(&1, phase, position)) -> incomplete()
      true -> {:ok, Enum.zip(work, rows)}
    end
  end

  defp canonical_item?(%StudyCollectionItem{} = item, %StudyPhase{id: phase_id}, position) do
    item.study_phase_id == phase_id and item.replica_position == position and
      is_integer(item.item_position) and item.item_position >= 0
  end

  defp summary(pairs, %Definition{} = definition) do
    result =
      Enum.reduce_while(pairs, {:ok, []}, fn {work, item}, {:ok, collected} ->
        case item_params(work, item, definition) do
          {:ok, params} -> {:cont, {:ok, [params | collected]}}
          {:error, %StudyError{} = error} -> {:halt, {:error, error}}
        end
      end)

    with {:ok, params} <- reverse(result) do
      case FinalReplicaSummary.new(%{items: params}) do
        {:ok, %FinalReplicaSummary{} = summary} -> {:ok, summary}
        {:error, _reason} -> {:error, StudyError.final_replica_summary_invalid()}
      end
    end
  end

  defp item_params(
         %CollectionWorkItem{} = work,
         %StudyCollectionItem{} = item,
         %Definition{} = definition
       ) do
    with {:ok, optimization} <- optimization(item),
         :ok <- validate_optimization(optimization, work),
         {:ok, actions} <- optimization_actions(optimization),
         {:ok, graph} <- output_graph(optimization),
         {:ok, experiment, runs} <- experiment(item),
         :ok <- validate_experiment(experiment, optimization, work, definition),
         :ok <- validate_runs(runs, experiment),
         {:ok, trials} <- trials(runs, graph),
         {:ok, canonical_graph} <- canonical_graph(graph) do
      {:ok,
       %{
         position: work.item_position,
         used_budget: optimization.used_budget,
         selected_actions: actions,
         output_graph: canonical_graph,
         pre_attack_capability_statuses:
           capability_statuses(MissionImpact.pre_attack_status(graph)),
         pre_attack_required_flow_statuses:
           flow_statuses(MissionImpact.required_flow_statuses(graph)),
         trials: trials
       }}
    end
  end

  defp optimization(%StudyCollectionItem{optimization_run_id: nil}), do: incomplete()

  defp optimization(%StudyCollectionItem{optimization_run_id: run_id}) do
    with {:ok, id} <- Ecto.UUID.cast(run_id),
         %OptimizationRun{} = run <- Repo.get(OptimizationRun, id) do
      {:ok, run}
    else
      _invalid -> incomplete()
    end
  end

  defp validate_optimization(%OptimizationRun{} = run, %CollectionWorkItem{} = work) do
    if completed_output?(run) and optimization_identity_matches?(run, work) and
         optimization_budget_matches?(run, work) and
         execution_config_matches?(run.execution_config, work) do
      :ok
    else
      incomplete()
    end
  end

  defp completed_output?(%OptimizationRun{} = run) do
    run.status == "completed" and is_binary(run.output_graph_revision_id) and
      run.output_graph_revision_id != ""
  end

  defp optimization_identity_matches?(%OptimizationRun{} = run, %CollectionWorkItem{} = work) do
    run.graph_revision_id == work.graph_revision_id and
      run.strategy == work.strategy.key and
      run.seed == work.selection_seed
  end

  defp optimization_budget_matches?(%OptimizationRun{} = run, %CollectionWorkItem{} = work) do
    run.requested_budget == work.budget and is_integer(run.used_budget) and run.used_budget >= 0
  end

  defp execution_config_matches?(%ExecutionConfig{} = config, %CollectionWorkItem{} = work) do
    strategy = work.strategy

    config.candidate_action_types == strategy.candidate_action_types and
      config.require_pre_attack_feasibility == strategy.require_pre_attack_feasibility and
      config.initial_foothold_node_id == expected_foothold(work) and
      scoring_matches?(config.scoring, strategy.scoring)
  end

  defp execution_config_matches?(_config, _work), do: false

  defp expected_foothold(%CollectionWorkItem{} = work) do
    if OptimizationParams.requires_initial_foothold?(work.strategy.key),
      do: work.initial_foothold_node_id
  end

  defp scoring_matches?(nil, nil), do: true
  defp scoring_matches?(nil, _declared), do: false
  defp scoring_matches?(_stored, nil), do: false

  defp scoring_matches?(stored, declared) do
    stored.objective == declared.objective and
      stored.monte_carlo_trials == declared.monte_carlo_trials and
      stored.iterations_per_run == declared.iterations_per_run and
      stored.max_attempts == declared.max_attempts and
      stored.rules == declared.rules
  end

  defp optimization_actions(%OptimizationRun{id: run_id}) do
    actions =
      Repo.all(
        from action in OptimizationAction,
          where: action.optimization_run_id == ^run_id,
          order_by: action.position
      )

    if contiguous?(Enum.map(actions, & &1.position), 1) do
      {:ok,
       Enum.map(actions, fn action ->
         %{
           position: action.position,
           action_type: action.action_type,
           target_id: action.target_id,
           cost: action.cost
         }
       end)}
    else
      incomplete()
    end
  end

  defp output_graph(%OptimizationRun{output_graph_revision_id: revision_id}) do
    case Graphs.load_revision(revision_id) do
      %Graph{} = graph -> {:ok, graph}
      _missing -> incomplete()
    end
  end

  defp experiment(%StudyCollectionItem{experiment_id: nil}), do: incomplete()

  defp experiment(%StudyCollectionItem{experiment_id: experiment_id}) do
    with {:ok, id} <- Ecto.UUID.cast(experiment_id),
         %Experiment{runs: runs} = experiment when is_list(runs) <- Experiments.load(id) do
      {:ok, experiment, Enum.sort_by(runs, & &1.trial_index)}
    else
      _invalid -> incomplete()
    end
  end

  defp validate_experiment(
         %Experiment{} = experiment,
         %OptimizationRun{} = run,
         %CollectionWorkItem{} = work,
         %Definition{} = definition
       ) do
    if completed_experiment?(experiment, run) and experiment_counts_match?(experiment, work) and
         experiment_settings_match?(experiment, definition) do
      :ok
    else
      incomplete()
    end
  end

  defp completed_experiment?(%Experiment{} = experiment, %OptimizationRun{} = run) do
    experiment.status == :completed and
      experiment.graph_revision_id == run.output_graph_revision_id
  end

  defp experiment_counts_match?(%Experiment{} = experiment, %CollectionWorkItem{} = work) do
    experiment.master_seed == work.evaluation_root and
      experiment.total_trials == work.attack_count and
      experiment.completed_trials == experiment.total_trials and
      experiment.iteration_count == work.iterations_per_run and
      experiment.max_attempts == work.max_attempts and
      experiment.initial_foothold_node_id == work.initial_foothold_node_id
  end

  defp experiment_settings_match?(%Experiment{} = experiment, %Definition{} = definition) do
    experiment.rules == definition.simulation.rules and
      experiment.require_pre_attack_feasibility ==
        definition.simulation.require_pre_attack_feasibility
  end

  defp validate_runs(runs, %Experiment{} = experiment) do
    cond do
      length(runs) != experiment.total_trials ->
        incomplete()

      Enum.map(runs, & &1.trial_index) != indices(experiment.total_trials) ->
        incomplete()

      not Enum.all?(runs, &RunIdentity.owned_by_experiment?(&1, experiment)) ->
        incomplete()

      not Enum.all?(runs, &RunIdentity.derived_seed?(&1, experiment)) ->
        incomplete()

      not Enum.all?(runs, &complete_run?/1) ->
        incomplete()

      true ->
        :ok
    end
  end

  defp complete_run?(%Run{initial_attacker_state: %AttackerState{}, iterations: iterations})
       when is_list(iterations) do
    contiguous?(Enum.map(iterations, & &1.index), 1) and
      Enum.all?(iterations, fn iteration ->
        match?(%AttackerState{}, iteration.attacker_state) and
          is_boolean(iteration.success?) and
          attempted_action_present?(iteration.attempted_action)
      end)
  end

  defp complete_run?(_run), do: false

  defp attempted_action_present?(nil), do: true

  defp attempted_action_present?(%AttemptedAction{action_type: type, attempt_count: count})
       when is_binary(type) and is_integer(count) and count >= 0,
       do: true

  defp attempted_action_present?(_action), do: false

  defp trials(runs, %Graph{} = graph) do
    runs
    |> Enum.reduce_while({:ok, []}, fn run, {:ok, collected} ->
      case trial(run, graph) do
        {:ok, trial} -> {:cont, {:ok, [trial | collected]}}
        {:error, %StudyError{} = error} -> {:halt, {:error, error}}
      end
    end)
    |> reverse()
  end

  defp trial(%Run{} = run, %Graph{} = graph) do
    with {:ok, steps} <- attack_steps(run),
         {:ok, initial_state, _initial_footholds} <-
           attacker_state(run.initial_attacker_state),
         {:ok, final_state, final_footholds} <-
           attacker_state(Run.current_attacker_state(run)) do
      {:ok,
       %{
         position: run.trial_index - 1,
         seed: run.seed,
         initial_state: initial_state,
         steps: steps,
         final_state: final_state,
         capability_outcomes:
           capability_statuses(MissionImpact.capability_statuses(graph, final_footholds))
       }}
    end
  end

  defp attack_steps(%Run{iterations: iterations}) when is_list(iterations) do
    iterations
    |> Enum.sort_by(& &1.index)
    |> Enum.reduce_while({:ok, []}, fn iteration, {:ok, collected} ->
      case attack_step(iteration) do
        {:ok, step} -> {:cont, {:ok, [step | collected]}}
        {:error, %StudyError{} = error} -> {:halt, {:error, error}}
      end
    end)
    |> reverse()
  end

  defp attack_steps(_run), do: incomplete()

  defp attack_step(iteration) do
    with {:ok, action} <- attack_action(iteration.attempted_action) do
      {:ok,
       %{
         index: iteration.index,
         success?: iteration.success?,
         action: action
       }}
    end
  end

  defp attack_action(nil), do: {:ok, nil}

  defp attack_action(%AttemptedAction{} = attempted) do
    case attempted_action_struct(attempted) do
      %ExploitVulnerability{} = action ->
        {:ok, attack_action_attrs(:exploit_vulnerability, attempted, action)}

      %AcquireCredential{} = action ->
        {:ok, attack_action_attrs(:acquire_credential, attempted, action)}

      %ReuseCredential{} = action ->
        {:ok, attack_action_attrs(:reuse_credential, attempted, action)}

      _unsupported ->
        incomplete()
    end
  end

  defp attack_action(_action), do: incomplete()

  defp attempted_action_struct(%AttemptedAction{} = attempted) do
    AttemptedAction.action(attempted)
  rescue
    _exception -> nil
  end

  defp attack_action_attrs(kind, %AttemptedAction{attempt_count: count}, action) do
    %{
      kind: kind,
      attempt_count: count,
      source_host_id: Map.get(action, :source_host_id),
      target_host_id: Map.get(action, :target_host_id),
      host_id: Map.get(action, :host_id),
      service_id: Map.get(action, :service_id),
      vulnerability_node_id: Map.get(action, :vulnerability_node_id),
      credential_id: Map.get(action, :credential_id),
      success_probability: Map.get(action, :success_probability),
      required_privilege: Map.get(action, :required_privilege),
      granted_privilege: Map.get(action, :granted_privilege),
      supporting_edge_ids: action |> Map.get(:supporting_edge_ids, []) |> Enum.sort()
    }
  end

  defp attacker_state(%AttackerState{} = state) do
    foothold_ids = state |> AttackerState.foothold_nodes() |> Enum.uniq() |> Enum.sort()

    footholds =
      Enum.map(foothold_ids, fn host_id ->
        %{host_id: host_id, privilege: privilege(state, host_id)}
      end)

    credentials = state.credential_ids |> Enum.uniq() |> Enum.sort()

    {:ok, %{footholds: footholds, credential_ids: credentials}, foothold_ids}
  end

  defp attacker_state(_state), do: incomplete()

  defp privilege(%AttackerState{privileges: privileges}, host_id) when is_map(privileges) do
    case Map.get(privileges, host_id, "none") do
      "none" -> :none
      "user" -> :user
      "administrator" -> :administrator
      _other -> :none
    end
  end

  defp privilege(_state, _host_id), do: :none

  defp capability_statuses(statuses) do
    statuses
    |> Enum.map(&%{capability_id: &1.capability_id, down?: &1.down?})
    |> Enum.sort_by(& &1.capability_id)
  end

  defp flow_statuses(statuses) do
    statuses
    |> Enum.map(fn status ->
      %{
        capability_id: status.capability_id,
        source_segment_id: status.source_segment_id,
        target_service_id: status.target_service_id,
        available?: status.available?
      }
    end)
    |> Enum.sort_by(&{&1.capability_id, &1.source_segment_id, &1.target_service_id})
  end

  defp canonical_graph(%Graph{} = graph) do
    with {:ok, nodes} <- canonical_nodes(graph),
         {:ok, edges} <- canonical_edges(graph) do
      {:ok, %{nodes: nodes, edges: edges}}
    end
  end

  defp canonical_nodes(%Graph{} = graph) do
    graph
    |> Graph.nodes()
    |> Enum.sort_by(& &1.id)
    |> Enum.reduce_while({:ok, []}, fn node, {:ok, collected} ->
      case canonical_node(node) do
        {:ok, projected} -> {:cont, {:ok, [projected | collected]}}
        {:error, %StudyError{} = error} -> {:halt, {:error, error}}
      end
    end)
    |> reverse()
  end

  defp canonical_node(node) do
    case Node.from_domain(node) do
      {:ok, contract} ->
        {:ok,
         contract
         |> Map.put(:view_data, %NodeViewData{x_pos: 0.0, y_pos: 0.0, radius: nil})
         |> Node.to_wire()}

      _invalid ->
        incomplete()
    end
  end

  defp canonical_edges(%Graph{} = graph) do
    graph
    |> Graph.edges()
    |> Enum.sort_by(& &1.id)
    |> Enum.reduce_while({:ok, []}, fn edge, {:ok, collected} ->
      case Edge.from_domain(edge) do
        {:ok, contract} -> {:cont, {:ok, [Edge.to_wire(contract) | collected]}}
        _invalid -> {:halt, incomplete()}
      end
    end)
    |> reverse()
  end

  defp indices(0), do: []
  defp indices(count), do: Enum.to_list(1..count)

  defp contiguous?([], _next), do: true
  defp contiguous?([next | rest], next), do: contiguous?(rest, next + 1)
  defp contiguous?(_values, _next), do: false

  defp incomplete, do: {:error, StudyError.final_replica_summary_invalid()}

  defp reverse({:ok, values}), do: {:ok, Enum.reverse(values)}
  defp reverse({:error, %StudyError{} = error}), do: {:error, error}
end
