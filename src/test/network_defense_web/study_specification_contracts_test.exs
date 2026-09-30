defmodule NetworkDefenseWeb.StudySpecificationContractsTest do
  use ExUnit.Case, async: true

  alias NetworkDefenseWeb.Contracts.Dashboard.Evaluation.DescribeStudySpecificationPayload
  alias NetworkDefenseWeb.Contracts.Dashboard.Evaluation.DescribeStudySpecificationReply
  alias NetworkDefenseWeb.Contracts.Dashboard.Evaluation.GetStudySpecificationPayload
  alias NetworkDefenseWeb.Contracts.Dashboard.Evaluation.GetStudySpecificationReply
  alias NetworkDefenseWeb.Contracts.Dashboard.Evaluation.ListStudySpecificationsReply
  alias NetworkDefenseWeb.Contracts.Dashboard.Evaluation.SaveStudySpecificationPayload
  alias NetworkDefenseWeb.Contracts.Dashboard.Evaluation.SaveStudySpecificationReply
  alias NetworkDefenseWeb.Contracts.Dashboard.Evaluation.StudySpecificationDescription
  alias NetworkDefenseWeb.Contracts.Dashboard.Evaluation.StudySpecificationSummary

  @specification_id "00000000-0000-0000-0000-0000000000a1"

  test "casts a study specification summary with content" do
    assert {:ok, summary} =
             StudySpecificationSummary.validate(%{
               "id" => @specification_id,
               "study_id" => "topology-scale-study",
               "specification_version" => 2,
               "title" => "Topology scale",
               "content" => %{"study_id" => "topology-scale-study"}
             })

    assert summary.specification_version == 2

    assert %{
             id: @specification_id,
             study_id: "topology-scale-study",
             specification_version: 2
           } = StudySpecificationSummary.to_wire(summary)
  end

  test "requires the summary identity fields and a positive version" do
    assert {:error, summary_changeset} =
             StudySpecificationSummary.validate(%{"specification_version" => 0})

    assert %{
             id: ["can't be blank"],
             study_id: ["can't be blank"],
             title: ["can't be blank"]
           } = errors_on(summary_changeset)

    assert %{specification_version: ["must be greater than 0"]} = errors_on(summary_changeset)
  end

  test "casts a study specification description" do
    assert {:ok, description} =
             StudySpecificationDescription.validate(%{
               "study_id" => "topology-scale-study",
               "specification_version" => 1,
               "tiers" => ["small", "medium"]
             })

    assert %{tiers: ["small", "medium"]} = StudySpecificationDescription.to_wire(description)
  end

  test "requires the description fields" do
    assert {:error, changeset} =
             StudySpecificationDescription.validate(%{
               "study_id" => "topology-scale-study",
               "specification_version" => 1
             })

    assert %{tiers: ["can't be blank"]} = errors_on(changeset)
  end

  test "requires a title and content on save" do
    assert {:ok, %SaveStudySpecificationPayload{title: "Study", content: %{"study_id" => "s"}}} =
             SaveStudySpecificationPayload.validate(%{
               "title" => "Study",
               "content" => %{"study_id" => "s"}
             })

    assert {:error, payload_changeset} = SaveStudySpecificationPayload.validate(%{})

    assert %{title: ["can't be blank"], content: ["can't be blank"]} =
             errors_on(payload_changeset)
  end

  test "validates the save reply status and payload" do
    assert {:ok, reply} =
             SaveStudySpecificationReply.validate(%{
               "status" => "ok",
               "specification" => %{
                 "id" => @specification_id,
                 "study_id" => "topology-scale-study",
                 "specification_version" => 1,
                 "title" => "Study"
               },
               "errors" => [%{"path" => "tiers", "message" => "must be a non-empty list"}]
             })

    assert %{status: "ok", specification: %{id: @specification_id}} =
             SaveStudySpecificationReply.to_wire(reply)

    assert {:ok, %{status: "immutable_conflict"}} =
             SaveStudySpecificationReply.validate(%{"status" => "immutable_conflict"})

    assert %{enum_values: save_enum_values} = SaveStudySpecificationReply.contract_meta()

    assert save_enum_values[:status] ==
             [:ok, :invalid_specification, :immutable_conflict, :invalid_request]

    assert {:error, changeset} =
             SaveStudySpecificationReply.validate(%{"status" => "bogus"})

    assert %{status: ["is invalid"]} = errors_on(changeset)
  end

  test "validates the list reply with summaries" do
    assert {:ok, reply} =
             ListStudySpecificationsReply.validate(%{
               "specifications" => [
                 %{
                   "id" => @specification_id,
                   "study_id" => "topology-scale-study",
                   "specification_version" => 1,
                   "title" => "Study"
                 }
               ]
             })

    assert [%{id: @specification_id}] = ListStudySpecificationsReply.to_wire(reply).specifications
  end

  test "validates the get payload as a UUID and returns one specification" do
    assert {:ok, %GetStudySpecificationPayload{id: @specification_id}} =
             GetStudySpecificationPayload.validate(%{"id" => @specification_id})

    assert {:error, changeset} = GetStudySpecificationPayload.validate(%{"id" => "not-a-uuid"})
    assert %{id: ["is invalid"]} = errors_on(changeset)

    assert {:ok, reply} =
             GetStudySpecificationReply.validate(%{
               "specification" => %{
                 "id" => @specification_id,
                 "study_id" => "topology-scale-study",
                 "specification_version" => 1,
                 "title" => "Study",
                 "content" => %{"study_id" => "topology-scale-study"}
               }
             })

    assert %{specification: %{content: %{"study_id" => "topology-scale-study"}}} =
             GetStudySpecificationReply.to_wire(reply)

    assert {:ok, %{specification: nil}} = GetStudySpecificationReply.validate(%{})
  end

  test "requires a content map on describe" do
    assert {:ok, %DescribeStudySpecificationPayload{content: %{"study_id" => "s"}}} =
             DescribeStudySpecificationPayload.validate(%{"content" => %{"study_id" => "s"}})

    assert {:error, changeset} = DescribeStudySpecificationPayload.validate(%{})
    assert %{content: ["can't be blank"]} = errors_on(changeset)
  end

  test "validates the describe reply status and description" do
    assert {:ok, reply} =
             DescribeStudySpecificationReply.validate(%{
               "status" => "ok",
               "description" => %{
                 "study_id" => "topology-scale-study",
                 "specification_version" => 1,
                 "tiers" => ["small"]
               },
               "errors" => []
             })

    assert %{description: %{tiers: ["small"]}} = DescribeStudySpecificationReply.to_wire(reply)

    assert %{enum_values: describe_enum_values} =
             DescribeStudySpecificationReply.contract_meta()

    assert describe_enum_values[:status] == [:ok, :invalid_specification, :invalid_request]

    assert {:ok, %{status: "invalid_specification", description: nil, errors: errors}} =
             DescribeStudySpecificationReply.validate(%{
               "status" => "invalid_specification",
               "errors" => [%{"path" => "tiers", "message" => "must be a non-empty list"}]
             })

    assert [%{path: "tiers"}] = errors

    assert {:error, changeset} =
             DescribeStudySpecificationReply.validate(%{"status" => "bogus"})

    assert %{status: ["is invalid"]} = errors_on(changeset)
  end

  defp errors_on(changeset) do
    Ecto.Changeset.traverse_errors(changeset, fn {message, options} ->
      Enum.reduce(options, message, &replace_error_option/2)
    end)
  end

  defp replace_error_option({key, value}, message) do
    placeholder = "%{#{key}}"

    if String.contains?(message, placeholder),
      do: String.replace(message, placeholder, to_string(value)),
      else: message
  end
end
