defmodule Cuerdo.Arazzo.RunWorkflowTest do
  use ExUnit.Case

  alias Cuerdo.Arazzo
  alias Cuerdo.Arazzo.Context

  import YamlElixir.Sigil
  import Cuerdo.ArazzoFixtures

  describe "run_workflow/3 ecommerce mock" do
    setup do
      document =
        Path.join(["test", "support", "ecommerce", "arazzo.yaml"]) |> YamlElixir.read_from_file!()

      %{document: document}
    end

    test "applies replacements for requestBody", %{document: document} do
      %{"workflows" => [%{"workflowId" => workflow_id}]} = document

      document =
        document
        |> RockSolid.Traversal.put_in_schema!(
          ["workflows", "0", "steps", "0", "requestBody", "replacements"],
          [
            %{
              "target" => "#/name",
              "value" => %{
                "context" => "$inputs.itemNew",
                "type" => "jsonpath",
                "selector" => "$.name"
              }
            }
          ]
        )
        |> RockSolid.Traversal.put_in_schema!(
          ["workflows", "0", "steps", "0", "successCriteria"],
          [
            %{"condition" => "$response.body#/price == $inputs.item#/price"},
            %{"condition" => "$response.body#/name == $inputs.itemNew#/name"}
          ]
        )
        |> RockSolid.Traversal.put_in_schema!(
          ["workflows", "0", "steps", "1", "successCriteria"],
          [
            %{"condition" => "$statusCode == 200"},
            %{"condition" => "$response.body#/id == $steps.createItemStep.outputs.itemId"},
            %{"condition" => "$response.body#/price == $inputs.item#/price"},
            %{"condition" => "$response.body#/name == $inputs.itemNew#/name"}
          ]
        )
        |> RockSolid.Traversal.put_in_schema!(
          ["workflows", "0", "inputs"],
          %{
            "type" => "object",
            "additionalProperties" => false,
            "required" => ["item", "itemNew"],
            "properties" => %{
              "item" => %{
                "$ref" => "{$sourceDescriptions.ecommerce.url}#/components/schemas/Item"
              },
              "itemNew" => %{
                "$ref" => "{$sourceDescriptions.ecommerce.url}#/components/schemas/Item"
              }
            }
          }
        )

      inputs = %{
        "item" => %{"name" => "Shoes", "price" => 12_345},
        "itemNew" => %{"name" => "newShoes", "price" => 67_890}
      }

      expected_item = %{"name" => "newShoes", "price" => 12_345}
      id = System.unique_integer([:positive])

      Req.Test.expect(Cuerdo.Client, 2, fn conn ->
        case conn.method do
          "POST" ->
            assert conn.body_params == expected_item
            Req.Test.json(conn, Map.put(expected_item, "id", id))

          "GET" ->
            assert conn.path_info == ["items", to_string(id)]
            Req.Test.json(conn, Map.put(expected_item, "id", id))
        end
      end)

      assert {:ok, ctx} = Arazzo.run_workflow(inputs, workflow_id, document)
      outputs = Context.workflow_outputs(ctx, workflow_id)
      assert outputs["itemId"] == id
    end

    test "returns error for invalid document", %{document: document} do
      assert {:error, %Cuerdo.Errors.ExecutionError{error: invalid_document_error}} =
               Arazzo.run_workflow(%{}, "workflowId", Map.delete(document, "workflows"))

      assert invalid_document_error
             |> Exception.message()
             |> String.starts_with?("Arazzo Document")
    end

    test "returns error for invalid condition", %{document: document} do
      workflow_id = "createAndRetrieveItem"
      item = %{"name" => "Shoes", "price" => 12_345}
      workflow_input = %{"item" => item}
      id = System.unique_integer([:positive])

      document =
        RockSolid.Traversal.put_in_schema!(
          document,
          ["workflows", "0", "steps", "0", "successCriteria", "0", "condition"],
          "$statusCode <> 200"
        )

      Req.Test.expect(Cuerdo.Client, 1, fn conn ->
        assert conn.method == "POST"
        Req.Test.json(conn, Map.put(item, "id", id))
      end)

      assert {:error,
              %Cuerdo.Errors.ExecutionError{
                error: %Cuerdo.Errors.InvalidExpression{
                  expression: "$statusCode <> 200",
                  message: "unexpected token" <> _
                }
              }} =
               Arazzo.run_workflow(workflow_input, workflow_id, document)
    end

    test "returns error for empty condition", %{document: document} do
      workflow_id = "createAndRetrieveItem"
      item = %{"name" => "Shoes", "price" => 12_345}
      workflow_input = %{"item" => item}
      id = System.unique_integer([:positive])

      document =
        RockSolid.Traversal.put_in_schema!(
          document,
          ["workflows", "0", "steps", "0", "successCriteria", "0", "condition"],
          ""
        )

      Req.Test.expect(Cuerdo.Client, 2, fn conn ->
        assert conn.method == "POST"
        Req.Test.json(conn, Map.put(item, "id", id))
      end)

      assert {:error,
              %Cuerdo.Errors.ExecutionError{
                error: %Cuerdo.Errors.InvalidExpression{
                  expression: "",
                  message: "unexpected end of input"
                }
              }} =
               Arazzo.run_workflow(workflow_input, workflow_id, document)
    end

    test "returns error when sourceDescription in operationPath is invalid", %{document: document} do
      # pattern is: '{$sourceDescriptions.tapiz.url}#/paths/~1api~1json~1categories~1{id}/get'
      workflow_id = "createAndRetrieveItem"
      item = %{"name" => "Shoes", "price" => 12_345}
      workflow_input = %{"item" => item}
      %{"workflows" => [%{"steps" => [step | _]}]} = document

      invalid_path = "'{$sourceDescriptions.invalidName.url}#/paths/~1invalid~1path"

      document =
        RockSolid.Traversal.put_in_schema!(
          document,
          ["workflows", "0", "steps", "0"],
          step |> Map.delete("operationId") |> Map.put("operationPath", invalid_path)
        )

      assert {:error,
              %Cuerdo.Errors.ExecutionError{
                error: %Cuerdo.Errors.InvalidSourceDescription{name: "invalidName"}
              }} =
               Arazzo.run_workflow(workflow_input, workflow_id, document)
    end

    test "returns error for invalid operationPath", %{document: document} do
      workflow_id = "createAndRetrieveItem"
      item = %{"name" => "Shoes", "price" => 12_345}
      workflow_input = %{"item" => item}

      %{"workflows" => [%{"steps" => [step | _]}]} = document

      document =
        RockSolid.Traversal.put_in_schema!(
          document,
          ["workflows", "0", "steps", "0"],
          step |> Map.delete("operationId") |> Map.put("operationPath", "/path/~invalid")
        )

      assert {:error,
              %Cuerdo.Errors.ExecutionError{
                error: %Cuerdo.Errors.InvalidOperation{value: "/path/~invalid"}
              }} =
               Arazzo.run_workflow(workflow_input, workflow_id, document)
    end

    test "returns error for invalid input reference", %{document: document} do
      workflow_id = "createAndRetrieveItem"
      item = %{"name" => "Shoes", "price" => 12_345}
      workflow_input = %{"item" => item}
      id = System.unique_integer([:positive])

      document =
        RockSolid.Traversal.put_in_schema!(
          document,
          ["workflows", "0", "steps", "0", "outputs", "itemId"],
          "$reponse.body#id"
        )

      Req.Test.expect(Cuerdo.Client, 2, fn conn ->
        assert conn.method == "POST"
        Req.Test.json(conn, Map.put(item, "id", id))
      end)

      assert {:error,
              %Cuerdo.Errors.ExecutionError{
                error: %Cuerdo.Errors.InvalidExpression{
                  expression: {"$reponse.body", "#id"},
                  message: "does not match any valid expression"
                }
              }} =
               Arazzo.run_workflow(workflow_input, workflow_id, document)
    end

    test "runs workflow with local OpenAPI document", %{document: document} do
      workflow_id = "createAndRetrieveItem"
      item = %{"name" => "Shoes", "price" => 12_345}
      workflow_input = %{"item" => item}
      id = System.unique_integer([:positive])

      Req.Test.expect(Cuerdo.Client, 2, fn conn ->
        case conn.method do
          "POST" ->
            assert conn.body_params == item
            Req.Test.json(conn, Map.put(item, "id", id))

          "GET" ->
            assert conn.path_info == ["items", to_string(id)]
            Req.Test.json(conn, Map.put(item, "id", id))
        end
      end)

      assert {:ok, ctx} = Arazzo.run_workflow(workflow_input, workflow_id, document)
      outputs = Context.workflow_outputs(ctx, workflow_id)
      assert outputs["itemId"] == id
    end
  end

  describe "run_workflow/3 people mock" do
    setup do
      %{document: people_document(with_self: true)}
    end

    test "invalid inputs return error", %{document: document} do
      workflow_id = "getPeople"
      inputs = %{"wrong" => 123}

      assert {:error, error} = Arazzo.run_workflow(inputs, workflow_id, document)
      assert String.starts_with?(Exception.message(error), "executing getPeople: Invalid inputs")
    end

    test "returns error when status code doesn't match condition", %{document: document} do
      workflow_id = "getPeople"
      inputs = %{"name" => "John", "min_age" => 20}

      response = [%{"name" => "John", "age" => 20}]

      Req.Test.expect(Cuerdo.Client, 1, fn conn ->
        conn
        |> Plug.Conn.put_resp_content_type("application/json")
        |> Plug.Conn.send_resp(201, JSON.encode!(response))
      end)

      assert {:error, error} = Arazzo.run_workflow(inputs, workflow_id, document)

      expected =
        "executing getPeople.getPeopleStep: expression $statusCode == 200 (simple) failed. Evaluated to 201 == 200"

      assert expected == Exception.message(error)
    end

    test "fails if step request timeouts", %{document: document} do
      workflow_id = "getPeople"
      inputs = %{"name" => "John", "min_age" => 20}

      Req.Test.expect(Cuerdo.Client, 1, &Req.Test.transport_error(&1, :timeout))

      {:error, %Cuerdo.Errors.ExecutionError{error: %Req.TransportError{reason: :timeout}}} =
        Arazzo.run_workflow(inputs, workflow_id, document)
    end

    test "successfully executes regex and jsonpath criteria", %{document: document} do
      workflow_id = "getPeople"
      inputs = %{"name" => "John", "min_age" => 20}

      response = [
        %{"name" => "Johnathan", "age" => 21},
        %{"name" => "Johnson", "age" => 22},
        %{"name" => "John", "age" => 23}
      ]

      Req.Test.expect(Cuerdo.Client, 1, fn conn ->
        assert conn.method == "GET"
        assert conn.query_params["min_age"] == to_string(inputs["min_age"])
        assert conn.query_params["name"] == inputs["name"]
        Req.Test.json(conn, response)
      end)

      {:ok, ctx} = Arazzo.run_workflow(inputs, workflow_id, document)

      assert Context.workflow_outputs(ctx, workflow_id)["firstMatchingName"] == "Johnathan"
    end

    test "executes a step referencing a local workflow", %{document: document} do
      workflow = %{
        "workflowId" => "getPeopleViaStep",
        "summary" => "Gets people by calling a local workflow",
        "inputs" => %{
          "type" => "object",
          "name" => %{"type" => "string"},
          "min_age" => %{"type" => "integer"}
        },
        "outputs" => %{
          "matchingName" => "$steps.executesWorkflowStep.outputs.firstMatchingName"
        },
        "steps" => [
          %{
            "stepId" => "executesWorkflowStep",
            "workflowId" => "getPeople",
            "parameters" => [
              %{"name" => "min_age", "value" => "$inputs.min_age"},
              %{"name" => "name", "value" => "$inputs.name"}
            ]
          }
        ]
      }

      %{"workflows" => workflows} = document

      document =
        RockSolid.Traversal.put_in_schema!(document, ["workflows"], [workflow | workflows])

      inputs = %{"min_age" => 20, "name" => "Juan"}

      response = [
        %{"name" => "Juan Cruz", "age" => 25},
        %{"name" => "Juan Manuel", "age" => 30},
        %{"name" => "Juan Jose", "age" => 35}
      ]

      Req.Test.expect(Cuerdo.Client, 1, fn conn ->
        assert conn.method == "GET"
        assert conn.query_params["min_age"] == to_string(inputs["min_age"])
        assert conn.query_params["name"] == inputs["name"]
        Req.Test.json(conn, response)
      end)

      {:ok, new_ctx} = Arazzo.run_workflow(inputs, "getPeopleViaStep", document)

      assert Context.workflow_outputs(new_ctx, "getPeopleViaStep")["matchingName"] == "Juan Cruz"
    end

    test "JSONPath selector in output", %{document: document} do
      %{"workflows" => [%{"workflowId" => workflow_id, "steps" => [%{"stepId" => step_id}]}]} =
        document

      document =
        document
        |> RockSolid.Traversal.put_in_schema!(
          ["workflows", "0", "steps", "0", "outputs"],
          %{
            "name" => %{
              "type" => "jsonpath",
              "context" => "$response.body",
              "selector" => "$[? @.age > 30].name"
            }
          }
        )
        |> RockSolid.Traversal.put_in_schema!(
          ["workflows", "0", "outputs"],
          %{
            "matchingName" => "$steps.#{step_id}.outputs.name"
          }
        )

      inputs = %{"min_age" => 20, "name" => "Juan"}

      response = [
        %{"name" => "Juan Cruz", "age" => 25},
        %{"name" => "Juan Manuel", "age" => 30},
        %{"name" => "Juan Jose", "age" => 35}
      ]

      Req.Test.expect(Cuerdo.Client, 1, fn conn ->
        assert conn.method == "GET"
        assert conn.query_params["min_age"] == to_string(inputs["min_age"])
        assert conn.query_params["name"] == inputs["name"]
        Req.Test.json(conn, response)
      end)

      {:ok, new_ctx} = Arazzo.run_workflow(inputs, workflow_id, document)

      assert Context.workflow_outputs(new_ctx, workflow_id)["matchingName"] == "Juan Jose"
    end

    test "runs workflow referenced remotely" do
      document = ~y"""
      arazzo: 1.1.0
      info:
        title: Remote  ref
        summary: Test for remote ref
        description: Title and summary should be enough
        version: 0.1.0
      sourceDescriptions:
        - name: peopleArazzo
          url: ./test/support/people/arazzo.yaml
          type: arazzo

      workflows:
        - workflowId: getPeopleRemote
          summary: Retrieves people from the archive
          outputs:
            firstMatchingName: $steps.getPeopleRemoteStep.outputs.firstMatchingName
          inputs:
            type: object
            additionalProperties: false
            required: ["min_age", "name"]
            properties:
              min_age:
                type: integer
                minimum: 0
              name:
                type: string
                minLength: 1
          steps:
          - stepId: getPeopleRemoteStep
            description: Lists people
            workflowId: $sourceDescriptions.peopleArazzo.getPeople
            parameters:
              - name: min_age
                value: $inputs.min_age
              - name: name
                value: $inputs.name
      """

      %{"workflows" => [%{"workflowId" => workflow_id}]} = document
      inputs = %{"name" => "John", "min_age" => 20}

      response = [
        %{"name" => "Johnathan", "age" => 21},
        %{"name" => "Johnson", "age" => 22},
        %{"name" => "John", "age" => 23}
      ]

      Req.Test.expect(Cuerdo.Client, 1, fn conn ->
        assert conn.method == "GET"
        assert conn.query_params["min_age"] == to_string(inputs["min_age"])
        assert conn.query_params["name"] == inputs["name"]
        Req.Test.json(conn, response)
      end)

      assert {:ok, ctx} = Arazzo.run_workflow(inputs, workflow_id, document)
      assert %{"firstMatchingName" => "Johnathan"} == Context.workflow_outputs(ctx, workflow_id)
    end
  end
end
