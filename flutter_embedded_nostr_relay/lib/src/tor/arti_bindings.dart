// ABOUTME: Dart FFI bindings for Arti Tor client library
// ABOUTME: Provides low-level interface to native Arti functions through FFI

import 'dart:ffi';
import 'dart:io';
import 'dart:typed_data';
import 'package:ffi/ffi.dart';

/// Opaque type for Arti client
final class ArtiTorClient extends Opaque {}

/// FFI function signatures for Arti library
typedef ArtiClientCreateNative = Pointer<ArtiTorClient> Function(
  Pointer<Utf8> configJson,
  Pointer<Utf8> stateDir,
  Pointer<Utf8> cacheDir,
);
typedef ArtiClientCreate = Pointer<ArtiTorClient> Function(
  Pointer<Utf8> configJson,
  Pointer<Utf8> stateDir,
  Pointer<Utf8> cacheDir,
);

typedef ArtiClientBootstrapNative = Int32 Function(Pointer<ArtiTorClient>);
typedef ArtiClientBootstrap = int Function(Pointer<ArtiTorClient>);

typedef ArtiClientConnectNative = Uint64 Function(
  Pointer<ArtiTorClient>,
  Pointer<Utf8> host,
  Uint16 port,
);
typedef ArtiClientConnect = int Function(
  Pointer<ArtiTorClient>,
  Pointer<Utf8> host,
  int port,
);

typedef ArtiConnectionReadNative = Int32 Function(
  Pointer<ArtiTorClient>,
  Uint64 connId,
  Pointer<Uint8> buffer,
  Size bufferLen,
);
typedef ArtiConnectionRead = int Function(
  Pointer<ArtiTorClient>,
  int connId,
  Pointer<Uint8> buffer,
  int bufferLen,
);

typedef ArtiConnectionWriteNative = Int32 Function(
  Pointer<ArtiTorClient>,
  Uint64 connId,
  Pointer<Uint8> data,
  Size dataLen,
);
typedef ArtiConnectionWrite = int Function(
  Pointer<ArtiTorClient>,
  int connId,
  Pointer<Uint8> data,
  int dataLen,
);

typedef ArtiConnectionCloseNative = Int32 Function(
  Pointer<ArtiTorClient>,
  Uint64 connId,
);
typedef ArtiConnectionClose = int Function(
  Pointer<ArtiTorClient>,
  int connId,
);

typedef ArtiClientDestroyNative = Void Function(Pointer<ArtiTorClient>);
typedef ArtiClientDestroy = void Function(Pointer<ArtiTorClient>);

typedef ArtiGetVersionNative = Pointer<Utf8> Function();
typedef ArtiGetVersion = Pointer<Utf8> Function();

/// Dart bindings for Arti FFI library
class ArtiBindings {
  late final DynamicLibrary _lib;
  late final ArtiClientCreate _create;
  late final ArtiClientBootstrap _bootstrap;
  late final ArtiClientConnect _connect;
  late final ArtiConnectionRead _read;
  late final ArtiConnectionWrite _write;
  late final ArtiConnectionClose _close;
  late final ArtiClientDestroy _destroy;
  late final ArtiGetVersion _getVersion;
  
  static ArtiBindings? _instance;
  
  /// Singleton factory constructor
  factory ArtiBindings() {
    _instance ??= ArtiBindings._internal();
    return _instance!;
  }
  
  /// Private constructor that loads the library and binds functions
  ArtiBindings._internal() {
    _lib = _loadLibrary();
    _bindFunctions();
  }
  
  /// Load the platform-specific Arti library
  DynamicLibrary _loadLibrary() {
    try {
      if (Platform.isAndroid) {
        return DynamicLibrary.open('libarti_ffi.so');
      } else if (Platform.isIOS) {
        return DynamicLibrary.process();
      } else if (Platform.isMacOS) {
        return DynamicLibrary.open('libarti_ffi.dylib');
      } else if (Platform.isWindows) {
        return DynamicLibrary.open('arti_ffi.dll');
      } else if (Platform.isLinux) {
        return DynamicLibrary.open('libarti_ffi.so');
      } else {
        throw UnsupportedError('Platform ${Platform.operatingSystem} not supported');
      }
    } catch (e) {
      throw Exception('Failed to load Arti library: $e');
    }
  }
  
