defmodule NetworkDefense.Evaluation.Study.Pipeline.GustAdapter do
  @moduledoc false

  alias NetworkDefense.Evaluation.Study.Contracts.StudyError
  alias NetworkDefense.Evaluation.Study.Pipeline.Failure

  # Transport boundary for one pipeline task.
  #
  # The adapter owns only the Gust contract: persistable arguments in, stage IO
  # through the domain function, a compact persistable result out. Graph edges
  # stay in the checked-in DAG.
  #
  # Options:
  #
  #   * `:step` — the domain module that exports `run/1`.
  #   * `:failures` — the module that turns a domain error into a Gust failure.
  #     The default is `Pipeline.Failure`, which encodes bounded study errors.
  #     A step that returns `{:error, :temporary, error}` needs a module that
  #     also exports `raise_retryable/1`, because that input can succeed later.
  #
  # A step returns `{:ok, next}`, `{:error, error}` for a permanent failure, or
  # `{:error, {:temporary, error}}` for a retryable one.
  @callback decode(keyword(), map()) :: {:ok, term()} | {:error, term()}
  @callback encode(term()) :: map()

  defmacro __using__(options) do
    step = Keyword.fetch!(options, :step)
    failures = Keyword.get(options, :failures, Failure)

    quote do
      alias NetworkDefense.Evaluation.Study.Pipeline.GustAdapter

      @behaviour Gust.Action
      @behaviour GustAdapter

      @failures unquote(failures)
      @step unquote(step)

      @impl Gust.Action
      def execute(args, context) do
        with {:ok, io} <- decode(args, context),
             {:ok, next_io} <- @step.run(io) do
          encode(next_io)
        else
          {:error, reason} -> GustAdapter.raise_failure(@failures, reason)
        end
      end
    end
  end

  # The single failure boundary of every generated adapter.
  #
  # The adapter passes its failure module as a value, so this one function keeps
  # all four outcomes reachable for Dialyzer. A generated per-adapter copy is
  # specialized at each call site, which makes some clauses unreachable there.
  @spec raise_failure(module(), term()) :: no_return()
  def raise_failure(_failures, %StudyError{} = error), do: Failure.raise_permanent(error)

  def raise_failure(failures, {:permanent, error}), do: failures.raise_permanent(error)

  def raise_failure(failures, {:temporary, error}), do: failures.raise_retryable(error)

  def raise_failure(failures, error), do: failures.raise_permanent(error)
end
