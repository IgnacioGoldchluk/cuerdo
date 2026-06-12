defmodule Cuerdo.ResolverTest do
  use ExUnit.Case

  alias Cuerdo.Resolver

  describe "resolve/2" do
    test "returns cached schema" do
      schema = %{"type" => "object"}
      url = "https://example.com"
      Resolver.store_schema(url, schema)

      assert {:ok, schema} == Resolver.resolve(url, [])
    end

    test "returns error for error status code" do
      Req.Test.expect(Cuerdo.Resolver, &Plug.Conn.send_resp(&1, 404, ""))
      assert {:error, "unexpected response" <> _} = Resolver.resolve("http://example.com", [])
    end

    test "returns error when response is invalid JSON" do
      url = "https://example.com"

      schema = """
      type: integer
      minimum: 10
      """

      Req.Test.expect(Cuerdo.Resolver, 1, &Plug.Conn.send_resp(&1, 200, schema))
      assert {:error, "invalid JSON: " <> _} = Resolver.resolve(url, [])
    end

    test "decodes body when received as binary" do
      schema = %{"type" => "string"}
      url = "https://example.com"
      Req.Test.expect(Cuerdo.Resolver, 1, &Plug.Conn.send_resp(&1, 200, JSON.encode!(schema)))

      assert {:ok, schema} == Resolver.resolve(url, [])
    end

    test "stores in cache when schema is not present" do
      schema = %{"type" => "string"}
      url = "https://example.com"
      Req.Test.expect(Cuerdo.Resolver, 1, &Req.Test.json(&1, schema))

      assert {:ok, schema} == Resolver.resolve(url, [])
      assert {:ok, schema} == Resolver.resolve(url, [])
    end
  end
end
