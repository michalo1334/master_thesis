defmodule NetworkDefense.Evaluation.TaskFailureCodec do
  @moduledoc false

  @version 1
  @max_bytes 65_536

  def decode(%{"type" => type, "message" => message}, kind, retryable_exception, parser)
      when is_binary(message) and byte_size(message) <= @max_bytes do
    if type in ["Gust.DAG.NonRecError", inspect(retryable_exception)] do
      with {:ok, envelope} <- Jason.decode(message),
           %{"kind" => ^kind, "version" => @version, "error" => error_map} <- envelope,
           {:ok, error} <- parser.(error_map) do
        {:ok, error}
      else
        _other -> :error
      end
    else
      :error
    end
  end

  def decode(_error, _kind, _retryable_exception, _parser), do: :error

  def encode(error, kind, encoder, fallback) do
    envelope = envelope(kind, encoder.(error))

    case Jason.encode(envelope) do
      {:ok, encoded} when byte_size(encoded) <= @max_bytes -> encoded
      _other -> fallback_message(kind, encoder, fallback)
    end
  rescue
    _exception -> fallback_message(kind, encoder, fallback)
  end

  defp fallback_message(kind, encoder, fallback) do
    Jason.encode!(envelope(kind, encoder.(fallback.())))
  end

  defp envelope(kind, error), do: %{"kind" => kind, "version" => @version, "error" => error}
end
