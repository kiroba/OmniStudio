// ============================================================================
// OmniStudio Local API Hook — read-only, loopback only (spec 2026-11-15).
//
// A small HTTP server inside the OmniStudio desktop app that exposes the
// app's live state to an authorized local caller (George, or any tool the
// owner authorizes). Rules from the spec:
//   * Loopback only: binds 127.0.0.1, never 0.0.0.0. Port 9200 by default
//     (the port the Manifest & Security screen already advertises).
//   * Auth: every route requires `Authorization: Bearer <token>`. The token
//     is per-run, generated with Random.secure unless one is supplied
//     (tests supply a fixed one), and exposed via [StudioApiServer.token]
//     so the app can surface it (UI / local token file). It is never
//     relayed and never written to a log.
//   * Read-only v1: GET only. Non-GET -> 405. Unknown path -> 404 JSON.
//     Missing/wrong token -> 401 JSON.
//   * The hook never gates the app: if the bind fails, start() returns
//     false, the server marks itself unavailable, and the app runs on.
//   * No request logging (Mesh-Monitor protocol: no logs with PII).
//   * Stack law: dart:io / dart:convert / dart:math only. No packages.
//
// Snapshot contract: the provider returns one map shaped as
//   { 'state': { ...shell state... }, 'library': { ...asset mappings... } }
// GET /api/v1/studio/state   -> { 'state':   <provider()['state']> }
// GET /api/v1/studio/library -> { 'library': <provider()['library']>,
//                                 'source': 'in-memory shell state' }
// GET /api/v1/studio/health  -> server-generated, provider-independent.
// ============================================================================

import 'dart:convert';
import 'dart:io';
import 'dart:math';

/// Supplies the app's live snapshot: a map with 'state' and 'library' keys.
typedef StudioSnapshotProvider = Map<String, Object?> Function();

class StudioApiServer {
  StudioApiServer({
    required StudioSnapshotProvider provider,
    String? token,
    int port = 9200,
    String version = 'unknown',
  })  : _provider = provider,
        _token = token ?? _generateToken(),
        _requestedPort = port,
        _version = version;

  final StudioSnapshotProvider _provider;
  final String _token;
  final int _requestedPort;
  final String _version;

  HttpServer? _server;
  DateTime? _startedAt;
  bool _unavailable = false;

  /// The per-run Bearer token callers must present.
  String get token => _token;

  /// The port the server is actually bound to (differs from the requested
  /// port when port 0 was requested, e.g. in tests). Before a successful
  /// start, returns the requested port.
  int get port => _server?.port ?? _requestedPort;

  bool get isRunning => _server != null;
  bool get isUnavailable => _unavailable;

  static String _generateToken() {
    final Random rng = Random.secure();
    final List<int> bytes = List<int>.generate(24, (_) => rng.nextInt(256));
    return bytes.map((int b) => b.toRadixString(16).padLeft(2, '0')).join();
  }

  /// Binds on loopback and starts serving. Returns true on success; on any
  /// bind failure marks the server unavailable and returns false — never
  /// throws into the app.
  Future<bool> start() async {
    if (_server != null) return true;
    try {
      _server = await HttpServer.bind(
        InternetAddress.loopbackIPv4,
        _requestedPort,
      );
      _startedAt = DateTime.now();
      _unavailable = false;
      _server!.listen(_handleRequest);
      return true;
    } catch (_) {
      _unavailable = true;
      _server = null;
      return false;
    }
  }

  Future<void> stop() async {
    final HttpServer? server = _server;
    _server = null;
    _startedAt = null;
    if (server != null) {
      await server.close(force: true);
    }
  }

  int get _uptimeSeconds {
    final DateTime? started = _startedAt;
    if (started == null) return 0;
    return DateTime.now().difference(started).inSeconds;
  }

  Future<void> _handleRequest(HttpRequest request) async {
    if (request.method != 'GET') {
      _sendJson(request, HttpStatus.methodNotAllowed, <String, Object?>{
        'error': 'method_not_allowed',
      });
      return;
    }
    if (request.headers.value(HttpHeaders.authorizationHeader) !=
        'Bearer $_token') {
      _sendJson(request, HttpStatus.unauthorized, <String, Object?>{
        'error': 'unauthorized',
      });
      return;
    }
    switch (request.uri.path) {
      case '/api/v1/studio/health':
        _sendJson(request, HttpStatus.ok, <String, Object?>{
          'app': 'OmniStudio',
          'version': _version,
          'platform': Platform.operatingSystem,
          'mode': 'standalone',
          'port': port,
          'uptimeSeconds': _uptimeSeconds,
        });
      case '/api/v1/studio/state':
        _sendSnapshot(request, 'state');
      case '/api/v1/studio/library':
        _sendSnapshot(request, 'library');
      default:
        _sendJson(request, HttpStatus.notFound, <String, Object?>{
          'error': 'not_found',
          'path': request.uri.path,
        });
    }
  }

  void _sendSnapshot(HttpRequest request, String section) {
    final Map<String, Object?> snapshot;
    try {
      snapshot = _provider();
    } catch (_) {
      _sendJson(request, HttpStatus.internalServerError, <String, Object?>{
        'error': 'snapshot_failed',
      });
      return;
    }
    final Map<String, Object?> body = <String, Object?>{
      section: snapshot[section] ?? <String, Object?>{},
    };
    if (section == 'library') {
      // Honest label (spec): v1 serves what the app holds in memory, not a
      // repo-side pack scan of assets/incoming or assets/compiled.
      body['source'] = 'in-memory shell state';
    }
    _sendJson(request, HttpStatus.ok, body);
  }

  void _sendJson(HttpRequest request, int status, Map<String, Object?> body) {
    final HttpResponse response = request.response;
    response.statusCode = status;
    response.headers.contentType = ContentType.json;
    response.write(jsonEncode(body));
    response.close();
  }
}
