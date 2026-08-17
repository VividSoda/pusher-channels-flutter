/// The web implementation of this plugin, bridging the plugin's method
/// channel onto pusher-js.
///
/// Registered automatically on web builds; application code uses
/// `PusherChannelsFlutter` from `vs_pusher_channels_flutter.dart` instead.
library;

import 'dart:async';
import 'dart:js_interop';

// In order to *not* need this ignore, consider extracting the 'web' version
// of your plugin as a separate package, instead of inlining it in the same
// package as the core of your plugin.
// ignore: avoid_web_libraries_in_flutter
import 'package:flutter/services.dart';
import 'package:flutter_web_plugins/flutter_web_plugins.dart';
import 'package:vs_pusher_channels_flutter/src/pusher-js/core/auth/options.dart';
import 'package:vs_pusher_channels_flutter/src/pusher-js/core/channels/channel.dart';
import 'package:vs_pusher_channels_flutter/src/pusher-js/core/channels/presence_channel.dart';
import 'package:vs_pusher_channels_flutter/src/pusher-js/core/options.dart';
import 'package:vs_pusher_channels_flutter/src/pusher-js/core/pusher.dart';

/// A web implementation of the PusherChannelsFlutter plugin.
///
/// Backed by pusher-js through the `dart:js_interop` bindings in
/// `lib/src/pusher-js`. Registered automatically by Flutter's web plugin
/// registrar — application code should use `PusherChannelsFlutter` instead of
/// touching this class directly.
class PusherChannelsFlutterWeb {
  /// Creates the web implementation. Called by [registerWith]; application
  /// code should not need this.
  PusherChannelsFlutterWeb();

  /// The underlying pusher-js client, created by [init].
  Pusher? pusher;

  /// Channel carrying calls from the Dart-side `PusherChannelsFlutter`.
  MethodChannel? methodChannel;

  /// Registers this implementation with the Flutter web plugin [registrar].
  static void registerWith(Registrar registrar) {
    final pluginInstance = PusherChannelsFlutterWeb();
    pluginInstance.methodChannel = MethodChannel(
      'pusher_channels_flutter',
      const StandardMethodCodec(),
      registrar,
    );
    pluginInstance.methodChannel!
        .setMethodCallHandler(pluginInstance.handleMethodCall);
  }

  /// Dispatches a [MethodCall] from the Dart side to pusher-js.
  ///
  /// Throws a [PlatformException] for methods the web implementation does not
  /// support.
  Future<dynamic> handleMethodCall(MethodCall call) async {
    switch (call.method) {
      case 'init':
        init(call);
        break;
      case 'connect':
        assertPusher();
        pusher!.connect();
        break;
      case 'disconnect':
        assertPusher();
        pusher!.disconnect();
        break;
      case 'subscribe':
        subscribe(call);
        break;
      case 'unsubscribe':
        unsubscribe(call);
        break;
      case 'trigger':
        trigger(call);
        break;
      case 'getSocketId':
        return pusher!.connection.socket_id;
      default:
        throw PlatformException(
          code: 'Unimplemented',
          details:
              'pusher_channels for web doesn\'t implement \'${call.method}\'',
        );
    }
  }

  /// Throws an [ArgumentError] if [init] has not run yet, so that calls made
  /// before `init()` surface as an error instead of a null dereference.
  void assertPusher() {
    if (pusher == null) {
      throw ArgumentError.notNull('Pusher not initialized');
    }
  }

  /// Deeply converts a JS value into plain Dart Maps/Lists/primitives.
  /// `dart:js_interop`'s built-in [JSAnyUtilityExtension.dartify] already
  /// does this recursively, so this just narrows the result to a Map.
  Map<String, dynamic> _dartifyMap(JSAny? jsObject) {
    final dartified = jsObject?.dartify();
    if (dartified is Map) {
      return Map<String, dynamic>.from(dartified);
    }
    return <String, dynamic>{};
  }

  /// Forwards a pusher-js `error` event to the Dart side.
  void onError(JSAny? jsError) {
    final error = _dartifyMap(jsError);

    if (error['type'] == 'PusherError') {
      methodChannel!.invokeMethod('onError', {
        'message': error['data']?['message'],
        'code': error['data']?['code'],
        'error': error,
      });
    }
  }

  /// Forwards a pusher-js `message` event to the Dart side, splitting the
  /// internal presence events out into member-added/-removed calls.
  void onMessage(JSAny? jsMessage) {
    final msg = _dartifyMap(jsMessage);
    final String event = msg['event'] ?? '';
    final String channel = msg['channel'] ?? '';
    final Map<String, dynamic> data = msg['data'] ?? {};
    String? userId = data['user_id'];
    final Map<String, dynamic>? userInfo = data['user_info'];

    if (event == 'pusher_internal:subscription_error') {
      methodChannel!.invokeMethod(
          'onSubscriptionError', {'message': msg['error'], 'error': data});
    } else if (event == 'pusher_internal:member_added') {
      methodChannel!.invokeMethod('onMemberAdded', {
        'channelName': channel,
        'user': {
          'userId': userId,
          'userInfo': userInfo,
        }
      });
    } else if (event == 'pusher_internal:member_removed') {
      methodChannel!.invokeMethod('onMemberRemoved', {
        'channelName': channel,
        'user': {
          'userId': userId,
          'userInfo': userInfo,
        }
      });
    } else {
      if (event == 'pusher_internal:subscription_succeeded') {
        if (channel.startsWith('presence-')) {
          final presenceChannel = pusher!.channel(channel) as PresenceChannel;
          userId = presenceChannel.members.myID?.dartify() as String?;
        }
      }
      methodChannel!.invokeMethod('onEvent', {
        'channelName': channel,
        'eventName': event,
        'data': data,
        'userId': userId,
      });
    }
  }

