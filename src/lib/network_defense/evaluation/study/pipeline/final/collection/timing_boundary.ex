defmodule NetworkDefense.Evaluation.Study.Pipeline.Final.Collection.TimingBoundary do
  @moduledoc false

  alias NetworkDefense.Evaluation.Study.Contracts.StudyError
  alias NetworkDefense.Evaluation.Study.Pipeline.Final.Collection.IO

  # One measured timing boundary.
  #
  # The coordinator owns the recorder, so the boundary only announces itself and
  # waits for its acknowledgement. The announcement carries the boundary
  # identity; the acknowledgement decides whether the run continues.
  @ack_timeout 5_000

  @spec run(IO.Marker.t()) :: {:ok, IO.Marker.t()} | {:error, StudyError.t()}
  def run(%IO.Marker{} = marker) do
    with :ok <- announce(marker), do: {:ok, marker}
  end

  defp announce(%IO.Marker{
         execution_id: execution_id,
         phase_run_id: phase_run_id,
         replica_position: position,
         event_kind: event_kind
       }) do
    marker_ref = make_ref()
    marker_pid = self()

    case Registry.lookup(
           NetworkDefense.Evaluation.Study.Pipeline.CoordinatorRegistry,
           execution_id
         ) do
      [{coordinator, _value} | _] when is_pid(coordinator) ->
        send(
          coordinator,
          {:final_timing_boundary, marker_ref, execution_id, phase_run_id, position, event_kind,
           marker_pid}
        )

        receive do
          {:final_timing_boundary_ack, ^marker_ref, :ok} ->
            :ok

          {:final_timing_boundary_ack, ^marker_ref, {:error, %StudyError{} = error}} ->
            {:error, error}

          {:final_timing_boundary_ack, ^marker_ref, {:error, _reason}} ->
            {:error, StudyError.final_timing_invalid()}
        after
          @ack_timeout -> {:error, StudyError.final_timing_unavailable()}
        end

      _ ->
        {:error, StudyError.final_timing_unavailable()}
    end
  rescue
    ArgumentError -> {:error, StudyError.final_timing_unavailable()}
  catch
    :exit, _reason -> {:error, StudyError.final_timing_unavailable()}
  end

  defmodule Gust do
    @moduledoc false

    use NetworkDefense.Evaluation.Study.Pipeline.GustAdapter,
      step: NetworkDefense.Evaluation.Study.Pipeline.Final.Collection.TimingBoundary

    alias NetworkDefense.Evaluation.Study.Pipeline.Final.Collection.IO
    alias NetworkDefense.Evaluation.Study.Pipeline.GustAdapter

    @impl GustAdapter
    def decode(args, %{run_id: run_id}) when is_list(args) do
      IO.load_marker(
        run_id,
        Keyword.get(args, :replica_position),
        Keyword.get(args, :event_kind)
      )
    end

    @impl GustAdapter
    def encode(%IO.Marker{phase_run_id: phase_run_id, replica_position: position}) do
      %{"study_phase_run_id" => phase_run_id, "replica_position" => position}
    end
  end
end
