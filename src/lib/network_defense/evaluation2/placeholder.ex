defmodule NetworkDefense.Evaluation2.Placeholder do
  @moduledoc false

  # Bounded placeholder value of an unimplemented study operation.
  #
  # A supported operation returns an `:unavailable` error instead of raising, so
  # the supported error type stays exact and a caller still receives a bounded
  # failure. The issue code states that the operation is not implemented yet, and
  # the operation name stays internal.
  #
  # Constructor reads and bang operations raise
  # `NetworkDefense.Evaluation2.NotImplementedError` instead, because their
  # declared type has no error member.

  alias NetworkDefense.Evaluation2.Study.Error

  @spec error(atom()) :: Error.t()
  def error(_function) do
    %Error{
      category: :unavailable,
      issues: [
        %Error.Issue{
          code: "not_implemented",
          path: [],
          message: "The study operation is not implemented."
        }
      ]
    }
  end
end
