defmodule Cuerdo.ArazzoCase do
  @moduledoc """
  Provides an `ExUnit.CaseTemplate` for automatically generating tests from Arazzo workflows.

  Each workflow in the document is executed as a test, with automatically generated inputs derived
  from the workfow's input schema.

  ## Basic Usage
  Define `use Cuerdo.ArazzoCase` in your test module, and add `arazzo_document_test` macro
  referencing the document you want to test
  ```elixir
  defmodule MyArazzoTest do
    use Cuerdo.ArazzoCase

    arazzo_document_test document: YamlElixir.read_from_file!("spec/to/arazzo.yaml")
  end
  ```

  ## Filtering workflows
  You can opt-in and opt-out from executing specific workflows via the `:only` and `:exclude`
  options respectively. For example:

  ```elixir
  # Executes "workflow1" and "workflow2"
  arazzo_document_test only: ["workflow1", "workflow2"], document: ...

  # Executes every workflow defined in the document except for "workflow1"
  arazzo_document_test exclude: ["workflow1"], document: ...

  # Executes "workflow1"
  arazzo_document_test only: ["workflow1", "workflow2"], exclude: ["workflow2"], document: ...
  ```

  ## Customizing Generated Inputs
  Consider for example a "book" input containing the book's title, author and ISBN:
  ```json
    {
      "type": "object",
      "additionalProperties": false,
      "properties": {
        "title": {"type": "string", "minLength": 1},
        "authorName": {"type": "string", "minLength": 1},
        "isbn": {"type": "string", "pattern": "^97(8|9)[0-9]{10}$"}
      }
    }
  ```
  Valid ISBNs cannot be generated from JSON schemas. Values might match the regular expression
  while failing the checksum validation. We can work around this issue via
  the `:transform_inputs` option.

  Define a function that generates valid ISBN identifiers:
  ```elixir
  defmodule MyModule do
    def valid_isbn do
      StreamData.bind(MoreStreamData.from_regex("^97(8|9)[0-9]{10}$"), fn invalid_isbn ->
        {digits, _wrong_check_digit} = String.split_at(invalid_isbn, 12)
        StreamData.constant(digits <> to_string(check_digit(digits)))
      end)
    end

    defp check_digit(digits) do
      digits
      |> String.codepoints()
      |> Enum.with_index()
      |> Enum.sum_by(fn {digit, idx} ->
        digit = String.to_integer(digit)
        if(rem(idx, 2) == 0, do: digit, else: 3 * digit)
      end)
      |> then(fn total -> 10 - rem(total, 10) end)
    end
  ```

  Define a transformation function that replaces the generated ISBN with a valid one. Notice
  that the fuction **must** return a `t:StreamData.t/1` generator:
  ```elixir
  def with_valid_isbn(book) do
    StreamData.bind(valid_isbn(), fn isbn ->
      StreamData.constant(Map.put(book, "isbn", isbn))
    end)
  end
  ```

  Pass the transformaion function through `:transform_inputs` option, as an MFA tuple.
  The function will be called for every input generated for the specified workflow, before
  starting to execut the first workflow step:
  ```elixir
  defmodule MyModuleTest do
    use Cuerdo.ArazzoCase

    arazzo_document_test transform_inputs: %{
      "createBookWorkflow" => {MyModule, :with_valid_isbn, []}
    },
    document: ...
  end
  ```

  ## Running the same document multiple times
  Declaring multiple `arazzo_document_test` allows for different execution strategies for
  the same document, such as:
  - Running expensive/slower workflows fewer times
  - Running workflows with different input transformations

  ```elixir
  defmodule MyArazzoTest do
    use Cuerdo.ArazzoCase

    arazzo_document_test transform_inputs: %{"workflowId" => {Module, :function, []}},
                         document: YamlElixir.read_from_file!("path/to/arazzo.yaml")

    arazzo_document_test document: YamlElixir.read_from_file!("path/to/arazzo.yaml")
  end
  ```

  Keep in mind that the test names are generated based on each workflow's `workflowId` field. If
  the Arazzo documents contains workflows with the same name then you **must** pass the `:prefix`
  option, otherwise the test generation will fail:
  ```elixir
  defmodule MyArazzoTest do
    use Cuerdo.ArazzoCase

    arazzo_document_test prefix: "custom_inputs",
                         transform_inputs: %{"workflowId" => {Module, :function, []}},
                         document: YamlElixir.read_from_file!("path/to/arazzo.yaml")

    arazzo_document_test prefix: "default_inputs",
                         document: YamlElixir.read_from_file!("path/to/arazzo.yaml")
  end
  ```
  """
  use ExUnit.CaseTemplate

  alias Cuerdo.Arazzo
  alias Cuerdo.Arazzo.Context
  alias Cuerdo.ArazzoCase.Result
  alias RockSolid.Resolution.Resolvers.DummyResolver

  using do
    quote do
      require Cuerdo.ArazzoCase
      import Cuerdo.ArazzoCase
    end
  end

  @doc """
  Generates property tests for every workflow in the Arazzo document.

  ## Options

    - `:document` (`t:map/0`) - Arazzo document
    - `:only` (`list(String.t())`) - List of `workflowId` to execute from the document. If
    provided, workflows that are not in the `:only` option are not tested. Defaults to
    executing all workflows in the document
    - `:exclude` (`list(String.t())`) - List of `workflowId` to exclude from the document.
    If both `:only` and `:exclude` are passed then the workflows from `:only` that are not in
    `:excluded` are executed
    - `:max_runs` (`t:pos_integer/0`) - The maximum number of cases to run. Defaults to `1`
    - `:transform_inputs` - A map of `%{workflowId => transformation}`, where `transformation` is
    a function that generates `t:StreamData.t/1` based on the initially generated value, specified
    as `{Module, :function_name}`, where `:function_name` is a 1-arity function
    - `:json_schema_resolver` - The resolver to use for fetching JSON Schemas. Defaults to
    a do-nothing resolver. Use this option if any OpenAPI document in your workflow references
    remote schemas. Refer to [JSV Resolvers](`e:jsv:resolvers.html`) section for more information
    - `:prefix` - (`t:String.t/0`) - The test name prefix
  """
  defmacro arazzo_document_test(opts \\ []) do
    # Fine to call Code.eval_quoted here because it's for tests
    {evaluated_opts, _} = Code.eval_quoted(opts, [], __CALLER__)

    evaluated_opts = NimbleOptions.validate!(evaluated_opts, opts_schema())
    document = Keyword.fetch!(evaluated_opts, :document)

    workflow_ids =
      evaluated_opts
      |> Keyword.get_lazy(:only, fn -> Enum.map(document.workflows, & &1.workflowId) end)
      |> Enum.reject(&(&1 in Keyword.fetch!(evaluated_opts, :exclude)))

    # This part was mostly generated by Codex. Would've taken me forever to do by myself
    tests =
      for workflow <- document.workflows, workflow.workflowId in workflow_ids do
        workflow_id = workflow.workflowId

        test_name =
          case evaluated_opts[:prefix] do
            nil -> "workflow #{workflow_id}"
            prefix when is_binary(prefix) -> "#{prefix} - workflow #{workflow_id}"
          end

        quote do
          test unquote(test_name) do
            workflow_id = unquote(workflow_id)
            document = unquote(Macro.escape(document))
            opts = unquote(Macro.escape(evaluated_opts))

            run_all(workflow_id, document, opts)
            |> Enum.reject(fn %Result{status: status} -> status == :passed end)
            |> case do
              [] ->
                :ok

              failures ->
                msg = Enum.map_join(failures, "\n", &Result.format_message/1)
                raise msg
            end
          end
        end
      end

    case tests do
      [] -> quote(do: :ok)
      tests -> {:__block__, [], tests}
    end
  end

  @doc false
  def run_all(workflow_id, arazzo_document, opts) do
    with {:ok, %Context{} = ctx} <- Context.from_document(arazzo_document),
         %Arazzo.Workflow{} = workflow = Arazzo.Document.workflow(ctx.document, workflow_id),
         {:ok, schema} <- Arazzo.build_schema(workflow.inputs, ctx) do
      generator(schema, workflow_id, opts)
      |> Enum.take(opts[:max_runs])
      |> Enum.reduce({[], ctx}, fn workflow_inputs, {results, ctx} ->
        case run_workflow(workflow_inputs, workflow_id, ctx) do
          {time_ms, {:ok, updated_ctx}} ->
            result = %Result{
              workflow_id: workflow_id,
              inputs: workflow_inputs,
              execution_time_ms: time_ms,
              status: :passed
            }

            {[result | results], Context.merge_cache(ctx, updated_ctx)}

          {time_ms, {:error, exc}} ->
            result = %Result{
              workflow_id: workflow_id,
              inputs: workflow_inputs,
              execution_time_ms: time_ms,
              status: :failed,
              reason: exc
            }

            {[result | results], ctx}
        end
      end)
      |> then(&elem(&1, 0))
    else
      {:error, exc} when is_exception(exc) ->
        [%Result{workflow_id: workflow_id, status: :error, reason: exc}]
    end
  end

  # Runs timed workflow
  defp run_workflow(workflow_inputs, workflow_id, ctx) do
    :timer.tc(fn -> Arazzo.run_workflow(workflow_inputs, workflow_id, ctx) end, :millisecond)
  end

  defp generator(schema, workflow_id, opts) do
    base = RockSolid.from_schema(schema, resolver: opts[:json_schema_resolver])

    case Map.get(opts[:transform_inputs], workflow_id) do
      nil -> base
      {mod, func, args} -> StreamData.bind(base, fn val -> apply(mod, func, [val] ++ args) end)
    end
  end

  defp opts_schema do
    [
      document: [type: {:custom, Arazzo.Document, :new, []}, required: true],
      prefix: [type: :string, required: false],
      only: [type: {:list, :string}, required: false],
      exclude: [type: {:list, :string}, default: []],
      max_runs: [type: :pos_integer, default: 1],
      transform_inputs: [type: {:map, :string, :mfa}, default: %{}],
      json_schema_resolver: [type: :any, default: DummyResolver]
    ]
  end
end
