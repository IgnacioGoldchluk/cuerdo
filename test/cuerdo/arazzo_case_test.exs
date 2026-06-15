defmodule Cuerdo.ArazzoCaseTest do
  use ExUnit.Case

  alias Cuerdo.ArazzoCase.Result

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

      result = Cuerdo.ArazzoCase.run_all(workflow_id, document, opts)
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

      result = Cuerdo.ArazzoCase.run_all(workflow_id, document, opts)
      [%Result{status: :passed}, %Result{status: :failed} = error_result] = result
      msg = Result.format_message(error_result)
      assert String.starts_with?(msg, "FAILED getPeople")
    end
  end
end
