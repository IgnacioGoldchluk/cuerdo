defmodule Cuerdo.Arazzo.ErrorsTest do
  @moduledoc """
  Tests for handling of error and malformed data cases
  """
  use ExUnit.Case
  alias Cuerdo.Arazzo
  alias Cuerdo.Errors

  test "invalid Arazzo document error" do
    document = %{"invalid" => "document"}

    assert {:error,
            %Errors.ExecutionError{path: ["workflowId"], error: %Errors.InvalidDocument{}}} =
             Arazzo.run_workflow(%{}, "workflowId", document)
  end

  test "invalid workflowId name error" do
    document = Cuerdo.ArazzoFixtures.example_document()
    name = "invalidWorkflowName"

    assert {:error, %Errors.ExecutionError{path: [^name], error: %Errors.InvalidWorkflowId{}}} =
             Arazzo.run_workflow(%{}, "invalidWorkflowName", document)
  end

  test "OpenAPI file contents are invalid" do
    Req.Test.expect(
      Cuerdo.Resolver,
      &Req.Test.json(&1, Cuerdo.ArazzoFixtures.example_openapi_json())
    )

    Req.Test.expect(Cuerdo.Client, &Plug.Conn.send_resp(&1, 200, "This was an error"))

    document = Cuerdo.ArazzoFixtures.example_document()
    book = %{"title" => "BookTitle", "author" => "BookAuthor", "isbn" => "0-976-77366-X"}
    workflow_id = "createAndRetrieveBook"

    assert {:error, %Errors.ExecutionError{path: ["createAndRetrieveBook", "createBookStep"]}} =
             Arazzo.run_workflow(%{"book" => book}, workflow_id, document)
  end

  test "fetching local file error" do
    document = Cuerdo.ArazzoFixtures.example_document()
    book = %{"title" => "BookTitle", "author" => "BookAuthor", "isbn" => "0-976-77366-X"}
    workflow_id = "createAndRetrieveBook"

    document =
      RockSolid.Traversal.put_in_schema!(
        document,
        ["#", "sourceDescriptions", "0", "url"],
        "./a/path/that/clearly/doesnt/exist.yml"
      )

    Req.Test.expect(Cuerdo.Resolver, &Req.Test.transport_error(&1, :econnrefused))

    assert {:error,
            %Errors.ExecutionError{error: %Errors.InvalidSchema{type: :invalid_inputs_schema}}} =
             Arazzo.run_workflow(%{"book" => book}, workflow_id, document)
  end

  test "unexpected response retrieving remote OpenAPI schema" do
    Req.Test.expect(Cuerdo.Client, &Plug.Conn.send_resp(&1, 403, ""))

    Req.Test.expect(
      Cuerdo.Resolver,
      &Req.Test.json(&1, Cuerdo.ArazzoFixtures.example_openapi_json())
    )

    document = Cuerdo.ArazzoFixtures.example_document()
    book = %{"title" => "BookTitle", "author" => "BookAuthor", "isbn" => "0-976-77366-X"}
    workflow_id = "createAndRetrieveBook"

    assert {:error,
            %Errors.ExecutionError{
              path: ["createAndRetrieveBook", "createBookStep"],
              error: %Errors.InvalidResponse{response: %Req.Response{status: 403}}
            }} = Arazzo.run_workflow(%{"book" => book}, workflow_id, document)
  end

  test "exception fetching OpenAPI schema" do
    Req.Test.expect(
      Cuerdo.Resolver,
      &Req.Test.json(&1, Cuerdo.ArazzoFixtures.example_openapi_json())
    )

    Req.Test.expect(Cuerdo.Client, &Req.Test.transport_error(&1, :econnrefused))
    document = Cuerdo.ArazzoFixtures.example_document()
    book = %{"title" => "BookTitle", "author" => "BookAuthor", "isbn" => "0-976-77366-X"}
    workflow_id = "createAndRetrieveBook"

    assert {:error,
            %Errors.ExecutionError{
              path: ["createAndRetrieveBook", "createBookStep"],
              error: %Req.TransportError{}
            }} = Arazzo.run_workflow(%{"book" => book}, workflow_id, document)
  end

  test "operationId does not exist error" do
    Cuerdo.ArazzoFixtures.mock_openapi_fetch()

    Req.Test.expect(
      Cuerdo.Resolver,
      &Req.Test.json(&1, Cuerdo.ArazzoFixtures.example_openapi_json())
    )

    document =
      Cuerdo.ArazzoFixtures.example_document()
      |> RockSolid.Traversal.put_in_schema!(
        ["#", "workflows", "0", "steps", "0", "operationId"],
        "$sourceDescriptions.bookStore.invalidOperationId"
      )

    book = %{"title" => "BookTitle", "author" => "BookAuthor", "isbn" => "0-976-77366-X"}

    assert {:error,
            %Errors.ExecutionError{
              path: ["createAndRetrieveBook", "createBookStep"],
              error: %Errors.InvalidOperation{
                value: "$sourceDescriptions.bookStore.invalidOperationId"
              }
            }} =
             Arazzo.run_workflow(%{"book" => book}, "createAndRetrieveBook", document)
  end

  test "invalid operationId format error" do
    Cuerdo.ArazzoFixtures.mock_openapi_fetch()

    document =
      Cuerdo.ArazzoFixtures.example_document()
      |> RockSolid.Traversal.put_in_schema!(
        ["#", "workflows", "0", "steps", "0", "operationId"],
        "$sourceDescriptions.bookStore"
      )

    book = %{"title" => "BookTitle", "author" => "BookAuthor", "isbn" => "0-976-77366-X"}

    Req.Test.expect(
      Cuerdo.Resolver,
      &Req.Test.json(&1, Cuerdo.ArazzoFixtures.example_openapi_json())
    )

    assert {:error,
            %Errors.ExecutionError{
              path: ["createAndRetrieveBook", "createBookStep"],
              error: %Errors.InvalidOperation{}
            }} =
             Arazzo.run_workflow(%{"book" => book}, "createAndRetrieveBook", document)
  end

  test "invalid sourceDescription name raises" do
    document =
      Cuerdo.ArazzoFixtures.example_document()
      |> RockSolid.Traversal.put_in_schema!(
        ["#", "workflows", "0", "steps", "0", "operationId"],
        "$sourceDescriptions.theWrongSourceDescription.createBook"
      )

    book = %{"title" => "BookTitle", "author" => "BookAuthor", "isbn" => "0-976-77366-X"}

    Req.Test.expect(
      Cuerdo.Resolver,
      &Req.Test.json(&1, Cuerdo.ArazzoFixtures.example_openapi_json())
    )

    {:error,
     %Errors.ExecutionError{
       path: ["createAndRetrieveBook", "createBookStep"],
       error: %Errors.InvalidSourceDescription{
         name: "theWrongSourceDescription",
         valid_names: ["bookStore"]
       }
     }} =
      Arazzo.run_workflow(%{"book" => book}, "createAndRetrieveBook", document)
  end

  describe "message/1" do
    test "formats error for ExecutionError" do
      path = ["theWorkflow", "theStep"]

      assert_raise Errors.ExecutionError, "executing theWorkflow.theStep: timeout", fn ->
        raise Errors.ExecutionError, path: path, error: %Req.TransportError{reason: :timeout}
      end
    end

    test "formats error for InvalidRequest" do
      msg = "Request body required but not present"

      assert_raise Errors.InvalidRequest, msg, fn ->
        raise Errors.InvalidRequest, type: :missing_body, value: ""
      end
    end

    test "formats error for InvalidResponse" do
      response = %Req.Response{status: 400}

      assert_raise Errors.InvalidResponse, ~r/received %Req/, fn ->
        raise Errors.InvalidResponse, response: response
      end
    end

    test "formats error message for InvalidWorkflowId" do
      msg = "Invalid workflowId foo. Defined workflow ids are: bar, baz"

      assert_raise Errors.InvalidWorkflowId, msg, fn ->
        raise Errors.InvalidWorkflowId, id: "foo", valid_ids: ["bar", "baz"]
      end
    end

    test "formats error message for MissingParameters" do
      msg = "Missing required parameters: foo (query),baz (path)"

      assert_raise Errors.MissingParameters, msg, fn ->
        raise Errors.MissingParameters, parameters: [{"foo", "query"}, {"baz", "path"}]
      end
    end

    test "formats error message for InvalidOperation" do
      msg = "operation name or path is invalid: invalidOperationId"

      assert_raise Errors.InvalidOperation, msg, fn ->
        raise Errors.InvalidOperation, value: "invalidOperationId"
      end
    end

    test "formats error message for InvalidSelector" do
      assert_raise Errors.InvalidSelector, ~r/Invalid selector/, fn ->
        raise Errors.InvalidSelector,
          context: "$request.body",
          type: "jsonpath",
          selector: "$.foo"
      end
    end

    test "formats error for FailedCriterion" do
      msg = "criterion $[?@.foo > 1] (jsonpath) for \"$response.body\" failed"

      assert_raise Errors.FailedCriterion, msg, fn ->
        raise Errors.FailedCriterion,
          criterion: "$[?@.foo > 1]",
          type: "jsonpath",
          expression: "$response.body"
      end
    end

    test "formats error message for InvalidExpression" do
      msg = "invalid unknown expression: $requestbody - does not match any valid expression"

      assert_raise Errors.InvalidExpression, msg, fn ->
        raise Errors.InvalidExpression,
          expression: "$requestbody",
          type: :unknown,
          value: "does not match any valid expression"
      end

      msg2 = "invalid unknown expression: foo/bar - does not match any valid expression"

      assert_raise Errors.InvalidExpression, msg2, fn ->
        raise Errors.InvalidExpression,
          expression: {"foo", "bar"},
          type: :unknown,
          value: "does not match any valid expression"
      end

      expression = %{"type" => "jsonpath", "context" => "$request.body", "selector" => "$.foo"}

      assert_raise Errors.InvalidExpression, ~r/invalid jsonpath expression/, fn ->
        raise Errors.InvalidExpression,
          type: :jsonpath,
          expression: expression,
          value: "invalid selector"
      end
    end

    test "formats error message for InvalidSourceDescription" do
      msg = "Invalid sourceDescription name invalidSD. Defined names are: foo, bar"

      assert_raise Errors.InvalidSourceDescription, msg, fn ->
        raise Errors.InvalidSourceDescription, name: "invalidSD", valid_names: ["foo", "bar"]
      end
    end

    test "formats message for InvalidFile" do
      assert_raise Errors.InvalidFile, "reading /foo: :badarg", fn ->
        raise Errors.InvalidFile, filename: "/foo", reason: :badarg
      end
    end

    test "formats message for UnexpectedResponse" do
      msg = "Unexpected response (mismatched_status_code): 200"

      assert_raise Errors.UnexpectedResponse, msg, fn ->
        raise Errors.UnexpectedResponse, type: :mismatched_status_code, value: 200
      end
    end
  end
end
