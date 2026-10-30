defmodule NetworkDefense.Evaluation2.Study.Persistence.UuidCodec do
  @moduledoc false

  # Spectral codec for `Ecto.UUID.t()` inside stored JSONB values.
  #
  # The value tree keeps UUID identifiers, while JSON stores them as canonical
  # strings. Both directions accept one binary string of 36 bytes and pass it
  # through `Ecto.UUID.cast/1`, so the codec validates and canonicalizes without
  # reading external type metadata.
  #
  # The codec owns one JSON reference only: `{Ecto.UUID, {:type, :t, 0}}`. Any
  # other value or length for that reference is a type mismatch, and any other
  # reference continues to the default Spectral codec.
  #
  # The type belongs to the Ecto library module, so the codec is registered in
  # `config/config.exs` instead of a `use Spectral` annotation.

  use Spectral.Codec

  @type_ref {:type, :t, 0}
  @uuid_string_size 36

  @impl Spectral.Codec
  def encode(:json, _caller_type_info, {:type, :t, 0}, _target_type, value, _config),
    do: cast(value)

  def encode(_format, _caller_type_info, {:type, :t, 0}, _target_type, value, _config),
    do: mismatch(value)

  def encode(_format, _caller_type_info, _type_ref, _target_type, _data, _config), do: :continue

  @impl Spectral.Codec
  def decode(:json, _caller_type_info, {:type, :t, 0}, _target_type, input, _config),
    do: cast(input)

  def decode(_format, _caller_type_info, {:type, :t, 0}, _target_type, input, _config),
    do: mismatch(input)

  def decode(_format, _caller_type_info, _type_ref, _target_type, _data, _config), do: :continue

  defp cast(value) when is_binary(value) and byte_size(value) == @uuid_string_size do
    case Ecto.UUID.cast(value) do
      {:ok, uuid} -> {:ok, uuid}
      :error -> mismatch(value)
    end
  end

  defp cast(value), do: mismatch(value)

  defp mismatch(value), do: Spectral.Error.type_mismatch(@type_ref, value)
end
