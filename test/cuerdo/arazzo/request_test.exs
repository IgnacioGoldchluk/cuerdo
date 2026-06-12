defmodule Cuerdo.Arazzo.RequestTest do
  use ExUnit.Case

  alias Cuerdo.Arazzo.Context
  alias Cuerdo.Arazzo.Request

  import Cuerdo.ArazzoFixtures

  setup_all do
    %{document: example_document()}
  end

  describe "fetch_base_url/2" do
    test "returns sourceDescription URL if spec doesn't have servers", %{document: document} do
      mock_openapi_fetch()
      %{"sourceDescriptions" => [%{"name" => name, "url" => url}]} = document
      ctx = Context.new!(document)

      expected = %URI{URI.parse(url) | path: nil, fragment: nil, query: nil} |> to_string()
      assert {:ok, expected} == Request.fetch_base_url(name, ctx)
    end

    test "returns URL if servers has full URL", %{document: document} do
      %{"sourceDescriptions" => [%{"name" => name}]} = document

      full_url = "https://example#{System.unique_integer()}.com/api/v1"
      openapi_document = Map.put(example_openapi_json(), "servers", [%{"url" => full_url}])
      mock_openapi_fetch(openapi_document)

      ctx = Context.new!(document)
      assert {:ok, full_url} == Request.fetch_base_url(name, ctx)
    end

    test "returns the first URL from servers", %{document: document} do
      %{"sourceDescriptions" => [%{"name" => name}]} = document
      full_url = "https://example#{System.unique_integer()}.com"

      openapi_document =
        Map.put(example_openapi_json(), "servers", [
          %{"url" => full_url},
          %{"url" => "/api/v1"}
        ])

      mock_openapi_fetch(openapi_document)

      ctx = Context.new!(document)

      assert {:ok, full_url} == Request.fetch_base_url(name, ctx)
    end

    test "returns composed URL if servers URL is relative", %{document: document} do
      %{"sourceDescriptions" => [%{"name" => name, "url" => url}]} = document

      openapi_document = Map.put(example_openapi_json(), "servers", [%{"url" => "/api/v1"}])
      mock_openapi_fetch(openapi_document)

      ctx = Context.new!(document)
      expected = %{URI.parse(url) | path: "/api/v1", fragment: nil, query: nil} |> to_string()
      assert {:ok, expected} == Request.fetch_base_url(name, ctx)
    end
  end
end
