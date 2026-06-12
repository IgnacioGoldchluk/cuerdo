defmodule Cuerdo.Arazzo.Document do
  @moduledoc """
  Top-level Arazzo [Document](https://spec.openapis.org/arazzo/v1.0.1.html#arazzo-specification-object)
  """
  alias Cuerdo.Arazzo.{Components, Info, SourceDescription, Utils, Workflow}
  alias Cuerdo.Errors.InvalidWorkflowId
  alias Cuerdo.Graph

  @type t :: %__MODULE__{}

  use Cuerdo.Object,
    schema: %{
      "$self":
        Zoi.string()
        |> Zoi.default(Utils.cwd_as_uri())
        |> Zoi.transform(&Utils.to_absolute_uri/1)
        |> Zoi.refine(&Utils.no_fragment/1),
      arazzo: Zoi.string() |> Zoi.one_of(["1.0.0", "1.0.1", "1.1.0"]),
      info: Info.schema(),
      sourceDescriptions: SourceDescription.schema() |> Zoi.array(min_length: 1),
      workflows: Workflow.schema() |> Zoi.array(min_length: 1),
      components: Components.schema() |> Zoi.optional()
    }

  @impl Cuerdo.Object
  def validations do
    [:unique_workflow_ids, :unique_source_description_names, :no_cyclic_workflows_dependencies]
  end

  @impl Cuerdo.Object
  def transformations do
    [:merge_self_url_to_source_descriptions]
  end

  def merge_self_url_to_source_descriptions(%__MODULE__{} = document) do
    self_url = Map.fetch!(document, :"$self")

    source_descriptions =
      document.sourceDescriptions
      |> Enum.map(fn %SourceDescription{url: url} = source_description ->
        merged_uri = URI.merge(self_url, url) |> to_string()
        %SourceDescription{source_description | url: merged_uri}
      end)

    %__MODULE__{document | sourceDescriptions: source_descriptions}
  end

  def unique_workflow_ids(%{workflows: workflows}) do
    workflow_ids = Enum.map(workflows, & &1.workflowId)

    if length(workflow_ids) != length(workflows) do
      {:error, "duplicate workflow Ids found"}
    else
      :ok
    end
  end

  def unique_source_description_names(%{sourceDescriptions: source_descriptions}) do
    source_description_names = Enum.map(source_descriptions, & &1.name)

    if length(source_description_names) != length(source_descriptions) do
      {:error, "duplicate sourceDescription names found"}
    else
      :ok
    end
  end

  def no_cyclic_workflows_dependencies(%{workflows: workflows}) do
    dependencies = for wf <- workflows, into: %{}, do: {wf.workflowId, wf.dependsOn}
    if Graph.cyclic?(dependencies), do: {:error, "'dependsOn' contains cycles"}, else: :ok
  end

  @doc """
  Returns the path at "document.components.inputs"
  """
  def component_inputs(%__MODULE__{components: %Components{inputs: inputs}} = _document) do
    inputs
  end

  def component_inputs(%__MODULE__{components: nil}), do: %{}

  @doc """
  Returns the workflow by id
  """
  def workflow(%__MODULE__{workflows: workflows}, workflow_id) do
    Enum.find(workflows, &(&1.workflowId == workflow_id))
  end

  @doc """
  Returns the source description by name
  """
  def source_description(%__MODULE__{sourceDescriptions: source_descriptions}, name) do
    Enum.find(source_descriptions, &(&1.name == name))
  end

  defp workflow_ids(%__MODULE__{workflows: workflows}), do: Enum.map(workflows, & &1.workflowId)

  def source_description_names(%__MODULE__{sourceDescriptions: source_descriptions}) do
    Enum.map(source_descriptions, & &1.name)
  end

  @doc """
  Returns the index of the workflow name.
  """
  @spec fetch_workflow_index(t(), String.t()) ::
          {:ok, non_neg_integer()} | {:error, InvalidWorkflowId.t()}
  def fetch_workflow_index(%__MODULE__{workflows: workflows} = document, workflow_id) do
    case Enum.find_index(workflows, &(&1.workflowId == workflow_id)) do
      nil -> {:error, %InvalidWorkflowId{id: workflow_id, valid_ids: workflow_ids(document)}}
      index when is_integer(index) -> {:ok, index}
    end
  end

  @doc """
  Resolves the "$self" key of the document based on the `url` used to retrieve
  the Arazzo document
  """
  @spec resolve_self(map(), String.t()) :: map()
  def resolve_self(document, url) do
    # Possible cases
    # - "$self" missing -> set to the (absolute) URL used to fetch the document
    # - "$self" is present and is an absolute URL -> do nothing
    # - "$self" is present and a relative URL -> merge with the (absolute) URL used
    # to fetch the document
    Map.update(document, "$self", url, fn absolute_or_relative_url ->
      URI.parse(url) |> URI.merge(absolute_or_relative_url) |> to_string()
    end)
  end
end
