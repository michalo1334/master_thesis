Code.require_file(Path.expand("../../../credo/checks/guardrail_ast.ex", __DIR__))
Code.require_file(Path.expand("../../../credo/checks/flattened_projection_contract.ex", __DIR__))
Code.require_file(Path.expand("../../../credo/checks/retired_projection_type_helper.ex", __DIR__))
Code.require_file(Path.expand("../../../credo/checks/live_view_repo_dependency.ex", __DIR__))
Code.require_file(Path.expand("../../../credo/checks/inline_contract_type_mapping.ex", __DIR__))
Code.require_file(Path.expand("../../../credo/checks/success_shaped_exit_catch.ex", __DIR__))

defmodule NetworkDefense.Credo.ProjectChecksTest do
  use ExUnit.Case, async: false
  alias Credo.SourceFile
  alias NetworkDefense.Credo.GuardrailAst

  setup_all do
    # The Credo CLI can leave its supervisor running outside the application controller.
    if Process.whereis(Credo.Supervisor) do
      :ok
    else
      {:ok, _apps} = Application.ensure_all_started(:credo)
      :ok
    end
  end

  alias NetworkDefense.Credo.{
    FlattenedProjectionContract,
    InlineContractTypeMapping,
    LiveViewRepoDependency,
    RetiredProjectionTypeHelper,
    SuccessShapedExitCatch
  }

  @root "NetworkDefenseWeb.Contracts.Dashboard.Graph.TopologyProjection"
  defp check(check, source, path \\ "lib/sample.ex") do
    source |> SourceFile.parse(path) |> check.run([])
  end

  test "resolves literal nesting without confusing a relative name with the project namespace" do
    assert check(
             FlattenedProjectionContract,
             "defmodule Unrelated do\n  defmodule #{@root}Record do\n  end\nend"
           ) == []

    assert check(
             RetiredProjectionTypeHelper,
             "defmodule Unrelated do\n  defmodule #{@root} do\n    defp node_type(value), do: value\n  end\nend"
           ) == []

    assert check(
             InlineContractTypeMapping,
             "defmodule Unrelated do\n  defmodule NetworkDefenseWeb.Contracts.Record do\n    defp label(:amber), do: \"A\"\n    defp label(:violet), do: \"V\"\n    defp label(:silver), do: \"S\"\n  end\nend"
           ) == []

    assert [%{line_no: 2}] =
             check(
               FlattenedProjectionContract,
               "defmodule NetworkDefenseWeb.Contracts.Dashboard.Graph do\n  defmodule TopologyProjectionRecord do\n  end\nend"
             )
  end

  test "walks complete module and function forms, while excluding quoted AST" do
    assert [%{line_no: 3}] =
             check(
               FlattenedProjectionContract,
               "defmodule Container do\n  def build do\n    defmodule Elixir.#{@root}Child do\n    end\n  end\nend"
             )

    assert check(
             FlattenedProjectionContract,
             "defmodule Container do\n  quote do\n    defmodule #{@root}Child do\n    end\n  end\nend"
           ) == []
  end

  test "projection names reject flattened extensions, not nested or unrelated declarations" do
    assert [%{line_no: 2}] =
             check(
               FlattenedProjectionContract,
               "# Root declaration\ndefmodule #{@root}Child do end"
             )

    assert check(
             FlattenedProjectionContract,
             "defmodule Container do\n  defmodule #{@root}.Child do end\nend"
           ) == []

    assert check(FlattenedProjectionContract, "defmodule Other.Child do end") == []

    assert [%{line_no: 2}] =
             check(
               FlattenedProjectionContract,
               "defmodule Container do\n  defmodule Elixir.#{@root}Child do end\nend"
             )
  end

  test "only guarded private arity-one helpers in the fully qualified root are reported" do
    source = """
    defmodule Container do
      defmodule Elixir.#{@root} do
        defp node_type(value) when is_atom(value), do: value
        defp relationship_type(value) when is_atom(value), do: value
        def node_type(value), do: value
        defp node_type(left, right), do: {left, right}
        defmodule Child do
          defp node_type(value), do: value
        end
      end
    end
    """

    assert [3, 4] =
             check(RetiredProjectionTypeHelper, source)
             |> Enum.map(& &1.line_no)
             |> Enum.sort()

    assert check(
             RetiredProjectionTypeHelper,
             "defmodule Container do\n  defmodule Other do\n    defp node_type(value) when is_atom(value), do: value\n  end\nend"
           ) == []

    # Child modules do not own the root module's retired-helper policy.
    assert check(
             RetiredProjectionTypeHelper,
             "defmodule #{@root} do\n  defmodule Child do\n    defp node_type(value), do: value\n  end\nend"
           ) == []
  end

  test "Repo dependency reports explicit module references only in LiveView paths" do
    path = "lib/network_defense_web/live/page.ex"

    assert [%{line_no: 3}] =
             check(
               LiveViewRepoDependency,
               "defmodule Page do\n  def load do\n    Elixir.NetworkDefense.Repo.get(Item, 1)\n  end\nend",
               path
             )

    assert check(
             LiveViewRepoDependency,
             "defmodule Page do\n  def load do\n    alias NetworkDefense.Repo, as: R\n    R.get(Item, 1)\n  end\nend",
             path
           ) != []

    assert check(
             LiveViewRepoDependency,
             "defmodule Page do\n  alias NetworkDefense.{Repo, Other}\nend",
             path
           ) != []

    assert check(
             LiveViewRepoDependency,
             "defmodule Page do\n  alias unquote(module)\nend",
             path
           ) == []

    assert GuardrailAst.alias_name({:__aliases__, [], [{:unquote, [], [{:module, [], nil}]}]}) ==
             nil

    assert check(
             LiveViewRepoDependency,
             "defmodule Page do\n  quote do\n    alias NetworkDefense.Repo\n  end\nend",
             path
           ) == []

    assert check(
             LiveViewRepoDependency,
             "defmodule Page do\n  alias NetworkDefense.Repo\nend\ndefmodule Other do\n  Repo.get(Item, 1)\nend",
             path
           ) != []

    assert check(
             LiveViewRepoDependency,
             "defmodule Page do\n  alias Repo\nend\ndefmodule Other do\n  Repo.get(Item, 1)\nend",
             path
           ) == []

    for other_path <- [
          "lib/network_defense/domain.ex",
          "lib/network_defense_web/health.ex",
          "lib/network_defense_web/telemetry.ex"
        ] do
      assert check(
               LiveViewRepoDependency,
               "defmodule Page do\n  alias NetworkDefense.Repo\nend",
               other_path
             ) == []
    end
  end

  test "contract mapping heuristic requires three literal atom-to-string clauses" do
    source = """
    defmodule Container do
      defmodule Elixir.NetworkDefenseWeb.Contracts.Demo do
        defp label(:first), do: "one"
        defp label(:second), do: "two"
        defp label(:third), do: "three"
      end
    end
    """

    assert [%{line_no: 3}] = check(InlineContractTypeMapping, source)

    assert check(InlineContractTypeMapping, String.replace(source, "defp label", "def label")) ==
             []

    assert check(
             InlineContractTypeMapping,
             String.replace(source, "NetworkDefenseWeb.Contracts.Demo", "Outside.Demo")
           ) == []

    assert check(
             InlineContractTypeMapping,
             String.replace(source, "    defp label(:third), do: \"three\"\n", "")
           ) == []

    assert check(
             InlineContractTypeMapping,
             "defmodule NetworkDefenseWeb.Contracts.Demo do\n  defp label(item) when is_atom(item), do: \"mapped\"\n  defp label(item) when is_binary(item), do: \"mapped\"\n  defp label(item) when is_integer(item), do: \"mapped\"\nend"
           ) == []

    assert check(
             InlineContractTypeMapping,
             "defmodule NetworkDefenseWeb.Contracts.Demo do\n  defp label(:first), do: compute(:first)\n  defp label(:second), do: compute(:second)\n  defp label(:third), do: compute(:third)\nend"
           ) == []

    assert check(
             InlineContractTypeMapping,
             "defmodule NetworkDefenseWeb.Contracts.Dashboard.Graph.TopologyProjection do\n  defp node_type(:first), do: \"one\"\n  defp node_type(:second), do: \"two\"\n  defp node_type(:third), do: \"three\"\nend"
           ) == []

    assert check(
             InlineContractTypeMapping,
             "defmodule NetworkDefenseWeb.Contracts.Other do\n  defp node_type(:first), do: \"one\"\n  defp node_type(:second), do: \"two\"\n  defp node_type(:third), do: \"three\"\nend"
           ) != []

    assert check(InlineContractTypeMapping, "quote do\n" <> source <> "\nend") == []
  end

  test "exit catch heuristic accepts only literal two-pattern exit catches" do
    assert [%{line_no: 6}] =
             check(
               SuccessShapedExitCatch,
               "defmodule Worker do\n  def run do\n    try do\n      work()\n    catch\n      :exit, _reason -> :ok\n    end\n  end\nend"
             )

    assert [%{line_no: 5}] =
             check(
               SuccessShapedExitCatch,
               "defmodule Worker do\n  def run do\n    work()\n  catch\n    :exit, _reason -> {:ok, :done}\n  end\nend"
             )

    for catcher <- [":exit -> :ok", ":throw, :exit -> :ok", ":error, :exit -> :ok"] do
      assert check(
               SuccessShapedExitCatch,
               "defmodule Worker do\n  def run do\n    try do\n      work()\n    catch\n      #{catcher}\n    end\n  end\nend"
             ) == []
    end

    for value <- ["{:error, :unavailable}", "fallback()", "exit(:unavailable)"] do
      assert check(
               SuccessShapedExitCatch,
               "defmodule Worker do\n  def run do\n    work()\n  catch\n    :exit, _reason -> #{value}\n  end\nend"
             ) == []
    end

    for value <- ["nil", "[]", "%{}", "{:ok, :value}"] do
      assert check(
               SuccessShapedExitCatch,
               "defmodule Worker do\n  def run do\n    try do\n      work()\n    catch\n      :exit, _reason -> #{value}\n    end\n  end\nend"
             ) != []
    end

    assert check(
             SuccessShapedExitCatch,
             "defmodule Worker do\n  quote do\n    try do\n      work()\n    catch\n      :exit, _reason -> :ok\n    end\n  end\nend"
           ) == []
  end
end
