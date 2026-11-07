defmodule NetworkDefenseWeb.Contracts.Dashboard.Study.Issue do
  @moduledoc false
  use NetworkDefenseWeb.Contracts, category: :study

  embedded_schema do
    field :code, :string
    field :path, :any, virtual: true
    field :message, :string
  end

  @type t :: %__MODULE__{
          code: String.t(),
          path: [String.t() | non_neg_integer()],
          message: String.t()
        }

  def changeset(schema, attrs) do
    NetworkDefenseWeb.StudyContract.changeset(schema, attrs)
    |> validate_change(:path, fn :path, value ->
      if is_list(value) and Enum.all?(value, &(is_binary(&1) or (is_integer(&1) and &1 >= 0))),
        do: [],
        else: [path: "must contain field names or indexes"]
    end)
  end
end
