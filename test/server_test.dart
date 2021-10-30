/*
 * Copyright (C) 2017 Miguel Castiblanco
 *
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 * http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 */

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:mock_web_server/mock_web_server.dart';
import 'package:test/test.dart';

late MockWebServer _server;

void main() {
  setUp(() {
    _server = MockWebServer();
    _server.start();
  });

  tearDown(() {
    _server.shutdown();
  });

  test("Set response code", () async {
    _server.enqueue(httpCode: 401);
    final response = await _get("");
    expect(response.statusCode, 401);
  });

  test("Set body", () async {
    _server.enqueue(body: "something");
    final response = await _get("");
    expect(await _read(response), "something");
  });

  test("Set body stream", () async {
    final f = File('../mock-web-server/test/test.jpg');
    _server.enqueue(body: f.openRead());
    final response = await _get("");
    expect(await _readStream(response), f.readAsBytesSync());
  });

  test("Set headers", () async {
    final headers = Map<String, String>();
    headers["X-Server"] = "MockDart";

    _server.enqueue(body: "Created", httpCode: 201, headers: headers);
    final response = await _get("");
    expect(response.statusCode, 201);
    expect(response.headers.value("X-Server"), "MockDart");
    expect(await _read(response), "Created");
  });

  test("Set body and response code", () async {
    _server.enqueue(body: "Created", httpCode: 201);
    final response = await _get("");
    expect(response.statusCode, 201);
    expect(await _read(response), "Created");
  });

  test("Set body, response code, and headers", () async {
    final headers = Map<String, String>();
    headers["X-Server"] = "MockDart";

    _server.enqueue(body: "Created", httpCode: 201, headers: headers);
    final response = await _get("");
    expect(response.statusCode, 201);
    expect(response.headers.value("X-Server"), "MockDart");
    expect(await _read(response), "Created");
  });

  test("Queue", () async {
    _server.enqueue(body: "hello");
    _server.enqueue(body: "world");
    final response1 = await _get("");
    expect(await _read(response1), "hello");

    final response2 = await _get("");
    expect(await _read(response2), "world");
  });

  test("Take requests & request count", () async {
    _server.enqueue(body: "a");
    _server.enqueue(body: "b");
    _server.enqueue(body: "c");
    await _get("first");
    await _get("second");
    await _get("third");

    expect(_server.takeRequest().uri.path, "/first");
    expect(_server.takeRequest().uri.path, "/second");
    expect(_server.takeRequest().uri.path, "/third");
    expect(_server.requestCount, 3);
  });

  test("Request count", () async {
    _server.enqueue(httpCode: HttpStatus.unauthorized);

    await _get("first");

    expect(_server.takeRequest().uri.path, "/first");
    expect(_server.requestCount, 1);
  });

  test("Dispatcher", () async {
    final dispatcher = (HttpRequest request) async {
      if (request.uri.path == "/users") {
        return MockResponse()
          ..httpCode = 200
          ..body = "working";
      } else if (request.uri.path == "/users/1") {
        return MockResponse()..httpCode = 201;
      } else if (request.uri.path == "/delay") {
        return MockResponse()
          ..httpCode = 200
          ..delay = Duration(milliseconds: 1500);
      }

      return MockResponse()..httpCode = 404;
    };

    _server.dispatcher = dispatcher;

    final response1 = await _get("unknown");
    expect(response1.statusCode, 404);

    final response2 = await _get("users");
    expect(response2.statusCode, 200);
    expect(await _read(response2), "working");

    final response3 = await _get("users/1");
    expect(response3.statusCode, 201);

    final stopwatch = Stopwatch()..start();
    final response4 = await _get("delay");
    stopwatch.stop();
    expect(
      stopwatch.elapsed.inMilliseconds,
      greaterThanOrEqualTo(Duration(milliseconds: 1500).inMilliseconds),
    );
    expect(response4.statusCode, 200);
  });

  test("Enqueue MockResponse", () async {
    final headers = Map<String, String>();
    headers["X-Server"] = "MockDart";

    final mockResponse = MockResponse()
      ..httpCode = 201
      ..body = "Created"
      ..headers = headers;

    _server.enqueueResponse(mockResponse);
    final response = await _get("");
    expect(response.statusCode, 201);
    expect(response.headers.value("X-Server"), "MockDart");
    expect(await _read(response), "Created");
  });

  test("Delay", () async {
    _server.enqueue(delay: Duration(seconds: 2), httpCode: 201);
    final stopwatch = Stopwatch()..start();
    final response = await _get("");

    stopwatch.stop();
    expect(
      stopwatch.elapsed.inMilliseconds,
      greaterThanOrEqualTo(Duration(seconds: 2).inMilliseconds),
    );
    expect(response.statusCode, 201);
  });

  test('Parallel delay', () async {
    final body70 = "70 milliseconds";
    final body40 = "40 milliseconds";
    final body20 = "20 milliseconds";
    _server.enqueue(delay: Duration(milliseconds: 40), body: body40);
    _server.enqueue(delay: Duration(milliseconds: 70), body: body70);
    _server.enqueue(delay: Duration(milliseconds: 20), body: body20);

    final completer = Completer();
    final responses = <String>[];

    _get("").then((res) async {
      // 40 milliseconds
      final result = await _read(res);
      responses.add(result);
    });

    _get("").then((res) async {
      // 70 milliseconds
      final result = await _read(res);
      responses.add(result);

      // complete on the longer operation
      completer.complete();
    });

    _get("").then((res) async {
      // 20 milliseconds
      final result = await _read(res);
      responses.add(result);
    });

    await completer.future;

    // validate that the responses happened in order 20, 40, 70
    expect(responses[0], body20);
    expect(responses[1], body40);
    expect(responses[2], body70);
  });

  test("Request specific port IPv4", () async {
    final _server = MockWebServer(port: 8029);
    await _server.start();

    final url = RegExp(r'(?:http[s]?:\/\/(?:127\.0\.0\.1):8029\/)');
    final host = RegExp(r'(?:127\.0\.0\.1)');

    expect(url.hasMatch(_server.url), true);
    expect(host.hasMatch(_server.host), true);
    expect(_server.port, 8029);

    _server.shutdown();
  });

  test("Request specific port IPv6", () async {
    final _server = MockWebServer(
      port: 8030,
      addressType: InternetAddressType.IPv6,
    );
    await _server.start();

    final url = RegExp(r'(?:http[s]?:\/\/(?:::1):8030\/)');
    final host = RegExp(r'(?:::1)');

    expect(url.hasMatch(_server.url), true);
    expect(host.hasMatch(_server.host), true);
    expect(_server.port, 8030);

    _server.shutdown();
  });

  test("TLS info", () async {
    final _server = MockWebServer(
      port: 8029,
      certificate: Certificate.included(),
    );
    await _server.start();

    final url = RegExp(r'(?:https:\/\/(?:127\.0\.0\.1):8029\/)');
    final host = RegExp(r'(?:127\.0\.0\.1)');

    expect(url.hasMatch(_server.url), true);
    expect(host.hasMatch(_server.host), true);
    expect(_server.port, 8029);

    _server.shutdown();
  });

  test("TLS cert", () async {
    final body = "S03E08 You Are Not Safe";

    final _server = MockWebServer(
      port: 8029,
      certificate: Certificate.included(),
    );
    await _server.start();
    _server.enqueue(body: body);

    // Calling without the proper security context
    final clientErr = HttpClient();

    expect(
      clientErr.getUrl(Uri.parse(_server.url)),
      throwsA(TypeMatcher<HandshakeException>()),
    );

    // Testing with security context
    final client = HttpClient(context: SecurityContext().defaultContext);
    final request = await client.getUrl(Uri.parse(_server.url));
    final response = await _read(await request.close());

    expect(response, body);

    _server.shutdown();
  });

  test("Check take request", () async {
    _server.enqueue();

    final client = HttpClient();
    final request = await client.post(
      _server.host,
      _server.port,
      "test",
    );
    request.headers.add("x-header", "nosniff");
    request.write("sample body");

    await request.close();
    final storedRequest = _server.takeRequest();

    expect(storedRequest.method, "POST");
    expect(storedRequest.body, "sample body");
    expect(storedRequest.uri.path, "/test");
    expect(storedRequest.headers['x-header'], "nosniff");
  });

  test("default response", () async {
    _server.defaultResponse = MockResponse()..httpCode = 404;

    final response = await _get("");
    expect(response.statusCode, 404);
  });
}

Future<HttpClientResponse> _get(String path) async {
  final client = HttpClient();
  final request = await client.get(
    _server.host,
    _server.port,
    path,
  );
  return await request.close();
}

Future<String> _read(HttpClientResponse response) async {
  final body = StringBuffer();
  final completer = Completer<String>();

  response.transform(utf8.decoder).listen((data) {
    body.write(data);
  }, onDone: () {
    completer.complete(body.toString());
  });

  await completer.future;
  return body.toString();
}

Future<List<int>> _readStream(HttpClientResponse response) async {
  final body = <int>[];
  final completer = Completer<List<int>>();

  response.listen((event) {
    body.addAll(event);
  }, onDone: () {
    completer.complete(body);
  });

  await completer.future;
  return body;
}
