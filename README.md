# LiveAttribute

LiveAttribute makes binding updateable values easier. To use it add it to your LiveView using `use LiveAttribute`
and then use the function `assign_attribute(socket, subscribe_callback, property_callbacks)` to register attributes.

The attributes will listen to all incoming events and update their assigns of your LiveView automatically, saving
you the hassle of implementing independent `handle_info()` and `update_...()` calls.

## Example using LiveAttribute

```
defmodule UserLive do
  use Phoenix.LiveView
  use LiveAttribute

  def mount(_params, _session, socket) do
    {:ok, assign_attribute(socket, &Accounts.subscribe/0, users: &Accounts.list_users/0)}
  end

  def handle_event("delete_user", %{"id" => user_id}, socket) do
    Accounts.get_user!(user_id)
    |> Accounts.delete_user()

    {:noreply, socket}
  end
end
```


## Same Example without LiveAttribute

```
defmodule UserLive do
  use Phoenix.LiveView

  def mount(_params, _session, socket) do
    if connected?(socket), do: Accounts.subscribe()
    {:ok, update_users(socket)}
  end

  defp update_users(socket) do
    users = Accounts.list_users()
    assign(socket, users: users)
  end

  def handle_event("delete_user", %{"id" => user_id}, socket) do
    Accounts.get_user!(user_id)
    |> Accounts.delete_user()

    {:noreply, socket}
  end

  def handle_info({Accounts, [:user, _], _}, socket) do
    {:noreply, update_users(socket)}
  end
end
```

## Installation

If [available in Hex](https://hex.pm/docs/publish), the package can be installed
by adding `live_attribute` to your list of dependencies in `mix.exs`:

```elixir
def deps do
  [
    {:live_attribute, "~> 1.0.0"}
  ]
end
```

