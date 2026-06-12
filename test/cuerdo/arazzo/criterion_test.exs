defmodule Cuerdo.Arazzo.CriterionTest do
  use ExUnit.Case

  alias Cuerdo.Arazzo.Criterion
  alias Cuerdo.Errors.{FailedCriterion, InvalidExpression}

  import Cuerdo.ArazzoFixtures

  describe "new/1" do
    test "passes for type jsonpath with context" do
      value = %{
        "type" => "jsonpath",
        "condition" => "$[? @.a > 1]",
        "context" => "$response.body"
      }

      assert {:ok, %Criterion{} = criterion} = Criterion.new(value)

      assert criterion.type == value["type"]
      assert criterion.condition == value["condition"]
      assert criterion.context == value["context"]
    end

    test "fails when context is not provided for type other than simple" do
      criterion = %{"type" => "jsonpath", "condition" => "$[?@.a > 1]"}

      assert {:error, [%Zoi.Error{message: msg}]} = Criterion.new(criterion)
      assert msg == "context is required when type is not 'simple'"
    end

    test "fails when context is provided for simple type" do
      criterion = %{
        "type" => "simple",
        "condition" => "$statusCode == 200",
        "context" => "$response"
      }

      assert {:error, [%Zoi.Error{message: msg}]} = Criterion.new(criterion)
      assert msg == "context must be empty for type 'simple'"
    end
  end

  describe "evaluate/3" do
    test "returns error when regex expression does not match or path is invalid" do
      context = default_context()

      %{workflows: [%{workflowId: workflow_id, steps: [%{stepId: step_id} | _]}]} =
        context.document

      response = %Req.Response{
        status: 200,
        headers: %{"content-type" => ["application/json"]},
        body: %{"name" => "Alice", "age" => 20}
      }

      ctx =
        Cuerdo.Arazzo.put_request_response_step(
          context,
          workflow_id,
          step_id,
          %Req.Request{},
          response
        )

      criterion =
        Criterion.new!(%{
          "type" => "regex",
          "condition" => "alce",
          "context" => "$response.body#/name"
        })

      path = [0, "steps", 0, "workflows"]

      expected =
        {:error,
         %FailedCriterion{
           expression: "$response.body#/name",
           criterion: criterion.condition,
           type: criterion.type
         }}

      assert expected == Criterion.evaluate(criterion, path, ctx)

      invalid_path = %Criterion{criterion | context: "$response.body#/foo/bar"}
      assert {:error, %InvalidExpression{}} = Criterion.evaluate(invalid_path, path, ctx)

      invalid_regex = %Criterion{criterion | condition: "a)"}
      assert {:error, %InvalidExpression{}} = Criterion.evaluate(invalid_regex, path, ctx)

      passing = %Criterion{criterion | condition: "^Al"}
      assert :ok == Criterion.evaluate(passing, path, ctx)
    end

    test "returns error when JSONPath expression evaluates to empty or is invalid" do
      context = default_context()

      %{workflows: [%{workflowId: workflow_id, steps: [%{stepId: step_id} | _]}]} =
        context.document

      response = %Req.Response{
        status: 200,
        headers: %{"content-type" => ["application/json"]},
        body: %{"people" => [%{"name" => "Alice", "age" => 20}, %{"name" => "Bob", "age" => 30}]}
      }

      ctx =
        Cuerdo.Arazzo.put_request_response_step(
          context,
          workflow_id,
          step_id,
          %Req.Request{},
          response
        )

      criterion =
        Criterion.new!(%{
          "type" => "jsonpath",
          "condition" => "$.foo[? @.age > 40]",
          "context" => "$response.body"
        })

      path = [0, "steps", 0, "workflows"]

      expected =
        {:error,
         %FailedCriterion{
           expression: response.body,
           criterion: criterion.condition,
           type: criterion.type
         }}

      assert expected == Criterion.evaluate(criterion, path, ctx)

      # Invalid expression case
      invalid_expression =
        Criterion.new!(%{
          "type" => "jsonpath",
          "condition" => "$.foo[length(@)]",
          "context" => "$response.body"
        })

      assert {:error, %JSONPath.Error{}} = Criterion.evaluate(invalid_expression, path, ctx)

      invalid_context = %Criterion{criterion | context: "$reponse.body"}
      assert {:error, %InvalidExpression{}} = Criterion.evaluate(invalid_context, path, ctx)
    end
  end
end
