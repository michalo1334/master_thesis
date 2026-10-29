defmodule NetworkDefense.Evaluation2.Contracts.CollectionPhaseContract do
  @moduledoc false

  # Generate distinct contract types from one source to avoid duplicate codecs.
  # Gust success is the completion fact, so collection outputs are empty.
  defmacro __using__(_options) do
    quote do
      defmodule Input do
        @moduledoc false
        @type t :: %__MODULE__{phase_run_id: Ecto.UUID.t()}
        defstruct [:phase_run_id]
      end

      defmodule Output do
        @moduledoc false
        @type t :: %__MODULE__{}
        defstruct []
      end

      @type input :: Input.t()
      @type output :: Output.t()

      @spec to_params(Input.t()) :: map()
      def to_params(%Input{phase_run_id: id}), do: %{"study_phase_run_id" => id}

      @spec decode_output!(map()) :: Output.t()
      def decode_output!(_params), do: %Output{}
    end
  end
end
