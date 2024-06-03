import 'dart:async';
import 'dart:ffi';
import 'dart:io';
import 'dart:isolate';

import 'grades_native_fibonacci_bindings_generated.dart';

/// A very short-lived native function.
///
/// For very short-lived functions, it is fine to call them on the main isolate.
/// They will block the Dart execution while running the native function, so
/// only do this for native functions which are guaranteed to be short-lived.
int fib(int n) => _bindings.fib(n);

/// A longer lived native function, which occupies the thread calling it.
///
/// Do not call these kind of native functions in the main isolate. They will
/// block Dart execution. This will cause dropped frames in Flutter applications.
/// Instead, call these native functions on a separate isolate.
///
/// Modify this to suit your own use case. Example use cases:
///
/// 1. Reuse a single isolate for various different kinds of requests.
/// 2. Use multiple helper isolates for parallel execution.
Future<int> fibAsync(int n) async {
  final SendPort helperIsolateSendPort = await _helperIsolateSendPort;
  final int requestId = _nextFibRequestId++;
  final _FibRequest request = _FibRequest(requestId, n);
  final Completer<int> completer = Completer<int>();
  _fibRequests[requestId] = completer;
  helperIsolateSendPort.send(request);
  return completer.future;
}

const String _libName = 'grades_native_fibonacci';

/// The dynamic library in which the symbols for [GradesNativeFibonacciBindings] can be found.
final DynamicLibrary _dylib = () {
  if (Platform.isMacOS || Platform.isIOS) {
    return DynamicLibrary.open('$_libName.framework/$_libName');
  }
  if (Platform.isAndroid || Platform.isLinux) {
    return DynamicLibrary.open('lib$_libName.so');
  }
  if (Platform.isWindows) {
    return DynamicLibrary.open('$_libName.dll');
  }
  throw UnsupportedError('Unknown platform: ${Platform.operatingSystem}');
}();

/// The bindings to the native functions in [_dylib].
final GradesNativeFibonacciBindings _bindings = GradesNativeFibonacciBindings(_dylib);

/// A request to compute `fib`.
///
/// Typically sent from one isolate to another.
class _FibRequest {
  final int id;
  final int n;

  const _FibRequest(this.id, this.n);
}

/// A response with the result of `fib`.
///
/// Typically sent from one isolate to another.
class _FibResponse {
  final int id;
  final int result;

  const _FibResponse(this.id, this.result);
}

/// Counter to identify [_FibRequest]s and [_FibResponse]s.
int _nextFibRequestId = 0;

/// Mapping from [_FibRequest] `id`s to the completers corresponding to the correct future of the pending request.
final Map<int, Completer<int>> _fibRequests = <int, Completer<int>>{};

/// The SendPort belonging to the helper isolate.
Future<SendPort> _helperIsolateSendPort = () async {
  // The helper isolate is going to send us back a SendPort, which we want to
  // wait for.
  final Completer<SendPort> completer = Completer<SendPort>();

  // Receive port on the main isolate to receive messages from the helper.
  // We receive two types of messages:
  // 1. A port to send messages on.
  // 2. Responses to requests we sent.
  final ReceivePort receivePort = ReceivePort()
    ..listen((dynamic data) {
      if (data is SendPort) {
        // The helper isolate sent us the port on which we can sent it requests.
        completer.complete(data);
        return;
      }
      if (data is _FibResponse) {
        // The helper isolate sent us a response to a request we sent.
        final Completer<int> completer = _fibRequests[data.id]!;
        _fibRequests.remove(data.id);
        completer.complete(data.result);
        return;
      }
      throw UnsupportedError('Unsupported message type: ${data.runtimeType}');
    });

  // Start the helper isolate.
  await Isolate.spawn((SendPort sendPort) async {
    final ReceivePort helperReceivePort = ReceivePort()
      ..listen((dynamic data) {
        // On the helper isolate listen to requests and respond to them.
        if (data is _FibRequest) {
          final int result = _bindings.fib_long_running(data.n);
          final _FibResponse response = _FibResponse(data.id, result);
          sendPort.send(response);
          return;
        }
        throw UnsupportedError('Unsupported message type: ${data.runtimeType}');
      });

    // Send the port to the main isolate on which we can receive requests.
    sendPort.send(helperReceivePort.sendPort);
  }, receivePort.sendPort);

  // Wait until the helper isolate has sent us back the SendPort on which we
  // can start sending requests.
  return completer.future;
}();
