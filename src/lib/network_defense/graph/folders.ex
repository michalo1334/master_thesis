defmodule NetworkDefense.Graph.Folders do
  @moduledoc false

  import Ecto.Query

  alias Ecto.Changeset
  alias NetworkDefense.Graph.{Folder, Graph}
  alias NetworkDefense.Repo

  def list do
    Folder
    |> order_by([folder], asc: folder.name, asc: folder.id)
    |> Repo.all()
  end

  def create(name) when is_binary(name) do
    %Folder{}
    |> Folder.changeset(%{name: String.trim(name)})
    |> Repo.insert()
  end

  def create(_name), do: {:error, :invalid_folder}

  def delete(id) do
    with {:ok, id} <- Ecto.UUID.cast(id),
         %Folder{} = folder <- Repo.get(Folder, id) do
      Repo.delete(folder)
    else
      :error -> {:error, :invalid_folder}
      nil -> {:error, :not_found}
    end
  end

  def move_graph(graph_id, folder_id) do
    with {:ok, graph_id} <- Ecto.UUID.cast(graph_id),
         %Graph{} = graph <- Repo.get(Graph, graph_id),
         {:ok, folder_id} <- folder_id(folder_id) do
      graph
      |> Changeset.change(folder_id: folder_id)
      |> Repo.update()
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
end
