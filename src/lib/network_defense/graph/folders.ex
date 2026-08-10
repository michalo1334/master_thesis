defmodule NetworkDefense.Graph.Folders do
  @moduledoc false

  import Ecto.Query

  alias Ecto.Changeset
  alias NetworkDefense.Graph.{Folder, Graph}
  alias NetworkDefense.Repo

  @type error ::
          :invalid_folder | :invalid_graph | :not_found | :folder_not_found | :internal_error

  @spec list() :: [Folder.t()]
  def list do
    Folder
    |> order_by([folder], asc: folder.name, asc: folder.id)
    |> Repo.all()
  end

  @spec create(String.t()) :: {:ok, Folder.t()} | {:error, error()}
  def create(name) when is_binary(name) do
    %Folder{}
    |> Folder.changeset(%{name: String.trim(name)})
    |> Repo.insert()
    |> normalize_persistence_error(:invalid_folder)
  end

  def create(_name), do: {:error, :invalid_folder}

  @spec delete(Ecto.UUID.t()) :: {:ok, Folder.t()} | {:error, error()}
  def delete(id) do
    with {:ok, id} <- Ecto.UUID.cast(id),
         %Folder{} = folder <- Repo.get(Folder, id) do
      folder
      |> Repo.delete()
      |> normalize_persistence_error(:internal_error)
    else
      :error -> {:error, :invalid_folder}
      nil -> {:error, :not_found}
    end
  end

  @spec move_graph(Ecto.UUID.t(), Ecto.UUID.t() | nil) ::
          {:ok, Graph.t()} | {:error, error()}
  def move_graph(graph_id, folder_id) do
    with {:ok, graph_id} <- Ecto.UUID.cast(graph_id),
         %Graph{} = graph <- Repo.get(Graph, graph_id),
         {:ok, folder_id} <- folder_id(folder_id) do
      graph
      |> Changeset.change(folder_id: folder_id)
      |> Repo.update()
      |> normalize_persistence_error(:internal_error)
    else
      :error -> {:error, :invalid_graph}
      nil -> {:error, :not_found}
      {:error, :invalid_folder} -> {:error, :invalid_folder}
      {:error, :folder_not_found} -> {:error, :folder_not_found}
    end
  end

  defp folder_id(nil), do: {:ok, nil}

  defp folder_id(id) do
    with {:ok, id} <- Ecto.UUID.cast(id),
         %Folder{} <- Repo.get(Folder, id) do
      {:ok, id}
    else
      :error -> {:error, :invalid_folder}
      nil -> {:error, :folder_not_found}
    end
  end

  defp normalize_persistence_error({:ok, entity}, _error), do: {:ok, entity}
  defp normalize_persistence_error({:error, _changeset}, error), do: {:error, error}
end
