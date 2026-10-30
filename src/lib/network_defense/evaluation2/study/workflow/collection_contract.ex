defmodule NetworkDefense.Evaluation2.Study.Workflow.CollectionContract do
  @moduledoc """
  Shared transport of the two collection phase contracts.

  The macro defines the input and output type aliases and the codec functions.
  The phase-specific `Input` and `Output` modules live in their own files, so one
  implementation serves both collection phases.

  The transport is strict, because a stored run input and a stored terminal
  result cross the Gust JSON boundary:

    * the run input carries one canonical phase-run UUID under
      `"study_phase_run_id"`;
    * the terminal output is the empty object, because the collection phase owns
      its snapshot and Gust success is the completion fact.

  Any other input or output value fails.
  """
  defmacro __using__(_options) do
    quote do
      alias __MODULE__.{Input, Output}

      @type input :: Input.t()
      @type output :: Output.t()

      @doc """
      Encode the root input of one collection run as JSON-safe run parameters.
      """
      @spec to_params(Input.t()) :: %{required(String.t()) => String.t()}
      def to_params(%Input{phase_run_id: phase_run_id}),
        do: %{"study_phase_run_id" => phase_run_id}

      @doc """
      Decode the stored input of one collection run.

      Only the canonical lower-case UUID form of the phase run is accepted, so a
      decoded input names exactly one stored phase run.
      """
      @spec decode_input(map()) :: {:ok, Input.t()} | :error
      def decode_input(%{"study_phase_run_id" => phase_run_id}) when is_binary(phase_run_id) do
        case Ecto.UUID.cast(phase_run_id) do
          {:ok, ^phase_run_id} -> {:ok, %Input{phase_run_id: phase_run_id}}
          _not_canonical -> :error
        end
      end

      def decode_input(_params), do: :error

      @doc """
      Decode the stored terminal result of one collection run.

      The empty Pilot and Final collection outputs accept the empty object only.
      """
      @spec decode_output(map()) :: {:ok, Output.t()} | :error
      def decode_output(params) when map_size(params) == 0, do: {:ok, %Output{}}
      def decode_output(_params), do: :error

      @doc false
      @spec decode_output!(map()) :: Output.t()
      def decode_output!(params) do
        {:ok, output} = decode_output(params)
        output
      end
    end
  end
end
