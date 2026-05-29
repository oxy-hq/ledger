// ignore_for_file: avoid_print
//
// Helpers used by brand.dart to bake a schemas-repo `config.yml` into the
// app's `assets/config.yaml` with environment variables resolved.
//
// Convention mirrors oxy / airlayer:
//   - Any YAML field whose key ends in `_var` is treated as an env-var
//     reference. The matching field without the suffix gets the resolved
//     value.
//     Example:
//       password_var: PG_PASSWORD     →   password: <value of $PG_PASSWORD>
//   - Env vars come from <schemas-dir>/.env (gitignored, never committed)
//     plus the process environment as a fallback.
//   - Missing env vars fail the build with a clear error.
//
// Special cases:
//   - `service_account_key_path` / `service_account_key_path_var` —
//     the value (after env var resolution) is treated as a filesystem path
//     and the file's full contents are inlined as `service_account_key`.

library;

import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:yaml/yaml.dart';

/// Loads `<dir>/.env` if it exists. Lines are `KEY=value`; blanks and
/// `#`-comments are skipped. Quoted values have surrounding quotes
/// stripped. Returns an empty map if the file is absent.
Map<String, String> loadEnvFile(String dir) {
  final f = File(p.join(dir, '.env'));
  if (!f.existsSync()) return const {};
  final out = <String, String>{};
  for (var line in f.readAsLinesSync()) {
    final trimmed = line.trim();
    if (trimmed.isEmpty || trimmed.startsWith('#')) continue;
    final eq = trimmed.indexOf('=');
    if (eq < 0) continue;
    final key = trimmed.substring(0, eq).trim();
    var value = trimmed.substring(eq + 1).trim();
    if (value.length >= 2 &&
        ((value.startsWith('"') && value.endsWith('"')) ||
            (value.startsWith("'") && value.endsWith("'")))) {
      value = value.substring(1, value.length - 1);
    }
    out[key] = value;
  }
  return out;
}

/// Walks a YAML structure recursively and resolves any `*_var:`
/// references against [env]. The resolved value replaces both the
/// `_var` field AND a corresponding bare field (e.g. `password_var: X`
/// becomes `password: <value>`).
///
/// Special-cased keys (after var-resolution):
///   - `service_account_key_path` / `service_account_key_path_var` —
///     reads the file at that path and inlines it as
///     `service_account_key`.
///
/// Throws [FormatException] if a referenced env var is missing.
dynamic resolveConfig(dynamic raw, Map<String, String> env) {
  return _resolveInner(_yamlToPlain(raw), env);
}

dynamic _resolveInner(dynamic node, Map<String, String> env) {
  if (node is Map) {
    final out = <String, dynamic>{};
    node.forEach((rawKey, value) {
      final key = rawKey.toString();
      if (key.endsWith('_var') && value is String) {
        final bareKey = key.substring(0, key.length - '_var'.length);
        final resolved = env[value] ?? Platform.environment[value];
        if (resolved == null) {
          throw FormatException(
            'env var \$$value (referenced by `$key`) is unset. '
            'Add it to <schemas-dir>/.env or the process environment.',
          );
        }
        out[bareKey] = resolved;
      } else {
        out[key] = _resolveInner(value, env);
      }
    });
    // SA-key path special case: inline the file's contents.
    if (out.containsKey('service_account_key_path') &&
        !out.containsKey('service_account_key')) {
      final path = out['service_account_key_path'] as String;
      final expanded = _expand(path);
      final f = File(expanded);
      if (!f.existsSync()) {
        throw FormatException(
          'service_account_key_path "$expanded" does not exist',
        );
      }
      out['service_account_key'] = f.readAsStringSync();
    }
    return out;
  }
  if (node is List) {
    return node.map((e) => _resolveInner(e, env)).toList();
  }
  return node;
}

dynamic _yamlToPlain(dynamic v) {
  if (v is YamlMap) {
    return <String, dynamic>{
      for (final entry in v.entries) entry.key.toString(): _yamlToPlain(entry.value),
    };
  }
  if (v is YamlList) return v.map(_yamlToPlain).toList();
  return v;
}

String _expand(String path) {
  if (path.startsWith('~/') || path == '~') {
    final home = Platform.environment['HOME'] ?? '';
    return p.join(home, path.substring(2));
  }
  return path;
}

/// Re-emits [config] as a YAML string suitable for the bundled
/// `assets/config.yaml`. Not byte-exact YAML — comments and ordering
/// from the source are lost — but the values round-trip correctly.
String emitYaml(dynamic node, [int depth = 0]) {
  final indent = '  ' * depth;
  if (node is Map) {
    final out = StringBuffer();
    for (final entry in node.entries) {
      final k = entry.key;
      final v = entry.value;
      if (v is Map && v.isNotEmpty) {
        out.writeln('$indent$k:');
        out.write(emitYaml(v, depth + 1));
      } else if (v is List && v.isNotEmpty) {
        out.writeln('$indent$k:');
        for (final item in v) {
          if (item is Map) {
            // Block-style list entry
            final block = emitYaml(item, depth + 2).trimRight();
            final lines = block.split('\n');
            if (lines.isNotEmpty) {
              out.writeln('$indent  - ${lines.first.trimLeft()}');
              for (final line in lines.skip(1)) {
                out.writeln(line);
              }
            }
          } else {
            out.writeln('$indent  - ${_yamlScalar(item)}');
          }
        }
      } else {
        out.writeln('$indent$k: ${_yamlScalar(v)}');
      }
    }
    return out.toString();
  }
  return '$indent${_yamlScalar(node)}\n';
}

String _yamlScalar(dynamic v) {
  if (v == null) return 'null';
  if (v is bool || v is num) return v.toString();
  final s = v.toString();
  if (s.isEmpty) return '""';
  // Quote if it contains characters that would change YAML parsing.
  if (s.contains('\n') ||
      s.contains(': ') ||
      s.contains('#') ||
      s.contains(': ') ||
      s.contains('  ') ||
      s.startsWith('-') ||
      s.startsWith('*') ||
      s.startsWith('!') ||
      s.startsWith('&') ||
      s.startsWith('?') ||
      s.startsWith('|') ||
      s.startsWith('>') ||
      s.startsWith('@') ||
      RegExp(r'^[\d.+\-]').hasMatch(s) ||
      ['true', 'false', 'null', 'yes', 'no', 'on', 'off']
          .contains(s.toLowerCase())) {
    // JSON-escape and double-quote — handles multiline strings (SA JSON)
    // by writing them as a single-line "...\n..." escaped form.
    final escaped = s
        .replaceAll(r'\', r'\\')
        .replaceAll('"', r'\"')
        .replaceAll('\n', r'\n')
        .replaceAll('\r', r'\r')
        .replaceAll('\t', r'\t');
    return '"$escaped"';
  }
  return s;
}
