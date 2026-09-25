import 'package:enxcci/jobs/job_script.dart';
// importe seus scripts aqui:
// import 'package:enxcci/jobs/scripts/sync_exemplo.dart';

class ScriptRegistry {
  static final Map<String, EnXScript> _scripts = {
    // SyncExemploScript().id: SyncExemploScript(),
  };

  static EnXScript? get(String id) => _scripts[id];
  static List<EnXScript> getAll() => _scripts.values.toList();
}