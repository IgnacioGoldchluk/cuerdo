defmodule Cuerdo.Arazzo.Request do
  @moduledoc """
  Functionality to build and validate requests in Arazzo workflows
  """

  alias Cuerdo.Arazzo.{Context, Document}
  alias Cuerdo.Errors.InvalidRequest

  @doc """
  Returns the base URL for the given source description name
  """
  @spec fetch_base_url(String.t(), Context.t()) :: {:ok, String.t()} | {:error, Exception.t()}
  def fetch_base_url(source_description_name, %Context{} = context) do
    %{url: source_description_url} =
      Document.source_description(context.document, source_description_name)

    source_description_uri = URI.parse(source_description_url)

    # We can ignore the updated context since we fetched the operation already
    case Context.fetch_source_description(context, source_description_name) do
      {:ok, %{"servers" => [%{"url" => url} | _]}, _updated_ctx} ->
        # Grab the first URL, if it's relative then inclue the base URL too
        url = URI.parse(url)
        if(relative?(url), do: %URI{source_description_uri | path: url.path}, else: url)

      {:ok, schema, _updated_ctx} when not is_map_key(schema, "servers") ->
        # No servers specified, it's same as OpenAPI document location base URI
        %URI{source_description_uri | path: nil, fragment: nil, query: nil}
    end
    |> case do
      %URI{scheme: scheme} = uri when scheme not in ["http", "https"] ->
        {:error, %InvalidRequest{message: "expected HTTP/HTTPS OpenAPI URL, got: #{uri}"}}

      %URI{} = uri ->
        {:ok, to_string(uri)}
    end
  end

  defp relative?(%URI{host: host}), do: is_nil(host)
end
