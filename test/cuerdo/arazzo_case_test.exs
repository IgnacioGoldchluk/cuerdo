defmodule Cuerdo.ArazzoCaseTest do
  use ExUnit.Case

  alias Cuerdo.ArazzoCase.{Result, Runner}

  import Cuerdo.ArazzoFixtures

  describe "run_all/3" do
    test "executes single case on failure" do
      Req.Test.expect(Cuerdo.Client, 1, fn conn ->
        %{"min_age" => min_age, "name" => name} = conn.params
        min_age = String.to_integer(min_age)

        Req.Test.json(conn, [
          %{"name" => "#{name}abc", "age" => min_age - 2}
        ])
      end)

      document = people_document(with_self: true)
      workflow_id = "getPeople"

      opts = [
        json_schema_resolver: Cuerdo.Resolver,
        max_runs: 2,
        transform_inputs: %{},
        max_shrink_steps: 0
      ]

      result = Runner.run_all(workflow_id, document, opts)
      assert [%Result{status: :failed}] = result
    end

    test "returns result struct with failure and error cases" do
      # 1st case pass, 2nd fails
      Req.Test.expect(Cuerdo.Client, 1, fn conn ->
        %{"min_age" => min_age, "name" => name} = conn.params
        min_age = String.to_integer(min_age)

        Req.Test.json(conn, [
          %{"name" => "#{name}abc", "age" => min_age + 2}
        ])
      end)

      Req.Test.expect(Cuerdo.Client, 1, fn conn ->
        %{"min_age" => min_age, "name" => name} = conn.params
        min_age = String.to_integer(min_age)

        Req.Test.json(conn, [
          # Incorrect age returned
          %{"name" => "#{name}abc", "age" => min_age - 2}
        ])
      end)

      document = people_document(with_self: true)
      workflow_id = "getPeople"

      opts = [
        json_schema_resolver: Cuerdo.Resolver,
        max_runs: 3,
        transform_inputs: %{},
        max_shrink_steps: 0
      ]

      result = Runner.run_all(workflow_id, document, opts)
      [%Result{status: :passed}, %Result{status: :failed} = error_result] = result
      msg = Result.format_message(error_result)
      assert String.starts_with?(msg, "FAILED getPeople")
    end
  end

  describe "result and reports" do
    setup do
      # 1st case pass, 2nd fails
      Req.Test.expect(Cuerdo.Client, 1, fn conn ->
        %{"min_age" => min_age, "name" => name} = conn.params
        min_age = String.to_integer(min_age)

        Req.Test.json(conn, [
          %{"name" => "#{name}abc", "age" => min_age + 2}
        ])
      end)

      Req.Test.expect(Cuerdo.Client, 2, fn conn ->
        %{"min_age" => min_age, "name" => name} = conn.params
        min_age = String.to_integer(min_age)

        Req.Test.json(conn, [
          # Incorrect age returned
          %{"name" => "#{name}abc", "age" => min_age - 2}
        ])
      end)

      %{document: people_document(with_self: true)}
    end

    test "%Result is JSON encoded for passing and failing results", %{document: document} do
      workflow_id = "getPeople"

      opts = [
        json_schema_resolver: Cuerdo.Resolver,
        max_runs: 2,
        transform_inputs: %{},
        max_shrink_steps: 1
      ]

      [r1, r2, _] = result = Runner.run_all(workflow_id, document, opts)
      [r1_serialized, r2_serialized, _] = result |> JSON.encode!() |> JSON.decode!()

      assert r1_serialized["workflow_id"] == r1.workflow_id
      assert r1_serialized["reason"] == nil
      assert r1_serialized["execution_time_ms"] == r1.execution_time_ms
      assert r1_serialized["status"] == "passed"

      assert r2_serialized["reason"] == Exception.message(r2.reason)
      assert r2_serialized["status"] == "failed"
      assert length(r2_serialized["logs"]["entries"]) == 2
    end
  end
end
