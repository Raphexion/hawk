defmodule Hawk.Reader.Coordinates do
  @moduledoc """
  Validation and PostGIS query compilation for declared coordinate filters.

  Coordinate filters target `geography(Point, 4326)` columns and compile a
  `{:near, params}` filter to `ST_DWithin/3`. The indexed column is passed to
  PostGIS unchanged; the query coordinate is built as WGS84 geography and the
  radius is expressed in meters.
  """

  import Ecto.Query

  @parameter_keys [:lat, :lng, :radius_meters]

  @type options :: %{required(:max_radius_meters) => number()}

  @doc false
  def filter_dynamic(field, {:near, params}, %{max_radius_meters: max_radius_meters})
      when is_atom(field) and is_map(params) do
    %{lat: lat, lng: lng, radius_meters: radius_meters} = normalize_params!(params)

    lat = number!(lat, :lat)
    lng = number!(lng, :lng)
    radius_meters = number!(radius_meters, :radius_meters)

    validate_range!(lat, :lat, -90, 90)
    validate_range!(lng, :lng, -180, 180)
    validate_radius!(radius_meters, max_radius_meters)

    dynamic(
      [row],
      fragment(
        "ST_DWithin(?, ST_SetSRID(ST_MakePoint(?, ?), 4326)::geography, ?)",
        field(row, ^field),
        ^lng,
        ^lat,
        ^radius_meters
      )
    )
  end

  def filter_dynamic(field, {operator, _value}, _opts) when is_atom(operator) do
    raise ArgumentError,
          "filter operator #{inspect(operator)} is not supported for coordinate field #{inspect(field)}"
  end

  defp normalize_params!(params) do
    normalized =
      Enum.reduce(params, %{}, fn {key, value}, acc ->
        key = parameter_key!(key)

        if Map.has_key?(acc, key) do
          raise ArgumentError, "duplicate near parameter #{inspect(key)}"
        end

        Map.put(acc, key, value)
      end)

    missing = Enum.reject(@parameter_keys, &Map.has_key?(normalized, &1))

    if missing == [] do
      normalized
    else
      raise ArgumentError, "coordinate near filter requires lat, lng, and radius_meters"
    end
  end

  defp parameter_key!(key) when key in @parameter_keys, do: key

  defp parameter_key!(key) when is_binary(key) do
    case Enum.find(@parameter_keys, &(Atom.to_string(&1) == key)) do
      nil -> raise ArgumentError, "unknown near parameter #{inspect(key)}"
      known -> known
    end
  end

  defp parameter_key!(key), do: raise(ArgumentError, "unknown near parameter #{inspect(key)}")

  defp number!(value, _name) when is_integer(value), do: value
  defp number!(value, _name) when is_float(value), do: value

  defp number!(value, name) when is_binary(value) do
    case Float.parse(value) do
      {number, ""} -> number
      _invalid -> raise ArgumentError, "coordinate near #{name} must be a number"
    end
  end

  defp number!(_value, name), do: raise(ArgumentError, "coordinate near #{name} must be a number")

  defp validate_range!(value, _name, minimum, maximum) when value >= minimum and value <= maximum,
    do: :ok

  defp validate_range!(_value, name, minimum, maximum) do
    raise ArgumentError, "coordinate near #{name} must be between #{minimum} and #{maximum}"
  end

  defp validate_radius!(radius_meters, _maximum) when radius_meters <= 0 do
    raise ArgumentError, "coordinate near radius_meters must be greater than 0"
  end

  defp validate_radius!(radius_meters, maximum) when radius_meters > maximum do
    raise ArgumentError,
          "coordinate near radius_meters must not exceed #{format_number(maximum)}"
  end

  defp validate_radius!(_radius_meters, _maximum), do: :ok

  defp format_number(number) when is_integer(number), do: Integer.to_string(number)
  defp format_number(number), do: to_string(number)
end
