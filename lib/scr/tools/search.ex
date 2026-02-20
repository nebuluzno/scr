defmodule SCR.Tools.Search do
  @moduledoc """
  Search tool for querying information from the web.

  Uses DuckDuckGo Instant Answer API to provide quick answers
  and web search capabilities.
  """

  @behaviour SCR.Tools.Behaviour

  @impl true
  def name, do: "search"

  @impl true
  def description do
    "Searches the web for information. Use this when you need to find current information, facts, or answers to questions."
  end

  @impl true
  def parameters_schema do
    %{
      type: "object",
      properties: %{
        query: %{
          type: "string",
          description: "The search query"
        }
      },
      required: ["query"]
    }
  end

  @impl true
  def execute(%{"query" => query}) do
    # Use DuckDuckGo HTML for search results
    url = "https://html.duckduckgo.com/html/?q=" <> URI.encode(query)

    case HTTPoison.get(url, [{"User-Agent", "SCR Bot/1.0"}], timeout: 30_000) do
      {:ok, %HTTPoison.Response{status_code: 200, body: body}} ->
        # Parse the HTML to extract search results
        results = parse_search_results(body)

        {:ok,
         %{
           query: query,
           results: results
         }}

      {:error, %HTTPoison.Error{reason: reason}} ->
        {:error, "Search failed: #{inspect(reason)}"}
    end
  end

  @impl true
  def execute(params) do
    {:error, "Invalid parameters: #{inspect(params)}"}
  end

  # Simple HTML parsing for DuckDuckGo results
  defp parse_search_results(html) do
    # Extract result links and snippets using regex
    # This is a simplified parser - a full implementation would use an HTML parser
    results =
      Regex.scan(~r/<a rel="nofollow" class="result__a" href="([^"]+)"[^>]*>([^<]+)<\/a>/, html)
      |> Enum.take(5)
      |> Enum.map(fn [_match, url, title] ->
        # Decode URL
        decoded_url =
          url
          |> URI.decode()
          # Remove DuckDuckGo redirect
          |> String.replace(~r/^.*\?q=/, "")
          |> String.replace(~r/&.*$/, "")

        %{
          title: String.trim(title),
          url: decoded_url
        }
      end)

    if results == [] do
      # Try alternative pattern
      Regex.scan(~r/class="result__title"[^>]*>.*?href="([^"]+)"[^>]*>([^<]+)</, html)
      |> Enum.take(5)
      |> Enum.map(fn [_match, url, title] ->
        %{
          title: String.trim(title),
          url: URI.decode(url)
        }
      end)
    else
      results
    end
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
