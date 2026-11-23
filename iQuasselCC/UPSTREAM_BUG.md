# Unauthenticated remote crash (NULL deref) in `operator>>(QDataStream&, SignedId64&)` before login

## Summary

A Quassel **core** can be crashed (SIGSEGV) by any client that can reach its
listening port, **before authenticating** — no valid username or password is
required. The core begins decoding SignalProxy messages on a connection as soon
as they arrive, but a message carrying a `SignedId64` (e.g. a `MsgId`) is
deserialized through `operator>>(QDataStream&, SignedId64&)`, which assumes a
logged-in peer exists. On a fresh, not-yet-authenticated connection it does not,
and the core dereferences a NULL pointer.

Because Quassel has no anonymous or password-less user, this is reachable
*ahead of* the authentication check — the deserialization happens first.

## Affected / tested

- Reproduced on **quassel-core 0.14.0** (Ubuntu package `1:0.14.0-4ubuntu2`,
  release build).
- Source is **identical on `master` and `0.14.0`**; the function has no runtime
  guard in release builds (see below), so current builds are expected to be
  affected too.

## Root cause

`src/common/types.cpp`:

```cpp
QDataStream& operator>>(QDataStream& in, SignedId64& signedId)
{
    Q_ASSERT(SignalProxy::current());
    Q_ASSERT(SignalProxy::current()->sourcePeer());

    if (SignalProxy::current()->sourcePeer()->hasFeature(Quassel::Feature::LongMessageId)) {
        in >> signedId.id;
    }
    else {
        qint32 id;
        in >> id;
        signedId.id = id;
    }
    return in;
}
```

The only guards are `Q_ASSERT`, which are compiled out in release builds
(`NDEBUG`). On a connection that has not completed login there is no current
SignalProxy / source peer for this context, so
`SignalProxy::current()->sourcePeer()->hasFeature(...)` dereferences NULL and
the core's main thread crashes. (`operator<<` for `SignedId64` has the same
shape via `targetPeer()`.)

Decoded from a user's production coredump, the crashing frame is
`operator>>(QDataStream&, SignedId64&)`, reached from
`Serializers::deserialize(...) → DataStreamPeer::processMessage → RemotePeer::onReadyRead`.

## Impact

- **Unauthenticated remote denial of service.** Any host that can open the core
  port (default 4242) can crash the core at will, with a single small message
  and no credentials. If the port is internet-facing, this is remotely
  exploitable by anyone.
- systemd will restart the core, but the crash can be repeated immediately, so
  the service can be kept down.

## Reproduction (described for maintainers)

Against a default core (no TLS needed for the trigger):

1. Open a TCP connection to the core port.
2. Send the normal protocol-detection handshake selecting the **DataStream**
   protocol (magic `0x42B33F00`, then the protocol list with the DataStream
   bit). The core replies as usual.
3. **Without sending `ClientInit` or logging in**, send one DataStream message
   frame (4-byte big-endian length prefix) whose payload is a `QVariantList`
   containing a single user-type variant of type name `"MsgId"` (a `SignedId64`)
   with an 8-byte value.
4. The core segfaults while deserializing that value.

`ClientInit` is not required; the protocol handshake plus this one frame is
enough. The same crash occurs whether the `LongMessageId` feature was announced
or not.

## Suggested fix

In `operator>>`/`operator<<` for `SignedId64`, replace the `Q_ASSERT`s with a
real runtime check that is present in release builds, e.g. bail out (and ideally
drop the peer) when `SignalProxy::current()` or its source/target peer is NULL,
instead of dereferencing. More broadly, the DataStream peer should not attempt
to deserialize arbitrary SignalProxy payloads on a connection that has not yet
authenticated.

## Mitigation for operators (until fixed)

Do not expose the core port directly to the internet; restrict it with a
firewall or reach it only over a VPN / SSH tunnel.
