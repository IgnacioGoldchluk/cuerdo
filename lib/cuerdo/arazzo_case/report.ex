defmodule Cuerdo.ArazzoCase.Report do
  @moduledoc false

  alias Cuerdo.ArazzoCase.Result

  @spec write(:json, list[Result.t()], String.t() | nil) :: :ok | {:error, any()}
  def write(:json, results, filename), do: json(filename, results)

  defp json(filename, results) when is_binary(filename) and is_list(results) do
    File.write(filename, JSON.encode!(results))
  end
end
