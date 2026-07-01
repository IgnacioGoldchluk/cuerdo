defmodule Cuerdo.Arazzo.ParameterTest do
  use ExUnit.Case

  alias Cuerdo.Arazzo.{Context, Parameter, ReusableObject}
  alias Cuerdo.Errors.{InvalidExpression, MissingParameters}
  alias Cuerdo.OpenAPI

  import Cuerdo.ArazzoFixtures

  describe "resolve/3" do
    test "resolves reusable objects with and without overridden value" do
      mock_openapi_fetch()

      document =
        put_in(example_document(), ["components", "parameters"], %{
          "fooPath" => %{
            "in" => "path",
            "name" => "foo",
            "value" => 2
          }
        })

      ctx = Context.new!(document)

      parameters = [%ReusableObject{reference: "$components.parameters.fooPath"}]
      path = [0, "steps", 0, "workflows"]

      expected = %Parameter{in: "path", name: "foo", value: 2}
      assert {:ok, [expected]} == Parameter.resolve(parameters, path, ctx)

      # Now with overridden value
      parameters = [
        %ReusableObject{reference: "$components.parameters.fooPath", value: "$inputs.foo"}
      ]

      workflow_id = ctx.document.workflows |> Enum.fetch!(0) |> Map.fetch!(:workflowId)

      value = System.unique_integer([:positive])
      ctx = Context.put_inputs(ctx, workflow_id, "foo", value)

      expected = %Parameter{in: "path", name: "foo", value: value}
      assert {:ok, [expected]} == Parameter.resolve(parameters, path, ctx)
    end

    test "returns error when reusable object is invalid" do
      ctx = default_context()

      parameters = [%ReusableObject{reference: "$components.parameters.fooPath"}]
      path = [0, "steps", 0, "workflows"]

      assert {:error,
              %InvalidExpression{
                type: :parameter,
                expression: "$components.parameters.fooPath",
                value: "not in document"
              }} =
               Parameter.resolve(parameters, path, ctx)
    end

    test "returns error when parameter value is invalid" do
      ctx = default_context()
      parameters = [Parameter.new!(%{"in" => "path", "name" => "foo", "value" => "$statusCode"})]

      path = [0, "steps", 0, "workflows"]

      assert {:error,
              %InvalidExpression{
                type: :response,
                expression: "$statusCode",
                value: "createAndRetrieveBook.createBookStep request not set"
              }} =
               Parameter.resolve(parameters, path, ctx)
    end

    test "resolves runtime expressions" do
      ctx = default_context()
      workflow_id = ctx.document.workflows |> Enum.fetch!(0) |> Map.fetch!(:workflowId)

      parameters = [Parameter.new!(%{"in" => "path", "name" => "foo", "value" => "$inputs.bar"})]

      value = System.unique_integer([:positive])
      ctx = Context.put_inputs(ctx, workflow_id, "bar", value)

      path = [0, "steps", 0, "workflows"]

      {:ok, [%Parameter{in: "path", name: "foo", value: val}]} =
        Parameter.resolve(parameters, path, ctx)

      assert val == value
    end

    test "removes duplicate elements" do
      ctx = default_context()

      parameters =
        [
          %{"in" => "path", "name" => "foo", "value" => "bar"},
          %{"in" => "query", "name" => "foo", "value" => "qux"},
          %{"in" => "path", "name" => "foo", "value" => "baz"}
        ]
        |> Enum.map(&Parameter.new!/1)

      path = [0, "steps", 0, "workflows"]

      expected = [
        %Parameter{in: "path", name: "foo", value: "bar"},
        %Parameter{in: "query", name: "foo", value: "qux"}
      ]

      assert {:ok, expected} == Parameter.resolve(parameters, path, ctx)
    end
  end

  describe "all_present/2" do
    test "returns :ok when there are no parameters" do
      assert :ok == Parameter.all_present([], [])
    end

    test "returns :ok, when operation parameters are empty" do
      step_parameters =
        [%{"name" => "foo", "in" => "path", "value" => "bar"}]
        |> Enum.map(&Parameter.new!/1)

      assert :ok == Parameter.all_present(step_parameters, [])
    end

    test "returns :ok when operation parameters are not required" do
      step_parameters =
        [%{"name" => "foo", "in" => "path", "value" => "bar"}]
        |> Enum.map(&Parameter.new!/1)

      operation_parameters =
        [
          %{"name" => "foo", "in" => "query"},
          %{"name" => "bar", "in" => "query"}
        ]
        |> Enum.map(&OpenAPI.Parameter.new!/1)

      assert :ok == Parameter.all_present(step_parameters, operation_parameters)
    end

    test "returns error tuple for missing parameters" do
      step_parameters =
        [
          %{"name" => "foo", "in" => "path", "value" => "bar"}
        ]
        |> Enum.map(&Parameter.new!/1)

      operation_parameters =
        [
          %{"name" => "foo", "in" => "query", "required" => true},
          %{"name" => "bar", "in" => "query"},
          %{"name" => "baz", "in" => "path", "required" => true}
        ]
        |> Enum.map(&OpenAPI.Parameter.new!/1)

      assert {:error, %MissingParameters{parameters: [{"foo", "query"}, {"baz", "path"}]}} =
               Parameter.all_present(step_parameters, operation_parameters)
    end
  end
end
