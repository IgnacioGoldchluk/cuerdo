defmodule Cuerdo.CLITest do
  use ExUnit.Case

  alias Cuerdo.CLI

  import Cuerdo.ArazzoFixtures

  import ExUnit.CaptureIO

  describe "run/1" do
    test "early return with error on invalid args" do
      args = [Path.join(["test", "support", "arazzo.yaml"]), "--nun-runs", "1"]

      capture_io(fn ->
        assert {:error, %CLI.Errors.UnexpectedArgs{}} = CLI.run(args)
      end)
    end

    test "returns single error result on failure" do
      args = [Path.join(["test", "support", "arazzo.yaml"]), "--max-runs", "1"]

      Req.Test.expect(Cuerdo.Resolver, &Req.Test.transport_error(&1, :econnrefused))

      # Silence stdout summary
      capture_io(fn ->
        assert {:ok, [result]} = CLI.run(args)
        assert result.status == :error
      end)
    end

    test "returns list of results on successful execution" do
      args = [Path.join(["test", "support", "arazzo.yaml"]), "--max-runs", "1"]

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

      capture_io(fn ->
        {:ok, [result]} = CLI.run(args)
        assert result.status == :passed
        assert result.inputs["book"] == Agent.get(agent, fn book -> Map.delete(book, "id") end)
      end)
    end
  end
end
