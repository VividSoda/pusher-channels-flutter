/// A Flutter client for [Pusher Channels](https://pusher.com/channels),
/// backed by the official native SDKs on Android and iOS and by pusher-js on
/// the web.
///
/// Start from [PusherChannelsFlutter], the singleton client.
library;

import 'dart:async';
import 'dart:convert';

import 'package:flutter/services.dart';

/// Typed representation of Pusher's connection lifecycle state.
///
/// This is a purely additive, non-breaking convenience on top of the
/// String-based [PusherChannelsFlutter.connectionState] value reported by
/// the native SDKs (which use `CONNECTED`/`connected`-style casing
/// depending on platform) — the raw string remains the value passed to
/// [PusherChannelsFlutter.onConnectionStateChange]. Use
/// [PusherChannelsFlutter.connectionStateEnum] to read this typed form.
enum PusherConnectionState {
  /// A connection is being established.
  connecting,

  /// The connection is open and events can be sent and received.
  connected,

  /// The connection is being closed after [PusherChannelsFlutter.disconnect].
  disconnecting,

  /// No connection is open.
  disconnected,

  /// The connection dropped and the SDK is retrying.
  reconnecting,

  /// The connection dropped while the device was offline; the SDK is waiting
  /// for the network to come back before retrying. Reported by iOS only.
  reconnectingWhenNetworkBecomesReachable,

  /// Reported by a platform SDK but not one of the known states above.
  /// Kept instead of throwing so that a new state added to a platform SDK
  /// doesn't crash apps built against an older version of this package.
  unknown;

  /// Parses a raw connection state string (as reported by the platform
  /// SDKs, e.g. `"CONNECTED"` on Android/iOS or `"connected"` on web) into
  /// a [PusherConnectionState].
  static PusherConnectionState parse(String value) {
    switch (value.toUpperCase()) {
      case 'CONNECTING':
        return PusherConnectionState.connecting;
      case 'CONNECTED':
        return PusherConnectionState.connected;
      case 'DISCONNECTING':
        return PusherConnectionState.disconnecting;
      case 'DISCONNECTED':
        return PusherConnectionState.disconnected;
      case 'RECONNECTING':
        return PusherConnectionState.reconnecting;
      case 'RECONNECTING_WHEN_NETWORK_BECOMES_REACHABLE':
        return PusherConnectionState.reconnectingWhenNetworkBecomesReachable;
      default:
        return PusherConnectionState.unknown;
    }
  }
}

/// An event received from — or triggered on — a channel.
///
/// The same type is used in both directions: it is handed to
/// [PusherChannelsFlutter.onEvent] for incoming events, and passed to
/// [PusherChannelsFlutter.trigger] to send a client event.
class PusherEvent {
  /// Name of the channel the event belongs to, e.g. `presence-chat`.
  String channelName;

  /// Name of the event, e.g. `client-typing` or `pusher:subscription_succeeded`.
  String eventName;

  /// Event payload. Depending on the platform this is either a JSON `String`
  /// or an already-decoded `Map`.
  dynamic data;

  /// Id of the user that sent the event, when the channel is a presence
  /// channel and the sender is known. Null otherwise.
  String? userId;

  /// Creates an event for [channelName]/[eventName], optionally carrying
  /// [data] and the sending [userId].
  PusherEvent({
    required this.channelName,
    required this.eventName,
    this.data,
    this.userId,
  });

  @override
  String toString() =>
      '{ channelName: $channelName, eventName: $eventName, data: $data, userId: $userId }';
}

/// A member of a presence channel.
class PusherMember {
  /// Id the authentication endpoint assigned to this member.
  String userId;

  /// Arbitrary payload the authentication endpoint returned for this member,
  /// typically a `Map` of profile fields. Null when none was supplied.
  dynamic userInfo;

  /// Creates a member from the [userId] and [userInfo] reported by the
  /// authentication endpoint.
  PusherMember(this.userId, this.userInfo);

  @override
  String toString() => '{ userId: $userId, userInfo: $userInfo }';
}

/// A subscribed channel, returned by [PusherChannelsFlutter.subscribe].
///
/// Holds the per-channel callbacks and, for presence channels, the member
/// list that this package keeps in sync as members come and go.
class PusherChannel {
  /// Name of the channel this instance represents.
  String channelName;

  /// Members currently in the channel, keyed by [PusherMember.userId].
  ///
  /// Only populated for presence channels; empty for public and private ones.
  Map<String, PusherMember> members = {};

  /// The local user's own membership, once the presence subscription has
  /// succeeded. Null on public and private channels.
  PusherMember? me;

  /// Number of connections subscribed to this channel.
  ///
  /// Updated from `pusher:subscription_count` events, which Pusher only sends
  /// when the subscription count feature is enabled for the app.
  int subscriptionCount = 0;

