defmodule Cuerdo.TraversalTest do
  use ExUnit.Case
  import Cuerdo.ArazzoFixtures

  alias Cuerdo.Arazzo.Context
  alias Cuerdo.Errors.InvalidExpression
  alias Cuerdo.Traversal

  setup_all do
    %{document: example_document()}
  end

  describe "fetch_value/2" do
    setup do
      mock_openapi_fetch()
      :ok
    end

    test "returns reusable components referenced by key", %{document: document} do
      ctx = Context.new!(document)

      expected_component = ctx.document.components.failureActions |> Map.get("refreshToken")

      assert {:ok, expected_component} ==
               Traversal.fetch_value("$components.failureActions.refreshToken", [], ctx)
    end

    test "returns value at workflow outputs", %{document: document} do
      workflow_id = Enum.fetch!(document["workflows"], 0)["workflowId"]
      book_id = System.unique_integer([:positive])

      assert length(document["workflows"]) == 1

      ctx =
        document
        |> Context.new!()
        |> Context.put_workflow_output(workflow_id, "bookId", book_id)

      assert {:ok, book_id} == Traversal.fetch_value("$outputs.bookId", [0, "workflows"], ctx)
    end

    test "returns value at workflow output + JSON pointer", %{document: document} do
      workflow_id = Enum.fetch!(document["workflows"], 0)["workflowId"]
      book = %{"bookId" => System.unique_integer([:positive])}
      assert length(document["workflows"]) == 1

      ctx =
        document
        |> Context.new!()
        |> Context.put_workflow_output(workflow_id, "book", book)

      assert {:ok, book["bookId"]} ==
               Traversal.fetch_value({"$outputs.book", "#/bookId"}, [0, "workflows"], ctx)
    end

    test "returns value at step output", %{document: document} do
      workflow = Enum.fetch!(document["workflows"], 0)
      workflow_id = workflow["workflowId"]
      book_id = System.unique_integer([:positive])

      assert length(document["workflows"]) == 1

      step_id = Enum.fetch!(workflow["steps"], 0)["stepId"]

      ctx =
        document
        |> Context.new!()
        |> Context.put_step_output(workflow_id, step_id, "bookId", book_id)

      rev_path = [0, "steps", 0, "workflows"]

      assert {:ok, book_id} ==
               Traversal.fetch_value("$steps.#{step_id}.outputs.bookId", rev_path, ctx)
    end

    test "returns value for step output + JSON pointer", %{document: document} do
      workflow = Enum.fetch!(document["workflows"], 0)
      workflow_id = workflow["workflowId"]

      assert length(document["workflows"]) == 1

      step_id = Enum.fetch!(workflow["steps"], 0)["stepId"]

      book = %{"bookId" => System.unique_integer([:positive])}

      ctx =
        document
        |> Context.new!()
        |> Context.put_step_output(workflow_id, step_id, "book", book)

      rev_path = [0, "steps", 0, "workflows"]

      assert {:ok, book["bookId"]} ==
               Traversal.fetch_value(
                 {"$steps.#{step_id}.outputs.book", "#/bookId"},
                 rev_path,
                 ctx
               )
    end

    test "returns status code for response at current step", %{document: document} do
      workflow = Enum.fetch!(document["workflows"], 0)
      workflow_id = workflow["workflowId"]

      assert length(document["workflows"]) == 1

      step_id = Enum.fetch!(workflow["steps"], 0)["stepId"]

      response = %Req.Response{status: 200}
      request = %Req.Request{}

      ctx =
        document
        |> Context.new!()
        |> Context.put_step_request_response([workflow_id, step_id], request, response)

      rev_path = [0, "steps", 0, "workflows"]
      assert {:ok, 200} = Traversal.fetch_value("$statusCode", rev_path, ctx)
    end

    test "returns header and path for response at current step", %{document: document} do
      workflow = Enum.fetch!(document["workflows"], 0)
      workflow_id = workflow["workflowId"]
      assert length(document["workflows"]) == 1

      step_id = Enum.fetch!(workflow["steps"], 0)["stepId"]

      body = "<html>foo</html>"
      request = %Req.Request{url: URI.parse("https://example.com")}
      response = %Req.Response{headers: %{"age" => ["300"]}, body: body}

      ctx =
        document
        |> Context.new!()
        |> Context.put_step_request_response([workflow_id, step_id], request, response)

      rev_path = [0, "steps", 0, "workflows"]

      assert {:ok, "300"} == Traversal.fetch_value("$response.header.age", rev_path, ctx)
      assert {:ok, body} == Traversal.fetch_value("$response.body", rev_path, ctx)
    end

    test "returns url, method, header and path for request at current step", %{document: document} do
      workflow = Enum.fetch!(document["workflows"], 0)
      workflow_id = workflow["workflowId"]
      assert length(document["workflows"]) == 1

      step_id = Enum.fetch!(workflow["steps"], 0)["stepId"]

      url = "https://example.com/foo"

      book_id = System.unique_integer([:positive])

      request = %Req.Request{
        url: URI.parse(url),
        method: :post,
        options: %{path_params: [foo: "bar"]},
        headers: %{"accept-encoding" => ["gzip"], "user-agent" => ["req/0.5.17"]},
        body: %{"bookId" => book_id}
      }

      response = %Req.Response{}

      ctx =
        document
        |> Context.new!()
        |> Context.put_step_request_response([workflow_id, step_id], request, response)

      rev_path = [0, "steps", 0, "workflows"]
      assert {:ok, url} == Traversal.fetch_value("$url", rev_path, ctx)
      assert {:ok, "POST"} == Traversal.fetch_value("$method", rev_path, ctx)
      assert {:ok, "bar"} == Traversal.fetch_value("$request.path.foo", rev_path, ctx)

      assert {:ok, "gzip"} ==
               Traversal.fetch_value("$request.header.Accept-Encoding", rev_path, ctx)

      assert {:ok, book_id} == Traversal.fetch_value({"$request.body", "#/bookId"}, rev_path, ctx)
    end

    test "returns value at inputs", %{document: document} do
      workflow_id = Enum.fetch!(document["workflows"], 0)["workflowId"]
      person_id = System.unique_integer([:positive])

      # Otherwise the reversed path might be incorrect
      assert length(document["workflows"]) == 1

      ctx =
        document
        |> Context.new!()
        |> Context.put_inputs(workflow_id, "personId", person_id)

      assert {:ok, person_id} == Traversal.fetch_value("$inputs.personId", [0, "workflows"], ctx)
    end

    test "returns value for map input + JSON pointer", %{document: document} do
      workflow_id = Enum.fetch!(document["workflows"], 0)["workflowId"]
      person = %{"personId" => System.unique_integer([:positive])}

      # Otherwise the reversed path might be incorrect
      assert length(document["workflows"]) == 1

      ctx =
        document
        |> Context.new!()
        |> Context.put_inputs(workflow_id, "person", person)

      assert {:ok, person["personId"]} ==
               Traversal.fetch_value({"$inputs.person", "#/personId"}, [0, "workflows"], ctx)
    end

    test "returns value located at sourceDescription", %{document: document} do
      %{"name" => name} = src_descr = source_description()

      ctx =
        document
        |> RockSolid.Traversal.put_in_schema!(["sourceDescriptions", "0"], src_descr)
        |> Context.new!()

      url_path = "$sourceDescriptions.#{name}.url"
      assert {:ok, src_descr["url"]} == Traversal.fetch_value(url_path, [], ctx)

      type_path = "$sourceDescriptions.#{name}.type"
      assert {:ok, src_descr["type"]} == Traversal.fetch_value(type_path, [], ctx)
    end

    test "fails retrieving response when stepId does not exist", %{document: document} do
      {:ok, ctx} = Context.from_document(document)
      rev_path = [123, "steps", 0, "workflows"]

      assert {:error,
              %InvalidExpression{
                type: :step_index,
                expression: "$statusCode",
                value: "createAndRetrieveBook.steps.123"
              }} =
               Traversal.fetch_value("$statusCode", rev_path, ctx)
    end

    test "fails retrieving request when not set yet", %{document: document} do
      {:ok, ctx} = Context.from_document(document)
      rev_path = [0, "steps", 0, "workflows"]

      assert {:error,
              %Cuerdo.Errors.InvalidExpression{
                expression: "createAndRetrieveBook.createBookStep",
                type: :request,
                value: "not set"
              }} =
               Traversal.fetch_value("$request.body", rev_path, ctx)
    end

    test "fails retrieving response when not set yet", %{document: document} do
      {:ok, ctx} = Context.from_document(document)
      rev_path = [0, "steps", 0, "workflows"]

      assert {:error,
              %Cuerdo.Errors.InvalidExpression{
                expression: "$statusCode",
                type: :response,
                value: "createAndRetrieveBook.createBookStep request not set"
              }} =
               Traversal.fetch_value("$statusCode", rev_path, ctx)
    end

    test "fails when workflow index is invalid", %{document: document} do
      {:ok, ctx} = Context.from_document(document)
      rev_path = [0, "steps", 123, "workflows"]

      assert {:error,
              %Cuerdo.Errors.InvalidExpression{
                expression: "$statusCode",
                type: :workflow_index,
                value: 123
              }} =
               Traversal.fetch_value("$statusCode", rev_path, ctx)
    end

    test "fails retrieving request when stepId does not exist", %{document: document} do
      {:ok, ctx} = Context.from_document(document)
      rev_path = [123, "steps", 0, "workflows"]

      assert {:error,
              %Cuerdo.Errors.InvalidExpression{
                expression: 123,
                type: :step_index,
                value: "createAndRetrieveBook.steps.123"
              }} =
               Traversal.fetch_value("$request.body", rev_path, ctx)
    end

    test "fails retrieving invalid source description name", %{document: document} do
      {:ok, ctx} = Context.from_document(document)
      rev_path = [0, "steps", 0, "workflows"]

      assert {:error,
              %Cuerdo.Errors.InvalidSourceDescription{
                name: "invalidName",
                valid_names: ["bookStore"]
              }} =
               Traversal.fetch_value("$sourceDescriptions.invalidName.url", rev_path, ctx)
    end

    test "fails retrieving invalid source description field", %{document: document} do
      {:ok, ctx} = Context.from_document(document)
      rev_path = [0, "steps", 0, "workflows"]

      assert {:error,
              %Cuerdo.Errors.InvalidExpression{
                expression: "$sourceDescriptions.bookStore.aaaa",
                type: :field,
                value: "not present",
                __exception__: true
              }} =
               Traversal.fetch_value("$sourceDescriptions.bookStore.aaaa", rev_path, ctx)
    end

    test "fails input for invalid workflow index", %{document: document} do
      {:ok, ctx} = Context.from_document(document)
      rev_path = [0, "steps", 123, "workflows"]

      expected = %Cuerdo.Errors.InvalidExpression{
        expression: "workflows.123",
        type: :workflow_index,
        value: 123
      }

      assert {:error, expected} == Traversal.fetch_value("$inputs.invalidInput", rev_path, ctx)
    end

    test "fails for missing inputs", %{document: document} do
      {:ok, ctx} = Context.from_document(document)
      rev_path = [0, "steps", 0, "workflows"]

      assert {:error,
              %Cuerdo.Errors.InvalidExpression{
                expression: "createAndRetrieveBook.inputs.invalidInput",
                type: :input,
                value: "missing"
              }} =
               Traversal.fetch_value("$inputs.invalidInput", rev_path, ctx)
    end

    test "fails output for invalid workflow index", %{document: document} do
      {:ok, ctx} = Context.from_document(document)
      rev_path = [0, "steps", 123, "workflows"]

      assert {:error,
              %Cuerdo.Errors.InvalidExpression{
                expression: "workflows.123",
                type: :workflow_index,
                value: 123
              }} =
               Traversal.fetch_value("$outputs.invalidOutputs", rev_path, ctx)
    end

    test "fails for missing step outputs", %{document: document} do
      {:ok, ctx} = Context.from_document(document)
      rev_path = [0, "workflows"]

      assert {:error,
              %Cuerdo.Errors.InvalidExpression{
                expression: "$steps.createBookStep.outputs.invalidOutput",
                type: :output,
                value: "missing"
              }} =
               Traversal.fetch_value(
                 "$steps.createBookStep.outputs.invalidOutput",
                 rev_path,
                 ctx
               )
    end

    test "fails for missing workflow outputs", %{document: document} do
      {:ok, ctx} = Context.from_document(document)
      rev_path = [0, "steps", 0, "workflows"]

      assert {:error,
              %Cuerdo.Errors.InvalidExpression{
                expression: "createAndRetrieveBook.outputs.invalidOutput",
                type: :output,
                value: "missing"
              }} =
               Traversal.fetch_value("$outputs.invalidOutput", rev_path, ctx)
    end

    test "fails for missing header", %{document: document} do
      {:ok, ctx} = Context.from_document(document)
      rev_path = [0, "steps", 0, "workflows"]

      path = ["createAndRetrieveBook", "createBookStep"]

      ctx = Context.put_step_request_response(ctx, path, %Req.Request{}, %Req.Response{})

      assert {:error,
              %Cuerdo.Errors.InvalidExpression{
                expression: "limit",
                type: :header,
                value: "Available headers: "
              }} =
               Traversal.fetch_value("$response.header.Limit", rev_path, ctx)
    end
  end
end
