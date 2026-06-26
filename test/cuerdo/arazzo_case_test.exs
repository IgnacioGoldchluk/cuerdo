defmodule Cuerdo.ArazzoCaseTest do
  use ExUnit.Case

  alias Cuerdo.ArazzoCase.{Report, Result, Runner}

  import Cuerdo.ArazzoFixtures

  describe "run_all/3" do
    test "executes num_cases when halt_on_error is false" do
      Req.Test.expect(Cuerdo.Client, 2, fn conn ->
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
        num_runs: 2,
        transform_inputs: %{},
        halt_on_error: false
      ]

      result = Runner.run_all(workflow_id, document, opts)
      assert [%Result{status: :failed}, %Result{status: :failed}] = result
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
        num_runs: 3,
        transform_inputs: %{},
        halt_on_error: true
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

      Req.Test.expect(Cuerdo.Client, 1, fn conn ->
        %{"min_age" => min_age, "name" => name} = conn.params
        min_age = String.to_integer(min_age)

        Req.Test.json(conn, [
          # Incorrect age returned
          %{"name" => "#{name}abc", "age" => min_age - 2}
        ])
      end)

      %{document: people_document(with_self: true)}
    end

    test "writes result summary to stdout", %{document: document} do
      workflow_id = "getPeople"

      opts = [
        json_schema_resolver: Cuerdo.Resolver,
        num_runs: 3,
        transform_inputs: %{},
        halt_on_error: true
      ]

      result = Runner.run_all(workflow_id, document, opts)

      total_time = Enum.sum_by(result, & &1.execution_time_ms)

      expected_msg =
        """

        Arazzo document test suite summary

        Total execution time: #{total_time}ms

        +-------------+--------+-------+
        | Workflow ID | PASSED | TOTAL |
        +-------------+--------+-------+
        | getPeople   | 1      | 2     |
        +-------------+--------+-------+


        """

      assert ExUnit.CaptureIO.capture_io(fn -> Report.write(:stdout, result, nil) end) ==
               expected_msg
    end

    test "%Result is JSON encoded for passing and failing results", %{document: document} do
      workflow_id = "getPeople"

      opts = [
        json_schema_resolver: Cuerdo.Resolver,
        num_runs: 3,
        transform_inputs: %{},
        halt_on_error: true
      ]

      [r1, r2] = result = Runner.run_all(workflow_id, document, opts)

      [r1_serialized, r2_serialized] = result |> JSON.encode!() |> JSON.decode!()

      assert r1_serialized["workflow_id"] == r1.workflow_id
      assert r1_serialized["reason"] == nil
      assert r1_serialized["execution_time_ms"] == r1.execution_time_ms
      assert r1_serialized["status"] == "passed"

      assert r2_serialized["reason"] == Exception.message(r2.reason)
      assert r2_serialized["status"] == "failed"
      assert length(r2_serialized["logs"]["entries"]) == 1
    end
  end
end
