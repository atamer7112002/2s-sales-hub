import 'package:dio/dio.dart';
import 'package:xml/xml.dart';

enum FailureKind {
  general,
  authentication,
  permission,
  validation,
  conflict,
  server,
}

class AppFailure implements Exception {
  const AppFailure(
    this.message, {
    this.offline = false,
    this.kind = FailureKind.general,
  });
  final String message;
  final bool offline;
  final FailureKind kind;
  bool get retryable => offline || kind == FailureKind.server;
  @override
  String toString() => message;
}

class OdooConfig {
  OdooConfig(String server, this.database)
    : server = server.replaceAll(RegExp(r'/+$'), '') {
    final uri = Uri.tryParse(this.server);
    if (uri == null ||
        uri.scheme != 'https' ||
        uri.host.isEmpty ||
        uri.userInfo.isNotEmpty ||
        uri.hasQuery ||
        uri.hasFragment ||
        (uri.path.isNotEmpty && uri.path != '/')) {
      throw const AppFailure(
        'Enter an HTTPS server origin, such as https://demo.example.com.',
      );
    }
    if (database.trim().isEmpty) {
      throw const AppFailure('Enter the database name.');
    }
  }
  final String server, database;
}

abstract interface class OdooApi {
  Future<int> authenticate(OdooConfig config, String username, String password);
  Future<dynamic> execute(
    OdooConfig config,
    int uid,
    String password,
    String model,
    String method,
    List<dynamic> args, [
    Map<String, dynamic> kwargs = const {},
  ]);
}

/// XML-RPC is isolated here so a future JSON-2/gateway adapter can replace it.
class XmlRpcOdooApi implements OdooApi {
  XmlRpcOdooApi(this.dio);
  final Dio dio;
  static String value(dynamic v) {
    if (v is bool) {
      return '<value><boolean>${v ? 1 : 0}</boolean></value>';
    }
    if (v is int) {
      return '<value><int>$v</int></value>';
    }
    if (v is num) {
      return '<value><double>$v</double></value>';
    }
    if (v is List) {
      return '<value><array><data>${v.map(value).join()}</data></array></value>';
    }
    if (v is Map) {
      return '<value><struct>${v.entries.map((e) => '<member><name>${XmlText(e.key.toString()).toXmlString()}</name>${value(e.value)}</member>').join()}</struct></value>';
    }
    return '<value><string>${XmlText(v?.toString() ?? '').toXmlString()}</string></value>';
  }

  static dynamic decode(XmlElement v) {
    final e = v.childElements.firstOrNull;
    if (e == null) {
      return v.innerText;
    }
    switch (e.name.local) {
      case 'int':
      case 'i4':
      case 'i8':
        return int.parse(e.innerText);
      case 'double':
        return double.parse(e.innerText);
      case 'boolean':
        return e.innerText == '1';
      case 'nil':
        return null;
      case 'array':
        return e.getElement('data')!.findElements('value').map(decode).toList();
      case 'struct':
        return {
          for (final m in e.findElements('member'))
            m.getElement('name')!.innerText: decode(m.getElement('value')!),
        };
      default:
        return e.innerText;
    }
  }

  Future<dynamic> _call(String url, String method, List<dynamic> args) async {
    try {
      final response = await dio.post<String>(
        url,
        data:
            '<?xml version="1.0"?><methodCall><methodName>$method</methodName><params>${args.map((v) => '<param>${value(v)}</param>').join()}</params></methodCall>',
        options: Options(
          contentType: 'text/xml',
          responseType: ResponseType.plain,
        ),
      );
      final doc = XmlDocument.parse(response.data!);
      final fault = doc.findAllElements('fault').firstOrNull;
      if (fault != null) {
        final payload = decode(fault.getElement('value')!);
        final code = payload is Map ? payload['faultCode'] : null;
        final detail = payload.toString();
        if (code == 3 || detail.contains('AccessDenied')) {
          throw const AppFailure(
            'Sign in again with the original account to synchronize saved edits.',
            kind: FailureKind.authentication,
          );
        }
        if (code == 4 || detail.contains('AccessError')) {
          throw const AppFailure(
            'Access denied. Check your Odoo permissions.',
            kind: FailureKind.permission,
          );
        }
        if (code == 2 ||
            detail.contains('ValidationError') ||
            detail.contains('UserError')) {
          throw const AppFailure(
            'Odoo rejected this operation. Check the record and its current status.',
            kind: FailureKind.validation,
          );
        }
        throw const AppFailure(
          'Odoo could not complete the request. Check installed apps and API access.',
        );
      }
      return decode(doc.findAllElements('param').first.getElement('value')!);
    } on AppFailure {
      rethrow;
    } on DioException catch (e) {
      if (e.response?.statusCode == 401) {
        throw const AppFailure(
          'Sign in again with the original account to synchronize saved edits.',
          kind: FailureKind.authentication,
        );
      }
      if (e.response?.statusCode == 403) {
        throw const AppFailure(
          'Odoo denied this operation. Check account permissions.',
          kind: FailureKind.permission,
        );
      }
      final offline = {
        DioExceptionType.connectionError,
        DioExceptionType.connectionTimeout,
        DioExceptionType.receiveTimeout,
        DioExceptionType.sendTimeout,
      }.contains(e.type);
      throw AppFailure(
        offline ? 'Cannot reach Odoo. Check your connection and retry.' : 'The server request failed. Check the server URL and API availability.',
        offline: offline,
        kind: (e.response?.statusCode ?? 0) >= 500
            ? FailureKind.server
            : FailureKind.general,
      );
    } catch (_) {
      throw const AppFailure('The server returned an unexpected response.');
    }
  }

  @override
  Future<int> authenticate(
    OdooConfig config,
    String username,
    String password,
  ) async {
    final result = await _call(
      '${config.server}/xmlrpc/2/common',
      'authenticate',
      [config.database, username, password, <String, dynamic>{}],
    );
    if (result is! int || result <= 0) {
      throw const AppFailure('Incorrect username, password, or database.');
    }
    return result;
  }

  @override
  Future<dynamic> execute(
    OdooConfig config,
    int uid,
    String password,
    String model,
    String method,
    List<dynamic> args, [
    Map<String, dynamic> kwargs = const {},
  ]) => _call('${config.server}/xmlrpc/2/object', 'execute_kw', [
    config.database,
    uid,
    password,
    model,
    method,
    args,
    kwargs,
  ]);
}
