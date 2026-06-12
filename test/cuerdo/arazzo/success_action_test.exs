defmodule Cuerdo.Arazzo.SuccessActionTest do
  use ExUnit.Case

  alias Cuerdo.Arazzo.{Criterion, SuccessAction}

  test "passes if workflowId and stepId are provided but type is 'end'" do
    action = %{
      "name" => "successAction",
      "type" => "end",
      "workflowId" => "foo",
      "stepId" => "foo",
      "criteria" => [%{"condition" => "$statusCode == 200"}]
    }

    expected = %SuccessAction{
      name: action["name"],
      stepId: action["stepId"],
      workflowId: action["workflowId"],
      type: "end",
      criteria: [%Criterion{context: nil, condition: "$statusCode == 200", type: "simple"}]
    }

    assert {:ok, expected} == SuccessAction.new(action)
  end

  test "fails if workflowId and stepId are provided for type 'goto'" do
    action = %{
      "name" => "successAction",
      "type" => "goto",
      "workflowId" => "foo",
      "stepId" => "foo",
      "criteria" => [%{"condition" => "$statusCode == 200"}]
    }

    assert {:error, [%Zoi.Error{message: msg}]} = SuccessAction.new(action)

    assert msg ==
             "type 'goto' given with both 'workflowId' (foo) and 'stepId' (foo). Only one must be set"
  end

  test "fails if workflowId and stepId are not set for type 'goto'" do
    action = %{
      "name" => "successAction",
      "type" => "goto",
      "criteria" => [%{"condition" => "$statusCode == 200"}]
    }

    assert {:error, [%Zoi.Error{message: msg}]} = SuccessAction.new(action)
    assert msg == "type 'goto' given with no 'workflowId' or 'stepId'"
  end

  test "passes if exactly one of workflowId and stepId are set for 'goto'" do
    action = %{
      "name" => "successAction",
      "type" => "goto",
      "workflowId" => "someWorkflowId",
      "criteria" => [%{"condition" => "$statusCode == 200"}]
    }

    assert {:ok, _} = SuccessAction.new(action)

    action = Map.delete(action, "workflowId") |> Map.put("stepId", "someStepId")
    assert {:ok, _} = SuccessAction.new(action)
  end
end
