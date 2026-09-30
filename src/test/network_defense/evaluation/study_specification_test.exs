defmodule NetworkDefense.Evaluation.StudySpecificationTest do
  use NetworkDefense.DataCase, async: true

  alias NetworkDefense.Evaluation
  alias NetworkDefense.Evaluation.Contracts.StudySpecification, as: StudySpecificationContract
  alias NetworkDefense.Evaluation.StudySpecification
  alias NetworkDefense.Evaluation.StudySpecifications
  alias NetworkDefense.EvaluationFixtures

  defp specification(overrides \\ %{}) do
    EvaluationFixtures.study_specification()
    |> Map.put("study_id", "study-#{System.unique_integer([:positive])}")
    |> Map.merge(overrides)
  end

  describe "StudySpecificationContract.validate/1" do
    test "accepts string tier labels" do
      spec = specification()

      assert {:ok, ^spec} = StudySpecificationContract.validate(spec)
    end

    test "accepts tier objects with labels" do
      spec = specification(%{"tiers" => [%{"label" => "small"}, %{"label" => "large"}]})

      assert {:ok, ^spec} = StudySpecificationContract.validate(spec)
    end

    test "rejects a non-map specification" do
      assert {:error, [%{path: "$", message: "study specification must be a JSON object"}]} =
               StudySpecificationContract.validate(["not", "a", "map"])
    end

    test "requires a non-empty study identity" do
      assert {:error, [%{path: "study_id"}]} =
               StudySpecificationContract.validate(Map.delete(specification(), "study_id"))

      assert {:error, [%{path: "study_id"}]} =
               StudySpecificationContract.validate(specification(%{"study_id" => ""}))
    end

    test "requires a positive integer specification version" do
      for version <- [0, -1, 1.5, nil] do
        assert {:error, [%{path: "specification_version"}]} =
                 StudySpecificationContract.validate(
                   specification(%{"specification_version" => version})
                 )
      end
    end

    test "coerces numeric scalars like the analysis service" do
      spec =
        specification(%{
          "specification_version" => "2",
          "expected_family" =>
            specification()["expected_family"]
            |> Map.put("budgets", ["1", 2, "3"]),
          "pilot" =>
            specification()["pilot"]
            |> Map.put("ci_half_width", "1.5")
            |> Map.put("plan_count_candidates", ["5", 6])
            |> Map.put("guard_quantile", "0.9")
            |> Map.put("subsamples", "100")
            |> Map.put("seed", "7"),
          "pilot_seed_schedule" => %{"selection" => ["10001"], "evaluation" => ["11001"]},
          "final_seed_schedule" => %{"selection" => ["20001"], "evaluation" => ["21001"]}
        })

      assert {:ok, validated} = StudySpecificationContract.validate(spec)

      assert validated["specification_version"] == 2
      assert validated["expected_family"]["budgets"] == [1, 2, 3]
      assert validated["pilot"]["ci_half_width"] == 1.5
      assert validated["pilot"]["plan_count_candidates"] == [5, 6]
      assert validated["pilot"]["guard_quantile"] == 0.9
      assert validated["pilot"]["subsamples"] == 100
      assert validated["pilot"]["seed"] == 7

      assert validated["pilot_seed_schedule"] ==
               %{"selection" => [10_001], "evaluation" => [11_001]}

      assert validated["final_seed_schedule"] ==
               %{"selection" => [20_001], "evaluation" => [21_001]}
    end

    test "accepts whitespace and underscore numeric strings like Python float" do
      for {input, expected} <- [
            {" 1.5 ", 1.5},
            {"\t1.5\n", 1.5},
            {"1_000.5", 1000.5},
            {"1_000", 1000.0},
            {"1e5", 100_000.0},
            {"1.0e5", 100_000.0},
            {".5", 0.5},
            {"1.", 1.0},
            {"+1.5", 1.5},
            {"1_0.0_1", 10.01},
            {"1e1_0", 1.0e10},
            {"1_0e1_0", 1.0e11},
            {".5_5", 0.55},
            {"+1_0", 10.0},
            {"1_2_3", 123.0},
            {"1.e1", 10.0}
          ] do
        pilot = Map.put(specification()["pilot"], "ci_half_width", input)

        assert {:ok, validated} =
                 StudySpecificationContract.validate(specification(%{"pilot" => pilot}))

        assert validated["pilot"]["ci_half_width"] == expected
      end

      assert {:ok, validated} =
               StudySpecificationContract.validate(
                 specification(%{
                   "pilot" => Map.put(specification()["pilot"], "guard_quantile", " 0.9_0 ")
                 })
               )

      assert validated["pilot"]["guard_quantile"] == 0.9
    end

    test "rejects malformed finite numeric strings like Python float" do
      for input <- [
            "",
            "  ",
            "1_",
            "_1",
            "1__0",
            "1.5_",
            "1._5",
            "1_.5",
            "5_",
            "1e_5",
            "1e5_",
            "0x10",
            "1.5abc",
            "1 000",
            "1 .5",
            "1e",
            ".",
            "+",
            "-",
            "inf",
            "infinity",
            "nan",
            "1e400",
            "1,5"
          ] do
        pilot = Map.put(specification()["pilot"], "ci_half_width", input)

        assert {:error, [%{path: "pilot.ci_half_width"}]} =
                 StudySpecificationContract.validate(specification(%{"pilot" => pilot}))
      end
    end

    test "rejects malformed numeric scalars" do
      for version <- ["", "1.5", "1 ", "1e3", "abc", true, nil] do
        assert {:error, [%{path: "specification_version"}]} =
                 StudySpecificationContract.validate(
                   specification(%{"specification_version" => version})
                 )
      end
    end

    test "detects a seed schedule overlap across string and integer encodings" do
      assert {:error, [%{path: "pilot_seed_schedule.selection"}]} =
               StudySpecificationContract.validate(
                 specification(%{
                   "pilot_seed_schedule" => %{
                     "selection" => ["10001"],
                     "evaluation" => [11_001]
                   },
                   "final_seed_schedule" => %{"selection" => [10_001], "evaluation" => [21_001]}
                 })
               )
    end

    test "requires a non-empty unique tier list" do
      assert {:error, [%{path: "tiers"}]} =
               StudySpecificationContract.validate(Map.delete(specification(), "tiers"))

      assert {:error, [%{path: "tiers"}]} =
               StudySpecificationContract.validate(specification(%{"tiers" => []}))

      assert {:error, [%{path: "tiers"}]} =
               StudySpecificationContract.validate(specification(%{"tiers" => "small"}))

      assert {:error, [%{path: "tiers"}]} =
               StudySpecificationContract.validate(
                 specification(%{"tiers" => ["small", "small"]})
               )

      assert {:error, [%{path: "tiers"}]} =
               StudySpecificationContract.validate(
                 specification(%{"tiers" => [%{"label" => "small"}, %{"label" => "small"}]})
               )
    end

    test "rejects unsafe and malformed tier entries" do
      assert {:error, [%{path: "tiers"}]} =
               StudySpecificationContract.validate(specification(%{"tiers" => ["../escape"]}))

      assert {:error, [%{path: "tiers.0"}]} =
               StudySpecificationContract.validate(specification(%{"tiers" => [123]}))

      assert {:error, [%{path: "tiers.0"}]} =
               StudySpecificationContract.validate(specification(%{"tiers" => [%{"label" => 7}]}))
    end

    test "requires the expected family block and its fields" do
      family = specification()["expected_family"]

      assert {:error, [%{path: "expected_family"}]} =
               StudySpecificationContract.validate(Map.delete(specification(), "expected_family"))

      assert {:error, [%{path: "expected_family.strategies"}]} =
               StudySpecificationContract.validate(
                 specification(%{"expected_family" => Map.delete(family, "strategies")})
               )

      assert {:error, [%{path: "expected_family.strategies"}]} =
               StudySpecificationContract.validate(
                 specification(%{
                   "expected_family" => %{family | "strategies" => ["random", "random"]}
                 })
               )

      assert {:error, [%{path: "expected_family.baseline"}]} =
               StudySpecificationContract.validate(
                 specification(%{
                   "expected_family" => %{
                     family
                     | "strategies" => ["random", "simulation_informed"],
                       "baseline" => "random"
                   }
                 })
               )

      assert {:error, [%{path: "expected_family.budgets"}]} =
               StudySpecificationContract.validate(
                 specification(%{"expected_family" => %{family | "budgets" => [1, 1]}})
               )

      assert {:error, [%{path: "expected_family.budgets"}]} =
               StudySpecificationContract.validate(
                 specification(%{"expected_family" => %{family | "budgets" => [0]}})
               )

      assert {:error, [%{path: "expected_family.outcome"}]} =
               StudySpecificationContract.validate(
                 specification(%{"expected_family" => %{family | "outcome" => "blast_radius"}})
               )
    end

    test "requires the pilot block and its candidate constraints" do
      pilot = specification()["pilot"]

      assert {:error, [%{path: "pilot"}]} =
               StudySpecificationContract.validate(Map.delete(specification(), "pilot"))

      assert {:error, [%{path: "pilot.ci_half_width"}]} =
               StudySpecificationContract.validate(
                 specification(%{"pilot" => %{pilot | "ci_half_width" => 0}})
               )

      for candidates <- [[6, 5], [5, 5], [4], [5, "x"], Enum.to_list(5..69)] do
        assert {:error, [%{path: "pilot.plan_count_candidates"}]} =
                 StudySpecificationContract.validate(
                   specification(%{"pilot" => %{pilot | "plan_count_candidates" => candidates}})
                 )
      end

      for candidates <- [[12, 10], [10, 10], [9], [10, 11.5]] do
        assert {:error, [%{path: "pilot.attacks_per_plan_candidates"}]} =
                 StudySpecificationContract.validate(
                   specification(%{
                     "pilot" => %{pilot | "attacks_per_plan_candidates" => candidates}
                   })
                 )
      end
    end

    test "validates declared pilot selection fields" do
      pilot = specification()["pilot"]

      assert {:error, [%{path: "pilot.guard_quantile"}]} =
               StudySpecificationContract.validate(
                 specification(%{"pilot" => Map.put(pilot, "guard_quantile", 1.0)})
               )

      assert {:error, [%{path: "pilot.subsamples"}]} =
               StudySpecificationContract.validate(
                 specification(%{"pilot" => Map.put(pilot, "subsamples", 0)})
               )

      assert {:error, [%{path: "pilot.seed"}]} =
               StudySpecificationContract.validate(
                 specification(%{"pilot" => Map.put(pilot, "seed", -1)})
               )

      assert {:error, [%{path: "pilot.selection_rule"}]} =
               StudySpecificationContract.validate(
                 specification(%{"pilot" => Map.put(pilot, "selection_rule", "fastest")})
               )

      assert {:ok, _specification} =
               StudySpecificationContract.validate(
                 specification(%{
                   "pilot" =>
                     pilot
                     |> Map.put("guard_quantile", 0.9)
                     |> Map.put("subsamples", 100)
                     |> Map.put("seed", 7)
                     |> Map.put("selection_rule", "lowest_predicted_runtime")
                 })
               )
    end

    test "requires the holm multiplicity correction" do
      assert {:error, [%{path: "multiplicity_correction"}]} =
               StudySpecificationContract.validate(
                 specification(%{"multiplicity_correction" => "none"})
               )
    end

    test "requires valid disjoint seed schedules" do
      assert {:error, [%{path: "pilot_seed_schedule"}]} =
               StudySpecificationContract.validate(
                 Map.delete(specification(), "pilot_seed_schedule")
               )

      assert {:error, [%{path: "final_seed_schedule"}]} =
               StudySpecificationContract.validate(
                 Map.delete(specification(), "final_seed_schedule")
               )

      assert {:error, [%{path: "pilot_seed_schedule.selection"}]} =
               StudySpecificationContract.validate(
                 specification(%{
                   "pilot_seed_schedule" => %{"selection" => [], "evaluation" => [1]}
                 })
               )

      assert {:error, [%{path: "pilot_seed_schedule.selection"}]} =
               StudySpecificationContract.validate(
                 specification(%{
                   "pilot_seed_schedule" => %{"selection" => [1, 1], "evaluation" => [2]}
                 })
               )

      assert {:error, [%{path: "final_seed_schedule.evaluation"}]} =
               StudySpecificationContract.validate(
                 specification(%{
                   "final_seed_schedule" => %{"selection" => [3], "evaluation" => [-1]}
                 })
               )

      assert {:error, [%{path: "pilot_seed_schedule.selection"}]} =
               StudySpecificationContract.validate(
                 specification(%{
                   "pilot_seed_schedule" => %{"selection" => [1], "evaluation" => [2]},
                   "final_seed_schedule" => %{"selection" => [1], "evaluation" => [3]}
                 })
               )
    end
  end

  describe "StudySpecificationContract.parse/1 and describe/1" do
    test "parses valid JSON" do
      spec = specification()

      assert {:ok, ^spec} = spec |> Jason.encode!() |> StudySpecificationContract.parse()
    end

    test "rejects invalid JSON" do
      assert {:error, [%{path: "$", message: "invalid JSON"}]} =
               StudySpecificationContract.parse("{not json")
    end

    test "describes declared tiers for both entry forms" do
      spec = specification(%{"tiers" => ["small", %{"label" => "medium"}]})

      assert {:ok,
              %{
                study_id: study_id,
                specification_version: 1,
                tiers: ["small", "medium"]
              }} = StudySpecificationContract.describe(spec)

      assert study_id == spec["study_id"]
    end

    test "describes only validated specifications" do
      assert {:error, [%{path: "tiers"}]} =
               StudySpecificationContract.describe(specification(%{"tiers" => []}))
    end
  end

  describe "save_study_specification/1" do
    test "creates one immutable version" do
      spec = specification()

      assert {:ok, %StudySpecification{} = saved} =
               EvaluationFixtures.save_study_specification(spec, "Topology scale")

      assert saved.study_id == spec["study_id"]
      assert saved.specification_version == 1
      assert saved.title == "Topology scale"
      assert saved.content == spec
    end

    test "is idempotent for identical content" do
      spec = specification()

      assert {:ok, first} = EvaluationFixtures.save_study_specification(spec)
      assert {:ok, second} = EvaluationFixtures.save_study_specification(spec)

      assert first.id == second.id
      assert [_single] = StudySpecifications.list_versions(spec["study_id"])
    end

    test "rejects different content for the same identity and version" do
      spec = specification()

      assert {:ok, saved} = EvaluationFixtures.save_study_specification(spec)

      changed = Map.put(spec, "tiers", ["small"])

      assert {:error, :immutable_conflict} = EvaluationFixtures.save_study_specification(changed)

      assert %StudySpecification{content: stored} = StudySpecifications.get(saved.id)
      assert stored == spec
    end

    test "rejects a changed title for the same identity and version" do
      spec = specification()

      assert {:ok, saved} = EvaluationFixtures.save_study_specification(spec, "First title")

      assert {:error, :immutable_conflict} =
               EvaluationFixtures.save_study_specification(spec, "Second title")

      assert StudySpecifications.get(saved.id).title == "First title"
    end

    test "stores coerced numeric scalars" do
      spec = specification(%{"specification_version" => "2"})

      assert {:ok, saved} = EvaluationFixtures.save_study_specification(spec)

      assert saved.specification_version == 2
      assert saved.content["specification_version"] == 2
    end

    test "stores the next version under the same study identity" do
      spec = specification()

      assert {:ok, first} = EvaluationFixtures.save_study_specification(spec)

      second_spec = Map.put(spec, "specification_version", 2)

      assert {:ok, second} = EvaluationFixtures.save_study_specification(second_spec)

      assert first.id != second.id
      assert [_first, _second] = StudySpecifications.list_versions(spec["study_id"])
    end

    test "returns validation errors without persisting" do
      spec = specification(%{"tiers" => []})

      assert {:error, [%{path: "tiers"}]} = EvaluationFixtures.save_study_specification(spec)
      assert StudySpecifications.list_versions(spec["study_id"]) == []
    end

    test "rejects an invalid title" do
      spec = specification()

      assert {:error, :invalid_request} =
               Evaluation.save_study_specification(%{title: "", content: spec})

      assert {:error, :invalid_request} =
               Evaluation.save_study_specification(%{content: spec})
    end
  end

  describe "list and fetch" do
    test "lists all versions newest first per study identity" do
      first_study = "study-a-#{System.unique_integer([:positive])}"
      second_study = "study-b-#{System.unique_integer([:positive])}"

      for {study_id, version} <- [
            {second_study, 1},
            {first_study, 1},
            {first_study, 2}
          ] do
        spec =
          specification(%{
            "study_id" => study_id,
            "specification_version" => version
          })

        assert {:ok, _saved} = EvaluationFixtures.save_study_specification(spec)
      end

      listed = Evaluation.list_study_specifications()

      identities =
        listed
        |> Enum.map(&{&1.study_id, &1.specification_version})
        |> Enum.filter(fn {id, _} ->
          id in [first_study, second_study]
        end)

      assert identities == [
               {first_study, 2},
               {first_study, 1},
               {second_study, 1}
             ]
    end

    test "lists one study identity's versions newest first" do
      study_id = "study-#{System.unique_integer([:positive])}"

      for version <- [1, 3, 2] do
        spec = specification(%{"study_id" => study_id, "specification_version" => version})
        assert {:ok, _saved} = EvaluationFixtures.save_study_specification(spec)
      end

      assert [3, 2, 1] =
               Enum.map(
                 Evaluation.list_study_specification_versions(study_id),
                 & &1.specification_version
               )
    end

    test "fetches the exact stored version by id" do
      spec = specification()

      assert {:ok, first} = EvaluationFixtures.save_study_specification(spec)

      second_spec = Map.put(spec, "specification_version", 2)
      assert {:ok, second} = EvaluationFixtures.save_study_specification(second_spec)

      fetched = Evaluation.get_study_specification(second.id)
      assert fetched.id == second.id
      assert fetched.specification_version == 2
      assert fetched.content == second_spec

      assert Evaluation.get_study_specification(first.id).specification_version == 1
    end

    test "returns nil for an unknown id" do
      assert Evaluation.get_study_specification(Ecto.UUID.generate()) == nil
    end
  end

  describe "StudySpecification.changeset/2" do
    test "requires the identity, version, title, and content" do
      changeset = StudySpecification.changeset(%StudySpecification{}, %{})
      refute changeset.valid?

      assert %{
               study_id: ["can't be blank"],
               specification_version: ["can't be blank"],
               title: ["can't be blank"],
               content: ["can't be blank"]
             } = errors_on(changeset)
    end

    test "rejects a non-positive version" do
      changeset =
        StudySpecification.changeset(%StudySpecification{}, %{
          study_id: "study",
          specification_version: 0,
          title: "Title",
          content: %{}
        })

      refute changeset.valid?
      assert %{specification_version: ["must be greater than 0"]} = errors_on(changeset)
    end

    test "treats a whitespace-only study identity and title as blank" do
      changeset =
        StudySpecification.changeset(%StudySpecification{}, %{
          study_id: "  ",
          specification_version: 1,
          title: "\t ",
          content: %{}
        })

      refute changeset.valid?

      assert %{study_id: ["can't be blank"], title: ["can't be blank"]} =
               errors_on(changeset)
    end

    test "enforces the named study identity database check" do
      error = assert_raise Postgrex.Error, fn -> insert_row("  ", "Title") end

      assert error.postgres.constraint == "study_specifications_study_id_present"
    end

    test "enforces the named title database check" do
      error = assert_raise Postgrex.Error, fn -> insert_row("study", "\t ") end

      assert error.postgres.constraint == "study_specifications_title_present"
    end

    defp insert_row(study_id, title) do
      now = DateTime.truncate(DateTime.utc_now(), :second)

      Repo.insert_all(StudySpecification, [
        %{
          id: Ecto.UUID.generate(),
          study_id: study_id,
          specification_version: 1,
          title: title,
          content: %{},
          inserted_at: now,
          updated_at: now
        }
      ])
    end
  end

  describe "StudySpecifications.insert/1" do
    test "maps a duplicate identity and version to the unique constraint" do
      spec = specification()
      assert {:ok, _saved} = EvaluationFixtures.save_study_specification(spec)

      assert {:error, changeset} =
               StudySpecifications.insert(%{
                 study_id: spec["study_id"],
                 specification_version: spec["specification_version"],
                 title: "Study",
                 content: spec
               })

      assert %{study_id: ["has already been taken"]} = errors_on(changeset)
    end
  end

  describe "canonical JSON enforcement" do
    test "rejects atom keys at any depth" do
      assert {:error, [%{path: "$", message: "must use string keys"}]} =
               Evaluation.save_study_specification(%{
                 title: "Study",
                 content: %{study_id: "study"}
               })

      nested = Map.put(specification(), "expected_family", %{outcome: "mission_impact"})

      assert {:error, [%{path: "expected_family", message: "must use string keys"}]} =
               Evaluation.save_study_specification(%{title: "Study", content: nested})
    end

    test "rejects non-JSON values at any depth" do
      assert {:error, [%{path: "note", message: "must be a JSON value"}]} =
               Evaluation.save_study_specification(%{
                 title: "Study",
                 content: Map.put(specification(), "note", :unsupported)
               })

      assert {:error, [%{path: "tiers[0]", message: "must be a JSON value"}]} =
               Evaluation.describe_study_specification(
                 Map.put(specification(), "tiers", [{"small", "large"}])
               )
    end

    test "accepts canonical JSON with extra keys" do
      content = Map.put(specification(), "note", %{"nested" => [1, 2, true, nil]})

      assert {:ok, %{study_id: study_id}} = Evaluation.describe_study_specification(content)
      assert study_id == content["study_id"]
    end
  end
end
