defmodule Cuerdo.Arazzo.Criterion.SimpleTest do
  use ExUnit.Case

  alias Cuerdo.Arazzo.Context
  alias Cuerdo.Arazzo.Criterion.Simple

  alias Cuerdo.Errors.InvalidExpression

  import Cuerdo.ArazzoFixtures

  describe "evaluate/3" do
    test "returns error when expression is invalid" do
      context = default_context()
      {workflow_id, step_id} = workflow_and_step_id(context)
      rev_path = [0, "steps", 0, "workflows"]

      response = %Req.Response{
        status: 201,
        headers: %{"content-type" => ["application/json"]},
        body: nil
      }

      context =
        context
        |> Context.put_step_output(workflow_id, step_id, "bookId", 123)
        |> Context.put_step_response(workflow_id, step_id, response)

      expression = "$stausCode == 201"

      assert {:error, %InvalidExpression{expression: "$stausCode == 201"}} =
               Simple.evaluate(expression, rev_path, context)

      # Wrong number
      expression = "$statusCode == 201.1.2"

      assert {:error, %InvalidExpression{expression: ^expression}} =
               Simple.evaluate(expression, rev_path, context)

      # Wrong character
      expression = "$statusCode == 2 & 5"

      assert {:error, %InvalidExpression{expression: ^expression}} =
               Simple.evaluate(expression, rev_path, context)
    end

    test "returns error when ordinal comparison cannot coerce to number" do
      context = default_context()
      {workflow_id, step_id} = workflow_and_step_id(context)
      rev_path = [0, "steps", 0, "workflows"]

      response = %Req.Response{
        status: 201,
        headers: %{"content-type" => ["application/json"]},
        body: nil
      }

      context =
        context
        |> Context.put_step_output(workflow_id, step_id, "bookId", 123)
        |> Context.put_step_response(workflow_id, step_id, response)

      expression = "$statusCode > true"
      assert {:ok, false} == Simple.evaluate(expression, rev_path, context)

      expression = "$statusCode < 'NotNumber'"
      assert {:ok, false} == Simple.evaluate(expression, rev_path, context)

      expression = "$statusCode != '201'"
      assert {:ok, true} == Simple.evaluate(expression, rev_path, context)
    end

    test "returns ok+boolean tuple when expression is valid" do
      context = default_context()
      {workflow_id, step_id} = workflow_and_step_id(context)
      rev_path = [0, "steps", 0, "workflows"]

      response = %Req.Response{
        status: 201,
        headers: %{"content-type" => ["application/json"]},
        body: nil
      }

      context =
        context
        |> Context.put_step_output(workflow_id, step_id, "bookId", 123)
        |> Context.put_step_response(workflow_id, step_id, response)

      expression =
        "$steps.createBookStep.outputs.bookId == 123 && $statusCode >= 200 && $statusCode < 400"

      assert {:ok, true} == Simple.evaluate(expression, rev_path, context)
    end

    test "strings are compared case-insensitive" do
      context = default_context()
      {workflow_id, step_id} = workflow_and_step_id(context)
      rev_path = [0, "steps", 0, "workflows"]

      response = %Req.Response{
        status: 201,
        headers: %{"content-type" => ["application/json"], "x-rate-limit" => ["300"]},
        body: %{"name" => "Alice"}
      }

      context =
        context
        |> Context.put_step_response(workflow_id, step_id, response)

      expression =
        "$response.body#/name == 'alice' || $response.header.X-Rate-Limit <= '300'"

      assert {:ok, true} == Simple.evaluate(expression, rev_path, context)
    end

    test "strings are coerced to numbers for ordinal comparison" do
      context = default_context()
      {workflow_id, step_id} = workflow_and_step_id(context)
      rev_path = [0, "steps", 0, "workflows"]

      response = %Req.Response{
        status: 201,
        headers: %{"content-type" => ["application/json"], "x-request-left" => ["10"]},
        body: nil
      }

      context =
        context
        |> Context.put_step_response(workflow_id, step_id, response)

      expression =
        "!($response.header.X-Request-Left <= 2)"

      assert {:ok, true} == Simple.evaluate(expression, rev_path, context)
    end
  end

  describe "parse/1" do
    test "composed comparison" do
      condition = "$response.body#/id != 0 && $statusCode > 399"

      expected =
        {:and, {:neq, {:runtime_expression, "$response.body#/id"}, {:literal, 0}},
         {:gt, {:runtime_expression, "$statusCode"}, {:literal, 399}}}

      assert {:ok, expected} == Simple.parse(condition)
    end

    test "returns error for unterminated string" do
      condition = "$response.body#/name == 'Name"
      assert {:error, "unterminated single-quoted string: Name"} == Simple.parse(condition)
    end

    test "retuns error for unclosed parens" do
      condition = "($response.body#/name == 'a'"
      assert {:error, "missing closing ')'"} == Simple.parse(condition)
    end

    test "parses string with escaped quotes" do
      condition = "$response.body#/name == 'O\\'Higgins'"
      expected = {:eq, {:runtime_expression, "$response.body#/name"}, {:literal, "O'Higgins"}}
      assert {:ok, expected} == Simple.parse(condition)
    end

    test "parses single comparison" do
      condition = "$response.statusCode == 200"
      expected = {:eq, {:runtime_expression, "$response.statusCode"}, {:literal, 200}}

      assert {:ok, expected} == Simple.parse(condition)
    end

    test "comparison with parens" do
      condition =
        "($response.statusCode <= 399 && $response.statusCode >= 200) && $response.body#/valid == true"

      expected =
        {:and,
         {:and, {:lte, {:runtime_expression, "$response.statusCode"}, {:literal, 399}},
          {:gte, {:runtime_expression, "$response.statusCode"}, {:literal, 200}}},
         {:eq, {:runtime_expression, "$response.body#/valid"}, {:literal, true}}}

      assert {:ok, expected} == Simple.parse(condition)
    end
  end

  describe "tokenize/1" do
    test "tokenizes literal special values" do
      condition =
        "$response.body#/valid == true && ($response.body#/expired == false || $response.body#/expired != null)"

      {:ok, tokens} = Simple.tokenize(condition)

      assert tokens == [
               {:runtime_expression, "$response.body#/valid"},
               :eq,
               {:literal, true},
               :and,
               :lparen,
               {:runtime_expression, "$response.body#/expired"},
               :eq,
               {:literal, false},
               :or,
               {:runtime_expression, "$response.body#/expired"},
               :neq,
               {:literal, nil},
               :rparen
             ]
    end

    test "tokenizes floating point numbers" do
      condition = "$outputs.x >= 1.4e-9"
      {:ok, tokens} = Simple.tokenize(condition)
      assert tokens == [{:runtime_expression, "$outputs.x"}, :gte, {:literal, 1.4e-9}]
    end

    test "tokenizes parens with literals and JSON pointers" do
      condition = "($response.body#/id == '123') || ($response.statusCode < 399)"
      {:ok, tokens} = Simple.tokenize(condition)

      assert tokens == [
               :lparen,
               {:runtime_expression, "$response.body#/id"},
               :eq,
               {:literal, "123"},
               :rparen,
               :or,
               :lparen,
               {:runtime_expression, "$response.statusCode"},
               :lt,
               {:literal, 399},
               :rparen
             ]
    end
  end

  defp workflow_and_step_id(%Context{document: document} = _context) do
    %{workflows: [%{workflowId: workflow_id, steps: [%{stepId: step_id} | _]} | _]} = document
    {workflow_id, step_id}
  end
end
