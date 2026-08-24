defmodule Rss2Nostr.HTTP.SafeURL do
  @moduledoc """
  Blocks SSRF to private, loopback, and link-local targets for outbound HTTP.
  """

  @doc """
  Validates that `url` is http(s) and does not resolve to a blocked address.

  Returns `:ok` or `{:error, reason}`.
  """
  @spec validate(String.t()) :: :ok | {:error, atom()}
  def validate(url) when is_binary(url) do
    if Application.get_env(:rss2nostr, :http_ssrf_protection, true) do
      do_validate(url)
    else
      :ok
    end
  end

  def validate(_), do: {:error, :invalid_url}

  @spec do_validate(String.t()) :: :ok | {:error, atom()}
  defp do_validate(url) do
    case URI.parse(url) do
      %URI{scheme: scheme, host: host} when scheme in ["http", "https"] and is_binary(host) ->
        host = String.trim(host) |> String.trim_leading("[") |> String.trim_trailing("]")

        cond do
          host == "" ->
            {:error, :invalid_url}

          blocked_hostname?(host) ->
            {:error, :blocked_host}

          true ->
            case resolve_ips(host) do
              {:ok, []} ->
                {:error, :nxdomain}

              {:ok, ips} ->
                if Enum.any?(ips, &blocked_ip?/1), do: {:error, :blocked_address}, else: :ok

              {:error, reason} ->
                {:error, reason}
            end
        end

      _ ->
        {:error, :invalid_url}
    end
  end

  @spec blocked_hostname?(String.t()) :: boolean()
  defp blocked_hostname?(host) do
    down = String.downcase(host)

    down in ["localhost", "metadata.google.internal"] or
      String.ends_with?(down, ".localhost") or
      String.ends_with?(down, ".local") or
      String.ends_with?(down, ".internal")
  end

  @spec resolve_ips(String.t()) :: {:ok, list()} | {:error, atom()}
  defp resolve_ips(host) do
    case :inet.parse_address(String.to_charlist(host)) do
      {:ok, ip} ->
        {:ok, [ip]}

      {:error, :einval} ->
        chars = String.to_charlist(host)

        case :inet.getaddrs(chars, :inet) do
          {:ok, v4} ->
            case :inet.getaddrs(chars, :inet6) do
              {:ok, v6} -> {:ok, v4 ++ v6}
              {:error, _} -> {:ok, v4}
            end

          {:error, :nxdomain} ->
            case :inet.getaddrs(chars, :inet6) do
              {:ok, v6} -> {:ok, v6}
              {:error, reason} -> {:error, reason}
            end

          {:error, reason} ->
            {:error, reason}
        end
    end
  end

  @spec blocked_ip?(term()) :: boolean()
  defp blocked_ip?({0, 0, 0, 0}), do: true
  defp blocked_ip?({127, _, _, _}), do: true
  defp blocked_ip?({10, _, _, _}), do: true
  defp blocked_ip?({192, 168, _, _}), do: true
  defp blocked_ip?({169, 254, _, _}), do: true
  defp blocked_ip?({100, b, _, _}) when b >= 64 and b <= 127, do: true

  defp blocked_ip?({172, b, _, _}) when b >= 16 and b <= 31, do: true

  defp blocked_ip?({0, 0, 0, 0, 0, 0, 0, 0}), do: true
  defp blocked_ip?({0, 0, 0, 0, 0, 0, 0, 1}), do: true
  defp blocked_ip?({0, 0, 0, 0, 0, 65535, a, b}) do
    blocked_ip?({div(a, 256), rem(a, 256), div(b, 256), rem(b, 256)})
  end

  defp blocked_ip?({a, _, _, _, _, _, _, _}) when a >= 0xFC00 and a <= 0xFDFF, do: true
  defp blocked_ip?({0xFE80, _, _, _, _, _, _, _}), do: true
  defp blocked_ip?(_), do: false
end
