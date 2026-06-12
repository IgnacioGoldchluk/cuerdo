defmodule Cuerdo.Arazzo.RuntimeExpressionTest do
  use ExUnit.Case

  alias Cuerdo.Arazzo.Context
  alias Cuerdo.Arazzo.{RuntimeExpression, Selector}

  import Cuerdo.ArazzoFixtures

  describe "resolve/3" do
    test "evaluates JSONPath selectors" do
      expr = %Selector{context: "$inputs.users", type: "jsonpath", selector: "$[?@.id == 2]"}

      ctx = default_context()
      %{workflows: [%{workflowId: workflow_id}]} = ctx.document

      users = [
        %{"id" => 1, "email" => "user1@email.com"},
        %{"id" => 2, "email" => "user2@email.com"},
        %{"id" => 3, "email" => "user3@email.com"}
      ]

      ctx = Context.put_inputs(ctx, workflow_id, "users", users)
      # Path is irrelevant here
      reversed_path = ["myuser", "outputs", 0, "steps", 0, "workflows"]

      assert {:ok, %{"id" => 2, "email" => "user2@email.com"}} ==
               RuntimeExpression.resolve(expr, reversed_path, ctx)
    end

    test "evaluates JSON Pointer selectors inside payload" do
      expression = %{
        "email" => %{
          "context" => "$inputs.user",
          "type" => "jsonpointer",
          "selector" => "#/email"
        }
      }

      ctx = default_context()
      %{workflows: [%{workflowId: workflow_id}]} = ctx.document

      user = %{"email" => "user123@email.com"}
      ctx = Context.put_inputs(ctx, workflow_id, "user", user)
      reversed_path = ["payload", "requestBody", 0, "steps", 0, "workflows"]

      assert {:ok, %{"email" => user["email"]}} ==
               RuntimeExpression.resolve(expression, reversed_path, ctx)
    end

    test "performs string interpolation with multiple values" do
      expression = """
      {
        "data": {
          "attributes": {
            "email": "{$inputs.email}",
            "password": "{$inputs.password}",
            "password_confirmation": "{$inputs.password}"
          }
        }
      }
      """

      ctx = default_context()
      %{workflows: [%{workflowId: workflow_id}]} = ctx.document
      email = "user123@email.com"
      password = "verysecure"

      ctx =
        ctx
        |> Context.put_inputs(workflow_id, "email", email)
        |> Context.put_inputs(workflow_id, "password", password)
        |> Context.put_inputs(workflow_id, "token", "theToken")

      reversed_path = [0, "steps", 0, "workflows"]

      {:ok, replacements} = RuntimeExpression.resolve(expression, reversed_path, ctx)
      replacements = JSON.decode!(replacements)

      assert replacements == %{
               "data" => %{
                 "attributes" => %{
                   "email" => email,
                   "password" => password,
                   "password_confirmation" => password
                 }
               }
             }

      assert {:ok, "Bearer theToken"} ==
               RuntimeExpression.resolve("Bearer $inputs.token", reversed_path, ctx)
    end
  end
end
