defmodule Rss2Nostr.Nostr.NIP05 do
  @moduledoc """
  NIP-05 identifier lookup (`name@domain` → `/.well-known/nostr.json`).
  """

  alias Rss2Nostr.HTTP

  @type document :: map()

  @spec parse_identifier(String.t()) :: {:ok, String.t(), String.t()} | :error
  def parse_identifier(identifier) when is_binary(identifier) do
    case String.split(String.trim(identifier), "@") do
      [name, domain] ->
        name = String.downcase(String.trim(name))
        domain = String.downcase(String.trim(domain))

        if name != "" and valid_domain?(domain) do
          {:ok, name, domain}
        else
          :error
        end

      _ ->
        :error
    end
  end

  def parse_identifier(_), do: :error

  @spec well_known_url(String.t(), String.t()) :: String.t()
  def well_known_url(name, domain) do
    "https://#{domain}/.well-known/nostr.json?name=#{URI.encode_www_form(name)}"
  end

  @spec fetch(String.t()) :: {:ok, document()} | {:error, term()}
  def fetch(identifier) do
    with {:ok, name, domain} <- parse_identifier(identifier),
         {:ok, %{status: 200, body: body}} <-
           HTTP.get(well_known_url(name, domain), receive_timeout: 10_000, retry: false),
         {:ok, json} when is_map(json) <- decode_body(body) do
      {:ok, json}
    else
      :error -> {:error, :invalid_identifier}
      {:ok, %{status: status}} -> {:error, {:http_error, status}}
      {:error, reason} -> {:error, reason}
      _ -> {:error, :invalid_response}
    end
  end

  @doc """
  Relays listed for `pubkey` when `names` maps the identifier to that key.
  """
  @spec relays_for(document(), String.t(), String.t()) :: [String.t()]
  def relays_for(document, name, pubkey)
      when is_map(document) and is_binary(name) and is_binary(pubkey) do
    hex = String.downcase(pubkey)

    if name_matches?(document, name, hex) do
      document
      |> relays_map()
      |> Map.get(hex, [])
      |> List.wrap()
      |> Enum.flat_map(&normalize_relay/1)
      |> Enum.uniq()
    else
      []
    end
  end

  def relays_for(_, _, _), do: []

  @spec name_matches?(document(), String.t(), String.t()) :: boolean()
  defp name_matches?(document, name, hex) do
    names = stringify_map(document["names"] || document[:names] || %{})
    listed = names[String.downcase(name)]
    is_binary(listed) and String.downcase(listed) == hex
  end

  @spec relays_map(document()) :: map()
  defp relays_map(document) do
    (document["relays"] || document[:relays] || %{})
    |> stringify_map()
    |> Map.new(fn {key, value} -> {String.downcase(key), value} end)
  end

  @spec stringify_map(map()) :: map()
  defp stringify_map(map) when is_map(map) do
    Map.new(map, fn {key, value} -> {to_string(key), value} end)
  end

  defp stringify_map(_), do: %{}

  @spec normalize_relay(term()) :: [String.t()]
  defp normalize_relay(url) when is_binary(url) do
    trimmed = String.trim(url)

    if String.starts_with?(trimmed, "wss://") or String.starts_with?(trimmed, "ws://") do
      [trimmed]
    else
      []
    end
  end

  defp normalize_relay(_), do: []

  @spec valid_domain?(String.t()) :: boolean()
  defp valid_domain?(domain) do
    String.contains?(domain, ".") and not String.contains?(domain, "/")
  end

  @spec decode_body(binary() | iodata()) :: {:ok, term()} | {:error, term()}
  defp decode_body(body) when is_binary(body), do: Jason.decode(body)
  defp decode_body(body), do: body |> IO.iodata_to_binary() |> Jason.decode()
end