  /// Bind all FFI functions from the loaded library
  void _bindFunctions() {
    _create = _lib.lookupFunction<ArtiClientCreateNative, ArtiClientCreate>(
      'arti_client_create',
    );
    _bootstrap = _lib.lookupFunction<ArtiClientBootstrapNative, ArtiClientBootstrap>(
      'arti_client_bootstrap',
    );
    _connect = _lib.lookupFunction<ArtiClientConnectNative, ArtiClientConnect>(
      'arti_client_connect',
    );
    _read = _lib.lookupFunction<ArtiConnectionReadNative, ArtiConnectionRead>(
      'arti_connection_read',
    );
    _write = _lib.lookupFunction<ArtiConnectionWriteNative, ArtiConnectionWrite>(
      'arti_connection_write',
    );
    _close = _lib.lookupFunction<ArtiConnectionCloseNative, ArtiConnectionClose>(
      'arti_connection_close',
    );
    _destroy = _lib.lookupFunction<ArtiClientDestroyNative, ArtiClientDestroy>(
      'arti_client_destroy',
    );
    _getVersion = _lib.lookupFunction<ArtiGetVersionNative, ArtiGetVersion>(
      'arti_get_version',
    );
  }
  
  /// Create a new Arti client
  Pointer<ArtiTorClient> createClient(
    String configJson,
    String stateDir,
    String cacheDir,
  ) {
    final configPtr = configJson.toNativeUtf8();
    final statePtr = stateDir.toNativeUtf8();
    final cachePtr = cacheDir.toNativeUtf8();
    
    try {
      final client = _create(configPtr, statePtr, cachePtr);
      if (client == nullptr) {
        throw Exception('Failed to create Arti client');
      }
      return client;
    } finally {
      malloc.free(configPtr);
      malloc.free(statePtr);
      malloc.free(cachePtr);
    }
  }
  
  /// Bootstrap the Tor client
  int bootstrap(Pointer<ArtiTorClient> client) {
    return _bootstrap(client);
  }
  
  /// Connect to a host through Tor
  int connect(Pointer<ArtiTorClient> client, String host, int port) {
    final hostPtr = host.toNativeUtf8();
    try {
      return _connect(client, hostPtr, port);
    } finally {
      malloc.free(hostPtr);
    }
  }
  
  /// Read data from a Tor connection
  int connectionRead(
    Pointer<ArtiTorClient> client,
    int connId,
    Uint8List buffer,
  ) {
    final bufferPtr = malloc<Uint8>(buffer.length);
    try {
      final bytesRead = _read(client, connId, bufferPtr, buffer.length);
      if (bytesRead > 0) {
        // Copy data from native buffer to Dart buffer
        final nativeList = bufferPtr.asTypedList(bytesRead);
        buffer.setRange(0, bytesRead, nativeList);
      }
      return bytesRead;
    } finally {
      malloc.free(bufferPtr);
    }
  }
  
  /// Write data to a Tor connection
  int connectionWrite(
    Pointer<ArtiTorClient> client,
    int connId,
    Uint8List data,
  ) {
    final dataPtr = malloc<Uint8>(data.length);
    try {
      // Copy Dart data to native buffer
      final nativeList = dataPtr.asTypedList(data.length);
      nativeList.setRange(0, data.length, data);
      
      return _write(client, connId, dataPtr, data.length);
    } finally {
      malloc.free(dataPtr);
    }
  }
  
  /// Close a Tor connection
  int connectionClose(Pointer<ArtiTorClient> client, int connId) {
    return _close(client, connId);
  }
  
  /// Destroy the Arti client and free resources
  void destroyClient(Pointer<ArtiTorClient> client) {
    _destroy(client);
  }
  
  /// Get the Arti library version
  String getVersion() {
    final versionPtr = _getVersion();
    return versionPtr.toDartString();
  }
  
  /// Check if the library is properly loaded
  bool get isLoaded => _lib.handle != nullptr;
}