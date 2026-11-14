defmodule NetworkDefense.Compute.OperationRegistry do
  @moduledoc false

  @otp_app :network_defense
  @config_key __MODULE__

  @type wire_name :: binary()

  @spec wire_name(module()) :: {:ok, wire_name()} | {:error, :unsupported_operation}
  def wire_name(operation_module) do
    with true <- valid_module?(operation_module),
         {name, _configured_module} <-
           Enum.find(operations(), &operation_entry?(&1, operation_module)) do
      {:ok, name}
    else
      _failure -> {:error, :unsupported_operation}
    end
  end

  @spec module(wire_name()) :: {:ok, module()} | {:error, :unknown_operation}
  def module(operation_name) do
    with true <- valid_wire_name?(operation_name),
         {:ok, operation_module} <- Map.fetch(operations(), operation_name),
         true <- valid_module?(operation_module) do
      {:ok, operation_module}
    else
      _failure -> {:error, :unknown_operation}
    end
  end

  defp operation_entry?({name, configured_module}, operation_module) do
    valid_wire_name?(name) and valid_module?(configured_module) and
      configured_module == operation_module
  end

  defp operations do
    @otp_app
    |> Application.get_env(@config_key, [])
    |> Keyword.get(:operations, %{})
    |> case do
      operations when is_map(operations) -> operations
      _invalid_operations -> %{}
    end
  end

  defp valid_wire_name?(name) when is_binary(name) do
    byte_size(name) in 1..255 and String.valid?(name)
  end

  defp valid_wire_name?(_name), do: false

  defp valid_module?(module) when is_atom(module) and not is_nil(module) do
    module
    |> Atom.to_string()
    |> String.starts_with?("Elixir.")
  end

  defp valid_module?(_module), do: false
end
