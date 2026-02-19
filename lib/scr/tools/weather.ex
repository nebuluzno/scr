defmodule SCR.Tools.Weather do
  @moduledoc """
  Weather tool for getting weather information.
  
  Uses Open-Meteo API (free, no API key required) to get weather data.
  """

  @behaviour SCR.Tools.Behaviour

  @impl true
  def name, do: "weather"

  @impl true
  def description do
    "Get current weather information for a location. Returns temperature, humidity, wind speed, and conditions."
  end

  @impl true
  def parameters_schema do
    %{
      type: "object",
      properties: %{
        location: %{
          type: "string",
          description: "City name or location (e.g., 'Stockholm', 'New York')"
        },
        unit: %{
          type: "string",
          enum: ["celsius", "fahrenheit"],
          description: "Temperature unit"
        }
      },
      required: ["location"]
    }
  end

  @impl true
  def execute(%{"location" => location} = params) do
    unit = Map.get(params, "unit", "celsius")
    
    with {:ok, coords} <- geocode(location),
         {:ok, weather} <- fetch_weather(coords, unit) do
      {:ok, weather}
    end
  end

  def execute(_params) do
    {:error, "Location is required"}
  end

  # Geocode location using Open-Meteo
  defp geocode(location) do
    url = "https://geocoding-api.open-meteo.com/v1/search?name=#{URI.encode_www_form(location)}&count=1"
    
    case HTTPoison.get(url, [], recv_timeout: 10_000) do
      {:ok, %{status_code: 200, body: body}} ->
        case Jason.decode(body) do
          {:ok, %{"results" => [first | _]}} ->
            {:ok, %{
              lat: first["latitude"],
              lon: first["longitude"],
              name: first["name"],
              country: first["country"]
            }}
          {:ok, %{"results" => []}} ->
            {:error, "Location not found: #{location}"}
          {:error, e} ->
            {:error, "Failed to parse geocoding response: #{inspect(e)}"}
        end
      {:error, e} ->
        {:error, "Geocoding request failed: #{inspect(e)}"}
    end
  end

  # Fetch weather from Open-Meteo
  defp fetch_weather(coords, unit) do
    temp_unit = if unit == "fahrenheit", do: "fahrenheit", else: "celsius"
    
    url = "https://api.open-meteo.com/v1/forecast?latitude=#{coords.lat}&longitude=#{coords.lon}&current=temperature_2m,relative_humidity_2m,wind_speed_10m,weather_code&temperature_unit=#{temp_unit}&timezone=auto"
    
    case HTTPoison.get(url, [], recv_timeout: 10_000) do
      {:ok, %{status_code: 200, body: body}} ->
        case Jason.decode(body) do
          {:ok, %{"current" => current}} ->
            {:ok, %{
              location: "#{coords.name}, #{coords.country}",
              temperature: current["temperature_2m"],
              temperature_unit: unit,
              humidity: current["relative_humidity_2m"],
              humidity_unit: "%",
              wind_speed: current["wind_speed_10m"],
              wind_speed_unit: "km/h",
              weather_code: current["weather_code"],
              weather_description: decode_weather_code(current["weather_code"]),
              fetched_at: DateTime.utc_now() |> DateTime.to_iso8601()
            }}
          {:error, e} ->
            {:error, "Failed to parse weather response: #{inspect(e)}"}
        end
      {:error, e} ->
        {:error, "Weather request failed: #{inspect(e)}"}
    end
  end

  # WMO weather code interpretation
  defp decode_weather_code(code) when code in 0..3, do: "Clear to partly cloudy"
  defp decode_weather_code(code) when code in 45..48, do: "Foggy"
  defp decode_weather_code(code) when code in 51..57, do: "Drizzle"
  defp decode_weather_code(code) when code in 61..67, do: "Rain"
  defp decode_weather_code(code) when code in 71..77, do: "Snow"
  defp decode_weather_code(code) when code in 80..82, do: "Rain showers"
  defp decode_weather_code(code) when code in 85..86, do: "Snow showers"
  defp decode_weather_code(code) when code in 95..99, do: "Thunderstorm"
  defp decode_weather_code(_), do: "Unknown"

  @impl true
  def to_openai_format do
    SCR.Tools.Behaviour.build_function_format(name(), description(), parameters_schema())
  end

  @impl true
  def on_register, do: :ok

  @impl true
  def on_unregister, do: :ok
end
