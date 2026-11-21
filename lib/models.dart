class ProjectManifest {
  final Map<String, dynamic> json;
  ProjectManifest(Map<String, dynamic> value)
    : json = Map.unmodifiable({
        ...value,
        if (value['devices'] is List)
          'devices': List.unmodifiable(value['devices'] as List),
        if (value['resources'] is List)
          'resources': List.unmodifiable(value['resources'] as List),
      }) {
    if (json['schema'] != 1 ||
        json['id'] is! String ||
        !RegExp(r'^[a-z0-9][a-z0-9-]{0,63}$').hasMatch(id)) {
      throw const FormatException('Unsupported project manifest');
    }
    for (final key in ['sha256', 'manifest_sha256']) {
      if (json[key] is! String ||
          !RegExp(r'^[0-9a-f]{64}$').hasMatch(json[key] as String)) {
        throw FormatException('Invalid $key');
      }
    }
    for (final key in ['archive_bytes', 'unpacked_bytes']) {
      if (json[key] is! int || (json[key] as int) <= 0) {
        throw FormatException('Invalid $key');
      }
    }
    if (json['version'] is! String ||
        version.trim().isEmpty ||
        version.length > 100 ||
        (json['name'] != null &&
            (json['name'] is! String ||
                name.trim().isEmpty ||
                name.length > 100))) {
      throw const FormatException('Invalid project name or version');
    }
    final minimum = json['min_manager_schema'] ?? 1;
    if (json['adapter'] != 'alpaca-pilot-v1' ||
        minimum is! int ||
        minimum != 1) {
      throw const FormatException('This project requires a newer Toolkit');
    }
    final devices = json['devices'];
    if (devices is! List ||
        devices.length != 1 ||
        devices.single != 'benro-polaris') {
      throw const FormatException('Unsupported device family');
    }
    final resources = json['resources'];
    const required = {'benro-controller', 'tcp:5555', 'tcp:5556', 'tcp:8081'};
    if (resources is! List ||
        resources.any((r) => r is! String || r.isEmpty || r.length > 100) ||
        resources.toSet().length != resources.length ||
        !resources.toSet().containsAll(required)) {
      throw const FormatException('Invalid project resource declarations');
    }
    if (json['asset_id'] != null &&
        (json['asset_id'] is! int || (json['asset_id'] as int) <= 0)) {
      throw const FormatException('Invalid release asset ID');
    }
  }
  String get id => json['id'] as String;
  String get name => json['name'] as String? ?? id;
  String get version => json['version'] as String;
  String get hash => json['sha256'] as String;
  int get bytes => json['archive_bytes'] as int;
  int? get assetId => json['asset_id'] as int?;
}

class InstalledProject {
  final Map<String, dynamic> json;
  InstalledProject(this.json);
  String get id => json['id'] as String;
  bool get running => json['running'] == true;
  Map<String, dynamic>? get pilot => json['pilot'] as Map<String, dynamic>?;
  ProjectManifest get manifest => ProjectManifest(
    Map<String, dynamic>.from(json['installation']['manifest'] as Map),
  );
}

class OperationStatus {
  final Map<String, dynamic> json;
  OperationStatus(this.json);
  String get phase => json['phase'] as String? ?? 'unknown';
  String get project => json['project'] as String? ?? '';
  String get action => json['action'] as String? ?? '';
}
