defmodule SCR.Tools.HTTPRequest do
  @moduledoc """
  HTTP Request tool for making web requests.
  
  Supports GET, POST, PUT, and DELETE methods with custom headers
  and JSON body support.
  """

  @behaviour SCR.Tools.Behaviour

  @impl true
  def name, do: "http_request"

  @impl true
  def description do
    "Makes HTTP requests to external URLs. Use this to fetch data from APIs or web pages. Supports GET, POST, PUT, and DELETE methods."
  end

  @impl true
  def parameters_schema do
    %{
      type: "object",
      properties: %{
        url: %{
          type: "string",
          description: "The URL to make the request to"
        },
        method: %{
          type: "string",
          enum: ["GET", "POST", "PUT", "DELETE"],
          description: "HTTP method to use"
        },
        headers: %{
          type: "object",
          description: "Optional HTTP headers as key-value pairs"
        },
        body: %{
          type: "string",
          description: "Request body (for POST/PUT)"
        }
      },
      required: ["url", "method"]
    }
  end

  @impl true
  def execute(%{"url" => url, "method" => method} = params) do
    headers = Map.get(params, "headers", %{})
    body = Map.get(params, "body")
    
    # Convert headers map to keyword list for HTTPoison
    header_list = Enum.map(headers, fn {k, v} -> {k, v} end)
    
    result = case method do
      "GET" -> 
        HTTPoison.get(url, header_list, timeout: 30_000)
      "POST" -> 
        HTTPoison.post(url, body || "", header_list, timeout: 30_000)
      "PUT" -> 
        HTTPoison.put(url, body || "", header_list, timeout: 30_000)
      "DELETE" -> 
        HTTPoison.delete(url, header_list, timeout: 30_000)
      _ ->
        {:error, "Unsupported method: #{method}"}
    end
    
    case result do
      {:ok, %HTTPoison.Response{status_code: status, body: body, headers: headers}} ->
        # Try to parse JSON response
        parsed_body = case Jason.decode(body) do
          {:ok, json} -> json
          {:error, _} -> body
        end
        
        {:ok, %{
          status: status,
          body: parsed_body,
          headers: Map.new(headers)
        }}
      
      {:error, %HTTPoison.Error{reason: reason}} ->
        {:error, "HTTP request failed: #{inspect(reason)}"}
    end
  end

  @impl true
  def execute(params) do
    {:error, "Invalid parameters: #{inspect(params)}"}
  end

  @impl true
  def to_openai_format do
    SCR.Tools.Behaviour.build_function_format(
      name(),
      description(),
      parameters_schema()
    )
  end

  @impl true
  def on_register, do: :ok

  @impl true
  def on_unregister, do: :ok
end
