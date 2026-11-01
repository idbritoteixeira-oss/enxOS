import 'package:enxcci/config/enxcci_config.dart';
import 'package:enxcci/dataniverse/dataniverse_client.dart';
import 'package:enxcci/database/enx_api_provider.dart';
import 'package:enxcci/engine/enxcci_engine.dart';
import 'package:enxcci/jobs/job_script.dart';

class DwellersScript extends EnXScript {
  @override
  String get id => 'dwellers';

  @override
  String get label => 'Dwellers Sealer';

  @override
  Future<void> run({
    required Map<String, EnXcciConfig> connections,
    required DataniverseClient dataniverse,
    required EnXcciEngine engine,
    required EngineLog log,
  }) async {
    final activeConnections = connections.values
        .where((c) => c.active)
        .toList();

    if (activeConnections.isEmpty) {
      log('ERROR', 'Dwellers: nenhuma conexão ativa');
      return;
    }

    final config = activeConnections.first;
    final api = EnXApiProvider(config: config);

    try {
      // Delay para sincronizar com o OttsVision
      await Future.delayed(const Duration(seconds: 3));

      // TRAVA DE DTTS
      final currentDtts = await _waitForValidDtts(
        api: api,
        dataniverse: dataniverse,
        log: log,
      );

      log('INFO', 'Dwellers: DTTS válido → $currentDtts');

      // Busca contas ainda não seladas (dataniverse = 0)
      final result = await api.query(
        'SELECT * FROM enx_nation WHERE dataniverse = 0',
        dtts: currentDtts,
      );

      if (result.isEmpty) {
        log('INFO', 'Dwellers: nenhuma conta pendente de selagem');
        return;
      }

      for (final row in result) {
        await _sealOwner(
          row: row,
          api: api,
          dataniverse: dataniverse,
          currentDtts: currentDtts,
          log: log,
        );
      }

      log('SUCCESS', 'Dwellers: ciclo de selagem concluído');
    } catch (e) {
      log('ERROR', 'Dwellers failed: $e');
    } finally {
      api.dispose();
    }
  }

  // =================================================================
  // SELA A CONTA NA DATANIVERSE
  // =================================================================
  Future<void> _sealOwner({
    required Map row,
    required EnXApiProvider api,
    required DataniverseClient dataniverse,
    required String currentDtts,
    required EngineLog log,
  }) async {
    final id = row['id'];

    // Copia todos os campos relevantes para a tabela owner na Dataniverse
    final data = {
      'nation': row['nation'],
      'id_pub': row['id_pub'],
      'id_private': row['id_private'],
      'pass': row['pass'],
      'name': row['name'],
      'loc_start': row['loc_start'],
      'private_key': row['private_key'],
      'id_origin': row['id_origin'],
      'stat': row['stat'],
      'status': row['status'],
      'id_inx': row['id_inx'],
      'id_pru': row['id_pru'],
      'id_act': row['id_act'],
      'id_free': row['id_free'],
      'created_at': row['created_at'],
      // pode adicionar mais campos se precisar
    };

    // 1. Grava na Dataniverse (tabela owner)
    await dataniverse.command({
      'action': 'INSERT',
      'table': 'owner',
      'data': data,
    });

    // 2. Marca como selado no MySQL
    await api.query(
      'UPDATE enx_nation SET dataniverse = 1 WHERE id = $id',
      dtts: currentDtts,
    );

    log('SUCCESS', 'Dwellers: conta selada → ${row['name'] ?? row['id_pub']}');
  }

  // =================================================================
  // Helper - Aguarda DTTS válido
  // =================================================================
  Future<String> _waitForValidDtts({
    required EnXApiProvider api,
    required DataniverseClient dataniverse,
    required EngineLog log,
  }) async {
    const maxAttempts = 15;

    for (var attempt = 1; attempt <= maxAttempts; attempt++) {
      final dtts = await OttsVision.currentDtts(dataniverse);
      if (dtts != null && dtts.isNotEmpty) {
        try {
          await api.query('SELECT 1 AS dtts_ready', dtts: dtts);
          return dtts;
        } catch (error) {
          final isDttsMismatch =
              error.toString().toLowerCase().contains('dtts inválido');
          if (!isDttsMismatch || attempt == maxAttempts) rethrow;
          log(
            'WARN',
            'Dwellers: aguardando sincronização do DTTS ($attempt/$maxAttempts)',
          );
        }
      } else if (attempt == maxAttempts) {
        throw StateError('DTTS não encontrado após $maxAttempts tentativas');
      }

      if (attempt < maxAttempts) {
        await Future.delayed(const Duration(seconds: 1));
      }
    }

    throw StateError('DTTS não sincronizado após 15 segundos');
  }
}