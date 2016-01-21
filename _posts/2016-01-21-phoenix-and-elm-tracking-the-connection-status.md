---
layout: post
title: 'Phoenix and Elm: tracking the connection status'
date: 2016-01-21 10:30
published: true
categories: elixir phoenix elm
---

When working with [Phoenix channels](http://www.phoenixframework.org/docs/channels) and [Elm](http://elm-lang.org) it may be useful to keep track of the websockets connection status. In this blog post, we'll see how this can be accomplished by leveraging interoperability.

<!--more-->

This blog post won't cover how to setup Phoenix and Elm together: if you're interested into that and/or want a primer on how they can fit together, I heavily recommend [Alan Gardner's series of tutorials on Cultivate's blog](http://www.cultivatehq.com/posts/phoenix-elm-1/).

Moreover, we assume the following versions:

- Phoenix ~> 1.0
- Elm 0.16

# Step 1: add the needed elements to the Elm Architecture

Assuming our Elm application is built with the [Elm Architecture](https://github.com/evancz/elm-architecture-tutorial), we need to make a few changes:

- Update the Model to hold a `connected` property

```haskell
model =
  { connected : False
  , ...
  }
```

- Add a new `Action` to express a connection change event

```haskell
type Action =
  NoOp
  | ConnectionChange Bool
  | ...
```

- Extend the main `update` function to handle the new `Action`

```haskell
update : Action -> Model -> ( Model, Effects Action )
update action model =
  case action of
    ...
    ConnectionChange connected ->
      ({ model | connected = connected }, Effects.none)
```

# Step 2: Open and wire a port

As we will receive the `connected` status value from the outside world, we need to open a port:

```haskell
port connectionStatusSignal : Signal Bool
```

Opening a port implies that now we have a new signal that we need to handle, so we need to extend the `StartApp` definition:

```haskell
import Signal exposing (map)

app : StartApp.App Model
app =
    StartApp.start
        { init = noFx model
        , view = view
        , update = update
        , inputs =
            [ ConnectionChange `map` connectionStatusSignal
            ]
        }
```

In the code above, we add a new input by mapping the incoming values from our port to the `ConnectionChange` action defined before.

# Step 3: Update the interop layer

As we added a new port, we need to update the JavaScript initialization step of our Elm application:

```javascript
  var elmApp = Elm.fullscreen(Elm.Main, {
    connectionStatusSignal: false
  });
```

Finally, we need to hook into the Phoenix `socket` lifecycle to send its status back through the port:

```javascript
  var socket = new Phoenix.Socket("/socket", {});

  socket.onOpen(function() {
    elmApp.ports.connectionStatusSignal.send(true);
  });

  socket.onClose(function() {
    elmApp.ports.connectionStatusSignal.send(false);
  });
```

This should be it! Feel free to ping [@fully_forged](https://twitter.com/fully_forged/) on Twitter if you have any questions.
