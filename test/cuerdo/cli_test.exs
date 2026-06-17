defmodule Cuerdo.CLITest do
  use ExUnit.Case

  alias Cuerdo.CLI

  import Cuerdo.ArazzoFixtures

  describe "run/1" do
    test "returns list of results on successful execution" do
      args = ["--document", Path.join(["test", "support", "arazzo.yaml"]), "--num-runs", "1"]

      # Mock for validating the inputs
      Req.Test.expect(Cuerdo.Resolver, 1, fn conn ->
        assert conn.request_path == "/openapi.json"
        Req.Test.json(conn, example_openapi_json())
      end)

      # Mock when fetching the operation. Happens only once because we store
      # in cache for all the workflow runs
      Req.Test.expect(Cuerdo.Client, 1, fn conn ->
        assert conn.request_path == "/openapi.json"
        Req.Test.json(conn, example_openapi_json())
      end)

      book_id = System.unique_integer([:positive])

      # Payload is generated dynamically but we have to return it again
      {:ok, agent} = Agent.start_link(fn -> nil end)
      # POST request
      Req.Test.expect(Cuerdo.Client, 1, fn %Plug.Conn{} = conn ->
        assert conn.method == "POST"
        assert conn.request_path == "/books"

        result = Map.put(conn.body_params, "id", book_id)
        Agent.update(agent, fn nil -> result end)

        conn |> Plug.Conn.put_status(201) |> Req.Test.json(result)
      end)

      # GET the params
      Req.Test.expect(Cuerdo.Client, 1, fn conn ->
        assert conn.method == "GET"

        book = Agent.get(agent, fn book -> book end)
        assert conn.request_path == "/books/#{book["id"]}"

        Req.Test.json(conn, book)
      end)

      # List books
      Req.Test.expect(Cuerdo.Client, 1, fn conn ->
        assert conn.method == "GET"
        assert conn.request_path == "/books"

        book = Agent.get(agent, fn book -> book end)
        Req.Test.json(conn, [book])
      end)

      {:ok, [result]} = CLI.run(args)
      assert result.status == :passed
      assert result.inputs["book"] == Agent.get(agent, fn book -> Map.delete(book, "id") end)
    end
  end
end
