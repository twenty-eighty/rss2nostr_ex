defmodule Rss2NostrWeb.ErrorHTMLTest do
  use ExUnit.Case, async: true

  alias Rss2Nostr.Web.Views.Error
  alias Rss2NostrWeb.ErrorHTML

  describe "not_found/0" do
    test "returns HTML with 404 message" do
      html = Error.not_found()

      assert html =~ "404"
      assert html =~ "Not Found"
      assert html =~ "Go to Dashboard"
      assert html =~ "<html"
    end
  end

  describe "bad_request/1" do
    test "returns HTML with 400 message" do
      html = Error.bad_request()

      assert html =~ "400"
      assert html =~ "Bad Request"
      assert html =~ "Go to Dashboard"
      assert html =~ "<html"
    end

    test "includes custom message when provided" do
      html = Error.bad_request("Invalid parameter format")

      assert html =~ "400"
      assert html =~ "Bad Request"
      assert html =~ "Invalid parameter format"
    end
  end

  describe "server_error/1" do
    test "returns HTML with 500 message" do
      html = Error.server_error()

      assert html =~ "500"
      assert html =~ "Server Error"
      assert html =~ "Something went wrong"
      assert html =~ "<html"
    end

    test "includes custom message when provided" do
      html = Error.server_error("Database connection failed")

      assert html =~ "500"
      assert html =~ "Database connection failed"
    end
  end

  describe "ErrorHTML" do
    test "renders 404" do
      html = ErrorHTML.render("404.html", %{})

      assert html =~ "404"
      assert html =~ "Page Not Found"
      assert html =~ "Go to Dashboard"
    end

    test "renders 400" do
      html = ErrorHTML.render("400.html", %{})

      assert html =~ "400"
      assert html =~ "Bad Request"
    end

    test "renders 500" do
      html = ErrorHTML.render("500.html", %{})

      assert html =~ "500"
      assert html =~ "Server Error"
    end
  end
end
