defmodule Rss2Nostr.Web.Views.Sources do
  @moduledoc """
  Views for source management.
  """

  alias Rss2Nostr.Web.Views.Sources.{Language, New, Show}

  def new(opts \\ []), do: New.new(opts)
  def compose(source, opts \\ []), do: Show.compose(source, opts)
  def show(source, opts \\ []), do: Show.show(source, opts)
  def language_select(selected), do: Language.language_select(selected)
end
