defmodule NetworkDefense.Evaluation.Study.YamlTest do
  use ExUnit.Case, async: true

  alias NetworkDefense.Evaluation.ErrorEnvelope
  alias NetworkDefense.Evaluation.Study.Yaml

  # Operational parser limits from decision D0.
  @input_limit 1_048_576
  @max_depth 32
  @max_entries 10_000

  describe "STUDY-YAML-01 valid documents" do
    test "nested YAML becomes a string-keyed JSON-compatible map" do
      yaml = """
      study:
        revision: 1
        tiers:
          - name: pilot
            budgets: [10, 20]
          - name: final
            budgets: []
        enabled: true
        missing: null
      """

      assert {:ok, parsed} = Yaml.parse(yaml)

      assert parsed == %{
               "study" => %{
                 "revision" => 1,
                 "tiers" => [
                   %{"name" => "pilot", "budgets" => [10, 20]},
                   %{"name" => "final", "budgets" => []}
                 ],
                 "enabled" => true,
                 "missing" => nil
               }
             }

      assert {:ok, _json} = Jason.encode(parsed)
    end

    test "every key at every depth is a binary" do
      yaml = """
      root:
        - nested: {deep: 1}
        - other: [{leaf: 2}]
      """

      assert {:ok, parsed} = Yaml.parse(yaml)
      assert parsed |> keys() |> Enum.all?(&is_binary/1)
    end

    test "document content never becomes an atom" do
      yaml = "study_yaml_probe_key: study_yaml_probe_value\n"

      assert {:ok, %{"study_yaml_probe_key" => "study_yaml_probe_value"}} = Yaml.parse(yaml)

      assert_raise ArgumentError, fn ->
        String.to_existing_atom("study_yaml_probe_key")
      end

      assert_raise ArgumentError, fn ->
        String.to_existing_atom("study_yaml_probe_value")
      end
    end
  end

  describe "STUDY-YAML-01 malformed YAML" do
    test "returns one bounded invalid_yaml issue without parser diagnostics" do
      assert {:error, error} = Yaml.parse("a: [1,\n")

      assert error.code == "validation_failed"

      assert [issue] = error.issues
      assert issue["code"] == "invalid_yaml"
      assert issue["path"] == ["yaml"]
      assert issue["message"] == "The YAML document is not valid YAML."
      assert byte_size(issue["message"]) <= 256

      refute inspect(error) =~ "yamerl"
      refute inspect(error) =~ "malformed"
      refute inspect(error) =~ "ParsingError"
      refute inspect(error) =~ ~r/line\s*\d/i
    end

    test "keeps the shared bounded error envelope shape" do
      assert {:error, error} = Yaml.parse("a: [1,\n")

      envelope = %{
        "schema_version" => error.schema_version,
        "error" => %{"code" => error.code, "issues" => error.issues}
      }

      assert {:ok, attrs} = ErrorEnvelope.materialize(envelope)
      assert attrs.code == "validation_failed"
      assert [%{"code" => "invalid_yaml"}] = attrs.issues
    end

    test "returns one bounded issue for input that is not a binary" do
      for input <- [nil, 1, [1], %{}] do
        assert {:error, error} = Yaml.parse(input)
        assert [issue] = error.issues
        assert issue["code"] == "invalid_yaml"
        assert issue["path"] == ["yaml"]
        assert issue["message"] == "The YAML document must be a binary string."
      end
    end
  end

  describe "STUDY-YAML-01 non-map roots" do
    test "rejects a sequence root" do
      assert {:error, error} = Yaml.parse("- 1\n- 2\n")
      assert_root_issue(error)
    end

    test "rejects a scalar root" do
      assert {:error, error} = Yaml.parse("plain text\n")
      assert_root_issue(error)
    end
  end

  describe "STUDY-YAML-01 unsafe values" do
    test "rejects a non-JSON value at its path" do
      assert {:error, error} = Yaml.parse("settings:\n  ratio: .inf\n")

      assert error.code == "validation_failed"
      assert [issue] = error.issues
      assert issue["code"] == "invalid_json_value"
      assert issue["path"] == ["settings", "ratio"]
      assert issue["message"] == "The study definition contains a value that is not valid JSON."

      refute inspect(error) =~ "+inf"
    end

    test "rejects a non-string key at the containing path" do
      assert {:error, error} = Yaml.parse("1: value\n")

      assert error.code == "validation_failed"
      assert [issue] = error.issues
      assert issue["code"] == "invalid_json_value"
      assert issue["path"] == []
    end
  end

  describe "STUDY-YAML-01 unsafe encodings" do
    test "rejects an invalid UTF-8 map key instead of putting it in a depth path" do
      assert {:error, error} = Yaml.parse(bad_key_with_deep_value())

      assert error.code == "validation_failed"
      assert [issue] = error.issues
      assert issue["code"] == "invalid_json_value"
      assert issue["path"] == []
      assert_encodable(error)
    end

    test "keeps an invalid UTF-8 key out of a nested error path" do
      assert {:error, error} = Yaml.parse(bad_key_under_valid_key_with_deep_value())

      assert [issue] = error.issues
      assert issue["code"] == "invalid_json_value"
      assert issue["path"] == ["outer"]
      assert_encodable(error)
    end

    test "rejects an invalid UTF-8 value at its exact path" do
      assert {:error, error} = Yaml.parse("settings:\n  blob: !!binary /w==\n")

      assert error.code == "validation_failed"
      assert [issue] = error.issues
      assert issue["code"] == "invalid_json_value"
      assert issue["path"] == ["settings", "blob"]
      assert issue["message"] == "The study definition contains a value that is not valid JSON."
      assert_encodable(error)
    end

    test "rejects an invalid UTF-8 sequence value at its index" do
      assert {:error, error} = Yaml.parse("items:\n  - ok\n  - !!binary /w==\n")

      assert [issue] = error.issues
      assert issue["code"] == "invalid_json_value"
      assert issue["path"] == ["items", 1]
      assert_encodable(error)
    end

    test "reports a limit before traversing an invalid UTF-8 key" do
      assert {:error, error} = Yaml.parse(wide_map_with_bad_key(@max_entries + 1))

      assert [issue] = error.issues
      assert issue["code"] == "invalid_yaml"
      assert issue["path"] == []
      assert issue["details"] == %{"limit" => @max_entries, "actual" => @max_entries + 1}
      assert_encodable(error)
    end

    test "every boundary error encodes as JSON" do
      for document <- unsafe_documents() do
        assert {:error, error} = Yaml.parse(document), "expected an error for probe document"
        assert [issue] = error.issues
        assert byte_size(issue["message"]) <= 256
        assert_encodable(error)
      end
    end
  end

  describe "STUDY-YAML-01 byte limits" do
    test "accepts an input document exactly at the byte limit" do
      yaml = fitting_document(@input_limit)
      assert byte_size(yaml) == @input_limit
      assert {:ok, %{"a" => 1}} = Yaml.parse(yaml)
    end

    test "rejects an input document above the byte limit before parsing" do
      assert {:error, error} = Yaml.parse(fitting_document(@input_limit) <> "x")

      assert error.code == "request_too_large"
      assert [issue] = error.issues
      assert issue["code"] == "request_too_large"
      assert issue["path"] == []
      assert issue["details"] == %{"limit_bytes" => @input_limit}
    end

    test "rejects oversized malformed input by size, not by parser failure" do
      assert {:error, error} = Yaml.parse(String.duplicate("a: [\n", 400_000))
      assert error.code == "request_too_large"
    end

    test "rejects normalized JSON above the byte limit" do
      yaml = alias_expanding_document()
      assert byte_size(yaml) < @input_limit

      assert {:error, error} = Yaml.parse(yaml)

      assert error.code == "request_too_large"
      assert [issue] = error.issues
      assert issue["code"] == "request_too_large"
      assert issue["details"] == %{"limit_bytes" => @input_limit}
    end

    test "accepts normalized JSON exactly at the byte limit" do
      {document, padding} = exact_normalized_document()

      assert byte_size(Jason.encode!(%{"a" => String.duplicate("x", padding)})) == @input_limit
      assert {:ok, %{"a" => payload}} = Yaml.parse(document)
      assert byte_size(payload) == padding

      {bigger, _padding} = exact_normalized_document(1)
      assert {:error, error} = Yaml.parse(bigger)
      assert error.code == "request_too_large"
    end
  end

  describe "STUDY-YAML-01 nesting depth" do
    test "accepts 32 nested levels and rejects 33" do
      assert {:ok, _parsed} = Yaml.parse(nested_maps(@max_depth))

      assert {:error, error} = Yaml.parse(nested_maps(@max_depth + 1))

      assert [issue] = error.issues
      assert issue["code"] == "invalid_yaml"
      assert issue["path"] == List.duplicate("a", 32)
      assert issue["message"] == "The YAML document nests deeper than the depth limit."
      assert issue["details"] == %{"limit" => @max_depth, "actual" => @max_depth + 1}
    end

    test "counts nested sequences toward the depth limit" do
      assert {:ok, _parsed} = Yaml.parse(nested_lists(@max_depth - 1))
      assert {:error, error} = Yaml.parse(nested_lists(@max_depth))

      assert [issue] = error.issues
      assert issue["code"] == "invalid_yaml"
      assert issue["details"]["limit"] == @max_depth
    end
  end

  describe "STUDY-YAML-01 collection entries" do
    test "accepts a map at the entry limit and rejects one above it" do
      assert {:ok, parsed} = Yaml.parse(wide_map(@max_entries))
      assert map_size(parsed) == @max_entries

      assert {:error, error} = Yaml.parse(wide_map(@max_entries + 1))

      assert [issue] = error.issues
      assert issue["code"] == "invalid_yaml"
      assert issue["path"] == []
      assert issue["message"] == "The YAML document holds more entries than the collection limit."
      assert issue["details"] == %{"limit" => @max_entries, "actual" => @max_entries + 1}
    end

    test "accepts a sequence at the entry limit and rejects one above it" do
      assert {:ok, parsed} = Yaml.parse(wide_list(@max_entries))
      assert length(parsed["items"]) == @max_entries

      assert {:error, error} = Yaml.parse(wide_list(@max_entries + 1))

      assert [issue] = error.issues
      assert issue["code"] == "invalid_yaml"
      assert issue["path"] == ["items"]
      assert issue["details"] == %{"limit" => @max_entries, "actual" => @max_entries + 1}
    end
  end

  defp assert_root_issue(error) do
    assert error.code == "validation_failed"
    assert [issue] = error.issues
    assert issue["code"] == "invalid_yaml"
    assert issue["path"] == ["yaml"]
    assert issue["message"] == "The YAML document root must be a mapping."
  end

  defp keys(value) when is_map(value),
    do: Map.keys(value) ++ Enum.flat_map(value, fn {_key, nested} -> keys(nested) end)

  defp keys(value) when is_list(value), do: Enum.flat_map(value, &keys/1)
  defp keys(_value), do: []

  # The wire form of one boundary error. It must always encode as JSON.
  defp envelope(error) do
    %{
      "schema_version" => error.schema_version,
      "error" => %{"code" => error.code, "issues" => error.issues}
    }
  end

  defp assert_encodable(error) do
    assert {:ok, _iodata} = Jason.encode_to_iodata(envelope(error))
    assert {:ok, _attrs} = ErrorEnvelope.materialize(envelope(error))
  end

  defp unsafe_documents do
    [
      "a: [1,\n",
      "- 1\n",
      "plain text\n",
      "1: value\n",
      "settings:\n  ratio: .inf\n",
      "settings:\n  blob: !!binary /w==\n",
      "items:\n  - ok\n  - !!binary /w==\n",
      "? !!binary /w==\n: 1\n",
      bad_key_with_deep_value(),
      bad_key_under_valid_key_with_deep_value(),
      nested_maps(@max_depth + 1),
      wide_map(@max_entries + 1),
      wide_map_with_bad_key(@max_entries + 1),
      wide_list(@max_entries + 1),
      fitting_document(@input_limit) <> "x",
      alias_expanding_document()
    ]
  end

  # A valid document with an unsafe root key and a value past the depth limit.
  defp bad_key_with_deep_value do
    "? !!binary /w==\n: " <> nested_list_value(@max_depth) <> "\n"
  end

  # The same shape one level down, so the safe part of the path is not empty.
  defp bad_key_under_valid_key_with_deep_value do
    "outer:\n  ? !!binary /w==\n  : " <> nested_list_value(@max_depth) <> "\n"
  end

  defp wide_map_with_bad_key(entries) do
    "? !!binary /w==\n: 0\n" <>
      Enum.map_join(1..(entries - 1), "\n", fn index -> "k#{index}: #{index}" end)
  end

  # The document normalizes to a JSON object of one exact byte size.
  defp exact_normalized_document(extra \\ 0) do
    padding = @input_limit - 8 + extra
    {"a: " <> String.duplicate("x", padding), padding}
  end

  # A tiny valid document padded with a comment to an exact byte size.
  defp fitting_document(bytes), do: "a: 1\n#" <> String.duplicate("x", bytes - 6)

  # Anchors copy the referenced value, so a small document normalizes to a large
  # JSON document.
  defp alias_expanding_document do
    payload = String.duplicate("x", 1_200)
    aliases = Enum.map_join(1..1_050, "\n", fn index -> "k#{index}: *a" end)
    "a: &a \"" <> payload <> "\"\n" <> aliases
  end

  defp nested_maps(levels),
    do: String.duplicate("{a: ", levels) <> "1" <> String.duplicate("}", levels)

  defp nested_lists(levels) do
    "a: " <>
      String.duplicate("[", levels) <> "1" <> String.duplicate("]", levels)
  end

  defp nested_list_value(levels) do
    String.duplicate("[", levels) <> "1" <> String.duplicate("]", levels)
  end

  defp wide_map(entries) do
    Enum.map_join(0..(entries - 1), "\n", fn index -> "k#{index}: #{index}" end)
  end

  defp wide_list(entries) do
    "items:\n" <> Enum.map_join(0..(entries - 1), "\n", fn index -> "  - #{index}" end)
  end
end
