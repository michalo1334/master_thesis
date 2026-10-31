defmodule NetworkDefense.Evaluation2.Study.Definition.Schema do
  @moduledoc false

  alias NetworkDefense.Evaluation2.Study.Error

  @path Application.app_dir(:network_defense, "priv/evaluation2/definition.schema.json")
  @external_resource @path
  @schema @path |> File.read!() |> Jason.decode!() |> ExJsonSchema.Schema.resolve()

  def validate(value) do
    case ExJsonSchema.Validator.validate(@schema, value, error_formatter: false) do
      :ok ->
        :ok

      {:error, _} ->
        {:error,
         error("invalid_definition", [], "The definition does not match the input schema.")}
    end
  end

  def error(code, path, message) do
    %Error{
      category: :validation_failed,
      issues: [%Error.Issue{code: code, path: path, message: message}]
    }
  end
end
