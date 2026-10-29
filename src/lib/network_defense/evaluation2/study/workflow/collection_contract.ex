defmodule NetworkDefense.Evaluation2.Study.Workflow.CollectionContract do
  @moduledoc false

  # Shared codec of the two collection phase contracts.
  #
  # The macro defines only the input and output type aliases and the two codec
  # functions. The phase-specific `Input` and `Output` modules live in their own
  # files, so this one implementation is shared without duplicate source.
  #
  # Gust success is the completion fact, so every collection output stays empty.
  defmacro __using__(_options) do
    quote do
      alias __MODULE__.{Input, Output}

      @type input :: Input.t()
      @type output :: Output.t()

      @spec to_params(Input.t()) :: map()
      def to_params(%Input{phase_run_id: id}), do: %{"study_phase_run_id" => id}

      @spec decode_output!(map()) :: Output.t()
      def decode_output!(_params), do: %Output{}
    end
  end
end
