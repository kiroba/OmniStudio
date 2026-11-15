// Tests for the OmniStudio local API hook (lib/studio_api.dart).
// Uses dart:io HttpClient only — no extra test dependencies.

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:phaser_studio/studio_api.dart';

void main() {
  const String testToken = 'test-token-fixed';

  Map<String, Object?> stubProvider() {
    return <String, Object?>{
      'state': <String, Object?>{
        'activeTab': 2,
        'title': 'Stub Project',
        'modId': 'omnimod.stub.project',
        'isCompiled': false,
        'statusMessage': 'stub ready',
      },
      'library': <String, Object?>{
        'spritesheets': <Map<String, String>>[
          <String, String>{
            'key': 'player_run',
            'path': 'assets/sprites/player_runner.png',
            'dims': '64x64',
          },
        ],
        'tilemaps': <Map<String, String>>[],
        'audioBanks': <Map<String, String>>[],
      },
    };
  }

  late StudioApiServer server;

  setUp(() async {
    server = StudioApiServer(
      provider: stubProvider,
      token: testToken,
      port: 0, // ephemeral
      version: 'test-version',
    );
    final bool started = await server.start();
    expect(started, isTrue);
    expect(server.isRunning, isTrue);
    expect(server.port, greaterThan(0));
  });

  tearDown(() async {
    await server.stop();
  });

  Future<HttpClientResponse> get(String path, {bool withToken = true}) async {
    final HttpClient client = HttpClient();
    final HttpClientRequest request = await client.get(
      InternetAddress.loopbackIPv4.host,
      server.port,
      path,
    );
    if (withToken) {
      request.headers.set(
        HttpHeaders.authorizationHeader,
        'Bearer $testToken',
      );
    }
    final HttpClientResponse response = await request.close();
    client.close();
    return response;
  }

  Future<Map<String, dynamic>> bodyJson(HttpClientResponse response) async {
    final String text = await response.transform(utf8.decoder).join();
    return jsonDecode(text) as Map<String, dynamic>;
  }

  test('401 without token', () async {
    final HttpClientResponse response =
        await get('/api/v1/studio/health', withToken: false);
    expect(response.statusCode, HttpStatus.unauthorized);
    final Map<String, dynamic> body = await bodyJson(response);
    expect(body['error'], 'unauthorized');
  });

  test('401 with wrong token', () async {
    final HttpClient client = HttpClient();
    final HttpClientRequest request = await client.get(
      InternetAddress.loopbackIPv4.host,
      server.port,
      '/api/v1/studio/health',
    );
    request.headers.set(HttpHeaders.authorizationHeader, 'Bearer nope');
    final HttpClientResponse response = await request.close();
    client.close();
    expect(response.statusCode, HttpStatus.unauthorized);
    await bodyJson(response);
  });

  test('health 200 with expected fields', () async {
    final HttpClientResponse response = await get('/api/v1/studio/health');
    expect(response.statusCode, HttpStatus.ok);
    final Map<String, dynamic> body = await bodyJson(response);
    expect(body['app'], 'OmniStudio');
    expect(body['version'], 'test-version');
    expect(body['platform'], Platform.operatingSystem);
    expect(body['mode'], 'standalone');
    expect(body['port'], server.port);
    expect(body['uptimeSeconds'], isA<int>());
  });

  test('state 200 echoes stub provider state', () async {
    final HttpClientResponse response = await get('/api/v1/studio/state');
    expect(response.statusCode, HttpStatus.ok);
    final Map<String, dynamic> body = await bodyJson(response);
    final Map<String, dynamic> state =
        body['state'] as Map<String, dynamic>;
    expect(state['title'], 'Stub Project');
    expect(state['modId'], 'omnimod.stub.project');
    expect(state['activeTab'], 2);
  });

  test('library 200 echoes stub provider library', () async {
    final HttpClientResponse response = await get('/api/v1/studio/library');
    expect(response.statusCode, HttpStatus.ok);
    final Map<String, dynamic> body = await bodyJson(response);
    expect(body['source'], 'in-memory shell state');
    final Map<String, dynamic> library =
        body['library'] as Map<String, dynamic>;
    final List<dynamic> sprites =
        library['spritesheets'] as List<dynamic>;
    expect(sprites, hasLength(1));
    expect((sprites.first as Map<String, dynamic>)['key'], 'player_run');
  });

  test('unknown path 404', () async {
    final HttpClientResponse response = await get('/api/v1/studio/nope');
    expect(response.statusCode, HttpStatus.notFound);
    final Map<String, dynamic> body = await bodyJson(response);
    expect(body['error'], 'not_found');
  });

  test('non-GET 405', () async {
    final HttpClient client = HttpClient();
    final HttpClientRequest request = await client.post(
      InternetAddress.loopbackIPv4.host,
      server.port,
      '/api/v1/studio/health',
    );
    request.headers.set(
      HttpHeaders.authorizationHeader,
      'Bearer $testToken',
    );
    final HttpClientResponse response = await request.close();
    client.close();
    expect(response.statusCode, HttpStatus.methodNotAllowed);
    await bodyJson(response);
  });
}
