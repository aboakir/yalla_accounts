import 'package:flutter_test/flutter_test.dart';
import 'package:yalla_accounts/core/commercial_backend/php_backend_endpoint.dart';

void main() {
  test('production API host maps v1 endpoints at the subdomain root', () {
    final uri = resolvePhpBackendEndpoint(
      Uri.parse('https://api.yallah.ps'),
      'api/v1/register.php',
    );
    expect(uri.toString(), 'https://api.yallah.ps/register.php');
  });

  test('local backend keeps the nested api/v1 path', () {
    final uri = resolvePhpBackendEndpoint(
      Uri.parse('http://127.0.0.1:8080/yallah_backend/'),
      'api/v1/register.php',
    );
    expect(
      uri.toString(),
      'http://127.0.0.1:8080/yallah_backend/api/v1/register.php',
    );
  });
}
