import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:myune_music/page/network/google_drive_pairing.dart';

Future<int> submit(HttpClient client, DrivePairingServer server) async {
  final uri = Uri.parse(server.url).replace(path: '/submit', query: '');
  final request = await client.postUrl(uri);
  request.headers.contentType = ContentType.json;
  request.write(jsonEncode({
    'pair': server.pair, 'name': 'fixture', 'clientId': 'fixture-client',
    'refreshToken': 'fixture-token',
  }));
  final response = await request.close();
  await response.drain<void>();
  return response.statusCode;
}

void main() {
  test('pairing submission serializes probes and unlocks failed requests', () async {
    var calls = 0;
    final entered = Completer<void>();
    final first = Completer<String?>();
    final server = DrivePairingServer(onSubmit: (_) async {
      calls++;
      if (calls == 1) {
        entered.complete();
        return first.future;
      }
      return null;
    });
    await server.start(bindAddress: InternetAddress.loopbackIPv4, port: 0);
    final client = HttpClient();
    addTearDown(() async { client.close(force: true); await server.stop(); });
    final pending = submit(client, server);
    await entered.future;
    expect(await submit(client, server), HttpStatus.conflict);
    expect(calls, 1);
    first.complete('fixture validation failed');
    expect(await pending, HttpStatus.badRequest);
    expect(await submit(client, server), HttpStatus.ok);
    expect(calls, 2);
    expect(await submit(client, server), HttpStatus.gone);
    expect(calls, 2);
  });

  test('a thrown pairing probe releases its busy lock', () async {
    var calls = 0;
    final server = DrivePairingServer(onSubmit: (_) async {
      if (++calls == 1) throw StateError('fixture failure');
      return null;
    });
    await server.start(bindAddress: InternetAddress.loopbackIPv4, port: 0);
    final client = HttpClient();
    addTearDown(() async { client.close(force: true); await server.stop(); });
    expect(await submit(client, server), HttpStatus.internalServerError);
    expect(await submit(client, server), HttpStatus.ok);
    expect(calls, 2);
  });
}
