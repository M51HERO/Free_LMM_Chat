import 'package:flutter_test/flutter_test.dart';
import 'package:free_llm_chat/data/manifest_config.dart';

String? norm(String s) => checkBaseUrl(s).url;
BaseUrlProblem? problem(String s) => checkBaseUrl(s).problem;

void main() {
  group('checkBaseUrl', () {
    test('accepts the URL with or without /v1 and trailing slashes', () {
      expect(norm('http://localhost:2099'), 'http://localhost:2099');
      expect(norm('http://localhost:2099/'), 'http://localhost:2099');
      expect(norm('http://localhost:2099/v1'), 'http://localhost:2099');
      expect(norm('http://localhost:2099/v1/'), 'http://localhost:2099');
      expect(norm('https://app.manifest.build/V1'), 'https://app.manifest.build');
      expect(norm('  https://app.manifest.build///  '), 'https://app.manifest.build');
    });

    test('accepts a pasted endpoint URL', () {
      expect(norm('http://localhost:2099/v1/chat/completions'), 'http://localhost:2099');
      expect(norm('http://192.168.1.20:2099/v1/models'), 'http://192.168.1.20:2099');
    });

    test('keeps a path prefix (reverse proxy) but removes /v1', () {
      expect(norm('https://example.com/manifest/v1'), 'https://example.com/manifest');
      expect(norm('https://example.com/manifest'), 'https://example.com/manifest');
    });

    test('drops credentials, query and fragment', () {
      expect(norm('https://user:pw@host.example/v1?x=1#frag'), 'https://host.example');
    });

    test('adds a scheme: http for local hosts, https for the rest', () {
      expect(norm('localhost:2099'), 'http://localhost:2099');
      expect(norm('192.168.1.20:2099/v1'), 'http://192.168.1.20:2099');
      expect(norm('app.manifest.build'), 'https://app.manifest.build');
      expect(norm('manifest.example.com/v1'), 'https://manifest.example.com');
    });

    test('plain http is accepted for loopback and LAN addresses', () {
      for (final u in [
        'http://127.0.0.1:2099',
        'http://[::1]:2099',
        'http://192.168.1.20:2099',
        'http://10.0.2.2:2099',
        'http://172.16.5.4:2099',
        'http://100.64.1.2:2099',
        'http://my-nas:2099',
        'http://nas.local:2099',
      ]) {
        expect(checkBaseUrl(u).ok, isTrue, reason: u);
      }
      expect(norm('http://[::1]:2099'), 'http://[::1]:2099');
    });

    test('plain http is refused for other hosts (the key would travel unencrypted)', () {
      expect(problem('http://app.manifest.build'), BaseUrlProblem.cleartextNotLocal);
      expect(problem('http://8.8.8.8:2099'), BaseUrlProblem.cleartextNotLocal);
      expect(problem('http://172.32.0.1'), BaseUrlProblem.cleartextNotLocal);
      expect(norm('https://app.manifest.build'), 'https://app.manifest.build');
    });

    test('rejects empty and invalid input', () {
      expect(problem(''), BaseUrlProblem.empty);
      expect(problem('   '), BaseUrlProblem.empty);
      expect(problem('ftp://example.com'), BaseUrlProblem.invalid);
      expect(problem('http://'), BaseUrlProblem.invalid);
    });
  });

  group('isLocalHost / isLoopbackHost', () {
    test('local', () {
      expect(isLocalHost('localhost'), isTrue);
      expect(isLocalHost('LOCALHOST'), isTrue);
      expect(isLocalHost('192.168.0.5'), isTrue);
      expect(isLocalHost('169.254.1.1'), isTrue);
      expect(isLocalHost('fd00::1'), isTrue);
      expect(isLocalHost('host.docker.internal'), isTrue);
    });

    test('not local', () {
      expect(isLocalHost(''), isFalse);
      expect(isLocalHost('example.com'), isFalse);
      expect(isLocalHost('1.1.1.1'), isFalse);
      expect(isLocalHost('172.15.0.1'), isFalse);
      expect(isLocalHost('100.128.0.1'), isFalse);
    });

    test('loopback only', () {
      expect(isLoopbackHost('localhost'), isTrue);
      expect(isLoopbackHost('127.0.0.1'), isTrue);
      expect(isLoopbackHost('::1'), isTrue);
      expect(isLoopbackHost('192.168.1.20'), isFalse);
    });
  });

  group('manifestEndpoint', () {
    test('builds {base}/v1/{path} whether or not the base has /v1', () {
      expect(manifestEndpoint('http://localhost:2099', 'chat/completions').toString(),
          'http://localhost:2099/v1/chat/completions');
      expect(manifestEndpoint('http://localhost:2099/v1', 'chat/completions').toString(),
          'http://localhost:2099/v1/chat/completions');
      expect(manifestEndpoint('https://app.manifest.build/v1/', 'chat/completions').toString(),
          'https://app.manifest.build/v1/chat/completions');
    });

    test('adds the query for the model list', () {
      expect(
        manifestEndpoint('http://localhost:2099/v1', 'models', query: const {'cost': 'true'})
            .toString(),
        'http://localhost:2099/v1/models?cost=true',
      );
    });

    test('throws for an unusable base URL', () {
      expect(() => manifestEndpoint('', 'models'), throwsFormatException);
      expect(() => manifestEndpoint('http://example.com', 'models'), throwsFormatException);
    });
  });

  test('constants match the documented defaults', () {
    expect(kManifestSelfHostedUrl, 'http://localhost:2099');
    expect(kManifestCloudUrl, 'https://app.manifest.build');
    expect(kAutoModel, 'auto');
    expect(kKeyPrefix, 'mnfst_');
  });
}
