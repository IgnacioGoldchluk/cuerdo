defmodule Cuerdo.Arazzo.StepTest do
  use ExUnit.Case

  alias Cuerdo.Arazzo
  alias Cuerdo.Arazzo.{Criterion, Parameter, Step}
  alias Cuerdo.OpenAPI

  test "onFailure must be unique" do
    step = %{
      "stepId" => "loginStep",
      "description" => "Demonstrates user login",
      "operationId" => "loginUser",
      "parameters" => [
        %{"name" => "username", "in" => "query", "value" => "$inputs.username"}
      ],
      "successCriteria" => [%{"condition" => "$statusCode == 200"}],
      "onFailure" => [
        %{
          "name" => "Finish",
          "type" => "end",
          "criteria" => [%{"condition" => "$statusCode == 200"}]
        },
        %{
          "name" => "Finish",
          "type" => "end",
          "criteria" => [%{"condition" => "$statusCode == 200"}]
        }
      ]
    }

    assert {:error, [%Zoi.Error{path: [:onFailure], message: msg}]} = Step.new(step)
    assert msg == "must contain unique items"
  end

  test "parameters elements must be unique" do
    step = %{
      "stepId" => "loginStep",
      "description" => "Demonstrates user login",
      "operationId" => "loginUser",
      "parameters" => [
        %{"name" => "username", "in" => "query", "value" => "$inputs.username"},
        %{"name" => "username", "in" => "query", "value" => "$inputs.username"}
      ],
      "successCriteria" => [%{"condition" => "$statusCode == 200"}]
    }

    assert {:error, [%Zoi.Error{path: [:parameters], message: msg}]} = Step.new(step)
    assert msg == "must contain unique items"
  end

  test "onSuccess elements must be unique" do
    step = %{
      "stepId" => "loginStep",
      "description" => "Demonstrates user login",
      "operationId" => "loginUser",
      "successCriteria" => [%{"condition" => "$statusCode == 200"}],
      "parameters" => [%{"name" => "username", "in" => "query", "value" => "$inputs.username"}],
      "onSuccess" => [
        %{
          "name" => "Finish",
          "type" => "end",
          "criteria" => [%{"condition" => "$statusCode == 200"}]
        },
        %{
          "name" => "Finish",
          "type" => "end",
          "criteria" => [%{"condition" => "$statusCode == 200"}]
        }
      ]
    }

    assert {:error, [%Zoi.Error{path: [:onSuccess], message: msg}]} = Step.new(step)
    assert msg == "must contain unique items"
  end

  test "successCriteria must be empty when step references workflowId" do
    step = %{
      "stepId" => "loginStep",
      "workflowId" => "workflowName",
      "parameters" => [
        %{"name" => "Authorization", "in" => "header", "value" => "Bearer $inputs.token"}
      ],
      "successCriteria" => [%{"condition" => "$statusCode == 200"}]
    }

    assert {:error, [%Zoi.Error{message: msg}]} = Step.new(step)
    assert msg == "successCriteria must be empty when step references a workflowId"
  end

  test "successCriteria is required when step does not reference workflowId" do
    step = %{
      "stepId" => "loginStep",
      "operationId" => "workflowName",
      "parameters" => [
        %{"name" => "Authorization", "in" => "header", "value" => "Bearer $inputs.token"}
      ]
    }

    assert {:error, [%Zoi.Error{message: msg}]} = Step.new(step)
    assert msg == "successCriteria required"
  end

  test "exactly one of 'operationId', 'workflowId' or 'operationPath' must be set" do
    step = %{
      "stepId" => "loginStep",
      "description" => "Demonstrates user login",
      "operationId" => "loginUser",
      "parameters" => [
        %{"name" => "username", "in" => "query", "value" => "$inputs.username"},
        %{"name" => "password", "in" => "query", "value" => "$inputs.password"}
      ],
      "successCriteria" => [%{"condition" => "$statusCode == 200"}],
      "outputs" => %{"token" => "$response.header.token"}
    }

    expected = %Step{
      description: step["description"],
      parameters: [
        %Parameter{in: "query", name: "username", value: "$inputs.username"},
        %Parameter{in: "query", name: "password", value: "$inputs.password"}
      ],
      outputs: step["outputs"],
      stepId: step["stepId"],
      operationId: step["operationId"],
      operationPath: nil,
      workflowId: nil,
      requestBody: nil,
      successCriteria: [%Criterion{context: nil, condition: "$statusCode == 200", type: "simple"}],
      onSuccess: [],
      onFailure: []
    }

    assert {:ok, expected} == Step.new(step)

    no_ids = Map.delete(step, "operationId")
    assert {:error, [%Zoi.Error{message: msg}]} = Step.new(no_ids)
    assert msg == "exactly one of 'operationId', 'operationPath' and 'workflowId' must be set"

    more_than_one =
      Map.put(step, "workflowId", "loginUserWorkflow")
      |> Map.delete("successCriteria")
      |> Map.delete("outputs")

    assert {:error, [%Zoi.Error{message: msg}]} = Step.new(more_than_one)
    assert msg == "exactly one of 'operationId', 'operationPath' and 'workflowId' must be set"
  end

  describe "build_request/5" do
    test "puts body in request body" do
      base_url = "https://example.com"
      parameters = []

      body = %{
        body: %{"name" => "Alice", "owner" => "Bob"},
        content_type: "application/json"
      }

      operation =
        OpenAPI.Operation.new!(%{
          "method" => "post",
          "source_description_name" => "bookStore",
          "path" => "/pets",
          "requestBody" => %{
            "content" => %{
              "application/json" => %{
                "schema" => %{
                  "type" => "object",
                  "required" => ["name", "owner"],
                  "properties" => %{
                    "name" => %{"type" => "string"},
                    "owner" => %{"type" => "string"}
                  }
                }
              }
            }
          },
          "responses" => %{
            "201" => %{
              "content" => %{
                "application/json" => %{
                  "schema" => %{"type" => "object"}
                }
              }
            }
          }
        })

      %Req.Request{} = request = Step.build_request(base_url, parameters, body, operation, nil)
      assert request.method == :post
      assert to_string(request.url) == "https://example.com/pets"
      assert Req.Request.get_header(request, "content-type") == ["application/json"]
      assert Req.Request.get_option(request, :params) == []
      assert Req.Request.get_option(request, :path_params) == []
      assert request.body == body[:body]
    end

    test "multiple query, path, and head parameters are added to the request" do
      base_url = "https://example.com"

      parameters =
        [
          %{"name" => "foo", "in" => "query", "value" => "1"},
          %{"name" => "bar", "in" => "path", "value" => "2"},
          %{"name" => "Authorization", "in" => "header", "value" => "Bearer token"},
          %{"name" => "baz", "in" => "query", "value" => "3"},
          %{"name" => "qux", "in" => "path", "value" => "4"}
        ]
        |> Enum.map(&Arazzo.Parameter.new!/1)

      operation =
        OpenAPI.Operation.new!(%{
          "method" => "get",
          "source_description_name" => "bookStore",
          "path" => "/{bar}/{qux}",
          "parameters" => [
            %{"name" => "foo", "in" => "query"},
            %{"name" => "bar", "in" => "path", "required" => true},
            %{"name" => "baz", "in" => "query"},
            %{"name" => "qux", "in" => "path", "required" => true}
          ],
          "responses" => %{
            "200" => %{
              "content" => %{
                "application/json" => %{
                  "schema" => %{"type" => "object"}
                }
              }
            }
          }
        })

      body = %{body: nil, content_type: "application/json"}

      %Req.Request{} = request = Step.build_request(base_url, parameters, body, operation, nil)
      assert to_string(request.url) == "https://example.com/{bar}/{qux}"
      assert request.method == :get
      assert Req.Request.get_header(request, "authorization") == ["Bearer token"]
      assert Req.Request.get_option(request, :params) == [{"baz", "3"}, {"foo", "1"}]
      assert Req.Request.get_option(request, :path_params) == [{:qux, "4"}, {:bar, "2"}]
    end

    test "sets receive_timeout when timeout is specified" do
      base_url = "https://example.com/api"

      operation =
        OpenAPI.Operation.new!(%{
          "method" => "get",
          "source_description_name" => "bookStore",
          "path" => "/books",
          "responses" => %{
            "200" => %{
              "content" => %{
                "application/json" => %{
                  "schema" => %{"type" => "object"}
                }
              }
            }
          }
        })

      parameters = []
      body = nil
      timeout = 5_000

      %Req.Request{} =
        request = Step.build_request(base_url, parameters, body, operation, timeout)

      assert Enum.empty?(Req.Request.get_header(request, "content-type"))
      assert is_nil(request.body)
      assert request.options.receive_timeout == timeout
    end

    test "does not include content-type or body when body is empty" do
      base_url = "https://example.com/api"

      operation =
        OpenAPI.Operation.new!(%{
          "method" => "get",
          "source_description_name" => "bookStore",
          "path" => "/books",
          "responses" => %{
            "200" => %{
              "content" => %{
                "application/json" => %{
                  "schema" => %{"type" => "object"}
                }
              }
            }
          }
        })

      parameters = []
      body = nil
      %Req.Request{} = request = Step.build_request(base_url, parameters, body, operation, nil)

      assert Enum.empty?(Req.Request.get_header(request, "content-type"))
      assert is_nil(request.body)
    end

    test "concatenates base URL and operation path" do
      base_url = "https://example.com/api/v1"

      parameters = [Arazzo.Parameter.new!(%{"name" => "book_id", "in" => "path", "value" => 1})]

      operation =
        OpenAPI.Operation.new!(%{
          "method" => "get",
          "source_description_name" => "bookStore",
          "path" => "/books/{book_id}",
          "parameters" => [
            %{"name" => "book_id", "in" => "path", "required" => true}
          ],
          "responses" => %{
            "200" => %{
              "content" => %{
                "application/json" => %{
                  "schema" => %{"type" => "object"}
                }
              }
            }
          }
        })

      %Req.Request{} =
        request =
        Step.build_request(
          base_url,
          parameters,
          %{body: nil, content_type: "application/json"},
          operation,
          nil
        )

      assert request.method == :get
      assert Req.Request.get_header(request, "content-type") == ["application/json"]
      assert to_string(request.url) == "https://example.com/api/v1/books/{book_id}"
      assert Req.Request.get_option(request, :params) == []
      assert Req.Request.get_option(request, :path_params) == [book_id: 1]
      assert Req.Request.get_option(request, :path_params_style) == :curly
    end
  end
end
