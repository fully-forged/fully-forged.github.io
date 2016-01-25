---
layout: post
title: Monitoring an external tcp service in Elixir
date: 2016-01-29 09:17
published: true
categories: elixir
---

More often than not an application depends on external services, like databases or message brokers. How can we handle failures in those services? In this blog post we'll look at how to implement a simple health status checker process that will help us surviving those crashes.

<!--more-->

# What we're building

Let's start from what we want to achieve and let's use, as an example, database availability. A deceptively simple requirement can be: **if the database goes down, I want my application to try and reconnect. After 10 unsuccesful attempts, I want to switch to a replacement service.**

This requirement means that our Health Status Checker (HSC) process needs to:

- constantly monitor the database server by opening a tcp connection to it
- if the connection drops, try to reconnect
- if the reconnect is successful, restore the application to a stable state
- if it fails 10 times in a row, switch to a replacement service

# Step 1: creating the HSC worker

We can start by creating a new worker that can be inserted into the top-level supervision tree of our application.

```elixir
defmodule HSC do
  use GenServer

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts)
  end
end
```

This worker needs to accept some options on start, as we will need to pass host and port.

We can then add it to the main supervision tree (usually in `lib/<name-of-your-app>.ex`).

```elixir
  def start(_type, _args) do
    import Supervisor.Spec, warn: false

    opts = [host: "localhost", port: 5432]

    children = [
      # Define workers and child supervisors to be supervised
      worker(HSC, [opts]),
    ]
    ...
  end
```

# Step 2: connect to the tcp service

To connect to the external service, we'll leverage the built-in `gen_tcp` module [provided by Erlang](http://www.erlang.org/doc/man/gen_tcp.html). I'd recommend a thorough read of the manual page, as `gen_tcp` is extremely powerful.

As we're using `GenServer`, we can override `init/1`:

```elixir
  defmodule HSC do
    use GenServer

    def start_link(opts) do
      GenServer.start_link(__MODULE__, opts)
    end

    def init(opts) do
      host = Keyword.get(opts, :host, "localhost") |> String.to_char_list
      port = Keyword.fetch!(opts, :port)
      case :gen_tcp.connect(host, port, []) do
        {:ok, _socket} -> {:ok, []}
        {:error, _reason} -> {:stop, :connection_failed}
      end
    end
  end
```

