defmodule Beacon.Content.PubSubResolverTest do
  use ExUnit.Case, async: true
  alias Beacon.Content.PubSubResolver

  # registry: %{name => %{ast: [nodes], handlers: %{"info"=>[],"event"=>[]}}}
  defp el(tag, children \\ []), do: %{type: :element, tag: tag, attrs: %{}, children: children}

  test "collects handlers of directly-embedded components, deduped" do
    registry = %{
      "vin_ticker" => %{ast: [], handlers: %{"info" => ["andon_vin_tick"], "event" => []}},
      "event_log" => %{ast: [], handlers: %{"info" => ["andon_vin_tick"], "event" => ["ack"]}}
    }
    page_ast = [el("div", [el("vin_ticker"), el("event_log")])]
    assert PubSubResolver.resolve(page_ast, registry) == %{"info" => ["andon_vin_tick"], "event" => ["ack"]}
  end

  test "collects transitively through nested components" do
    registry = %{
      "panel" => %{ast: [%{type: :element, tag: "vin_ticker", attrs: %{}, children: []}], handlers: %{}},
      "vin_ticker" => %{ast: [], handlers: %{"info" => ["andon_vin_tick"], "event" => []}}
    }
    page_ast = [el("panel")]
    assert PubSubResolver.resolve(page_ast, registry) == %{"info" => ["andon_vin_tick"], "event" => []}
  end

  test "walks into conditional/loop/fragment branches" do
    registry = %{"vin_ticker" => %{ast: [], handlers: %{"info" => ["t"], "event" => []}}}
    page_ast = [%{type: :conditional, test: %{}, then: [el("vin_ticker")], else: []}]
    assert PubSubResolver.resolve(page_ast, registry) == %{"info" => ["t"], "event" => []}
  end

  test "empty when no components referenced" do
    assert PubSubResolver.resolve([%{type: :element, tag: "div", attrs: %{}, children: []}], %{}) ==
             %{"info" => [], "event" => []}
  end

  test "tolerates circular references without infinite loop" do
    registry = %{
      "comp_a" => %{ast: [%{type: :element, tag: "comp_b", attrs: %{}, children: []}], handlers: %{"info" => ["x"], "event" => []}},
      "comp_b" => %{ast: [%{type: :element, tag: "comp_a", attrs: %{}, children: []}], handlers: %{"info" => ["y"], "event" => []}}
    }
    assert PubSubResolver.resolve([%{type: :element, tag: "comp_a", attrs: %{}, children: []}], registry) ==
             %{"info" => ["x", "y"], "event" => []}
  end
end
