defmodule Mix.Tasks.Evaluate.Options do
  @moduledoc false

  @spec validate(keyword(), [String.t()], keyword(), [atom()]) :: :ok | {:error, String.t()}
  def validate(options, [], [], required_options) do
    Enum.find_value(required_options, :ok, fn option ->
      if is_nil(options[option]) do
        flag = option |> Atom.to_string() |> String.replace("_", "-")
        {:error, "missing required option --#{flag}"}
      end
    end)
  end

  def validate(_options, positional, invalid, _required_options) do
    invalid_options = Enum.map(invalid, fn {option, _value} -> to_string(option) end)
    {:error, "invalid options: #{Enum.join(positional ++ invalid_options, ", ")}"}
  end
end
