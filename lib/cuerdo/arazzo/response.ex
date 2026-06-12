defmodule Cuerdo.Arazzo.Response do
  @moduledoc """
  Functionality to build and validate responses in Arazzo workflows
  """

  alias Cuerdo.Arazzo.{Context, HTTP}
  alias Cuerdo.Errors.UnexpectedResponse

  alias Cuerdo.OpenAPI

  @doc """
  Validates that a response matches the defined operation responses
  """
  @spec matches(Req.Response.t(), OpenAPI.Operation.t(), Context.t()) ::
          :ok | {:error, Exception.t()}
  def matches(
        %Req.Response{status: status_code, body: body} = response,
        %OpenAPI.Operation{source_description_name: source_description_name} = operation,
        %Context{} = ctx
      ) do
    valid_response =
      operation.responses
      |> Map.get(status_code, Map.get(operation.responses, "default"))

    with {:nil?, false} <- {:nil?, is_nil(valid_response)},
         {:content, content} when not is_nil(content) <-
           {:content, Map.fetch!(valid_response, :content)},
         {:header, [content_type]} <- {:header, Req.Response.get_header(response, "content-type")},
         {:matching_response, matching_response} when not is_nil(matching_response) <-
           {:matching_response, HTTP.matching_body(content_type, content)},
         {:ok, source_description, _} =
           Context.fetch_source_description(ctx, source_description_name),
         %{schema: schema} = matching_response,
         :ok <- HTTP.validate_body(body, schema, source_description) do
      :ok
    else
      {:nil?, true} ->
        {:error,
         %UnexpectedResponse{message: "no matching response for status code #{status_code}"}}

      {:content, nil} when body in ["", nil] ->
        :ok

      {:content, nil} ->
        {:error,
         %UnexpectedResponse{message: "No 'content' defined for status code #{status_code}"}}

      {:matching_response, nil} ->
        [content_type] = Req.Response.get_header(response, "content-type")
        {:error, %UnexpectedResponse{message: "no matching content-type for #{content_type}"}}

      {:header, header} ->
        {:error,
         %UnexpectedResponse{message: "unexpected 'content-type' header: #{inspect(header)}"}}

      {:error, exc} when is_exception(exc) ->
        {:error, %UnexpectedResponse{message: Exception.message(exc)}}
    end
  end
end
