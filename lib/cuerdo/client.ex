defmodule Cuerdo.Client do
  @moduledoc false

  alias Cuerdo.Arazzo.Utils
  alias Cuerdo.Errors.{InvalidFile, InvalidResponse}

  @doc """
  Fetches and decodes the OpenAPI or Arazzo spec at the given URL or local path
  """
  @spec fetch_schema(String.t()) :: {:ok, map()} | {:error, any()}
  def fetch_schema(url) do
    case URI.parse(url) do
      %URI{scheme: scheme} when scheme in [nil, "file"] ->
        fetch_local(url)

      _ ->
        case do_fetch_schema(url) do
          {:ok, %Req.Response{status: status} = response} when status < 400 and status >= 200 ->
            decode_schema(response.body)

          {:ok, %Req.Response{} = response} ->
            {:error, %InvalidResponse{response: response}}

          {:error, e} when is_exception(e) ->
            {:error, e}
        end
    end
  end

  defp fetch_local(file_path) do
    file_path
    |> String.trim_leading(Utils.linux_file_prefix())
    |> File.read()
    |> case do
      {:ok, contents} -> decode_schema(contents)
      {:error, reason} -> {:error, %InvalidFile{filename: file_path, reason: reason}}
    end
  end

  defp do_fetch_schema(url) do
    [url: url]
    |> Keyword.merge(Application.get_env(:cuerdo, :client_options, []))
    |> Req.request()
  end

  defp decode_schema(schema) when is_map(schema), do: {:ok, schema}

  defp decode_schema(schema) do
    case JSON.decode(schema) do
      {:ok, decoded} -> {:ok, decoded}
      {:error, _} -> YamlElixir.read_from_string(schema)
    end
  end
end
