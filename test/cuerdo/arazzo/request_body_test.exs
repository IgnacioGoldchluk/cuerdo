defmodule Cuerdo.Arazzo.RequestBodyTest do
  use ExUnit.Case

  alias Cuerdo.Arazzo.{Context, RequestBody}

  alias Cuerdo.Errors.{InvalidRequest, InvalidSchema}
  alias Cuerdo.OpenAPI

  import Cuerdo.ArazzoFixtures

  describe "new/1" do
    test "returns error for unsupported content-type" do
      assert {:error, [%Zoi.Error{message: msg, path: [:contentType]}]} =
               RequestBody.new(%{"contentType" => "text/plain", "payload" => "Lorem ipsum"})

      assert String.starts_with?(msg, "invalid value")
    end
  end

  describe "resolve/3" do
    test "returns nil when there is no requestBody" do
      ctx = default_context()
      path = [0, "steps", 0, "workflows"]
      assert {:ok, nil} == RequestBody.resolve(nil, path, ctx)
    end

    test "resolves non JSON body as string" do
      mock_openapi_fetch()

      document =
        example_document()
        |> RockSolid.Traversal.put_in_schema!(
          ["workflows", "0", "steps", "0", "requestBody"],
          %{
            "contentType" => "application/x-www-form-urlencoded",
            "payload" => "author=$inputs.bookAuthor&title=$inputs.bookTitle"
          }
        )

      %{"workflows" => [%{"workflowId" => workflow_id}]} = document
      author = "John"
      title = "Title"

      ctx =
        Context.new!(document)
        |> Context.put_inputs(workflow_id, %{"bookAuthor" => author, "bookTitle" => title})

      %{workflows: [%{steps: [%{requestBody: req_body} | _]}]} = ctx.document

      assert {:ok,
              %{
                body: "author=John&title=Title",
                content_type: "application/x-www-form-urlencoded"
              }} ==
               RequestBody.resolve(req_body, [0, "steps", 0, "workflows"], ctx)
    end

    test "resolves body with multiple references" do
      mock_openapi_fetch()

      document =
        RockSolid.Traversal.put_in_schema!(
          example_document(),
          ["workflows", "0", "steps", "0", "requestBody"],
          %{
            "contentType" => "application/json",
            "payload" => %{
              "bookId" => "$inputs.bookId",
              "author" => "$inputs.bookAuthor",
              "publication" => "{$inputs.month} of {$inputs.year}"
            }
          }
        )

      book_id = System.unique_integer([:positive])
      author = "John Doe"
      year = "2010"
      month = "January"

      workflow_id = document["workflows"] |> Enum.fetch!(0) |> Map.fetch!("workflowId")

      ctx =
        Context.new!(document)
        |> Context.put_inputs(workflow_id, "bookId", book_id)
        |> Context.put_inputs(workflow_id, "bookAuthor", author)
        |> Context.put_inputs(workflow_id, "month", month)
        |> Context.put_inputs(workflow_id, "year", year)

      %{document: %{workflows: [%{steps: [%{requestBody: req_body} | _]} | _]}} = ctx
      path = [0, "steps", 0, "workflows"]

      expected_body = %{
        "bookId" => book_id,
        "author" => author,
        "publication" => "January of 2010"
      }

      {:ok, %{body: body, content_type: "application/json"}} =
        RequestBody.resolve(req_body, path, ctx)

      assert JSON.decode!(body) == expected_body
    end

    test "applies replacements" do
      mock_openapi_fetch()

      value = System.unique_integer([:positive])

      document =
        RockSolid.Traversal.put_in_schema!(
          example_document(),
          ["workflows", "0", "steps", "0", "requestBody"],
          %{
            "contentType" => "application/json",
            "payload" => %{"bookId" => 123},
            "replacements" => [%{"target" => "/bookId", "value" => "$inputs.foo"}]
          }
        )

      workflow_id = document["workflows"] |> Enum.fetch!(0) |> Map.fetch!("workflowId")

      ctx = Context.new!(document) |> Context.put_inputs(workflow_id, "foo", value)

      %{document: %{workflows: [%{steps: [%{requestBody: req_body} | _]} | _]}} = ctx
      path = [0, "steps", 0, "workflows"]

      expected = %{body: %{"bookId" => value} |> JSON.encode!(), content_type: "application/json"}
      assert {:ok, expected} == RequestBody.resolve(req_body, path, ctx)
    end
  end

  describe "matches/3" do
    test "returns :ok when both request and operation body are empty" do
      operation =
        OpenAPI.Operation.new!(%{
          "method" => "delete",
          "source_description_name" => "bookStore",
          "path" => "/books",
          "responses" => %{
            "200" => %{
              "content" => %{"application/json" => %{"schema" => %{"type" => "array"}}}
            }
          }
        })

      assert :ok == RequestBody.matches(nil, operation, default_context())
    end

    test "returns error when resolving remote schema fails" do
      operation =
        OpenAPI.Operation.new!(%{
          "method" => "post",
          "source_description_name" => "bookStore",
          "path" => "/books",
          "requestBody" => %{
            "required" => true,
            "content" => %{
              "application/json" => %{
                "schema" => %{"$ref" => "http://example.com/schema.json#/$defs/Book"}
              }
            }
          },
          "responses" => %{
            "200" => %{
              "content" => %{"application/json" => %{"schema" => %{"type" => "array"}}}
            }
          }
        })

      Req.Test.expect(Cuerdo.Resolver, &Req.Test.transport_error(&1, :econnrefused))
      body = %{body: %{"author" => "John Doe"}, content_type: "application/json"}

      ctx =
        Context.new!(example_document())
        |> Context.put_source_description("bookStore", example_openapi_json())

      assert {:error, %InvalidSchema{type: :invalid_request_schema}} =
               RequestBody.matches(body, operation, ctx)
    end

    test "resolves remote refs in operation schema" do
      operation =
        OpenAPI.Operation.new!(%{
          "method" => "post",
          "source_description_name" => "bookStore",
          "path" => "/books",
          "requestBody" => %{
            "required" => true,
            "content" => %{
              "application/json" => %{
                "schema" => %{"$ref" => "http://example.com/schema.json#/$defs/Book"}
              }
            }
          },
          "responses" => %{
            "200" => %{
              "content" => %{"application/json" => %{"schema" => %{"type" => "array"}}}
            }
          }
        })

      Req.Test.expect(Cuerdo.Resolver, 1, fn %Plug.Conn{} = conn ->
        assert conn.host == "example.com"

        Req.Test.json(conn, %{
          "$defs" => %{
            "Book" => %{
              "type" => "object",
              "properties" => %{"author" => %{"type" => "string"}},
              "required" => ["author"]
            }
          }
        })
      end)

      body = %{body: %{"author" => "John Doe"}, content_type: "application/json"}

      ctx =
        Context.new!(example_document())
        |> Context.put_source_description(
          "bookStore",
          example_openapi_json()
        )

      assert :ok == RequestBody.matches(body, operation, ctx)

      assert {:error, %InvalidRequest{type: :mismatched_body_schema}} =
               RequestBody.matches(
                 %{
                   body: %{"isbn" => "123"},
                   content_type: "application/json"
                 },
                 operation,
                 ctx
               )
    end

    test "returns ok when body matches schema, error otherwise" do
      operation =
        OpenAPI.Operation.new!(%{
          "method" => "post",
          "source_description_name" => "bookStore",
          "path" => "/books",
          "requestBody" => %{
            "required" => true,
            "content" => %{
              "application/json" => %{
                "schema" => %{"$ref" => "#/components/schemas/Book"}
              }
            }
          },
          "responses" => %{
            "200" => %{
              "content" => %{"application/json" => %{"schema" => %{"type" => "array"}}}
            }
          }
        })

      body = %{
        body: %{"title" => "The book", "author" => "John Doe", "isbn" => "0-999-73298-1"},
        content_type: "application/json"
      }

      ctx =
        Context.new!(example_document())
        |> Context.put_source_description("bookStore", example_openapi_json())

      assert :ok == RequestBody.matches(body, operation, ctx)

      assert {:error, %InvalidRequest{type: :mismatched_body_schema}} =
               RequestBody.matches(
                 %{
                   body: %{"title" => "The book", "author" => "John Doe", "isbn" => "1"},
                   content_type: "application/json"
                 },
                 operation,
                 ctx
               )
    end

    test "returns error when body is present and operation does not define body" do
      operation =
        OpenAPI.Operation.new!(%{
          "method" => "delete",
          "source_description_name" => "bookStore",
          "path" => "/books",
          "responses" => %{
            "200" => %{
              "content" => %{"application/json" => %{"schema" => %{"type" => "array"}}}
            }
          }
        })

      assert {:error, %InvalidRequest{type: :unexpected_body}} =
               RequestBody.matches(
                 %{body: %{"name" => "foo"}, content_type: "application/json"},
                 operation,
                 default_context()
               )
    end

    test "returns error when no content type matches" do
      operation =
        OpenAPI.Operation.new!(%{
          "method" => "delete",
          "source_description_name" => "bookStore",
          "path" => "/books",
          "requestBody" => %{
            "required" => true,
            "content" => %{"text/plain" => %{"schema" => %{"type" => "string"}}}
          },
          "responses" => %{
            "200" => %{
              "content" => %{"application/json" => %{"schema" => %{"type" => "array"}}}
            }
          }
        })

      body = %{body: "foo", content_type: "application/json"}

      assert {:error, %InvalidRequest{type: :mismatched_content_type}} =
               RequestBody.matches(body, operation, default_context())
    end

    test "returns error when schema has 'components' key" do
      operation =
        OpenAPI.Operation.new!(%{
          "method" => "delete",
          "source_description_name" => "bookStore",
          "path" => "/books",
          "requestBody" => %{
            "required" => true,
            "content" => %{
              "application/json" => %{
                "schema" => %{"components" => %{"foo" => %{"const" => "bar"}}, "type" => "string"}
              }
            }
          },
          "responses" => %{
            "200" => %{
              "content" => %{"application/json" => %{"schema" => %{"type" => "array"}}}
            }
          }
        })

      body = %{body: "foo", content_type: "application/json"}

      assert {:error, %InvalidSchema{type: :ambiguous_key, value: "components"}} =
               RequestBody.matches(body, operation, default_context())
    end

    test "returns error when body is empty and operation body is required" do
      operation =
        OpenAPI.Operation.new!(%{
          "method" => "delete",
          "source_description_name" => "bookStore",
          "path" => "/books",
          "requestBody" => %{
            "required" => true,
            "content" => %{"application/json" => %{"schema" => %{"type" => "string"}}}
          },
          "responses" => %{
            "200" => %{
              "content" => %{"application/json" => %{"schema" => %{"type" => "array"}}}
            }
          }
        })

      assert {:error, %InvalidRequest{type: :missing_body}} =
               RequestBody.matches(nil, operation, default_context())
    end

    test "returns :ok when body is empty and operation body is optional" do
      operation =
        OpenAPI.Operation.new!(%{
          "method" => "delete",
          "source_description_name" => "bookStore",
          "path" => "/books",
          "requestBody" => %{
            "content" => %{"application/json" => %{"schema" => %{"type" => "string"}}}
          },
          "responses" => %{
            "200" => %{
              "content" => %{"application/json" => %{"schema" => %{"type" => "array"}}}
            }
          }
        })

      assert :ok == RequestBody.matches(nil, operation, default_context())
    end
  end
end