This implementation tries to connect to the server: in case of success, the worker starts normally. In case of failure, it stops, taking down the entire application (for more information about return values in `init/1`, see [the docs](http://elixir-lang.org/docs/stable/elixir/GenServer.html#c:init/1)).

We can also see that `:gen_tcp.connect/3` requires us to cast the host to a char list (this is quite frequent when using Erlang libraries). In case you need to pass an IP address, it needs to be in a tuple form (`{127,0,0,1}`). Regarding option handling, we can see two different approaches: we fall back to a default for the `host`, but require a `port` to be supplied explicitly.

At this point, the `HSC` worker has very limited usefulness: we need to tackle the idea of retries. For starters, we'll focus on retrying the initial connection attempt.

# Step 3: retrying the initial connection attempt

As our external service can be unavailable at application boot time, we need to think about how to reconnect.

Let's start by saying: "We want to retry indefinitely every second".

```elixir
defmodule HSC do
  use GenServer
  @retry_interval 1000

  ...

  def init(opts) do
    host = Keyword.get(opts, :host, "localhost") |> String.to_char_list
    port = Keyword.fetch!(opts, :port)
    case :gen_tcp.connect(host, port, []) do
      {:ok, _socket} ->
        {:ok, {host, port}}
      {:error, _reason} ->
        {:ok, {host, port}, @retry_interval}
    end
  end

  def handle_info(:timeout, {host, port}) do
    case :gen_tcp.connect(host, port, []) do
      {:ok, _socket} ->
        {:noreply, {host, port}}
      {:error, _reason} ->
        {:noreply, {host, port}, @retry_interval}
    end
  end
end
...
```

We need to revise a few things:

- in case of failure, we don't stop the worker, but return a `{:ok, state, timeout}` response. This means that in `1000` milliseconds, our worker will receive a `:timeout` message, which we handle with `handle_info/2`. In this callback, we repeat the pattern: try to connect and send a timeout in case of failure.
- we need to keep `host` and `port` in our GenServer state, as we need to pass them around between `GenServer` callbacks. As a first step, we can use a tuple, but this doesn't scale well. We will revise this data structure in the next step.

# Step 4: stop after 10 attempts

Instead of retrying indefinitely, we want to switch back to an in-memory service replacement after ten attempts. This implies that we need to keep an attempt counter in the state. Before doing that, let's refactor and use a better data structure.

```elixir
defmodule HSC do
  use GenServer

  defmodule State do
    defstruct host: "localhost",
              port: 1234
  end

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts)
  end

  def init(opts) do
    state = opts_to_initial_state(opts)
    case :gen_tcp.connect(state.host, state.port, []) do
      {:ok, _socket} ->
        {:ok, state}
      {:error, _reason} ->
        {:ok, state, @retry_interval}
    end
  end

  def handle_info(:timeout, state) do
    case :gen_tcp.connect(state.host, state.port, []) do
      {:ok, _socket} ->
        {:noreply, state}
      {:error, _reason} ->
        {:noreply, state, @retry_interval}
    end
  end

  defp opts_to_initial_state(opts) do
    host = Keyword.get(opts, :host, "localhost") |> String.to_char_list
    port = Keyword.fetch!(opts, :port)
    %State{host: host, port: port}
  end
end
```

We introduce a `State` struct which gets populated from `opts`. We can then adapt the rest of the code to use it. This also simplifies the callbacks code, as we don't have pattern match on the state tuple anymore. We can now more comfortably handle the maximum number of retries feature.

Tracking the failure count can be implemented as follows:

```elixir
defmodule State do
  defstruct host: "localhost",
            port: 1234,
            failure_count: 0
end

...

def init(opts) do
  state = opts_to_initial_state(opts)
  case :gen_tcp.connect(state.host, state.port, []) do
    {:ok, _socket} ->
      {:ok, state}
    {:error, _reason} ->
      {:ok, %{state | failure_count: 1}, @retry_interval}
  end
end

def handle_info(:timeout, state = %State{failure_count: failure_count}) do
  case :gen_tcp.connect(state.host, state.port, []) do
    {:ok, _socket} ->
      {:noreply, %{state | failure_count: 0}}
    {:error, _reason} ->
      {:noreply, %{state | failure_count: failure_count + 1}, @retry_interval}
  end
end
```

We add a new property to `State` and update/reset its value accordingly depending on the outcome of every `:gen_tcp.connect/3` call.

Tracking the failure count is just the first half of this feature: next is stopping the process when reaching 10 consecutive failures.

```elixir
defmodule HSC do
  use GenServer
  @retry_interval 1000
  @max_retries 10

  ...

  def handle_info(:timeout, state = %State{failure_count: failure_count}) do
    if failure_count <= @max_retries do
      case :gen_tcp.connect(state.host, state.port, []) do
        {:ok, _socket} ->
          {:noreply, %{state | failure_count: 0}}
        {:error, _reason} ->
          {:noreply, %{state | failure_count: failure_count + 1}, @retry_interval}
      end
    else
      {:stop, :max_retry_exceeded, state}
    end
  end
end
```

We stop the worker by returning `{:stop, reason, state}` as we did in the beginning. At this point the worker will be restarted by the supervisor and will conform to its strategy.

By default the `Supervisor` will restart this worker a maximum of 3 times over 5 seconds (see [the documentation for `supervise/2`](http://elixir-lang.org/docs/stable/elixir/Supervisor.Spec.html#supervise/2) for more details on how to change that), while the worker's lifetime, in case of continuous failure, is at least 10 seconds (1 second interval, 10 retries). With this configuration, **it will never crash the top level supervisor**.

# Step 5: handling connection failures

So far we focused on the behaviour needed to implement the initial connection, but we also need to think about how to react when the connection breaks.

When using `:gen_tcp.connect/3`, the calling process will receive messages sent to the socket: we're interested into `:tcp_closed`, which is the message received when the connection closes. We can implement `handle_info/2` to handle it:

```elixir
def handle_info({:tcp_closed, _socket}, state) do
  case :gen_tcp.connect(state.host, state.port, []) do
    {:ok, _socket} ->
      {:noreply, %{state | failure_count: 0}}
    {:error, _reason} ->
      {:noreply, %{state | failure_count: 1}, @retry_interval}
  end
end
```

When the connection closes, we try to reconnect, once again setting the failure counts to the right values.

# Step 6: callbacks

We're now tracking the complete lifecycle of our tcp connection, so we can focus on exposing callbacks to act on disconnect/reconnect/failure events. There are different strategies we can follow for this: one option is to initialized the `HSC` worker with the `pid` of another process that will receive messages for the aforementioned events, another is to simply pass the callback functions with the rest of the configuration. We'll stick with the latter for now, as the former requires a more extended process infrastructure.

We can revise our application entry point as follows:

```elixir
  def start(_type, _args) do
    import Supervisor.Spec, warn: false

    children = [
      # Define workers and child supervisors to be supervised
      worker(HSC, [hsc_config]),
    ]
    ...
  end
  
  defp hsc_config do
    [host: "localhost",
     port: 5432,
     on_connect: fn(state) -> Logger.info "connected" end,
     on_disconnect: fn(state) -> Logger.error "disconnected" end,
     on_failure: fn(state) -> MyApp.use_in_memory_store end]
  end
```

Our ideal api exposes 3 functions, `on_connect/1`, `on_disconnect/1` and `on_failure/1`, that will receive the `HSC` worker state as an argument. This way we can use the state information to print a logline, etc. In the `on_connect/1` function we can do whatever's needed to restore the health of our application, for example calling `Applicaton.ensure_started/2` to restart (if needed) our external service dependant application. If we were monitoring a Postgresql server and using [Ecto](https://github.com/elixir-lang/ecto), we could call:

```elixir
Application.ensure_started(:poolboy)
Application.ensure_started(:ecto)
MyApp.use_external_store
```

These semantics may not be enough, depending on how complicated the use case is. If we switch to a in-memory alternative, for example, we may need to migrate that data to the external service when back up.

As for the implementation of the three callbacks, we can revise the `HSC` module by extending its `State` struct definition and calling the relevant callbacks where needed:

```elixir
defmodule HSC do
  use GenServer

  @max_retries 10
  @retry_interval 1000

  defmodule DefaultCallbacks do
    require Logger

    def on_connect(state) do
      Logger.info("tcp connect to #{state.host}:#{state.port}")
    end

    def on_disconnect(state) do
      Logger.info("tcp disconnect from #{state.host}:#{state.port}")
    end

    def on_failure(state) do
      Logger.info("tcp failure from #{state.host}:#{state.port}. Max retries exceeded.")
    end
  end

  defmodule State do
    defstruct host: "localhost",
              port: 1234,
              failure_count: 0,
              on_connect: &DefaultCallbacks.on_connect/1,
              on_disconnect: &DefaultCallbacks.on_disconnect/1,
              on_failure: &DefaultCallbacks.on_failure/1

  end

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts)
  end

  def init(opts) do
    state = opts_to_initial_state(opts)
    case :gen_tcp.connect(state.host, state.port, []) do
      {:ok, _socket} ->
        state.on_connect.(state)
        {:ok, state}
      {:error, _reason} ->
        new_state = %{state | failure_count: 1}
        new_state.on_disconnect.(new_state)
        {:ok, new_state, @retry_interval}
    end
  end

  def handle_info(:timeout, state = %State{failure_count: failure_count}) do
    if failure_count <= @max_retries do
      case :gen_tcp.connect(state.host, state.port, []) do
        {:ok, _socket} ->
          new_state = %{state | failure_count: 0}
          new_state.on_connect.(new_state)
          {:noreply, new_state}
        {:error, _reason} ->
          new_state = %{state | failure_count: failure_count + 1}
          new_state.on_disconnect.(new_state)
          {:noreply, new_state, @retry_interval}
      end
    else
      state.on_failure.(state)
      {:stop, :max_retry_exceeded, state}
    end
  end

def handle_info({:tcp_closed, _socket}, state) do
  case :gen_tcp.connect(state.host, state.port, []) do
    {:ok, _socket} ->
      new_state = %{state | failure_count: 0}
      new_state.on_connect.(new_state)
      {:noreply, new_state}
    {:error, _reason} ->
      new_state = %{state | failure_count: 1}
      new_state.on_disconnect.(new_state)
      {:noreply, new_state, @retry_interval}
  end
end

  defp opts_to_initial_state(opts) do
    host = Keyword.get(opts, :host, "localhost") |> String.to_char_list
    port = Keyword.fetch!(opts, :port)
    %State{host: host, port: port}
  end
end
```

Note that we define a `DefaultCallbacks` module that logs via `Logger` and then proceed to use the newly defined callbacks throughout the rest of the module, paying attention to modify the state **before** passing it to the functions (otherwise we would log incorrect failure counts).

# Where do we go from here

There's much more that we could build into this module: staggered retries, tcp connection timeout, extend configurability. All of these ideas can be built on top of the patterns we've seen, so they're left as an exercise for the reader. In addition, in a production scenario we may need to use a more sophisticated approach to retries, maybe leveraging a library like [backoff](https://github.com/ferd/backoff).

In this post we've seen how to use Elixir to increase the resiliency of our application when dependant on external services by building a simple healthcheck monitor. Please feel free to reach out with questions and/or suggestions on how to improve this!

Thanks to [Saša Jurić](http://www.theerlangelist.com) and [Olly Legg](http://www.51degrees.net) for their feedback on the initial draft.
