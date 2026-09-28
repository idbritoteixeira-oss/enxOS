import 'package:enxcci/config/enxcci_config.dart';
import 'package:enxcci/dataniverse/dataniverse_client.dart';
import 'package:enxcci/database/enx_api_provider.dart';
import 'package:enxcci/engine/enxcci_engine.dart';
import 'package:enxcci/engine/modules/enx_crypt.dart';
import 'package:enxcci/jobs/job_script.dart';

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
    // Igual ao OttsVisionHashScript — só conexões ativas
    final activeConnections = connections.values
        .where((c) => c.active)
        .toList();
    if (activeConnections.isEmpty) {
      log('ERROR', 'OttsSeed: nenhuma conexão externa ativa');
      return;
    }

    final config = activeConnections.first;

    // Busca dtts atual do Dataniverse — mesmo padrão do OttsVision
    final dtts = await OttsVision.currentDtts(dataniverse);
    if (dtts == null) {
      log('WARN', 'OttsSeed: dtts não encontrado no Dataniverse');
    }

    final api = EnXApiProvider(config: config);
    try {
      for (int modulo = 1; modulo <= 8; modulo++) {
        await _processModulo(api, modulo, dtts, log);
      }
      log('SUCCESS', 'OttsSeed: selagem concluída para módulos 1-8');
    } catch (e) {
      log('ERROR', 'OttsSeed fatal: $e');
    } finally {
      api.dispose();
    }
  }

  Future<void> _processModulo(
    EnXApiProvider api,
    int moduloId,
    String? dtts,
    EngineLog log,
  ) async {
    final tabela = 'ottsseeds_$moduloId';
    final colunaFatia = 'seed_$moduloId';

    try {
      // ETAPA 1: limpa registros fechados
      await api.query(
        'DELETE FROM $tabela WHERE seal = "closed"',
        dtts: dtts,
      );

      // ETAPA 2: busca fila collecting (mais antigos primeiro)
      final coletas = await api.query(
        'SELECT id, seed, inseed, content FROM $tabela '
        'WHERE seal = "collecting" ORDER BY id ASC LIMIT 500',
        dtts: dtts,
      );

      if (coletas.isEmpty) return;

      log('INFO', 'OttsSeed módulo $moduloId: ${coletas.length} na fila');

      for (final row in coletas) {
        final id = row['id']?.toString() ?? '';
        final seedBase = row['seed']?.toString() ?? '';
        final inSeed = row['inseed']?.toString() ?? '';
        final content = row['content']?.toString() ?? '';

        // Cifra com EnXCrypt
        final inSeedBig = BigInt.tryParse(inSeed) ?? BigInt.zero;
        final hashCifrado = EnXCrypt.enXCrypt(content, inSeedBig);

        // Primeiros 8 dígitos da seed
        final seedOito = seedBase.length >= 8
            ? seedBase.substring(0, 8)
            : seedBase.padLeft(8, '0');

        // ETAPA 3: busca seed_1 e seed_2 no ottshash
        final rowsHash = await api.query(
          'SELECT seed_1, seed_2 FROM ottshash '
          'WHERE $colunaFatia = "$seedOito" LIMIT 1',
          dtts: dtts,
        );

        if (rowsHash.isEmpty) {
          log('WARN', 'OttsSeed módulo $moduloId: sem ottshash para $seedOito');
          continue;
        }

        final seed1 = rowsHash.first['seed_1']?.toString() ?? '';
        final seed2 = rowsHash.first['seed_2']?.toString() ?? '';
        final chainHash = '$seed1$seed2';

        // ETAPA 4: insere em ottschain
        await api.query(
          'INSERT INTO ottschain (ottschain, seed, hash) '
          'VALUES ("$chainHash", "$seedOito", "$hashCifrado")',
          dtts: dtts,
        );

        // ETAPA 5: fecha o registro
        await api.query(
          'UPDATE $tabela SET seal = "closed" WHERE id = "$id"',
          dtts: dtts,
        );
      }
    } catch (e) {
      log('ERROR', 'OttsSeed módulo $moduloId: $e');
    }
  }
}