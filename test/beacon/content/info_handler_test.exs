defmodule Beacon.Content.InfoHandlerTest do
  use Beacon.DataCase, async: true
  alias Beacon.Content.InfoHandler

  test "changeset casts :name" do
    cs = InfoHandler.changeset(%InfoHandler{}, %{site: :my_site, msg: "{:tick, x}", code: "{:noreply, socket}", name: "tick_handler"})
    assert cs.valid?
    assert Ecto.Changeset.get_field(cs, :name) == "tick_handler"
  end

  test "name is optional (backward compatible)" do
    cs = InfoHandler.changeset(%InfoHandler{}, %{site: :my_site, msg: "{:tick, x}", code: "{:noreply, socket}"})
    assert cs.valid?
  end
end
