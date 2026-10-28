defmodule NetworkDefense.Evaluation.Study.Pipeline.GustCallback do
  @moduledoc false

  # Completion callbacks are wake-up signals only. The persisted Gust run
  # remains authoritative, so a failed notification cannot change a result.
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
