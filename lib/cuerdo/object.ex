defmodule Cuerdo.Object do
  @moduledoc """
  Base Object behaviour
  """

  @doc """
  List of additional validations to perform. Validations are specified as atoms,
  and defined as 1-arity public functions that take the full schema and return
  `:ok | {:error, any()}`.

  For example an Arazzo object for a valid regular expression could be
  ```elixir
  defmodule MyArazzoRegex do
    use Cuerdo.Object, schema: Zoi.string()

    @impl Cuerdo.Object
    def validations do
      [:is_valid_regex]
    end

    def is_valid_regex(input) when is_binary(input) do
      case Regex.compile(input) do
        {:ok, _} -> :ok
        _ -> {:error, "invalid regex pattern"}
      end
    end
  end
  ```
  """
  @callback validations() :: list(atom())
  @callback transformations() :: list(atom())

  defmacro __using__(opts) do
    schema = Keyword.fetch!(opts, :schema)

    caller = __CALLER__.module

    quote bind_quoted: [schema: schema, caller: caller] do
      @behaviour Cuerdo.Object

      @schema Zoi.struct(caller, schema, coerce: true)

      defstruct Zoi.Struct.struct_fields(@schema)

      @spec schema :: Zoi.schema()
      def schema do
        Enum.reduce(__MODULE__.validations(), @schema, fn validation, schema ->
          Zoi.refine(schema, Function.capture(__MODULE__, validation, 1))
        end)
        |> then(fn validated_schema ->
          Enum.reduce(__MODULE__.transformations(), validated_schema, fn transformation, schema ->
            Zoi.transform(schema, Function.capture(__MODULE__, transformation, 1))
          end)
        end)
      end

      def new(attrs), do: Zoi.parse(schema(), attrs)

      def new!(attrs) do
        case new(attrs) do
          {:ok, object} -> object
          {:error, reasons} -> raise "Failed creating #{__MODULE__}: #{inspect(reasons)}"
        end
      end

      def validations, do: []
      def transformations, do: []
      defoverridable validations: 0, transformations: 0
    end
  end
end
