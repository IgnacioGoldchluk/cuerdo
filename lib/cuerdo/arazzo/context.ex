defmodule Cuerdo.Arazzo.Context do
  @moduledoc """
  Internal Arazzo Context. Stores workflows and steps inputs/outputs, request/response, etc.
  """
  alias Cuerdo.Arazzo.{Document, SourceDescription, Workflow}
  alias Cuerdo.Errors.{InvalidDocument, InvalidSourceDescription}

  defstruct [
    # The fully parsed document
    :document,
    # Each of the `workflows` input as a map of %{"workflowId" => input}
    # No need to cover `steps` here because they don't have inputs
    :inputs,
    # Workflow outputs in the form of
    # %{workflowId => %{outputKey => outputValue, steps: %{stepId => output}}}
    :outputs,
    # Steps objects can do a single request/response each, so we can store as
    # %{workflowId => %{stepId => %{request: req, response: resps}}}
    :api_calls,
    # Resolver module for building and validating JSV schemas
    :resolver,
    # Cached remotely fetched Arazzo files and sourceDescriptions
    :cache,
    # Client module for fetching sourceDescriptions
    client: Cuerdo.Client
  ]

  @type t :: %__MODULE__{}

  # Creates a new context from an unparsed document or context
  @doc false
  @spec from_document(t() | Document.t() | map(), Keyword.t()) ::
          {:ok, t()} | {:error, Exception.t()}
  def from_document(document_or_context, opts \\ [])

  def from_document(%__MODULE__{} = context, _opts), do: {:ok, context}

  def from_document(%Document{} = document, opts) do
    case NimbleOptions.validate(opts, context_opts()) do
      {:error, _reason} = error ->
        error

      {:ok, opts} ->
        {:ok,
         %__MODULE__{
           document: document,
           inputs: empty_inputs(document),
           outputs: empty_outputs(document),
           api_calls: empty_api_calls(document),
           resolver: Keyword.fetch!(opts, :resolver),
           cache: %{}
         }}
    end
  end

  def from_document(arazzo_document, opts) do
    case new(arazzo_document, opts) do
      {:ok, context} -> {:ok, context}
      {:error, errors} -> {:error, %InvalidDocument{errors: errors}}
    end
  end

  @doc """
  Same as `new/2` but raises on error
  """
  @spec new!(map(), module()) :: t()
  def new!(document_data, opts \\ []) when is_map(document_data) do
    case new(document_data, opts) do
      {:ok, %__MODULE__{} = ctx} -> ctx
      {:error, errors} when is_list(errors) -> raise InvalidDocument, errors: errors
    end
  end

  @doc """
  Creates a new context
  """
  @spec new(map(), Keyword.t()) :: {:ok, t()} | {:error, Exception.t()}
  def new(document_data, opts \\ []) when is_map(document_data) do
    with {:ok, opts} <- NimbleOptions.validate(opts, context_opts()),
         {:ok, %Document{} = document} <- Document.new(document_data) do
      {:ok,
       %__MODULE__{
         document: document,
         inputs: empty_inputs(document),
         outputs: empty_outputs(document),
         api_calls: empty_api_calls(document),
         resolver: Keyword.fetch!(opts, :resolver),
         cache: %{}
       }}
    end
  end

  @doc """
  Fetch a source description by name. Returns `{:ok, source_description, updated_context}`
  on success, or an error tuple
  """
  @spec fetch_source_description(t(), binary()) :: {:ok, map(), t()} | {:error, Exception.t()}
  def fetch_source_description(%__MODULE__{} = context, name) when is_binary(name) do
    case Enum.find(context.document.sourceDescriptions, &(&1.name == name)) do
      nil ->
        valid_names = Document.source_description_names(context.document)
        {:error, %InvalidSourceDescription{name: name, valid_names: valid_names}}

      %SourceDescription{value: nil} = source_description ->
        case resolve_source_description(context, source_description) do
          {:ok, %__MODULE__{} = updated_ctx} -> fetch_source_description(updated_ctx, name)
          {:error, e} = error when is_exception(e) -> error
        end

      %SourceDescription{value: value} ->
        {:ok, value, context}
    end
  end

  @doc false
  def merge_cache(%__MODULE__{} = to, %__MODULE__{cache: cache2} = _from) do
    Map.update!(to, :cache, fn cache -> Map.merge(cache, cache2) end)
  end

  defp resolve_source_description(%__MODULE__{cache: cache} = context, %{url: url})
       when is_map_key(cache, url) do
    {:ok, context}
  end

  defp resolve_source_description(context, %SourceDescription{} = source_description) do
    %{name: name, url: url} = source_description

    case context.client.fetch_schema(url) do
      {:ok, schema} when is_map(schema) ->
        schema =
          case source_description.type do
            "arazzo" -> Document.resolve_self(schema, url)
            _ -> schema
          end

        ctx =
          context
          |> put_source_description(name, schema)
          |> maybe_store_in_cache(url, schema)

        {:ok, ctx}

      {:error, _} = error ->
        error
    end
  end

  @doc """
  Sets the source description value to the given schema. Returns the updated context
  """
  @spec put_source_description(t(), String.t(), map()) :: t()
  def put_source_description(%__MODULE__{} = context, name, schema) do
    idx = Enum.find_index(context.document.sourceDescriptions, &(&1.name == name))

    Map.update!(
      context,
      :document,
      fn %Document{} = document ->
        Map.update!(document, :sourceDescriptions, fn source_descriptions ->
          List.update_at(source_descriptions, idx, &Map.put(&1, :value, schema))
        end)
      end
    )
  end

  defp maybe_store_in_cache(%__MODULE__{} = context, url, schema) do
    case URI.parse(url) do
      %URI{scheme: scheme} when scheme in ["http", "https"] ->
        Map.update!(context, :cache, fn cache -> Map.put(cache, url, schema) end)

      _ ->
        context
    end
  end

  defp empty_inputs(%Document{} = document) do
    Map.new(document.workflows, fn %Workflow{} = workflow ->
      # This one can be empty map because we're always enforcing workflow inputs,
      # and since it's a schema some of the keys might not exist if they're not "required"
      {workflow.workflowId, Map.new()}
    end)
  end

  defp empty_outputs(%Document{} = document) do
    Map.new(document.workflows, fn %Workflow{} = workflow ->
      # Only consider steps that have outputs
      steps =
        for step <- workflow.steps,
            into: %{},
            do:
              {step.stepId, Map.new(step.outputs, fn {key, ref} -> {key, {:unresolved, ref}} end)}

      workflow_outputs = Map.new(workflow.outputs, fn {key, ref} -> {key, {:unresolved, ref}} end)

      {workflow.workflowId, %{steps: steps} |> Map.merge(workflow_outputs)}
    end)
  end

  defp empty_api_calls(%Document{} = document) do
    Map.new(document.workflows, fn %Workflow{} = workflow ->
      steps =
        for step <- workflow.steps, into: %{}, do: {step.stepId, %__MODULE__.APICalls{}}

      {workflow.workflowId, steps}
    end)
  end

  @doc """
  Puts a map of `%{input_name => value}` in the `worfklow_id` inputs. Returns
  the updated context
  """
  @spec put_inputs(t(), String.t(), map()) :: t()
  def put_inputs(%__MODULE__{} = ctx, workflow_id, workflow_inputs)
      when is_map(workflow_inputs) do
    Enum.reduce(workflow_inputs, ctx, fn {input_key, input_value}, ctx ->
      put_inputs(ctx, workflow_id, input_key, input_value)
    end)
  end

  @doc false
  def put_inputs(%__MODULE__{inputs: inputs} = ctx, workflow_id, key, value) do
    %__MODULE__{ctx | inputs: put_in(inputs, [workflow_id, key], value)}
  end

  @doc false
  def put_workflow_output(%__MODULE__{outputs: outputs} = ctx, workflow_id, key, value) do
    %__MODULE__{ctx | outputs: put_in(outputs, [workflow_id, key], value)}
  end

  @doc false
  def put_step_output(%__MODULE__{outputs: outputs} = ctx, workflow_id, step_id, key, value) do
    %__MODULE__{ctx | outputs: put_in(outputs, [workflow_id, :steps, step_id, key], value)}
  end

  @doc false
  def put_step_response(
        %__MODULE__{api_calls: api_calls} = ctx,
        workflow_id,
        step_id,
        %Req.Response{} = response
      ) do
    api_call = %{api_calls[workflow_id][step_id] | response: response}
    %__MODULE__{ctx | api_calls: put_in(api_calls, [workflow_id, step_id], api_call)}
  end

  @doc false
  def put_step_request(
        %__MODULE__{api_calls: api_calls} = ctx,
        workflow_id,
        step_id,
        %Req.Request{} = request
      ) do
    api_call = %{api_calls[workflow_id][step_id] | request: request}
    %__MODULE__{ctx | api_calls: put_in(api_calls, [workflow_id, step_id], api_call)}
  end

  @doc """
  Returns the outputs map for the given stepId, or an empty map if the step
  does not define any outputs
  """
  @spec step_outputs(t(), String.t(), String.t()) :: map()
  def step_outputs(%__MODULE__{outputs: outputs}, workflow_id, step_id) do
    outputs |> Map.fetch!(workflow_id) |> Map.fetch!(:steps) |> Map.get(step_id, %{})
  end

  @doc """
  Returns the outputs map for the given workflowId.
  """
  @spec workflow_outputs(t(), String.t()) :: map()
  def workflow_outputs(%__MODULE__{outputs: outputs}, workflow_id) do
    outputs |> Map.fetch!(workflow_id) |> Map.delete(:steps)
  end

  @doc """
  Returns the request and response structs for the given stepId
  """
  @spec step_request_response(t(), String.t(), String.t()) ::
          %{request: Req.Request.t(), response: Req.Response.t()} | nil
  def step_request_response(%__MODULE__{api_calls: api_calls}, workflow_id, step_id) do
    get_in(api_calls, [workflow_id, step_id])
  end

  @doc """
  Returns the source description name for a given operation path or id
  """
  @spec get_source_description_name(String.t(), t()) :: String.t()
  def get_source_description_name(op_path_or_id, ctx) when is_binary(op_path_or_id) do
    pattern = ~r/^["']?{?\$sourceDescriptions\.([\w\-]+)/

    case Regex.run(pattern, op_path_or_id, capture: :all_but_first) do
      [name] ->
        name

      nil ->
        [%SourceDescription{name: name}] = ctx.document.sourceDescriptions
        name
    end
  end

  defp context_opts do
    [
      resolver: [type: :atom, default: Cuerdo.Resolver]
    ]
  end

  @doc """
  Creates a new Context, using an existing context as base
  """
  @spec from_base(t(), map()) :: {:ok, t()} | {:error, Exception.t()}
  def from_base(%__MODULE__{} = ctx, document) do
    opts = [resolver: ctx.resolver]

    case from_document(document, opts) do
      {:ok, %__MODULE__{} = new_ctx} -> {:ok, merge_cache(new_ctx, ctx)}
      {:error, exc} = error when is_exception(exc) -> error
    end
  end
end