  /// Called once the subscription is confirmed, with the raw payload.
  Function(dynamic data)? onSubscriptionSucceeded;

  /// Called for every [PusherEvent] received on this channel.
  Function(dynamic event)? onEvent;

  /// Called when a member joins a presence channel.
  Function(PusherMember member)? onMemberAdded;

  /// Called when a member leaves a presence channel.
  Function(PusherMember member)? onMemberRemoved;

  /// Called when [subscriptionCount] changes.
  Function(int subscriptionCount)? onSubscriptionCount;

  /// Creates a channel handle for [channelName] with the given callbacks.
  ///
  /// Prefer [PusherChannelsFlutter.subscribe], which constructs this and
  /// registers the subscription with the platform SDK.
  PusherChannel({
    required this.channelName,
    this.onSubscriptionSucceeded,
    this.onEvent,
    this.onMemberAdded,
    this.onMemberRemoved,
    this.onSubscriptionCount,
    this.me,
  });

  /// Unsubscribes from this channel.
  Future<void> unsubscribe() async {
    return PusherChannelsFlutter.getInstance()
        .unsubscribe(channelName: channelName);
  }

  /// Sends a client event on this channel.
  ///
  /// Only private and presence channels accept client events, and
  /// [PusherEvent.eventName] must be prefixed with `client-`. Throws if
  /// [PusherEvent.channelName] is not [channelName].
  Future<void> trigger(PusherEvent event) async {
    if (event.channelName != channelName) {
      throw ('Event is not for this channel');
    }
    return PusherChannelsFlutter.getInstance().trigger(event);
  }
}

/// Entry point of the plugin: a singleton client for Pusher Channels.
///
/// Obtain it with [getInstance], configure it with [init], then [connect] and
/// [subscribe]. Callbacks registered here fire for every channel; the
/// per-channel equivalents live on [PusherChannel].
///
/// ```dart
/// final pusher = PusherChannelsFlutter.getInstance();
/// await pusher.init(apiKey: 'APP_KEY', cluster: 'eu');
/// await pusher.connect();
/// await pusher.subscribe(channelName: 'my-channel');
/// ```
class PusherChannelsFlutter {
  static PusherChannelsFlutter? _instance;

  /// Creates an unconfigured client.
  ///
  /// Prefer [getInstance]: a single connection is shared process-wide, and the
  /// web implementation binds to one method channel.
  PusherChannelsFlutter();

  /// Channel used to talk to the Android, iOS and web implementations.
  MethodChannel methodChannel = const MethodChannel('pusher_channels_flutter');

  /// Currently subscribed channels, keyed by channel name.
  Map<String, PusherChannel> channels = {};

  /// Raw connection state as reported by the platform SDK, upper-cased —
  /// e.g. `CONNECTED`. See [connectionStateEnum] for a typed view.
  String connectionState = 'DISCONNECTED';

  /// Typed view of [connectionState]. See [PusherConnectionState].
  PusherConnectionState get connectionStateEnum =>
      PusherConnectionState.parse(connectionState);

  /// Called on every connection state transition, with both states as raw
  /// upper-cased strings. Parse with [PusherConnectionState.parse].
  Function(String currentState, String previousState)? onConnectionStateChange;

  /// Called when any channel's subscription is confirmed.
  Function(String channelName, dynamic data)? onSubscriptionSucceeded;

  /// Called when a subscription is rejected, typically because the
  /// authentication endpoint refused it.
  Function(String message, dynamic error)? onSubscriptionError;

  /// Called when an event on a private-encrypted channel could not be
  /// decrypted.
  Function(String event, String reason)? onDecryptionFailure;

  /// Called on connection-level errors, with the Pusher error [code] when the
  /// platform SDK reports one.
  Function(String message, int? code, dynamic error)? onError;

  /// Called for every event received on any subscribed channel.
  Function(PusherEvent event)? onEvent;

  /// Called when a member joins any subscribed presence channel.
  Function(String channelName, PusherMember member)? onMemberAdded;

  /// Called when a member leaves any subscribed presence channel.
  Function(String channelName, PusherMember member)? onMemberRemoved;

  /// Called to authorize a private or presence subscription, when set in
  /// [init]. Return a `Map` with an `auth` key (plus `channel_data` for
  /// presence channels, `shared_secret` for encrypted ones). Use this instead
  /// of `authEndpoint` when the auth request has to go through your own code.
  Function(String channelName, String socketId, dynamic options)? onAuthorizer;

  /// Called when the subscription count of any subscribed channel changes.
  Function(String channelName, int subscriptionCount)? onSubscriptionCount;

