defmodule Cuerdo.Arazzo.Step do
  @moduledoc """
  An Arazzo [Step Object](https://spec.openapis.org/arazzo/v1.0.1.html#step-object)
  """
  import Cuerdo.Arazzo.Utils

  alias Cuerdo.Arazzo.{Criterion, FailureAction, Output, Parameter, RequestBody, SuccessAction}
  alias Cuerdo.OpenAPI

  use Cuerdo.Object,
    schema: %{
      description: Zoi.string() |> Zoi.optional(),
      stepId: programming_friendly_id(),
      operationId:
        Zoi.string(
          description: """
          The operationId existing in one of the sourceDescription. If multiple
          sourceDescription are present then it must be specified as
          $sourceDescription.${NAME}.operationId
          """
        )
        |> Zoi.optional(),
      operationPath:
        Zoi.string(
          description: """
          The operationPath referencing something like
          '{$sourceDescriptions.petstoreDescription.url}#/paths/~1pet~1findByStatus/get'
          Which maps to the OpenAPI URL at #/paths/"/pet"/"/findByStatus"/get
          """
        )
        |> Zoi.optional(),
      workflowId: Zoi.string() |> Zoi.optional(),
      parameters:
        Zoi.array(Parameter.schema() |> or_reusable(), unique_items: true) |> Zoi.default([]),
      requestBody: RequestBody.schema() |> Zoi.optional(),
      timeout:
        Zoi.integer(description: "The step (single API call) timeout in millisecond")
        |> Zoi.gt(0)
        |> Zoi.optional(),
      successCriteria: Zoi.array(Criterion.schema(), min_length: 1) |> Zoi.optional(),
      onSuccess:
        Zoi.array(SuccessAction.schema() |> or_reusable(), unique_items: true) |> Zoi.default([]),
      onFailure:
        Zoi.array(FailureAction.schema() |> or_reusable(), unique_items: true) |> Zoi.default([]),
      outputs: Output.schema() |> Zoi.default(%{})
    }

  @impl Cuerdo.Object
  def validations do
    [:single_reference, :success_criteria, :no_workflow_outputs]
  end

  def no_workflow_outputs(%{workflowId: workflow_id, outputs: outputs}) do
    if not is_nil(workflow_id) and not Enum.empty?(outputs) do
      {:error, "step referencing workflowId cannot define outputs"}
    else
      :ok
    end
  end

  def success_criteria(%{workflowId: nil, successCriteria: criteria})
      when criteria in [nil, []] do
    {:error, "successCriteria required"}
  end

  def success_criteria(%{workflowId: workflow_id, successCriteria: criteria})
      when not is_nil(workflow_id) and not is_nil(criteria) do
    {:error, "successCriteria must be empty when step references a workflowId"}
  end

  def success_criteria(_), do: :ok

  def single_reference(step) do
    %{operationId: operation_id, operationPath: operation_path, workflowId: workflow_id} = step

    case Enum.count([operation_id, operation_path, workflow_id], &(not is_nil(&1))) do
      1 -> :ok
      _ -> {:error, "exactly one of 'operationId', 'operationPath' and 'workflowId' must be set"}
    end
  end

  @doc """
  Builds a step request
  """
  @spec build_request(
          String.t(),
          [Parameter.t()],
          nil | %{body: any(), content_type: String.t()},
          OpenAPI.Operation.t(),
          pos_integer() | nil
        ) :: Req.Request.t()
  def build_request(base_url, parameters, request_body, operation, timeout) do
    {body, headers} =
      case request_body do
        nil -> {nil, []}
        %{body: body, content_type: content_type} -> {body, [{"content-type", content_type}]}
      end

    req_opts = %{
      url: URI.append_path(URI.parse(base_url), operation.path) |> to_string(),
      method: String.to_existing_atom(operation.method),
      body: body,
      headers: headers,
      path_params_style: :curly,
      params: [],
      path_params: []
    }

    Enum.reduce(parameters, req_opts, fn parameter, req_opts ->
      %{name: name} = parameter

      case parameter.in do
        "path" ->
          name = String.to_atom(name)
          Map.update!(req_opts, :path_params, &Keyword.put(&1, name, parameter.value))

        "query" ->
          Map.update!(req_opts, :params, &[{name, parameter.value} | &1])

        "header" ->
          Map.update!(req_opts, :headers, &[{String.downcase(name), parameter.value} | &1])
      end
    end)
    |> Keyword.new()
    |> Keyword.merge(Application.get_env(:cuerdo, :client_options, []))
    |> add_timeout(timeout)
    |> Req.new()
  end

  defp add_timeout(request_opts, nil), do: request_opts

  defp add_timeout(request_opts, timeout_ms) when is_integer(timeout_ms) do
    Keyword.put(request_opts, :receive_timeout, timeout_ms)
  end
end
