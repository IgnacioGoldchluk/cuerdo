defmodule Cuerdo.ArazzoCase.Report do
  @moduledoc false

  alias Cuerdo.ArazzoCase.Result

  @spec write(:json, list[Result.t()], String.t() | nil, String.t()) :: :ok | {:error, any()}
  def write(:json, results, filename, document_path), do: json(filename, results, document_path)

  defp json(filename, results, document_path) when is_binary(filename) and is_list(results) do
    report = %{"arazzo_document" => document_path, "results" => results}
    File.write(filename, JSON.encode!(report))
  end
end
