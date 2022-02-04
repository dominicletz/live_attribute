defmodule LiveAttribute do
  use GenServer
  require Logger
  defstruct [:refresher, :subscribe, :target, :filter, :keys]

  @moduledoc """
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

    # assign_attribute(socket, subscribe, filter \\ :_, refresher)

    * `socket` the LiveView socket where the assigns should be executed on
    * `subscribe` the subscribe callback to start the subscription e.g. `&Users.subscribe/0`
    * `filter` an optional filter if you don't want to update on each event. The filter can either be an expression
               using `:_` as wildcard parameter such as `{Accounts, [:user, :_], :_}`. Alternatively `filter`
               can be a function with one parameter
               _Note_ LiveAttribute is issuing each subscribe call in an isolated helper process, so you only need
               to add filters to reduce the scope of a single subscription.
    * `refresher` the function callback to load the new values after a subscription event has
                fired.

  """

  @type socket :: map()

  @typedoc """
    The refresher list or function.

    Should preferably be a list of `{key, callback}` pairs to load the new attribute values.
    The `callback` thereby can have optionally one argument to read context from the socket.

    Alternatively the refresher can be a single argument function instead of a list. In this
    case the function is applied to the socket and thus the user has to ensure that
    needed `assign()` calls are made manually.

    ## Examples

    iex> assign_attribute(socket, &User.subscribe(), users: &User.list_all/0)

    iex> assign_attribute(socket, &User.subscribe(),
      fn socket -> User.list_all() -- socket.assigns.blacklist end
    )
    iex> assign_attribute(socket, &User.subscribe(), fn socket ->
      assign(users: User.list_all() -- socket.assigns.blacklist)
    end)
  """
  @type refresher :: [{atom(), (() -> any()) | (socket() -> any())}] | (socket() -> socket())

  defmacro __using__(_opts) do
    quote do
      import LiveAttribute, only: [update_attribute: 2]

      def handle_info({LiveAttribute, refresher}, socket) do
        {:noreply, refresher.(socket)}
      end

      def assign_attribute(socket, {subscribe, refresher}),
        do: assign_attribute(socket, subscribe, refresher)

      def assign_attribute(socket, {subscribe, filter, refresher}),
        do: assign_attribute(socket, subscribe, filter, refresher)

      @spec assign_attribute(
              LiveAttribute.socket(),
              (() -> any()),
              any(),
              LiveAttribute.refresher()
            ) :: LiveAttribute.socket()
      def assign_attribute(socket, subscribe, filter \\ :_, refresher)

      def assign_attribute(socket, subscribe, filter, refresher) when is_list(refresher) do
        keys = Keyword.keys(refresher)

        update_fun = fn socket ->
          Enum.reduce(refresher, socket, fn {key, value}, socket ->
            assign(socket, [{key, LiveAttribute.apply(socket, value)}])
          end)
        end

        socket =
          if connected?(socket) do
            {:ok, pid} = LiveAttribute.new(subscribe, filter, update_fun, keys)

            entry =
              Enum.map(refresher, fn {key, _fun} -> {key, pid} end)
              |> Map.new()

            meta =
              Map.get(socket.assigns, :_live_attributes, %{})
              |> Map.merge(entry)

            assign(socket, _live_attributes: meta)
          else
            socket
          end

        update_fun.(socket)
      end

      def assign_attribute(socket, subscribe, filter, refresher) when is_function(refresher, 1) do
        # Logger.error("using deprecated assign_attribute/4 with fun as refresher")
        if connected?(socket) do
          LiveAttribute.new(subscribe, filter, refresher, [])
        end

        refresher.(socket)
      end
    end
  end

  def update_attribute(socket, name) do
    pid =
      Map.get(socket.assigns, :_live_attributes, %{})
      |> Map.get(name)

    if pid != nil do
      refresher = GenServer.call(pid, :get_refresher)
      refresher.(socket)
    else
      Logger.error("update_attribute: #{inspect(name)} is not bound")
      socket
    end
  end

  @doc false
  def new(subscribe, filter, refresher, keys) do
    la = %LiveAttribute{
      filter: filter,
      refresher: refresher,
      subscribe: subscribe,
      target: self(),
      keys: keys
    }

    GenServer.start_link(__MODULE__, la, hibernate_after: 5_000)
  end

  @impl true
  @doc false
  def init(%LiveAttribute{target: target, subscribe: subscribe} = la) do
    Process.monitor(target)
    subscribe.()
    {:ok, la}
  end

  @impl true
  @doc false
  def handle_info({:DOWN, _ref, :process, _pid}, state) do
    {:stop, :normal, state}
  end

  @impl true
  @doc false
  def handle_info(
        any,
        %LiveAttribute{target: target, refresher: refresher, filter: filter} = state
      ) do
    if matches?(filter, any) do
      send(target, {LiveAttribute, refresher})
    end

    {:noreply, state}
  end

  @impl true
  def handle_call(:get_refresher, _from, %LiveAttribute{refresher: refresher} = state) do
    {:reply, refresher, state}
  end

  @doc false
  def matches?(:_, _any), do: true
  def matches?(fun, any) when is_function(fun, 1), do: fun.(any)
  def matches?(same, same), do: true

  def matches?(tuple1, tuple2) when is_tuple(tuple1) and is_tuple(tuple2),
    do: matches?(Tuple.to_list(tuple1), Tuple.to_list(tuple2))

  def matches?([head1 | rest1], [head2 | rest2]),
    do: matches?(head1, head2) and matches?(rest1, rest2)

  def matches?(_, _), do: false

  @doc false
  def apply(_socket, refresher) when is_function(refresher, 0), do: refresher.()
  def apply(socket, refresher) when is_function(refresher, 1), do: refresher.(socket)
end
