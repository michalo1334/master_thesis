defmodule NetworkDefense.Evaluation.ContractSupport do
  @moduledoc false

  # Shared issue shape and mixed string/index path order. Owners keep their
  # validation rules, diagnostic order, and output limits.
  def issue(code, path, message, details \\ %{}) do
    %{"code" => code, "path" => path, "message" => message, "details" => details}
  end

  def path_sort_key(path) do
    Enum.map(path, fn
      value when is_binary(value) -> {0, value}
      value when is_integer(value) -> {1, value}
    end)
  end
end
