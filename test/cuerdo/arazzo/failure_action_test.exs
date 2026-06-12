defmodule Cuerdo.Arazzo.FailureActionTest do
  use ExUnit.Case
  alias Cuerdo.Arazzo.{Criterion, FailureAction}

  test "fails if retryAfter is not specified for type 'retry'" do
    action = %{
      "name" => "failureAction",
      "type" => "retry",
      "workflowId" => "foo",
      "criteria" => [%{"condition" => "$statusCode == 404"}]
    }

    assert {:error, [%Zoi.Error{message: msg}]} = FailureAction.new(action)
    assert msg == "'retryAfter' is required when 'type' is 'retry'"
  end

  test "passes when exactly one of workflowId or stepId are provided for type 'goto'" do
    action = %{
      "name" => "failureAction",
      "type" => "goto",
      "stepId" => "foo",
      "criteria" => [%{"condition" => "$statusCode == 404"}]
    }

    assert {:ok, _} = FailureAction.new(action)
  end

  test "passes if workflowId and stepId are provided but type is 'end'" do
    action = %{
      "name" => "failureAction",
      "type" => "end",
      "workflowId" => "foo",
      "stepId" => "foo",
      "criteria" => [%{"condition" => "$statusCode == 404"}]
    }

    expected = %FailureAction{
      name: action["name"],
      stepId: action["stepId"],
      workflowId: action["workflowId"],
      type: "end",
      criteria: [%Criterion{context: nil, condition: "$statusCode == 404", type: "simple"}]
    }

    assert {:ok, expected} == FailureAction.new(action)
  end

  test "fails if workflowId and stepId are provided for type 'goto' or 'retry'" do
    action = %{
      "name" => "successAction",
      "type" => "goto",
      "workflowId" => "foo",
      "stepId" => "foo",
      "criteria" => [%{"condition" => "$statusCode == 200"}]
    }

    assert {:error, [%Zoi.Error{message: msg}]} = FailureAction.new(action)

    assert msg ==
             "type 'goto' given with both 'workflowId' (foo) and 'stepId' (foo). Only one must be set"

    action = Map.put(action, "type", "retry") |> Map.put("retryAfter", 10)

    assert {:error, [%Zoi.Error{message: msg}]} = FailureAction.new(action)

    assert msg ==
             "type 'retry' given with both 'workflowId' (foo) and 'stepId' (foo). Only one must be set"
  end

  test "fails if workflowId and stepId are not set for type 'goto'" do
    action = %{
      "name" => "failureAction",
      "type" => "goto",
      "criteria" => [%{"condition" => "$statusCode == 404"}]
    }

    assert {:error, [%Zoi.Error{message: msg}]} = FailureAction.new(action)
    assert msg == "type 'goto' given with no 'workflowId' or 'stepId'"
  end
end
