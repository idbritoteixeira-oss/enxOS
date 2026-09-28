import 'package:enxcci/config/enxcci_config.dart';
import 'package:enxcci/dataniverse/dataniverse_client.dart';
import 'package:enxcci/engine/enxcci_engine.dart';
import 'package:enxcci/jobs/job_script.dart';
import 'package:enxcci/database/enx_api_provider.dart';

class OttsSeedScript extends EnXScript {
  @override
  String get id => 'otts_seed';

  @override
  String get label => 'OttsSeed — Selagem';

  @override
  Future<void> run({
    required Map<String, EnXcciConfig> connections,
    required DataniverseClient dataniverse,
    required EnXcciEngine engine,
    required EngineLog log,
  }) async {
    final config = connections.values.firstOrNull;
    if (config == null) {
      log('ERROR', 'OttsSeed: nenhuma conexão configurada');
      return;
    }

    final dtts = await OttsVision.currentDtts(dataniverse);
if (dtts == null) {
  log('WARN', 'OttsSeed: dtts não encontrado, requisições sem validação dtts');
}
    
    final api = EnXApiProvider(config: config);
    try {
      for (int modulo = 1; modulo <= 8; modulo++) {
        await api.query('DELETE FROM ...', dtts: dtts);
      }
      log('SUCCESS', 'OttsSeed: selagem concluída ');
    } catch (e) {
      log('ERROR', 'OttsSeed fatal: $e');
    } finally {
      api.dispose();
    }
  }

}