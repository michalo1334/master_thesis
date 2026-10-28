defmodule NetworkDefense.Evaluation.Study.Pipeline.GustAdapter do
  @moduledoc false

  alias NetworkDefense.Evaluation.Study.Pipeline.Failure

  @callback decode(keyword(), map()) :: {:ok, term()} | {:error, Failure.t()}
  @callback encode(term()) :: map()

  defmacro __using__(options) do
    step = Keyword.fetch!(options, :step)

    quote bind_quoted: [step: step] do
      @behaviour Gust.Action
      @behaviour NetworkDefense.Evaluation.Study.Pipeline.GustAdapter

      alias NetworkDefense.Evaluation.Study.Pipeline.Failure

      @step step

      @impl Gust.Action
      def execute(args, context) do
        with {:ok, io} <- decode(args, context),
             {:ok, next_io} <- @step.run(io) do
          encode(next_io)
        else
          {:error, error} -> Failure.raise_permanent(error)
        end
      end
    end
  end
end

defmodule NetworkDefense.Evaluation.Study.Pipeline.GustCallback do
  @moduledoc false

  defmacro __using__(_options) do
    quote do
      alias NetworkDefense.Evaluation.Study.Pipeline.GustNotifier

      def notify_waiters(_status, %{id: run_id}) do
        GustNotifier.notify(run_id)
      rescue
        _exception -> :ok
      catch
        _kind, _reason -> :ok
      end

      def notify_waiters(_status, _run), do: :ok
    end
  end
end
