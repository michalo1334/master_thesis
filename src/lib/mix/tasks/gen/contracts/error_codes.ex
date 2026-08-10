defmodule Mix.Tasks.Gen.Contracts.ErrorCodes do
  @moduledoc false

  alias NetworkDefense.Errors

  def render do
    values = Enum.map(Errors.codes(), &"\"#{&1}\"")

    "export type ErrorCode =\n  | " <> Enum.join(values, "\n  | ") <> ";"
  end
end
