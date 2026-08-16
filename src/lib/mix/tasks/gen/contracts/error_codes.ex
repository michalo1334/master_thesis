defmodule Mix.Tasks.Gen.Contracts.ErrorCodes do
  @moduledoc false

  alias Mix.Tasks.Gen.Contracts.Renderer
  alias NetworkDefense.Errors

  def render do
    values = Enum.map(Errors.codes(), &"\"#{&1}\"")
    comment = Renderer.source_comment(Errors, "union of codes/0")

    "#{comment}\nexport type ErrorCode =\n  | " <> Enum.join(values, "\n  | ") <> ";"
  end
end
