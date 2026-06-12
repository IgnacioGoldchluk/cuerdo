defmodule Cuerdo.Arazzo.ResponseTest do
  use ExUnit.Case

  alias Cuerdo.Arazzo.{Context, Response}
  alias Cuerdo.Errors.UnexpectedResponse
  alias Cuerdo.OpenAPI

  import Cuerdo.ArazzoFixtures

  describe "matches/3" do
    test "returns error for non-matching schema" do
      ctx = Context.new!(people_document(with_self: true))

      operation =
        OpenAPI.Operation.new!(%{
          "method" => "get",
          "path" => "/people/{id}",
          "source_description_name" => "peopleService",
          "operationId" => "getPerson",
          "parameters" => [%{"in" => "path", "name" => "id", "required" => true}],
          "responses" => %{
            "200" => %{
              "content" => %{
                "application/json" => %{
                  "schema" => %{
                    "type" => "object",
                    "properties" => %{
                      "name" => %{"type" => "string"},
                      "age" => %{"type" => "integer", "minimum" => 0}
                    }
                  }
                }
              }
            }
          },
          "summary" => "Gets a person"
        })

      response =
        Req.Response.new(status: 200, body: %{"name" => "Alice", "age" => -1})
        |> Req.Response.put_header("content-type", "application/json")

      assert {:error, %UnexpectedResponse{message: msg}} =
               Response.matches(response, operation, ctx)

      assert String.starts_with?(msg, "json schema validation failed")
    end

    test "returns error when response has content-type but operation did not define any" do
      ctx = Context.new!(people_document())

      operation =
        OpenAPI.Operation.new!(%{
          "method" => "get",
          "path" => "/people/{id}",
          "source_description_name" => "peopleService",
          "operationId" => "getPerson",
          "parameters" => [%{"in" => "path", "name" => "id", "required" => true}],
          "responses" => %{"200" => %{"description" => "This is missing the content"}},
          "summary" => "Gets a person"
        })

      response =
        Req.Response.new(status: 200, body: %{"name" => "Alice", "age" => 20})
        |> Req.Response.put_header("content-type", "multipart/form-data")

      assert {:error, %UnexpectedResponse{message: msg}} =
               Response.matches(response, operation, ctx)

      assert msg == "No 'content' defined for status code 200"
    end

    test "returns error when there is no matching content-type" do
      ctx = Context.new!(people_document())

      operation =
        OpenAPI.Operation.new!(%{
          "method" => "get",
          "path" => "/people/{id}",
          "source_description_name" => "peopleService",
          "operationId" => "getPerson",
          "parameters" => [%{"in" => "path", "name" => "id", "required" => true}],
          "responses" => %{
            "200" => %{
              "content" => %{
                "application/json" => %{
                  "schema" => %{
                    "type" => "object",
                    "properties" => %{
                      "name" => %{"type" => "string"},
                      "age" => %{"type" => "integer", "minimum" => 0}
                    }
                  }
                }
              }
            }
          },
          "summary" => "Gets a person"
        })

      response =
        Req.Response.new(status: 200, body: %{"name" => "Alice", "age" => 20})
        |> Req.Response.put_header("content-type", "multipart/form-data")

      assert {:error, %UnexpectedResponse{message: msg}} =
               Response.matches(response, operation, ctx)

      assert msg == "no matching content-type for multipart/form-data"
    end

    test "returns error when content-type header is missing from the response" do
      ctx = Context.new!(people_document())

      operation =
        OpenAPI.Operation.new!(%{
          "method" => "get",
          "path" => "/people/{id}",
          "source_description_name" => "peopleService",
          "operationId" => "getPerson",
          "parameters" => [%{"in" => "path", "name" => "id", "required" => true}],
          "responses" => %{
            "200" => %{
              "content" => %{
                "application/json" => %{
                  "schema" => %{
                    "type" => "object",
                    "properties" => %{
                      "name" => %{"type" => "string"},
                      "age" => %{"type" => "integer", "minimum" => 0}
                    }
                  }
                }
              }
            }
          },
          "summary" => "Gets a person"
        })

      response = Req.Response.new(status: 200, body: %{"name" => "Alice", "age" => 20})

      assert {:error, %UnexpectedResponse{message: msg}} =
               Response.matches(response, operation, ctx)

      assert msg == "unexpected 'content-type' header: []"
    end

    test "returns error when no status code matches" do
      ctx = Context.new!(people_document())

      operation =
        OpenAPI.Operation.new!(%{
          "method" => "delete",
          "path" => "/people/{id}",
          "source_description_name" => "peopleService",
          "operationId" => "deletePerson",
          "parameters" => [%{"in" => "path", "name" => "id", "required" => true}],
          "responses" => %{"204" => %{"description" => "Successful Deletion"}},
          "summary" => "Deletes a person"
        })

      response = Req.Response.new(status: 201)

      assert {:error, %UnexpectedResponse{message: msg}} =
               Response.matches(response, operation, ctx)

      assert msg == "no matching response for status code 201"
    end

    test "returns :ok when response body and expected body are empty" do
      ctx = Context.new!(people_document())

      operation =
        OpenAPI.Operation.new!(%{
          "method" => "delete",
          "path" => "/people/{id}",
          "source_description_name" => "peopleService",
          "operationId" => "deletePerson",
          "parameters" => [%{"in" => "path", "name" => "id", "required" => true}],
          "responses" => %{"204" => %{"description" => "Successful Deletion"}},
          "summary" => "Deletes a person"
        })

      response = Req.Response.new(status: 204)

      assert :ok == Response.matches(response, operation, ctx)
    end
  end
end
