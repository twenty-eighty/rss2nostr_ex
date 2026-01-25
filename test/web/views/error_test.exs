defmodule Rss2Nostr.Web.Views.ErrorTest do
  use ExUnit.Case, async: true

  alias Rss2Nostr.Web.Views.Error

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
end
