/**
 * Hourly forecast from Open-Meteo (https://open-meteo.com), a free weather API that needs no key.
 * Only a latitude and longitude are sent, nothing that identifies the person.
 */
const ENDPOINT = "https://api.open-meteo.com/v1/forecast";

export interface HourForecast {
  /** Start of the hour, in milliseconds since the epoch. */
  time: number;
  temperatureC: number;
  /** Chance of precipitation, 0–100. */
  precipProbPct: number;
  /** Expected precipitation during the hour, in mm. */
  precipMm: number;
  /** WMO weather code. */
  code: number;
  gustKmh: number;
}

interface OpenMeteoResponse {
  hourly?: {
    time: string[];
    temperature_2m: (number | null)[];
    precipitation_probability: (number | null)[];
    precipitation: (number | null)[];
    weather_code: (number | null)[];
    wind_gusts_10m: (number | null)[];
  };
}

export async function fetchForecast(
  latitude: number,
  longitude: number,
  signal?: AbortSignal,
): Promise<HourForecast[]> {
  const params = new URLSearchParams({
    latitude: latitude.toFixed(3),
    longitude: longitude.toFixed(3),
    hourly: "temperature_2m,precipitation_probability,precipitation,weather_code,wind_gusts_10m",
    wind_speed_unit: "kmh",
    forecast_days: "2",
    // GMT, so the hourly timestamps below are UTC and need no time zone handling.
    timezone: "GMT",
  });
  const response = await fetch(`${ENDPOINT}?${params}`, { signal });
  if (!response.ok) throw new Error(`Weather service answered ${response.status}`);
  const hourly = ((await response.json()) as OpenMeteoResponse).hourly;
  if (!hourly) throw new Error("Weather service sent no forecast");

  return hourly.time.map((time, i) => ({
    time: Date.parse(`${time}:00Z`),
    temperatureC: hourly.temperature_2m[i] ?? 0,
    precipProbPct: hourly.precipitation_probability[i] ?? 0,
    precipMm: hourly.precipitation[i] ?? 0,
    code: hourly.weather_code[i] ?? 0,
    gustKmh: hourly.wind_gusts_10m[i] ?? 0,
  }));
}
