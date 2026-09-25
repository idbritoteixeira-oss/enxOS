import 'package:enxcci/config/enxcci_config.dart';
import 'package:enxcci/dataniverse/dataniverse_client.dart';
import 'package:enxcci/engine/enxcci_engine.dart';
import 'package:enxcci/jobs/job_script.dart';

class GenericScript extends EnXScript {
  @override
  String get id => 'generic';

  @override
  String get label => 'Script genérico';

  @override
  Future<void> run({
    required Map<String, EnXcciConfig> connections,
    required DataniverseClient dataniverse,
    required EnXcciEngine engine,
    required EngineLog log,
  }) async {
    log('INFO', 'Script genérico executado — implemente a lógica aqui');
  }
}