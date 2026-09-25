import 'package:enxcci/jobs/scripts/generic_script.dart';

class ScriptRegistry {
  static final Map<String, EnXScript> _scripts = {
    GenericScript().id: GenericScript(),
  };

  static EnXScript? get(String id) => _scripts[id];
  static List<EnXScript> getAll() => _scripts.values.toList();
}