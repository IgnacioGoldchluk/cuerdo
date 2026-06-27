defmodule Cuerdo.Resolver do
  @moduledoc false
  @behaviour JSV.Resolver

  @table_key :cuerdo_process_cache

  @to_ignore [
    "https://json-schema.org/draft/2020-12/schema",
    "http://json-schema.org/draft-07/schema#",
    "http://json-schema.org/draft-07/schema"
  ]

  @impl true
  def resolve(url, _) when url in @to_ignore, do: {:error, :ignored}

  def resolve("file://" <> file_path, _opts) do
    case File.read(file_path) do
      {:ok, contents} -> JSON.decode(contents)
      error -> error
    end
  end

  def resolve(url, _opts) do
    case :ets.lookup(table(), {:schema, url}) do
      [] -> fetch_schema(url)
      [{{:schema, _url}, schema}] -> {:ok, schema}
    end
  end

  defp fetch_schema(url) do
    case do_fetch_schema(url) do
      {:ok, %Req.Response{body: body, status: status}} when is_map(body) and status < 399 ->
        store_schema(url, body)
        resolve(url, [])

      {:ok, %Req.Response{body: body, status: status}} when is_binary(body) and status < 399 ->
        case JSON.decode(body) do
          {:ok, decoded} ->
            store_schema(url, decoded)
            resolve(url, [])

          {:error, _reason} ->
            {:error, "invalid JSON: #{body}"}
        end

      {:ok, %Req.Response{} = response} ->
        {:error, "unexpected response: #{inspect(response)}"}

      {:error, _reason} = error ->
        error
    end
  end

  defp do_fetch_schema(url) do
    [url: url]
    |> Keyword.merge(Application.get_env(:cuerdo, :resolver_options, []))
    |> Req.request()
  end

  defp table do
    case Process.get(@table_key) do
      nil ->
        Process.put(@table_key, :ets.new(:whatever, [:set, :protected]))
        table()

      table_ref when is_reference(table_ref) ->
        table_ref
    end
  end

  def store_schema(url, schema), do: :ets.insert(table(), {{:schema, url}, schema})
end
