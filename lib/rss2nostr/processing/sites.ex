defmodule Rss2Nostr.Processing.Sites do
  @moduledoc """
  Site-specific HTML rewrites applied before generic Markdown conversion.

  Adapters run only when the article URL or body selector matches that
  site, so Word footnotes, WATCH ON rows, or embed cards on one
  publisher do not change conversion for others.
  """

  alias Rss2Nostr.Processing.Sites.{Corbett, Substack}

  @adapters [Corbett, Substack]

  @spec preprocess(String.t() | nil, keyword() | map()) :: String.t() | nil
  def preprocess(html, opts \\ [])
  def preprocess(html, _opts) when html in [nil, ""], do: html

  def preprocess(html, opts) when is_binary(html) do
    opts = Map.new(opts)

    Enum.reduce(@adapters, html, fn adapter, acc ->
      if adapter.applies?(opts), do: adapter.preprocess(acc), else: acc
    end)
  end
end
