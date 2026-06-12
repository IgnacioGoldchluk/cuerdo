defmodule Cuerdo.ArazzoFixtures do
  @moduledoc """
  Fixtures for Arazzo data
  """
  alias Cuerdo.Arazzo.Context

  @openapi ["test", "support", "openapi.json"]
  @arazzo ["test", "support", "arazzo.yaml"]

  @external_resource Path.join(@arazzo)
  @external_resource Path.join(@openapi)

  @example_document Path.join(@arazzo) |> YamlElixir.read_from_file!()
  @example_openapi_json Path.join(@openapi) |> File.read!() |> JSON.decode!()

  def default_context do
    mock_openapi_fetch()
    document = example_document()
    Context.new!(document)
  end

  def people_document(opts \\ []) do
    with_self = Keyword.get(opts, :with_self, false)
    location = Path.join(["test", "support", "people", "arazzo.yaml"])

    YamlElixir.read_from_file!(location)
    |> then(fn document ->
      if(with_self, do: Map.put(document, "$self", location), else: document)
    end)
  end

  def example_document, do: @example_document
  def example_openapi_json, do: @example_openapi_json

  def openapi_url, do: "https://example#{System.unique_integer()}.com/openapi.json"

  def source_description do
    %{
      "type" => "openapi",
      "url" => openapi_url(),
      "name" => "OpenAPI#{System.unique_integer()}"
    }
  end

  def mock_openapi_fetch(document \\ @example_openapi_json) do
    Req.Test.expect(Cuerdo.Client, &Req.Test.json(&1, document))
  end

  # Generators for Arazzo documents
  def with_unique_email(input) do
    input
    |> Map.put("email", "user#{System.unique_integer([:positive])}@email.com")
    |> StreamData.constant()
  end
end