  /// Returns the singleton client, creating it on first call.
  static PusherChannelsFlutter getInstance() {
    _instance ??= PusherChannelsFlutter();
    return _instance!;
  }

  /// Initializes the client.
  ///
  /// Supply either [cluster] (Pusher Channels cloud) or [host] (a self-hosted
  /// server such as Soketi or laravel-websockets). When [host] is given,
  /// [wsPort]/[wssPort] select the plaintext/TLS ports.
  ///
  /// [authParams] may carry an `headers` entry, which is applied to requests
  /// made to [authEndpoint] on every platform.
  Future<void> init({
    required String apiKey,
    String? cluster,
    String? host, // self-hosted server (Soketi, laravel-websockets, ...)
    int? wsPort, // port used for plaintext connections
    int? wssPort, // port used for TLS connections
    bool? useTLS,
    int? activityTimeout,
    int? pongTimeout,
    int? maxReconnectionAttempts,
    int? maxReconnectGapInSeconds,
    String? proxy, // pusher-websocket-java only
    bool? enableStats, // pusher-js only
    List<String>? disabledTransports, // pusher-js only
    List<String>? enabledTransports, // pusher-js only
    bool? ignoreNullOrigin, // pusher-js only
    String? authEndpoint,
    String? authTransport, // pusher-js only
    Map<String, Map<String, String>>? authParams,
    bool? logToConsole, // pusher-js only
    Function(String currentState, String previousState)?
        onConnectionStateChange,
    Function(String channelName, dynamic data)? onSubscriptionSucceeded,
    Function(String message, dynamic error)? onSubscriptionError,
    Function(String event, String reason)? onDecryptionFailure,
    Function(String message, int? code, dynamic error)? onError,
    Function(PusherEvent event)? onEvent,
    Function(String channelName, PusherMember member)? onMemberAdded,
    Function(String channelName, PusherMember member)? onMemberRemoved,
    Function(String channelName, String socketId, dynamic options)?
        onAuthorizer,
    Function(String channelName, int subscriptionCount)? onSubscriptionCount,
  }) async {
    assert(cluster != null || host != null,
        'Supply either a cluster or a host to connect to.');
    methodChannel.setMethodCallHandler(_platformCallHandler);
    this.onConnectionStateChange = onConnectionStateChange;
    this.onError = onError;
    this.onSubscriptionSucceeded = onSubscriptionSucceeded;
    this.onEvent = onEvent;
    this.onSubscriptionError = onSubscriptionError;
    this.onDecryptionFailure = onDecryptionFailure;
    this.onMemberAdded = onMemberAdded;
    this.onMemberRemoved = onMemberRemoved;
    this.onAuthorizer = onAuthorizer;
    this.onSubscriptionCount = onSubscriptionCount;
    await methodChannel.invokeMethod('init', {
      "apiKey": apiKey,
      "cluster": cluster,
      // Left null when not supplied, so a cluster-only setup keeps the
      // endpoint the cluster resolves to.
      "host": host,
      "wsPort": wsPort,
      "wssPort": wssPort,
      "useTLS": useTLS,
      "activityTimeout": activityTimeout,
      "pongTimeout": pongTimeout,
      "maxReconnectionAttempts": maxReconnectionAttempts,
      "maxReconnectGapInSeconds": maxReconnectGapInSeconds,
      "authorizer": onAuthorizer != null ? true : null,
      "proxy": proxy,
      "enableStats": enableStats,
      "disabledTransports": disabledTransports,
      "enabledTransports": enabledTransports,
      "ignoreNullOrigin": ignoreNullOrigin,
      "authEndpoint": authEndpoint,
      "authTransport": authTransport,
      "authParams": authParams,
      "logToConsole": logToConsole
    });
  }

