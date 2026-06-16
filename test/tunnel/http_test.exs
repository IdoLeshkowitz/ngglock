defmodule Tunnel.HttpTest do
  use ExUnit.Case, async: true

  test "extracts subdomain from Host header" do
    head = "GET / HTTP/1.1\r\nHost: foo.localtest.me\r\nConnection: close\r\n\r\n"
    assert Tunnel.Http.subdomain(head) == {:ok, "foo"}
  end

  test "strips port from Host" do
    head = "GET / HTTP/1.1\r\nHost: bar.localtest.me:8080\r\n\r\n"
    assert Tunnel.Http.subdomain(head) == {:ok, "bar"}
  end

  test "case-insensitive Host header" do
    head = "GET / HTTP/1.1\r\nHOST: baz.localtest.me\r\n\r\n"
    assert Tunnel.Http.subdomain(head) == {:ok, "baz"}
  end

  test "returns :error when no Host header" do
    head = "GET / HTTP/1.1\r\nConnection: close\r\n\r\n"
    assert Tunnel.Http.subdomain(head) == :error
  end

  test "single-label host" do
    head = "GET / HTTP/1.1\r\nHost: localhost\r\n\r\n"
    assert Tunnel.Http.subdomain(head) == {:ok, "localhost"}
  end
end
