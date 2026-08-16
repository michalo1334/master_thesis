defmodule NetworkDefense.Workflows.AnalysisTitle do
  @moduledoc false

  # WordNet 3.1 adjective and noun lemmas, selected for short readable labels.
  @adjectives ~w(
    able agile alert amber ample ardent atomic brisk calm candid careful central certain civil clever
    clear coastal common compact cool crisp curious daring direct eager early easy electric elegant
    even fair faithful fast fertile final firm fluent formal fresh full gentle global golden good
    grand green handy hardy honest humble ideal keen kind level light lively local logical lucky
    lucid major mellow modern moral native neat noble open patient plain poised polite precise prime
    proud quick quiet rapid ready real regal remote robust round royal safe secure sharp silent simple
    skilled smooth solid sound spare stable steady stern still strong subtle sure swift tidy true urban
    useful valid vivid warm wary whole wise young zealous
  )
  @nouns ~w(
    anchor beacon bridge canyon circuit compass domain ember falcon forest frontier garden harbor horizon
    island junction lantern meadow network orbit path quartz river signal summit valley vessel
  )

  @spec generate() :: String.t()
  def generate, do: Enum.join(distinct_adjectives() ++ [pick(@nouns)], " ")

  @spec from_id(Ecto.UUID.t()) :: String.t()
  def from_id(id) do
    Enum.join(distinct_adjectives(id) ++ [at(@nouns, {id, :noun})], " ")
  end

  defp distinct_adjectives, do: roll_adjectives(fn words -> pick(words) end)

  defp distinct_adjectives(id),
    do: roll_adjectives(fn words -> at(words, {id, length(words)}) end)

  defp roll_adjectives(roll) do
    {adjectives, _remaining} =
      Enum.reduce(1..2, {[], @adjectives}, fn _, {rolled, remaining} ->
        adjective = roll.(remaining)
        {[adjective | rolled], List.delete(remaining, adjective)}
      end)

    Enum.reverse(adjectives)
  end

  defp pick(words), do: Enum.at(words, :rand.uniform(length(words)) - 1)
  defp at(words, key), do: Enum.at(words, :erlang.phash2(key, length(words)))
end