  Future<dynamic> _platformCallHandler(MethodCall call) async {
    final String? channelName = call.arguments['channelName'];
    final String? eventName = call.arguments['eventName'];
    final dynamic data = call.arguments['data'];
    final dynamic user = call.arguments['user'];
    final String? userId = call.arguments["userId"];
    switch (call.method) {
      case 'onConnectionStateChange':
        connectionState = call.arguments['currentState'].toUpperCase();
        onConnectionStateChange?.call(
            call.arguments['currentState'].toUpperCase(),
            call.arguments['previousState'].toUpperCase());
        return Future.value(null);
      case 'onError':
        onError?.call(call.arguments['message'], call.arguments['code'],
            call.arguments['error']);
        return Future.value(null);
      case 'onEvent':
        switch (eventName) {
          case 'pusher:subscription_succeeded':
          case 'pusher_internal:subscription_succeeded':
            // Depending on the platform implementation we get json or a Map.
            var decodedData = data is Map ? data : jsonDecode(data);
            decodedData?["presence"]?["hash"]?.forEach((userId_, userInfo) {
              var member = PusherMember(userId_, userInfo);
              channels[channelName]?.members[userId_] = member;
              if (userId_ == userId) {
                channels[channelName]?.me = member;
              }
            });
            onSubscriptionSucceeded?.call(channelName!, decodedData);
            channels[channelName]?.onSubscriptionSucceeded?.call(decodedData);
            break;
          case 'pusher:subscription_count':
          case 'pusher_internal:subscription_count':
            // Depending on the platform implementation we get json or a Map.
            var decodedData = data is Map ? data : jsonDecode(data);
            var subscriptionCount = decodedData['subscription_count'];
            channels[channelName]?.subscriptionCount = subscriptionCount;
            onSubscriptionCount?.call(channelName!, subscriptionCount);
            channels[channelName]?.onSubscriptionCount?.call(subscriptionCount);
            break;
        }
        final event = PusherEvent(
            channelName: channelName!,
            eventName: eventName!.replaceFirst("pusher_internal", "pusher"),
            data: data,
            userId: call.arguments['userId']);
        onEvent?.call(event);
        channels[channelName]?.onEvent?.call(event);
        return Future.value(null);
      case 'onSubscriptionError':
        onSubscriptionError?.call(
            call.arguments['message'], call.arguments['error']);
        return Future.value(null);
      case 'onDecryptionFailure':
        onDecryptionFailure?.call(
            call.arguments['event'], call.arguments['reason']);
        return Future.value(null);
      case 'onMemberAdded':
        var member = PusherMember(user["userId"], user["userInfo"]);
        channels[channelName]?.members[member.userId] = member;
        onMemberAdded?.call(channelName!, member);
        channels[channelName]?.onMemberAdded?.call(member);
        return Future.value(null);
      case 'onMemberRemoved':
        var member = PusherMember(user["userId"], user["userInfo"]);
        channels[channelName]?.members.remove(member.userId);
        onMemberRemoved?.call(channelName!, member);
        channels[channelName]?.onMemberRemoved?.call(member);
        return Future.value(null);
      case 'onAuthorizer':
        return await onAuthorizer?.call(channelName!,
            call.arguments['socketId'], call.arguments['options']);
      default:
        throw MissingPluginException('Unknown method ${call.method}');
    }
  }

  /// Opens the connection. Call [init] first.
  Future<void> connect() async {
    await methodChannel.invokeMethod('connect');
  }

  /// Closes the connection. Subscriptions are restored on the next [connect].
  Future<void> disconnect() async {
    await methodChannel.invokeMethod('disconnect');
  }

  /// Subscribes to [channelName] and returns a handle to the channel.
  ///
  /// The optional callbacks mirror the fields on [PusherChannel] and fire only
  /// for this channel, alongside the global callbacks passed to [init].
  Future<PusherChannel> subscribe(
      {required String channelName,
      var onSubscriptionSucceeded,
      var onSubscriptionError,
      var onMemberAdded,
      var onMemberRemoved,
      var onEvent,
      var onSubscriptionCount}) async {
    var channel = PusherChannel(
        channelName: channelName,
        onSubscriptionSucceeded: onSubscriptionSucceeded,
        onMemberAdded: onMemberAdded,
        onMemberRemoved: onMemberRemoved,
        onSubscriptionCount: onSubscriptionCount,
        onEvent: onEvent);
    await methodChannel.invokeMethod("subscribe", {"channelName": channelName});
    channels[channelName] = channel;
    return channel;
  }

  /// Unsubscribes from [channelName] and drops it from [channels].
  Future<void> unsubscribe({required String channelName}) async {
    channels.remove(channelName);
    await methodChannel
        .invokeMethod("unsubscribe", {"channelName": channelName});
  }

  /// Sends a client event.
  ///
  /// Throws unless [PusherEvent.channelName] is a private or presence channel,
  /// the only kinds that accept client events. [PusherEvent.eventName] must be
  /// prefixed with `client-`.
  Future<void> trigger(PusherEvent event) async {
    if (event.channelName.startsWith("private-") ||
        event.channelName.startsWith("presence-")) {
      await methodChannel.invokeMethod('trigger', {
        "channelName": event.channelName,
        "eventName": event.eventName,
        "data": event.data
      });
    } else {
      throw ('Trigger event is only for private/presence channels');
    }
  }

  /// Returns the id of the current connection, as required by authentication
  /// endpoints. Only meaningful once connected.
  Future<String> getSocketId() async {
    return (await methodChannel.invokeMethod('getSocketId')).toString();
  }

  /// Returns the subscribed channel named [channelName], or null if this
  /// client is not subscribed to it.
  PusherChannel? getChannel(String channelName) {
    return channels[channelName];
  }
}
