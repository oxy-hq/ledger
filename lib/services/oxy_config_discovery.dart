import 'dart:io';

import 'package:path/path.dart' as p;

/// Result of an oxy `config.yml` lookup.
class OxyConfigLocation {
  /// Absolute path to the discovered `config.yml`.
  final String configPath;

  /// Project root — the directory holding the config.
  final String projectRoot;

  OxyConfigLocation({
    required this.configPath,
    required this.projectRoot,
  });

  @override
  String toString() =>
      'OxyConfigLocation(config=$configPath, root=$projectRoot)';
}

/// Walks up from [from] looking for `./config.yml` at each ancestor level.
/// Mirrors airlayer's `find_project_root`
/// (`~/repos/airlayer/src/cli/mod.rs`) one-for-one — same single-path
/// lookup at each level, same stop condition at the filesystem root.
///
/// The canonical layout (see `docs/oxy-compatibility.md`) puts
/// `config.yml` at the customer-repo root with `oxy/` and `ledger/` as
/// subdirs. Both tools run from their respective subdir and walk up to
/// the shared config. No cross-sibling lookups, no escape hatches —
/// matches airlayer's behavior exactly.
///
/// Returns null if no config is found before hitting the filesystem root.
OxyConfigLocation? findOxyConfig({required String from}) {
  var dir = Directory(p.absolute(from));
  while (true) {
    final candidate = File(p.join(dir.path, 'config.yml'));
    if (candidate.existsSync()) {
      return OxyConfigLocation(
        configPath: candidate.path,
        projectRoot: dir.path,
      );
    }
    final parent = dir.parent;
    if (parent.path == dir.path) return null; // reached fs root
    dir = parent;
  }
}
