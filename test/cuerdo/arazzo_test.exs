defmodule Cuerdo.ArazzoTest do
  use ExUnit.Case

  alias Cuerdo.Arazzo
  alias Cuerdo.Arazzo.Context
  import Cuerdo.ArazzoFixtures

  setup_all do
    %{document: example_document()}
  end

  describe "build_schema/2" do
    setup do
      mock_openapi_fetch()
      :ok
    end

    test "raises if inputs contains unexpected 'components' key", %{document: document} do
      ctx = Context.new!(document)
      inputs = %{"type" => "object", "components" => %{"foo" => %{"type" => "string"}}}

      assert_raise ArgumentError, ~r/inputs schema has ambiguous .*/, fn ->
        Arazzo.build_schema(inputs, ctx)
      end
    end

    test "expands fully referenced component", %{document: document} do
      inputs = %{
        "type" => "object",
        "properties" => %{
          "foo" => %{"const" => "$components.inputs.foo#/bar"},
          "baz" => "$components.inputs.quux"
        }
      }

      updated_doc =
        document
        |> put_in(["components", "inputs"], %{
          "quux" => %{"type" => "boolean"},
          "foo" => %{"bar" => %{"baz" => "qux"}}
        })

      ctx = Context.new!(updated_doc)

      expected = %{
        "components" => %{
          "inputs" => %{"foo" => %{"bar" => %{"baz" => "qux"}}, "quux" => %{"type" => "boolean"}}
        },
        "properties" => %{
          "baz" => %{"type" => "boolean"},
          "foo" => %{"const" => %{"baz" => "qux"}}
        },
        "type" => "object"
      }

      assert {:ok, expected} == Arazzo.build_schema(inputs, ctx)
    end

    test "sourceDescription pointers are not expanded", %{document: document} do
      inputs = %{"const" => "{$sourceDescriptions.bookStore.url#/foo}"}

      expected = %{
        "const" => "http://127.0.0.1:8000/openapi.json#/foo",
        "components" => %{"inputs" => %{}}
      }

      ctx = Context.new!(document)
      assert {:ok, expected} == Arazzo.build_schema(inputs, ctx)
    end

    test "multiple references are string-interpolated", %{document: document} do
      inputs = %{"const" => "{$components.inputs.foo#/bar}-{$components.inputs.baz}"}

      reusable_inputs = %{"foo" => %{"bar" => 1}, "baz" => "hi"}
      updated_doc = put_in(document, ["components", "inputs"], reusable_inputs)

      expected = %{
        "const" => "1-hi",
        "components" => %{"inputs" => reusable_inputs}
      }

      ctx = Context.new!(updated_doc)
      assert {:ok, expected} == Arazzo.build_schema(inputs, ctx)
    end

    test "expands reusable components and referenced OpenAPI source", %{document: document} do
      inputs = %{
        "type" => "object",
        "required" => ["foo", "bar", "baz"],
        "properties" => %{
          "foo" => %{
            "$ref" => "$sourceDescriptions.bookStore.url#/components/schemas/Book/properties/isbn"
          },
          "bar" => %{"$ref" => "#/components/inputs/bar"},
          "baz" => %{"constant" => 1}
        }
      }

      updated_doc = put_in(document, ["components", "inputs"], %{"bar" => %{"type" => "number"}})
      ctx = Context.new!(updated_doc)

      expected = %{
        "components" => %{"inputs" => %{"bar" => %{"type" => "number"}}},
        "properties" => %{
          "bar" => %{"$ref" => "#/components/inputs/bar"},
          "foo" => %{
            "$ref" =>
              "http://127.0.0.1:8000/openapi.json#/components/schemas/Book/properties/isbn"
          },
          "baz" => %{"constant" => 1}
        },
        "type" => "object",
        "required" => ["foo", "bar", "baz"]
      }

      assert {:ok, expected} == Arazzo.build_schema(inputs, ctx)
    end
  end

  describe "update_step_outputs/4" do
    test "updates with response body, including pointer and response headers" do
      mock_openapi_fetch()

      document =
        Map.update!(example_document(), "workflows", fn workflows ->
          List.update_at(workflows, 0, fn workflow ->
            Map.update!(workflow, "steps", fn steps ->
              List.update_at(steps, 0, fn step ->
                Map.update!(step, "outputs", fn outputs ->
                  Map.put(outputs, "rateLimit", "$response.header.X-Rate-Limit")
                end)
              end)
            end)
          end)
        end)

      workflow = document["workflows"] |> Enum.fetch!(0)
      workflow_id = workflow["workflowId"]
      step_id = workflow["steps"] |> Enum.fetch!(0) |> Map.fetch!("stepId")

      req_body = %{"title" => "Book Title", "author" => "Book Author", "isbn" => "1-123-12345-X"}

      request = %Req.Request{
        body: req_body |> JSON.encode!(),
        url: "http://127.0.0.1:8000/books" |> URI.parse(),
        method: :post,
        headers: %{"content-type" => "application/json"}
      }

      resp_body = Map.put(req_body, "id", System.unique_integer([:positive]))

      response = %Req.Response{
        status: 201,
        headers: %{"content-type" => ["application/json"], "x-rate-limit" => ["300"]},
        body: resp_body
      }

      {:ok, ctx} =
        document
        |> Context.new!()
        |> Arazzo.put_request_response_step(workflow_id, step_id, request, response)
        |> Arazzo.update_step_outputs(workflow_id, step_id, [0, "steps", 0, "workflows"])

      step_outputs = Context.step_outputs(ctx, workflow_id, step_id)
      assert step_outputs["bookId"] == resp_body["id"]
      assert step_outputs["bookAuthor"] == req_body["author"]
      assert step_outputs["bookIsbn"] == req_body["isbn"]
      assert step_outputs["bookTitle"] == req_body["title"]
      assert step_outputs["rateLimit"] == "300"
    end
  end
end
