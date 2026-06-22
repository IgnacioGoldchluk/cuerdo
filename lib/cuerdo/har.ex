defmodule Cuerdo.HAR do
  @moduledoc """
  Converts request and responses to (almost) HAR
  """

  alias Cuerdo.Arazzo.Context.APICalls

  @version Mix.Project.config() |> Keyword.fetch!(:version)

  def to_har(api_calls) when is_list(api_calls) do
    %{
      "creator" => %{"name" => "Cuerdo", "version" => @version},
      "entries" => Enum.map(api_calls, &to_har/1)
    }
  end

  def to_har(%APICalls{request: request, response: response, path: path} = _api_call) do
    %{
      "startedDateTime" => datetime(response),
      "time" => 0,
      "comment" => path_to_comment(path),
      "request" => to_har(request),
      "response" => to_har(response)
    }
  end

  def to_har(%Req.Request{} = request) do
    %{
      "method" => request.method |> to_string() |> String.upcase(),
      "url" => url_minus_fragment(request.url),
      # Hardcodeed for now
      "httpVersion" => "HTTP/1.1",
      "cookies" => [],
      "headers" => headers(request),
      "queryString" => querystring(request.url),
      "headersSize" => -1,
      "bodySize" => -1,
      "postData" => post_data(request)
    }
  end

  def to_har(%Req.Response{} = response) do
    %{
      "status" => response.status,
      "statusText" => Plug.Conn.Status.reason_phrase(response.status),
      "cookies" => [],
      "headers" => headers(response),
      "content" => content(response)
    }
  end

  defp path_to_comment(path) when is_list(path), do: Enum.join(path, ".")

  defp datetime(%Req.Response{} = request) do
    case Req.Response.get_header(request, "date") do
      [date | _] ->
        date
        |> to_charlist()
        |> :httpd_util.convert_request_date()
        |> NaiveDateTime.from_erl!()
        |> DateTime.from_naive!("Etc/UTC")
        |> to_string()

      _ ->
        DateTime.utc_now() |> to_string()
    end
  end

  defp url_minus_fragment(%URI{} = uri), do: uri |> Map.put(:fragment, nil) |> to_string()
  defp querystring(%URI{query: nil}), do: []

  defp querystring(%URI{query: query}) when is_binary(query) do
    for {name, value} <- URI.decode_query(query), do: %{"name" => name, "value" => value}
  end

  defp headers(req_resp) do
    for {header, values} <- Req.get_headers_list(req_resp) do
      %{"name" => header, "value" => values}
    end
  end

  defp post_data(%Req.Request{} = request) do
    %{"mimeType" => content_type(request), "params" => [], "text" => body(request)}
  end

  defp body(request_response) do
    case request_response.body do
      nil -> ""
      body when is_binary(body) -> body
      body -> JSON.encode!(body)
    end
  end

  defp content_type(%Req.Request{} = request) do
    case Req.Request.get_header(request, "content-type") do
      [] -> "text/plain"
      others -> Enum.join(others, "; ")
    end
  end

  defp content_type(%Req.Response{} = response) do
    case Req.Response.get_header(response, "content-type") do
      [] -> "text/plain"
      others -> Enum.join(others, "; ")
    end
  end

  defp content(response) do
    %{
      "size" => -1,
      "compression" => -1,
      "mimeType" => content_type(response),
      "text" => body(response)
    }
  end
end
