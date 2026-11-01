import 'package:enxcci/jobs/job_script.dart';
import 'package:enxcci/jobs/scripts/generic_script.dart';
import 'package:enxcci/jobs/scripts/ottsvision_hash_script.dart';
import 'package:enxcci/jobs/scripts/otts_seed_script.dart';
import 'package:enxcci/jobs/scripts/obj_ah.dart';
import 'package:enxcci/jobs/scripts/dwellers.dart';

class ScriptRegistry {
  static const customJavaScriptId = 'custom_js';
  static const customJavaScriptLabel = 'Código personalizado (JS)';

  static final Map<String, EnXScript> _scripts = {
    'otts_seed': OttsSeedScript(),
    GenericScript().id: GenericScript(),
    OttsVisionHashScript().id: OttsVisionHashScript(),
    ActionHashScript().id: ActionHashScript(),
    DwellersScript().id: DwellersScript(), // ← novo Job ActionHash
  };

  static EnXScript? get(String id) => _scripts[id];
  static List<EnXScript> getAll() => _scripts.values.toList();
}