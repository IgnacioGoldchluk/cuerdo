defmodule Cuerdo.OpenApiTest do
  use ExUnit.Case

  alias Cuerdo.OpenAPI
  import Cuerdo.ArazzoFixtures

  setup do
    %{schema: example_openapi_json()}
  end

  describe "fetch_operation_by_path/3" do
    test "returns error tuple when operationId does not exist", %{schema: schema} do
      operation_id = "invalidOperationId"
      source_description_name = "openapi"

      assert {:error, "operationId invalidOperationId not found"} ==
               OpenAPI.fetch_operation_by_id(operation_id, schema, source_description_name)
    end

    test "returns error if multiple operations have the same operationId", %{schema: schema} do
      operation_id = "listBooks"
      source_description_name = "openapi"
      wrong_schema = put_in(schema, ["paths", "/books", "post", "operationId"], operation_id)

      assert {:error, "multiple operationId listBooks found"} ==
               OpenAPI.fetch_operation_by_id(operation_id, wrong_schema, source_description_name)
    end

    test "expands non-schema references" do
      schema = %{
        "components" => %{
          "schemas" => %{
            "errors" => %{
              "type" => "object",
              "required" => ["code", "message"],
              "properties" => %{
                "code" => %{"type" => "integer"},
                "message" => %{"type" => "string"}
              }
            }
          },
          "responses" => %{
            "errors" => %{
              "content" => %{
                "application/json" => %{
                  "schema" => %{
                    "$ref" => "#/components/schemas/error"
                  }
                }
              }
            }
          }
        },
        "paths" => %{
          "/books/{book_id}" => %{
            "get" => %{
              "responses" => %{
                "default" => %{"$ref" => "#/components/responses/errors"},
                "200" => %{
                  "content" => %{
                    "application/json" => %{
                      "schema" => %{
                        "type" => "object",
                        "properties" => %{
                          "id" => %{"type" => "string"}
                        }
                      }
                    }
                  }
                }
              }
            }
          }
        }
      }

      path = "#/paths/~1books~1{book_id}/get"
      source_description_name = "openapi"

      {:ok, %OpenAPI.Operation{} = operation} =
        OpenAPI.fetch_operation_by_path(path, schema, source_description_name)

      assert operation.responses["default"] == %Cuerdo.OpenAPI.Response{
               content: %{
                 "application/json" => %{schema: %{"$ref" => "#/components/schemas/error"}}
               }
             }
    end

    test "returns operation for the given operationId", %{schema: schema} do
      operation_id = "listBooks"
      source_description_name = "openapi"

      {:ok, %OpenAPI.Operation{} = operation} =
        OpenAPI.fetch_operation_by_id(operation_id, schema, source_description_name)

      assert operation.path == "/books"
      assert operation.method == "get"
      assert operation.parameters == []
      assert operation.source_description_name == source_description_name
      assert is_nil(operation.requestBody)

      assert operation.responses == %{
               200 => %Cuerdo.OpenAPI.Response{
                 content: %{
                   "application/json" => %{
                     schema: %{
                       "items" => %{"$ref" => "#/components/schemas/Book"},
                       "title" => "Response Listbooks",
                       "type" => "array"
                     }
                   }
                 }
               }
             }
    end

    test "returns operation at the given path", %{schema: schema} do
      path = "#/paths/~1books~1{book_id}/get"
      source_description_name = "openapi"

      {:ok, %OpenAPI.Operation{} = operation} =
        OpenAPI.fetch_operation_by_path(path, schema, source_description_name)

      assert operation.source_description_name == source_description_name
      assert operation.path == "/books/{book_id}"
      assert operation.method == "get"
      assert is_nil(operation.requestBody)

      assert operation.parameters == [
               %OpenAPI.Parameter{in: "path", name: "book_id", required: true}
             ]

      assert operation.responses == %{
               200 => %OpenAPI.Response{
                 content: %{
                   "application/json" => %{
                     schema: %{"$ref" => "#/components/schemas/Book"}
                   }
                 }
               },
               422 => %OpenAPI.Response{
                 content: %{
                   "application/json" => %{
                     schema: %{"$ref" => "#/components/schemas/HTTPValidationError"}
                   }
                 }
               }
             }
    end
  end
end
