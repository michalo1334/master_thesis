defmodule NetworkDefense.Evaluation.ErrorEnvelopeTest do
  use ExUnit.Case, async: true

  alias NetworkDefense.Evaluation.ErrorEnvelope

  alias NetworkDefense.Evaluation.Comparison.Contracts.ComparisonError
  alias NetworkDefense.Evaluation.Comparison.SchemaValidator, as: ComparisonSchemaValidator
  alias NetworkDefense.Evaluation.Comparison.Wire, as: ComparisonWire
  alias NetworkDefense.Evaluation.Family.Contracts.FamilyError
  alias NetworkDefense.Evaluation.Family.SchemaValidator, as: FamilySchemaValidator
  alias NetworkDefense.Evaluation.Family.Wire, as: FamilyWire
  alias NetworkDefense.Evaluation.Final.Contracts.FinalError
  alias NetworkDefense.Evaluation.Final.SchemaValidator, as: FinalSchemaValidator
  alias NetworkDefense.Evaluation.Final.Wire, as: FinalWire
  alias NetworkDefense.Evaluation.Pilot.Contracts.PilotError
  alias NetworkDefense.Evaluation.Pilot.SchemaValidator, as: PilotSchemaValidator
  alias NetworkDefense.Evaluation.Pilot.Wire, as: PilotWire

  @issue %{
    "code" => "workflow_failed",
    "path" => [],
    "message" => "Probe issue.",
    "details" => %{}
  }

  @diagnostic %{
    "message" => "Probe diagnostic.",
    "path" => "#/probe",
    "causes" => []
  }

  defp roles do
    [
      {ComparisonError, &ComparisonWire.error/1, &ComparisonSchemaValidator.validate/2,
       "The comparison workflow failed safely."},
      {FamilyError, &FamilyWire.error/1, &FamilySchemaValidator.validate/2,
       "The family workflow failed safely."},
      {PilotError, &PilotWire.error/1, &PilotSchemaValidator.validate/2,
       "The pilot workflow failed safely."},
      {FinalError, &FinalWire.error/1, &FinalSchemaValidator.validate/2,
       "The Final workflow failed safely."}
    ]
  end

  test "ERROR-BODY-01: issues take precedence over diagnostics" do
    fallback = %{"code" => "fallback", "issues" => [@issue]}

    assert ErrorEnvelope.body("probe_code", [@issue], [@diagnostic], fallback) == %{
             "code" => "probe_code",
             "issues" => [@issue]
           }
  end

  test "ERROR-BODY-02: diagnostics are used only when issues are empty" do
    fallback = %{"code" => "fallback", "issues" => [@issue]}

    assert ErrorEnvelope.body("validation_failed", [], [@diagnostic], fallback) == %{
             "code" => "validation_failed",
             "schema_errors" => [@diagnostic]
           }
  end

  test "ERROR-BODY-03: the caller supplies the exact empty-list fallback" do
    fallback = %{"code" => "caller_fallback", "issues" => [@issue]}
    assert ErrorEnvelope.body("ignored", [], [], fallback) == fallback
  end

  test "ERROR-WIRE-01: all role writers preserve precedence, versions, codes, and fallbacks" do
    for {error_module, write_error, _validate_schema, fallback_message} <- roles() do
      issues_error =
        struct!(error_module,
          schema_version: 7,
          code: "probe_code",
          issues: [@issue],
          schema_errors: []
        )

      diagnostics_error =
        struct!(error_module,
          schema_version: 1,
          code: "validation_failed",
          issues: [],
          schema_errors: [@diagnostic]
        )

      both_error =
        struct!(error_module,
          schema_version: 1,
          code: "both_code",
          issues: [@issue],
          schema_errors: [@diagnostic]
        )

      empty_error =
        struct!(error_module,
          schema_version: 9,
          code: "ignored_probe_code",
          issues: [],
          schema_errors: []
        )

      assert write_error.(issues_error) == %{
               "schema_version" => 7,
               "error" => %{"code" => "probe_code", "issues" => [@issue]}
             }

      assert write_error.(diagnostics_error) == %{
               "schema_version" => 1,
               "error" => %{
                 "code" => "validation_failed",
                 "schema_errors" => [@diagnostic]
               }
             }

      assert write_error.(both_error) == %{
               "schema_version" => 1,
               "error" => %{"code" => "both_code", "issues" => [@issue]}
             }

      assert write_error.(empty_error) == %{
               "schema_version" => 9,
               "error" => %{
                 "code" => "workflow_failed",
                 "issues" => [
                   %{
                     "code" => "workflow_failed",
                     "path" => [],
                     "message" => fallback_message,
                     "details" => %{}
                   }
                 ]
               }
             }
    end
  end

  test "ERROR-WIRE-02: each role schema accepts emitted issue and diagnostic forms" do
    for {error_module, write_error, validate_schema, _fallback_message} <- roles() do
      issue_envelope = error_module.workflow_failed() |> write_error.()
      diagnostic_envelope = error_module.schema_failure([@diagnostic]) |> write_error.()

      assert :ok = validate_schema.(:error, issue_envelope)
      assert :ok = validate_schema.(:error, diagnostic_envelope)
    end
  end
end
