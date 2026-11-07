defmodule NetworkDefenseWeb.StudyContract do
  @moduledoc false
  import Ecto.Changeset
  alias NetworkDefenseWeb.Contracts.Dashboard.Study.Vocabulary

  defmacro __using__(opts) do
    fields = Keyword.fetch!(opts, :enums)

    quote do
      use NetworkDefenseWeb.Contracts, category: :study

      def contract_meta,
        do: Vocabulary.for_fields(unquote(fields))
    end
  end

  def changeset(%module{} = schema, attrs) do
    embeds = module.__schema__(:embeds)
    fields = (module.__schema__(:fields) ++ module.__schema__(:virtual_fields)) -- embeds

    Enum.reduce(embeds, cast(schema, attrs, fields, empty_values: []), fn field, changeset ->
      cast_embed(changeset, field)
    end)
  end
end
