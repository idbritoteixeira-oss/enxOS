import 'package:enxcci/jobs/job_script.dart';
import 'package:enxcci/jobs/scripts/generic_script.dart';
import 'package:enxcci/jobs/scripts/ottsvision_hash_script.dart';

class ScriptRegistry {
  static final Map<String, EnXScript> _scripts = {
    GenericScript().id: GenericScript(),
    OttsVisionHashScript().id: OttsVisionHashScript(),
  };

  static EnXScript? get(String id) => _scripts[id];
  static List<EnXScript> getAll() => _scripts.values.toList();
}