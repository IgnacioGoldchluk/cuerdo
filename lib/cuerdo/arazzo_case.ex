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
  alias Cuerdo.ArazzoCase.{Result, Runner}
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
    - `:num_runs` (`t:pos_integer/0`) - The number of cases to run. Defaults to `1`
    - `:halt_on_error` (`t:boolean/0`) - Whether to stop on the first failure. Defaults to `false`
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
      case Runner.workflow_ids(document, evaluated_opts[:only], evaluated_opts[:exclude]) do
        {:ok, ids} -> ids
        {:error, exc} -> raise exc
      end

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

            Runner.run_all(workflow_id, document, opts)
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

  defp opts_schema do
    [
      document: [type: {:custom, Arazzo.Document, :new, []}, required: true],
      prefix: [type: :string, required: false],
      only: [type: {:list, :string}, required: false],
      exclude: [type: {:list, :string}, required: false],
      num_runs: [type: :pos_integer, default: 1],
      halt_on_error: [type: :boolean, default: false],
      transform_inputs: [type: {:map, :string, :mfa}, default: %{}],
      json_schema_resolver: [type: :any, default: DummyResolver]
    ]
  end
end
