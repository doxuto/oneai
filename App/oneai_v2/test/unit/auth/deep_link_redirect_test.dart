import 'package:flutter_test/flutter_test.dart';

/// The router's sign-in redirect keeps a deep link in `?from=` and only ever
/// returns to an in-app path (never an external URL). Mirrors app_router.dart.
String redirectSignedOut(String target) => target == '/' ? '/login' : Uri(path: '/login', queryParameters: {'from': target}).toString();
String redirectSignedInAtLogin(String? from) => (from != null && from.startsWith('/') && !from.startsWith('//')) ? from : '/';

void main() {
  test('signed out: a deep link is preserved, Home is not', () {
    expect(redirectSignedOut('/'), '/login');
    expect(redirectSignedOut('/s?t=abc'), '/login?from=%2Fs%3Ft%3Dabc');
    expect(Uri.parse(redirectSignedOut('/n/m1')).queryParameters['from'], '/n/m1');
  });
  test('signed in at login: goes back to the deep link, never off-app', () {
    expect(redirectSignedInAtLogin('/s?t=abc'), '/s?t=abc');
    expect(redirectSignedInAtLogin(null), '/');
    expect(redirectSignedInAtLogin('//evil.test/x'), '/');
    expect(redirectSignedInAtLogin('https://evil.test'), '/');
  });
}
