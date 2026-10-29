defmodule NetworkDefense.Evaluation2.Study.Revision do
  @moduledoc """
  Declared identity of one frozen study revision.

  The value holds the study identifier and the revision number of the YAML
  definition. Internal storage keeps a UUID for its foreign keys; operators and
  Mix tasks refer to a revision by the declared pair.
  """

  @typedoc "Revision number of one study definition."
  @type revision :: pos_integer()

  @type t :: %__MODULE__{
          study_id: String.t(),
          revision: revision()
        }

  defstruct [:study_id, :revision]
end
