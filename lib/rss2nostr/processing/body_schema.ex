defmodule Rss2Nostr.Processing.BodySchema do
  @moduledoc """
  Picks an article-body region without requiring CSS knowledge.

  Known site URL patterns can preselect a schema. Matching page-builder
  markup (WPBakery, Elementor, Divi, …) is always offered. Other pages
  use semantic tags, schema.org, common content classes, and discovered
  wrappers; the tightest substantial region is recommended.
  """

  alias Rss2Nostr.Processing.BodySchema.{Extract, Presets, Regions}

  @type schema :: Presets.schema()
  @type region :: Regions.region()

  @type start_block :: %{
          xpath: String.t(),
          text: String.t(),
          selected: boolean()
        }

  @spec schema_for_url(String.t() | nil) :: schema() | nil
  def schema_for_url(url), do: Presets.schema_for_url(url)

  @spec selector_for_url(String.t() | nil) :: String.t() | nil
  def selector_for_url(url), do: Presets.selector_for_url(url)

  @doc """
  Selector to use when the source has none stored: a known URL schema
  if it matches, otherwise the tightest substantial region in `html`.
  """
  @spec preferred_selector(String.t() | nil, String.t() | nil) :: String.t() | nil
  def preferred_selector(html, url), do: Regions.preferred_selector(html, url)

  @doc """
  True when `selector` is a known site preset (Substack, Corbett, WordPress, …).
  """
  @spec known_selector?(String.t() | nil) :: boolean()
  def known_selector?(selector), do: Presets.known_selector?(selector)

  @spec known_selectors() :: [String.t()]
  def known_selectors, do: Presets.known_selectors()

  @spec matches?(String.t(), String.t()) :: boolean()
  def matches?(html, selector), do: Extract.matches?(html, selector)

  @spec candidates(String.t() | nil, keyword()) :: [region()]
  def candidates(html, opts \\ []), do: Regions.candidates(html, opts)

  @doc """
  HTML for `selector`, keeping only outermost matches that still look
  like article body (drops nested duplicates and tiny sibling chrome).
  """
  @spec extract(String.t() | nil, String.t() | nil) :: String.t() | nil
  def extract(html, selector), do: Extract.extract(html, selector)

  @spec start_blocks(String.t() | nil, keyword()) :: [start_block()]
  def start_blocks(html, opts \\ []), do: Extract.start_blocks(html, opts)

  @spec apply_start_at(String.t() | nil, String.t() | nil) :: String.t() | nil
  def apply_start_at(html, start_at), do: Extract.apply_start_at(html, start_at)
end