  /// Forwards a pusher-js `state_change` event to the Dart side.
  void onStateChange(JSAny? jsState) {
    final state = _dartifyMap(jsState);
    final String current = state['current'] ?? '';
    final String previous = state['previous'] ?? '';
    methodChannel!.invokeMethod('onConnectionStateChange', {
      'currentState': current,
      'previousState': previous,
    });
  }

  /// Handles the pusher-js `connected` event. The state transition is already
  /// reported through [onStateChange], so nothing more is needed here.
  void onConnected(JSAny? jsMessage) {}

  /// Handles the pusher-js `disconnected` event. As with [onConnected], the
  /// transition is already reported through [onStateChange].
  void onDisconnected() {}

  /// Builds the pusher-js authorizer that delegates to the Dart-side
  /// `onAuthorizer` callback for [channel].
  Authorizer onAuthorizer(Channel channel, AuthorizerOptions options) {
    void authorize(String socketId, JSFunction callback) async {
      try {
        var authData = await methodChannel!.invokeMethod('onAuthorizer', {
          'socketId': socketId,
          'channelName': channel.name,
          'options': options.toMap(),
        });
        callback.callAsFunction(
            null,
            null,
            AuthData(
              auth: authData['auth'],
              channel_data: authData['channel_data'],
              shared_secret: authData['shared_secret'],
            ));
      } catch (e) {
        callback.callAsFunction(null, e.toString().toJS, AuthData(auth: ''));
      }
    }

    return Authorizer(authorize: authorize.toJS);
  }

  /// Subscribes to the channel named in [call].
  void subscribe(MethodCall call) {
    assertPusher();
    var channelName = call.arguments['channelName'];
    pusher!.subscribe(channelName);
  }

  /// Unsubscribes from the channel named in [call] and drops its bindings.
  void unsubscribe(MethodCall call) {
    var channelName = call.arguments['channelName'];
    var channel = pusher!.channel(channelName);
    pusher!.unsubscribe(channelName);
    channel?.unbind_all();
  }

  /// Triggers the client event described by [call] on its channel.
  void trigger(MethodCall call) {
    var channelName = call.arguments['channelName'];
    var channel = pusher!.channel(channelName);
    channel?.trigger(call.arguments['eventName'],
        (call.arguments['data'] as Object?).jsify());
  }

  /// Creates the pusher-js client from the options in [call] and binds the
  /// connection events. Tears down a previous client first, so that `init()`
  /// can be called more than once.
  void init(MethodCall call) {
    if (pusher != null) {
      pusher!.unbind_all();
      pusher!.disconnect();
    }
    var options = Options();
    if (call.arguments['cluster'] != null) {
      options.cluster = call.arguments['cluster'];
    }
    if (call.arguments['host'] != null) {
      options.wsHost = call.arguments['host'];
    }
    if (call.arguments['wsPort'] != null) {
      options.wsPort = call.arguments['wsPort'];
    }
    if (call.arguments['wssPort'] != null) {
      options.wssPort = call.arguments['wssPort'];
    }
    if (call.arguments['forceTLS'] != null) {
      options.forceTLS = call.arguments['forceTLS'];
    }
    if (call.arguments['pongTimeout'] != null) {
      options.pongTimeout = call.arguments['pongTimeout'];
    }
    if (call.arguments['enableStats'] != null) {
      options.enableStats = call.arguments['enableStats'];
    }
    if (call.arguments['disabledTransports'] != null) {
      options.disabledTransports =
          (call.arguments['disabledTransports'] as Object?).jsify()
              as JSArray<JSString>;
    }
    if (call.arguments['enabledTransports'] != null) {
      options.enabledTransports =
          (call.arguments['enabledTransports'] as Object?).jsify()
              as JSArray<JSString>;
    }
    if (call.arguments['ignoreNullOrigin'] != null) {
      options.ignoreNullOrigin = call.arguments['ignoreNullOrigin'];
    }
    if (call.arguments['authTransport'] != null) {
      options.authTransport = call.arguments['authTransport'];
    }
    if (call.arguments['authEndpoint'] != null) {
      options.authEndpoint = call.arguments['authEndpoint'];
    }
    if (call.arguments['authParams'] != null) {
      options.auth =
          (call.arguments['authParams'] as Object?).jsify() as AuthOptions;
    }
    if (call.arguments['logToConsole'] != null) {
      Pusher.logToConsole = call.arguments['logToConsole'];
    }
    if (call.arguments['authorizer'] != null) {
      options.authorizer = onAuthorizer.toJS;
    }
    pusher = Pusher(call.arguments['apiKey'], options);
    pusher!.connection.bind('error', onError.toJS);
    pusher!.connection.bind('message', onMessage.toJS);
    pusher!.connection.bind('state_change', onStateChange.toJS);
    pusher!.connection.bind('connected', onConnected.toJS);
    pusher!.connection.bind('disconnected', onDisconnected.toJS);
  }
}
