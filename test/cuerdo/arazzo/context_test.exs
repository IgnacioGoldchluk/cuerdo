defmodule Cuerdo.Arazzo.ContextTest do
  use ExUnit.Case

  import Cuerdo.ArazzoFixtures

  alias Cuerdo.Arazzo.{Context, Document}
  alias Cuerdo.Errors

  describe "from_document/1" do
    test "formats nested errors in invalid document" do
      document =
        example_document()
        |> RockSolid.Traversal.put_in_schema!(
          ["workflows", "0", "steps", "0", "requestBody", "contentType"],
          "invalidContentType"
        )

      assert {:error, %Errors.InvalidDocument{errors: errors} = exc} =
               Context.from_document(document)

      assert String.contains?(
               Exception.message(exc),
               "workflows.0.steps.0.requestBody.contentType: invalid value"
             )

      # This is just to increase coverage
      assert_raise Errors.InvalidDocument, fn ->
        raise Errors.InvalidDocument, errors: errors
      end
    end
  end

  describe "new/1" do
    test "creates context with parsed document and fetched OpenAPI JSON schema" do
      document = example_document()

      assert {:ok, %Context{} = ctx} = Context.new(document)
      assert %Document{} = document = ctx.document
      assert document.info.title == "Bookstore workflow"
    end

    test "pre-populates inputs, outputs and API calls" do
      document = example_document()
      assert {:ok, %Context{} = ctx} = Context.new(document)

      assert ctx.outputs == %{
               "createAndRetrieveBook" => %{
                 "bookId" => {:unresolved, "$steps.createBookStep.outputs.bookId"},
                 steps: %{
                   "createBookStep" => %{
                     "bookAuthor" => {:unresolved, "$request.body#/author"},
                     "bookId" => {:unresolved, "$response.body#/id"},
                     "bookIsbn" => {:unresolved, "$request.body#/isbn"},
                     "bookTitle" => {:unresolved, "$request.body#/title"}
                   },
                   "getBookStep" => %{},
                   "listBooksStep" => %{}
                 }
               }
             }

      assert ctx.inputs == %{"createAndRetrieveBook" => %{}}

      assert ctx.api_calls == %{
               "createAndRetrieveBook" => %{
                 "createBookStep" => %Context.APICalls{request: nil, response: nil},
                 "getBookStep" => %Context.APICalls{request: nil, response: nil},
                 "listBooksStep" => %Context.APICalls{request: nil, response: nil}
               }
             }
    end

    @tag skip: "Test as part of a workflow instead"
    test "creates context with parsed YAML OpenAPI schema" do
      Req.Test.expect(Cuerdo.Client, fn conn ->
        assert conn.host == "127.0.0.1"
        assert conn.request_path == "/openapi.yaml"

        Plug.Conn.send_resp(
          conn,
          200,
          Path.join(["test", "support", "openapi.yaml"]) |> File.read!()
        )
      end)

      document =
        RockSolid.Traversal.put_in_schema!(
          example_document(),
          ["sourceDescriptions", "0", "url"],
          "http://127.0.0.1:8000/openapi.yaml"
        )

      assert {:ok, %Context{} = ctx} = Context.new(document)
      assert %Document{} = document = ctx.document
      assert document.info.title == "Bookstore workflow"
    end

    test "returns error if document is invalid" do
      assert {:error, _} = Context.new(%{"invalid" => "document"})
    end

    test "returns error when step is missing successCriteria" do
      document = example_document()

      document =
        RockSolid.Traversal.put_in_schema!(
          document,
          ["workflows", "0", "steps", "0", "successCriteria"],
          []
        )

      assert {:error, _} = Context.new(document)
    end
  end
end
