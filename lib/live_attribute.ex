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
      {:ok, assign_attribute(socket, &User.subscribe/0, users: &User.list_users/0)}
    end

    def handle_event("delete_user", %{"id" => user_id}, socket) do
      User.get_user!(user_id)
      |> User.delete_user()

      {:noreply, socket}
    end
  end
  ```


  ## Same Example without LiveAttribute
  ```
  defmodule UserLive do
    use Phoenix.LiveView

    def mount(_params, _session, socket) do
      if connected?(socket), do: User.subscribe()
      {:ok, update_users(socket)}
    end

    defp update_users(socket) do
      users = User.list_users()
      assign(socket, users: users)
    end

    def handle_event("delete_user", %{"id" => user_id}, socket) do
      User.get_user!(user_id)
      |> User.delete_user()

      {:noreply, socket}
    end

    def handle_info({User, [:user, _], _}, socket) do
      {:noreply, update_users(socket)}
    end
  end
  ```

  ### assign\\_attribute(socket, subscribe, filter \\\\ :\\_, refresher)

  * `socket` the LiveView socket where the assigns should be executed on
  * `subscribe` the subscribe callback to start the subscription e.g. `&Users.subscribe/0`
  * `filter` an optional filter if you don't want to update on each event. The filter can either be an expression
    using `:_` as wildcard parameter such as `{User, [:user, :_], :_}`. Alternatively `filter`
    can be a function with one parameter
    _Note_ LiveAttribute is issuing each subscribe call in an isolated helper process, so you only need
    to add filters to reduce the scope of a single subscription.
  * `refresher` the function callback to load the new values after a subscription event has
    fired.

  """

  @doc false
  @type socket :: %Phoenix.LiveView.Socket{}

  @typedoc """
  The refresher list is passed to `assign_attribute()` to know which assigns to update when
  the subscription source issues an event.

  It is a list of `{key, callback}` pairs specifying how to load the new attribute values.
  The `callback` thereby can have optionally one argument to read context from the socket.

  ## refresher() examples
  ```
  # 1. Zero argument callback to update the users list:
  [users: &User.list_all/0]

  # 2. Single argument callback to use the socket state in the update:
  [users: fn socket ->
    User.list_all() -- socket.assigns.blacklist
  end]

  # 3. Special `socket` key to assign multiple values at once manually
  [socket: fn socket ->
    assign(socket,
      users: User.list_all() -- socket.assigns.blacklist,
      last_update: System.os_time()
    )
  end]
  ```


  ## Usage Examples

  ```
  iex> assign_attribute(socket, &User.subscribe(), users: &User.list_all/0)

  iex> assign_attribute(socket, &User.subscribe(), fn socket ->
    assign(socket, users: User.list_all() -- socket.assigns.blacklist)
  end)
  ```
  """
  @type refresher :: [{atom(), (() -> any()) | (socket() -> any())}] | (socket() -> socket())

  @typedoc """
  The filter allows doing optimzation by a) ignoring certain events of the subscription
  source and b) pass event values directly to assign values, instead of using refresher
  functions to re-load them.

  It can be either a match object defining which events should be matched, or a function
  returning `false` when the event should be ignored or a map when it should be processed.
  Keys that are present in the map will be assigned to the socket. (if there are matching
  keys in the refresher list)

  ## Filter function
  The filter function receives the event and should return either `false` or a map of
  the new values:

  ```
  fn event ->
    case event do
      {User, :users_updated, users} -> %{users: users}
      _ -> false
    end
  end)
  ```

  ## Filter object
  Match objects are defined by example of a matching list or tuple. These can be customized
  using two special terms:
  - `:_` the wildcard which matches any value, but ignores it
  - `{:"$", some_key}` - which matches any value, and uses it as update value in the socket assigns

  ## Examples
  ```
  # Let's assumg the `User` module is generating the following event each time
  # the user list is updated: `{User, :users_updated, all_users}`
  # then the following match object will extract the users

  {User, :users_updated, {:"$", :users}}

  # Full function call with match object
  assign_attribute(socket, &User.subscribe/0, users: &User.list/0, {User, :users_updated, {:"$", :users}})


  # Now the same we could get with this function callback instead:
  fn event ->
    case event do
      {User, :users_updated, users} -> %{users: users}
      _ -> false
    end
  end)

  # Full function call with callback
  assign_attribute(socket, &User.subscribe/0, users: &User.list/0,
    fn event ->
      case event do
        {User, :users_updated, users} -> %{users: users}
        _ -> false
      end
    end)
  ```
  """
  @type filter :: atom() | tuple() | list() | (() -> false | %{})

  defmacro __using__(_opts) do
    quote do
      import LiveAttribute,
        only: [update_attribute: 2, assign_attribute: 2, assign_attribute: 3, assign_attribute: 4]

      def handle_info({LiveAttribute, refresher, updates}, socket) do
        {:noreply, refresher.(socket, updates)}
      end
    end
  end

  @doc """
  Shortcut version of `assign_attribute` to capture an attribute configuration
  in a tuple and re-use in multiple LiveViews. This accepts two-element and three-
  element tuples with: `{subscribe, refresher}` or  `{subscribe, filter, refresher}`
  correspondingly

  Use with:
  ```
  socket = assign_attribute(socket, User.live_attribute())
  ```

  When there is an `User` method:

  ```
  defmodule User do
    def live_attribute() do
      {&subscribe/0, users: &list_users/0}
    end
    ...
  end
  ```
  """
  @spec assign_attribute(socket(), tuple()) :: socket()
  def assign_attribute(socket, tuple) when is_tuple(tuple) do
    case tuple do
      {subscribe, refresher} -> assign_attribute(socket, subscribe, refresher)
      {subscribe, filter, refresher} -> assign_attribute(socket, subscribe, filter, refresher)
    end
  end

  @doc """
  ```
  socket = assign_attribute(socket, &User.subscribe/0, users: &User.list/0)
  ```

  `assign_attribute` updates the specified assign keys each time there is a new event sent from
  the subscription source.

  See `refresher()` and `filter()` for advanced usage of these parameters. Simple usage:

  """
  @spec assign_attribute(
          socket(),
          (() -> any()),
          filter(),
          refresher()
        ) :: socket()
  def assign_attribute(socket, subscribe, filter \\ :_, refresher)

  def assign_attribute(socket, subscribe, filter, refresher) when is_list(refresher) do
    keys = Keyword.keys(refresher)

    update_fun = fn socket, updates ->
      Enum.reduce(refresher, socket, fn
        {:socket, value}, socket ->
          value.(socket)

        {key, value}, socket ->
          reload = fn -> LiveAttribute.apply(socket, value) end
          value = Map.get_lazy(updates, key, reload)
          assign(socket, [{key, value}])
      end)
    end

    socket =
      if connected?(socket) do
        {:ok, pid} = LiveAttribute.new(subscribe, filter, update_fun, keys)

        entry =
          Enum.map(refresher, fn {key, _fun} -> {key, pid} end)
          |> Map.new()

        meta = Map.get(socket.assigns, :_live_attributes, %{})

        meta =
          Enum.reduce(entry, meta, fn {key, pid}, meta ->
            LiveAttribute.stop(Map.get(meta, key))
            Map.put(meta, key, pid)
          end)

        assign(socket, _live_attributes: meta)
      else
        socket
      end

    update_fun.(socket, %{})
  end

  def assign_attribute(socket, subscribe, filter, refresher) when is_function(refresher, 1) do
    # Logger.error("using deprecated assign_attribute/4 with fun as refresher")
    if connected?(socket) do
      LiveAttribute.new(subscribe, filter, refresher, [])
    end

    refresher.(socket)
  end

  @doc """
    ```
      socket = update_attribute(socket, :users)
    ```

    Helper method to issue a update callback manually on a live attribute, when there
    is a known update but no subscription event.
  """
  def update_attribute(socket, name) do
    pid =
      Map.get(socket.assigns, :_live_attributes, %{})
      |> Map.get(name)

    if pid != nil do
      refresher = GenServer.call(pid, :get_refresher)
      refresher.(socket, %{})
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

  @doc false
  def stop(nil), do: :ok

  def stop(pid) do
    GenServer.cast(pid, :stop)
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
    case matches?(filter, any) do
      false -> :noop
      %{} = updates -> send(target, {LiveAttribute, refresher, updates})
    end

    {:noreply, state}
  end

  @impl true
  def handle_call(:get_refresher, _from, %LiveAttribute{refresher: refresher} = state) do
    {:reply, refresher, state}
  end

  @impl true
  def handle_cast(:stop, %LiveAttribute{} = state) do
    {:stop, :normal, state}
  end

  @doc false
  def matches?({:"$", key}, value), do: %{key => value}
  def matches?(:_, _any), do: %{}
  def matches?(fun, any) when is_function(fun, 1), do: fun.(any)
  def matches?(same, same), do: %{}

  def matches?(tuple1, tuple2) when is_tuple(tuple1) and is_tuple(tuple2),
    do: matches?(Tuple.to_list(tuple1), Tuple.to_list(tuple2))

  def matches?([head1 | rest1], [head2 | rest2]) do
    case matches?(head1, head2) do
      false ->
        false

      %{} = updates ->
        case matches?(rest1, rest2) do
          false -> false
          %{} = more_updates -> Map.merge(updates, more_updates)
        end
    end
  end

  def matches?(_, _), do: false

  @doc false
  def apply(_socket, refresher) when is_function(refresher, 0), do: refresher.()
  def apply(socket, refresher) when is_function(refresher, 1), do: refresher.(socket)

  defp connected?(socket) do
    case socket do
      %Phoenix.LiveView.Socket{} -> Phoenix.LiveView.connected?(socket)
      %other{} -> other.connected?(socket)
    end
  end

  defp assign(socket, values) do
    case socket do
      %Phoenix.LiveView.Socket{} -> Phoenix.LiveView.assign(socket, values)
      %other{} -> other.assign(socket, values)
    end
  end
end
