defmodule Cuerdo.ArazzoCase do
  @moduledoc """
  Automated test runner case for Arazzo documents


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
  options respectively. Some examples

  ```elixir
  # Executes "workflow1" and "workflow2"
  arazzo_document_test only: ["workflow1", "workflow2"], document: ...

  # Executes every workflow defined in the document except for "workflow1"
  arazzo_document_test exclude: ["workflow1"], document: ...

  # Executes "workflow1"
  arazzo_document_test only: ["workflow1", "workflow2"], exclude: ["workflow2"], document: ...
  ```

  ## Fine-tuning input
  Consider for example a "book" input containing the book's title, author and ISBN
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
  ISBNs consist of 13 digits, where the last digit is a check digit. In order for an ISBN
  to be valid, the total weighted sum must be a multiple of 10. If the service under test
  checks that the ISBN is valid then tests will fail because JSON Schema cannot express
  this constraint and invalid ISBNs will be generated.

  We can work around this issue via the `:transform_inputs` option.

  First, let's define a function that generates valid ISBN identifiers
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

  Then we will define a function that receives a book input and inserts the valid ISBN
  ```elixir
  def with_valid_isbn(book) do
    StreamData.bind(valid_isbn(), fn isbn ->
      StreamData.constant(Map.put(book, "isbn", isbn))
    end)
  end
  ```
  Finally, in the `arazzo_document_test` definition we have to add `:transform_inputs` option
  with the name of the workflow and the function as `{Module, :function_name, [args]}`.
  The generated value will be passed through the function we defineds, ensuring that we test
  the workflow with valid data.
  ```elixir
  defmodule MyModuleTest do
    use Cuerdo.ArazzoCase

    arazzo_document_test transform_inputs: %{
      "createBookWorkflow" => {MyModule, :with_valid_isbn, []}
    },
    document: ...
  end
  ```

  ## Multiple arazzo_document_test
  You can define multipel `arazzo_document_test` in the same module. This is useful if, for example,
  you have an expensive workflow that you want to run fewer times, or if you want to run workflows
  both with default generated inputs and custom inputs
  ```elixir
  defmodule MyArazzoTest do
    use Cuerdo.ArazzoCase

    arazzo_document_test max_runs: 20,
                         exclude: ["expensiveWorkflowId"],
                         document: YamlElixir.read_from_file!("path/to/arazzo.yaml")

    arazzo_document_test max_runs: 3,
                         only: ["expensiveWorkflowId"],
                         document: YamlElixir.read_from_file!("path/to/arazzo.yaml")
  end
  ```

  Keep in mind that the test names are generated based on each workflow's `workflowId` field. If you
  run the same workflows with different inputs you must use the `:prefix` option, otherwise the test
  generation step will fail
  ```elixir
  defmodule MyArazzoTest do
    use Cuerdo.ArazzoCase

    arazzo_document_test prefix: "custom_inputs",
                         transform_inputs: %{"workflowId" => {Module, :function, []}},
                         document: YamlElixir.read_from_file!("path/to/arazzo.yaml")

    arazzo_document_test prefix: "default_inputs,
                         document: YamlElixir.read_from_file!("path/to/arazzo.yaml")
  end
  ```
  """
  use ExUnit.CaseTemplate

  alias Cuerdo.Arazzo
  alias Cuerdo.Arazzo.Context
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

    - `:document` (`t:map/0`) - Arazzo document containing the workflows to test
    - `:only` (`list(String.t())`) - List of `workflowId` to execute from the document. If
    provided, workflows that are not in the `:only` option are not tested.
    - `:exclude` (`list(String.t())`) - List of `workflowId` to exclude from the document.
    If both `:only` and `:exclude` are passed then the workflows from `:only` that are not in
    `:excluded` are executed.
    - `:max_runs` (`t:pos_integer/0`) - The maximum number of cases to run. Defaults to `1`.
    - `:json_schema_resolver` - The resolver to use for fetching JSON Schemas. Defaults to
    a do-nothing resolver. Use this option if any OpenAPI document in your workflow references
    remote schemas. Refer to [JSV Resolvers](`e:jsv:resolvers.html`) section for more information.
    - `:transform_inputs` - A map of `%{workflowId => transformation}`, where `transformation` is
    a function that generates `t:StreamData.t/1` based on the initially generated value, specified
    as `{Module, :function_name}`, where `:function_name` is a 1-arity function.
    `:input_transforms` is also accepted as an alias.
    - `:prefix` - (`t:String.t/0`) - The test name prefix.
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
            inputs_schema = unquote(Macro.escape(workflow.inputs))
            document = unquote(Macro.escape(document))
            opts = unquote(Macro.escape(evaluated_opts))

            generator =
              case Arazzo.build_schema(inputs_schema, Context.from_document!(document)) do
                {:ok, schema} ->
                  RockSolid.from_schema(schema, resolver: opts[:json_schema_resolver])

                {:error, exc} ->
                  raise exc
              end

            generator =
              case Map.get(opts[:transform_inputs], workflow_id) do
                nil ->
                  generator

                {mod, f_name, args} ->
                  StreamData.bind(generator, fn input -> apply(mod, f_name, [input] ++ args) end)
              end

            generator
            |> Enum.take(opts[:max_runs])
            |> Enum.reduce(Context.from_document!(document), fn workflow_inputs, ctx ->
              case Arazzo.run_workflow(workflow_inputs, workflow_id, ctx) do
                {:ok, updated_ctx} ->
                  Context.merge_cache(ctx, updated_ctx)

                {:error, exc} ->
                  raise "For input #{inspect(workflow_inputs)}: #{Exception.message(exc)}"
              end
            end)
          end
        end
      end

    case tests do
      [] -> quote(do: :ok)
      tests -> {:__block__, [], tests}
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
