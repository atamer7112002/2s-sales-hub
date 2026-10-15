import 'package:flutter_test/flutter_test.dart';
import 'package:dio/dio.dart';
import 'package:xml/xml.dart';
import 'package:task_2s_egypt/core/network/odoo_api.dart';
import 'package:task_2s_egypt/features/customers/domain/customer.dart';

import 'dart:typed_data';

class FixtureAdapter implements HttpClientAdapter {
  FixtureAdapter(this.body);
  String body;
  RequestOptions? request;
  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    request = options;
    return ResponseBody.fromString(
      body,
      200,
      headers: {
        'content-type': ['text/xml'],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

String response(dynamic v) =>
    '<methodResponse><params><param>${XmlRpcOdooApi.value(v)}</param></params></methodResponse>';
void main() {
  late Dio dio;
  late FixtureAdapter adapter;
  late XmlRpcOdooApi api;
  final config = OdooConfig('https://example.com', 'demo');
  setUp(() {
    adapter = FixtureAdapter(response(7));
    dio = Dio()..httpClientAdapter = adapter;
    api = XmlRpcOdooApi(dio);
  });
  test('valid authentication and XML escaping', () async {
    expect(await api.authenticate(config, 'a&b', '<secret>'), 7);
    final doc = XmlDocument.parse(adapter.request!.data);
    expect(
      doc.findAllElements('string').map((v) => v.innerText),
      containsAll(['a&b', '<secret>']),
    );
    expect(adapter.request!.path, 'https://example.com/xmlrpc/2/common');
  });
  test('invalid credentials', () async {
    adapter.body = response(false);
    expect(
      () => api.authenticate(config, 'a', 'b'),
      throwsA(isA<AppFailure>()),
    );
  });
  test('RPC permission errors are sanitized', () async {
    adapter.body =
        '<methodResponse><fault>${XmlRpcOdooApi.value({'faultCode': 1, 'faultString': 'AccessError private traceback'})}</fault></methodResponse>';
    expect(
      () => api.authenticate(config, 'a', 'b'),
      throwsA(
        isA<AppFailure>().having(
          (e) => e.message,
          'message',
          isNot(contains('traceback')),
        ),
      ),
    );
  });
  test('array struct and false decoding', () {
    final v = [
      {
        'id': 1,
        'phone': false,
        'partner_id': [2, 'Name'],
      },
    ];
    expect(
      XmlRpcOdooApi.decode(
        XmlDocument.parse(XmlRpcOdooApi.value(v)).rootElement,
      ),
      v,
    );
  });
  test('customer handles false and many2one values', () {
    final c = Customer.fromOdoo({
      'id': 1,
      'name': 'A',
      'phone': false,
      'city': false,
      'country_id': [4, 'Egypt'],
    });
    expect(c.phone, '');
    expect(c.address, 'Egypt');
  });
  test('configuration requires HTTPS and no URL credentials', () {
    expect(
      () => OdooConfig('http://example.com', 'a'),
      throwsA(isA<AppFailure>()),
    );
    expect(
      () => OdooConfig('https://user:password@example.com', 'a'),
      throwsA(isA<AppFailure>()),
    );
  });
  test('Odoo numeric fault codes classify permission and expired authentication without tracebacks', () async {
    for (final entry in {
      4: FailureKind.permission,
      3: FailureKind.authentication,
      2: FailureKind.validation,
    }.entries) {
      adapter.body =
          '<methodResponse><fault>${XmlRpcOdooApi.value({'faultCode': entry.key, 'faultString': 'Localized message with no exception class'})}</fault></methodResponse>';
      await expectLater(
        () => api.authenticate(config, 'a', 'b'),
        throwsA(
          isA<AppFailure>().having((e) => e.kind, 'failure kind', entry.value),
        ),
      );
    }
  });
}
