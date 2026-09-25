import 'package:enxcci/config/enxcci_config.dart';
import 'package:enxcci/dataniverse/dataniverse_client.dart';
import 'package:enxcci/engine/enxcci_engine.dart';

abstract class EnXScript {
  String get id;
  String get label;

  Future<void> run({
    required Map<String, EnXcciConfig> connections,
    required DataniverseClient dataniverse,
    required EnXcciEngine engine,
    required EngineLog log,
  });
}