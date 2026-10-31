defmodule NetworkDefense.Evaluation2.Placeholder do
  @moduledoc false

  # Historical scaffold helper retained until the verification/deletion gate.
  # Supported Study operations use the implemented native path. This helper is
  # outside that supported interface.

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
