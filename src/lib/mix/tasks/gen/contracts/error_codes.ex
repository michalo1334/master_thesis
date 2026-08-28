defmodule Mix.Tasks.Gen.Contracts.ErrorCodes do
  @moduledoc false

  alias Mix.Tasks.Gen.Contracts.Renderer
  alias NetworkDefense.Errors

  def render do
    values = Enum.map(Errors.codes(), &"\"#{&1}\"")
    comment = Renderer.source_comment(Errors, "union of codes/0")

    body = "export type ErrorCode =\n  | " <> Enum.join(values, "\n  | ") <> ";"

    "#{comment}\n" <> Renderer.namespaced(Renderer.module_namespace(Errors), body)
  end
end
