import 'package:enxcci/config/enxcci_config.dart';
import 'package:enxcci/dataniverse/dataniverse_client.dart';
import 'package:enxcci/database/enx_api_provider.dart';
import 'package:enxcci/engine/enxcci_engine.dart';
import 'package:enxcci/jobs/job_script.dart';

class ActionHashScript extends EnXScript {
  @override
  String get id => 'actionhash';

  @override
  String get label => 'ActionHash Finalizer';

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
      log('ERROR', 'ActionHash: nenhuma conexão ativa');
      return;
    }

    final config = activeConnections.first;
    final api = EnXApiProvider(config: config);

    try {
      // DELAY OBRIGATÓRIO (3 segundos)
      await Future.delayed(const Duration(seconds: 3));

      // TRAVA DE SEGURANÇA DTTS
      final currentDtts = await _waitForValidDtts(
        api: api,
        dataniverse: dataniverse,
        log: log,
      );

      log('INFO', 'ActionHash: DTTS sincronizado com o MySQL → $currentDtts');

      // Varre a tabela actionhash
      final result = await api.query(
        "SELECT * FROM actionhash WHERE executes IN ('obj','use','transation','burn')",
        dtts: currentDtts,
      );

      if (result.isEmpty) {
        log('INFO', 'ActionHash: nenhum registro pendente de finalização');
        return;
      }

      for (final row in result) {
        final executes = (row['executes'] ?? 'none').toString().toLowerCase();
        final idaction = row['idaction']?.toString();
        final owner = row['owner']?.toString();

        switch (executes) {
          case 'obj':
            await _createObjAh(
              row: row,
              api: api,
              dataniverse: dataniverse,
              currentDtts: currentDtts,
              log: log,
            );
            break;

          case 'use':
            await _useObjAh(
              idaction: idaction,
              owner: owner,
              row: row,
              api: api,
              dataniverse: dataniverse,
              currentDtts: currentDtts,
              log: log,
            );
            break;

          case 'transation':
            await _transferObjAh(
              idaction: idaction,
              owner: owner,
              row: row,
              api: api,
              dataniverse: dataniverse,
              currentDtts: currentDtts,
              log: log,
            );
            break;

          case 'burn':
            await _burnObjAh(
              idaction: idaction,
              owner: owner,
              row: row,
              api: api,
              dataniverse: dataniverse,
              currentDtts: currentDtts,
              log: log,
            );
            break;

          default:
            break;
        }
      }

      log('SUCCESS', 'ActionHash: ciclo de finalização concluído');
    } catch (e) {
      log('ERROR', 'ActionHash failed: $e');
    } finally {
      api.dispose();
    }
  }

  // =================================================================
  // CRIAÇÃO (executes = 'obj') + controle de limite
  // =================================================================
  Future<void> _createObjAh({
    required Map row,
    required EnXApiProvider api,
    required DataniverseClient dataniverse,
    required String currentDtts,
    required EngineLog log,
  }) async {
    final planted = row['planted']?.toString() ?? '';
    final limiteStr = row['limite']?.toString() ?? '';
    final limite = int.tryParse(limiteStr) ?? 0;

    String serieInfo = '';
    String logMsg = 'criando obj.ah';

    // === Controle de emissão limitada ===
    if (limite > 0 && planted.isNotEmpty) {
      final existing = await _countByPlanted(dataniverse, planted);

      if (existing >= limite) {
        // Limite esgotado
        await api.query(
          "UPDATE actionhash SET executes = 'none', log = 'limite atingido ($existing/$limite)' WHERE id = ${row['id']}",
          dtts: currentDtts,
        );
        log('WARN', 'ActionHash: limite atingido para planted=$planted ($existing/$limite)');
        return;
      }

      final next = existing + 1;
      serieInfo = '${next.toString().padLeft(2, '0')}/$limite';
      logMsg = 'criando obj.ah $serieInfo';
    }

    // Gera idaction + hashprivate
    final hash64 = OttsVision.generateHash64();
    final idaction = hash64.substring(0, 16);
    final hashprivate = hash64.substring(16, 48);

    final seeds = OttsVision.sliceSeeds(hash64);
    final chain = OttsChain(
      idModulo: 'actionhash',
      seed: seeds.first,
      idPub: 'actionhash',
      content: [row['content_json']?.toString() ?? ''],
    ).seal();

    // Monta content_json com a numeração da série (se limitada)
    String contentJson = row['content_json']?.toString() ?? '{}';
    if (serieInfo.isNotEmpty) {
      // injeta a numeração no content
      contentJson = contentJson.replaceFirst('{', '{"serie":"$serieInfo",');
      if (!contentJson.contains('"serie"')) {
        contentJson = '{"serie":"$serieInfo"}';
      }
    }

    final data = {
      'idaction': idaction,
      'hashprivate': hashprivate,
      'owner': row['owner'],
      'typeobj': row['typeobj'],
      'value': row['value'],
      'planted': planted,
      'unlimited': limite <= 0,
      'limited': limite > 0 ? 'true' : 'false',
      'transferable': row['transferable'],
      'used': 'no',
      'image_pixel': row['image_pixel'],
      'content_json': contentJson,
      'sealHash': chain.sealHash,
      'seed': seeds.first,
      'limite': limiteStr,
      'serie': serieInfo, // útil para consultas futuras
    };

    // 1. Grava na Dataniverse
    await dataniverse.command({
      'action': 'INSERT',
      'table': 'actionhash',
      'data': data,
    });

    // 2. Atualiza o MySQL
    final updateSql = """
      UPDATE actionhash SET 
        idaction = '$idaction', 
        executes = 'none', 
        used = 'false',
        log = '$logMsg'
      WHERE id = ${row['id']}
    """;
    await api.query(updateSql, dtts: currentDtts);

    log('SUCCESS', 'ActionHash CRIADO → idaction: $idaction ${serieInfo.isNotEmpty ? "($serieInfo)" : ""}');
  }

  // =================================================================
  // USAR (executes = 'use')
  // =================================================================
  Future<void> _useObjAh({
    required String? idaction,
    required String? owner,
    required Map row,
    required EnXApiProvider api,
    required DataniverseClient dataniverse,
    required String currentDtts,
    required EngineLog log,
  }) async {
    if (idaction == null || owner == null) return;

    final obj = await _findInDataniverse(dataniverse, idaction, owner);
    if (obj == null) {
      await api.query(
        "UPDATE actionhash SET executes = 'none', log = 'obj.ah attacked!' WHERE id = ${row['id']}",
        dtts: currentDtts,
      );
      log('ERROR', 'ActionHash USE: registro não encontrado ou owner inválido → $idaction');
      return;
    }

    final updated = {...obj, 'used': 'yes'};

    await dataniverse.command({
      'action': 'UPDATE',
      'table': 'actionhash',
      'id': obj['id'],
      'data': updated,
    });

    await api.query(
      "UPDATE actionhash SET executes = 'none', used = 'true', log = 'abrindo obj.ah' WHERE idaction = '$idaction'",
      dtts: currentDtts,
    );

    log('SUCCESS', 'ActionHash USADO → $idaction');
  }

  // =================================================================
  // TRANSFERIR (executes = 'transation')
  // =================================================================
  Future<void> _transferObjAh({
    required String? idaction,
    required String? owner,
    required Map row,
    required EnXApiProvider api,
    required DataniverseClient dataniverse,
    required String currentDtts,
    required EngineLog log,
  }) async {
    if (idaction == null || owner == null) return;

    final newOwner = row['content_json']?.toString();
    if (newOwner == null || newOwner.isEmpty) {
      await api.query(
        "UPDATE actionhash SET executes = 'none', log = 'obj.ah attacked!' WHERE id = ${row['id']}",
        dtts: currentDtts,
      );
      log('ERROR', 'ActionHash TRANSFER: novo owner não informado');
      return;
    }

    final obj = await _findInDataniverse(dataniverse, idaction, owner);
    if (obj == null) {
      // Dataniverse não reconhece → attacked
      await api.query(
        "UPDATE actionhash SET executes = 'none', log = 'obj.ah attacked!' WHERE id = ${row['id']}",
        dtts: currentDtts,
      );
      log('ERROR', 'ActionHash TRANSFER: registro não encontrado ou owner inválido → $idaction');
      return;
    }

    final updated = {...obj, 'owner': newOwner};

    await dataniverse.command({
      'action': 'UPDATE',
      'table': 'actionhash',
      'id': obj['id'],
      'data': updated,
    });

    await api.query(
      "UPDATE actionhash SET owner = '$newOwner', executes = 'none', log = 'transferindo obj.ah' WHERE idaction = '$idaction'",
      dtts: currentDtts,
    );

    log('SUCCESS', 'ActionHash TRANSFERIDO → $idaction → novo owner: $newOwner');
  }

  // =================================================================
  // QUEIMAR (executes = 'burn')
  // =================================================================
  Future<void> _burnObjAh({
    required String? idaction,
    required String? owner,
    required Map row,
    required EnXApiProvider api,
    required DataniverseClient dataniverse,
    required String currentDtts,
    required EngineLog log,
  }) async {
    if (idaction == null || owner == null) {
      await api.query(
        "UPDATE actionhash SET executes = 'none', log = 'obj.ah burned!' WHERE id = ${row['id']}",
        dtts: currentDtts,
      );
      return;
    }

    final obj = await _findInDataniverse(dataniverse, idaction, owner);

    if (obj == null) {
      // Cache pediu burn mas Dataniverse não tem → já estava queimado
      await api.query(
        "UPDATE actionhash SET executes = 'none', log = 'obj.ah burned!' WHERE id = ${row['id']}",
        dtts: currentDtts,
      );
      log('INFO', 'ActionHash BURN: It no longer existed in the Dataniverse. → $idaction');
      return;
    }

    // 1. Remove da Dataniverse
    await dataniverse.command({
      'action': 'DELETE',
      'table': 'actionhash',
      'id': obj['id'],
    });

    // 2. Remove da cache (MySQL)
    await api.query(
      "DELETE FROM actionhash WHERE idaction = '$idaction'",
      dtts: currentDtts,
    );

    log('SUCCESS', 'ActionHash BURNED (Dataniverse + Cache) → $idaction');
  }

  // =================================================================
  // Helper - Conta quantos obj.ah já existem com o mesmo planted
  // =================================================================
  Future<int> _countByPlanted(
    DataniverseClient dataniverse,
    String planted,
  ) async {
    final records = await dataniverse.command({
      'action': 'LIST_RECORDS',
      'table': 'actionhash',
    });

    final data = records['data'];
    if (data is! List) return 0;

    return data.where((r) => r['planted']?.toString() == planted).length;
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
              error.toString().toLowerCase().contains('dtts invalid');
          if (!isDttsMismatch || attempt == maxAttempts) rethrow;
          log(
            'WARN',
            'ActionHash: Waiting for OttsVision to synchronize DTTS. '
            'com o cache ($attempt/$maxAttempts)',
          );
        }
      } else if (attempt == maxAttempts) {
        throw StateError(
          'DTTS Not found in Dataniverse after $maxAttempts attempts.',
        );
      }

      if (attempt < maxAttempts) {
        await Future.delayed(const Duration(seconds: 1));
      }
    }

    throw StateError('DTTS Not synchronized with the cache after 15 seconds.');
  }

  // =================================================================
  // Helper - Busca registro na Dataniverse
  // =================================================================
  Future<Map<String, dynamic>?> _findInDataniverse(
    DataniverseClient dataniverse,
    String idaction,
    String owner,
  ) async {
    final records = await dataniverse.command({
      'action': 'LIST_RECORDS',
      'table': 'actionhash',
    });

    final data = records['data'];
    if (data is! List) return null;

    try {
      return data.cast<Map<String, dynamic>>().firstWhere(
            (r) =>
                r['idaction']?.toString() == idaction &&
                r['owner']?.toString() == owner,
          );
    } catch (_) {
      return null;
    }
  }
}