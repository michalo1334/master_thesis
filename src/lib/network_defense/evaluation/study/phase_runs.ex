defmodule NetworkDefense.Evaluation.Study.PhaseRuns do
  @moduledoc false
  import Ecto.Query

  alias NetworkDefense.Evaluation.Study.Contracts.StudyError
  alias NetworkDefense.Evaluation.{StudyPhase, StudyPhaseRun}
  alias NetworkDefense.Repo

  def get_or_create(%StudyPhase{id: phase_id}, tier, position)
      when is_binary(tier) and is_integer(position) and position >= 0 do
    if String.trim(tier) == "" do
      {:error, StudyError.invalid_tier()}
    else
      transaction(fn -> lock_and_create(phase_id, tier, position) end)
    end
  end

  def get_or_create(_, _, _), do: {:error, StudyError.phase_run_conflict()}

  defp lock_and_create(phase_id, tier, position) do
    case Repo.one(from p in StudyPhase, where: p.id == ^phase_id, lock: "FOR UPDATE") do
      nil -> Repo.rollback(StudyError.phase_run_storage_failed())
      _ -> create_or_find(phase_id, tier, position)
    end
  end

  defp create_or_find(phase_id, tier, position) do
    rows =
      Repo.all(
        from r in StudyPhaseRun,
          where:
            r.study_phase_id == ^phase_id and (r.tier == ^tier or r.tier_position == ^position)
      )

    case rows do
      [%StudyPhaseRun{tier: ^tier, tier_position: ^position} = row] ->
        row

      [] ->
        case Repo.insert(
               StudyPhaseRun.changeset(%StudyPhaseRun{}, %{
                 study_phase_id: phase_id,
                 tier: tier,
                 tier_position: position
               })
             ) do
          {:ok, row} -> row
          {:error, _} -> Repo.rollback(StudyError.phase_run_storage_failed())
        end

      _ ->
        Repo.rollback(StudyError.phase_run_conflict())
    end
  end

  def link_gust_run(%StudyPhaseRun{id: id}, run_id) when is_integer(run_id) and run_id > 0 do
    transaction(fn ->
      case Repo.one(from r in StudyPhaseRun, where: r.id == ^id, lock: "FOR UPDATE") do
        %StudyPhaseRun{gust_run_id: ^run_id} = row ->
          row

        %StudyPhaseRun{gust_run_id: nil} = row ->
          update_link(row, run_id)

        %StudyPhaseRun{} ->
          Repo.rollback(StudyError.phase_run_conflict())

        nil ->
          Repo.rollback(StudyError.phase_run_storage_failed())
      end
    end)
  end

  def link_gust_run(_, _), do: {:error, StudyError.phase_run_conflict()}

  defp update_link(row, run_id) do
    case Repo.update(StudyPhaseRun.changeset(row, %{gust_run_id: run_id})) do
      {:ok, linked} -> linked
      {:error, _} -> Repo.rollback(StudyError.phase_run_conflict())
    end
  end

  def ordered_for_phase(phase_id) do
    case Ecto.UUID.cast(phase_id) do
      {:ok, id} ->
        try do
          rows =
            Repo.all(
              from r in StudyPhaseRun, where: r.study_phase_id == ^id, order_by: r.tier_position
            )

          if complete_position_sequence?(rows) do
            {:ok, rows}
          else
            {:error, StudyError.phase_runs_incomplete()}
          end
        rescue
          _ in [DBConnection.ConnectionError, Postgrex.Error] ->
            {:error, StudyError.phase_run_storage_failed()}
        end

      :error ->
        {:error, StudyError.phase_run_storage_failed()}
    end
  end

  def ordered_run_ids(phase_id) do
    with {:ok, rows} <- ordered_for_phase(phase_id) do
      if Enum.all?(rows, &(is_integer(&1.gust_run_id) and &1.gust_run_id > 0)) do
        {:ok, Enum.map(rows, & &1.gust_run_id)}
      else
        {:error, StudyError.phase_runs_incomplete()}
      end
    end
  end

  defp complete_position_sequence?([]), do: false

  defp complete_position_sequence?(rows) do
    rows
    |> Enum.with_index()
    |> Enum.all?(fn {%StudyPhaseRun{tier_position: position}, index} -> position == index end)
  end

  defp transaction(fun) do
    Repo.transaction(fun)
  rescue
    _ in [DBConnection.ConnectionError, Postgrex.Error, Ecto.ConstraintError] ->
      {:error, StudyError.phase_run_storage_failed()}
  end
end
