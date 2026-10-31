import 'package:enxcci/config/enxcci_config.dart';
import 'package:enxcci/dataniverse/dataniverse_client.dart';
import 'package:enxcci/database/enx_api_provider.dart';
import 'package:enxcci/engine/enxcci_engine.dart';
import 'package:enxcci/engine/modules/enx_crypt.dart';
import 'package:enxcci/engine/modules/enx_math.dart';
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
      // =========================================================
      // TRAVA DE SEGURANÇA DTTS (obrigatória)
      // =========================================================
      final currentDtts = await OttsVision.currentDtts(dataniverse);

      if (currentDtts == null || currentDtts.isEmpty) {
        log('ERROR', 'ActionHash: DTTS não encontrado → Acesso negado');
        return;
      }

      // Busca o registro do DTTS para verificar expiração (60s)
      final dttsRecords = await dataniverse.command({
        'action': 'LIST_RECORDS',
        'table': 'dtts',
      });

      final dttsData = dttsRecords['data'];
      if (dttsData is List && dttsData.isNotEmpty) {
        final last = dttsData.last;
        final createdAt = DateTime.tryParse(last['created_at'] ?? '');
        if (createdAt != null && OttsVision.isExpired(createdAt)) {
          log('ERROR', 'ActionHash: DTTS expirado (>60s) → Acesso negado');
          return;
        }
      }

      log('INFO', 'ActionHash: DTTS válido → $currentDtts');

      // =========================================================
      // 1. Varre a tabela actionhash no MySQL/cache
      // =========================================================
      final result = await api.query(
        "SELECT * FROM actionhash WHERE executes IN ('obj','use','transation','burn')",
        dtts: currentDtts, // envia o DTTS junto (mesmo padrão do backend)
      );

      if (result is! List || result.isEmpty) {
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
  // CRIAÇÃO (executes = 'obj')
  // =================================================================
  Future<void> _createObjAh({
    required Map row,
    required EnXApiProvider api,
    required DataniverseClient dataniverse,
    required String currentDtts,
    required EngineLog log,
  }) async {
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

    final data = {
      'idaction': idaction,
      'hashprivate': hashprivate,
      'owner': row['owner'],
      'typeobj': row['typeobj'],
      'value': row['value'],
      'planted': row['planted'],
      'unlimited': (row['limited']?.toString() == 'false'),
      'limited': row['limited'],
      'transferable': row['transferable'],
      'used': 'no',
      'image_pixel': row['image_pixel'],
      'content_json': row['content_json'],
      'sealHash': chain.sealHash,
      'seed': seeds.first,
    };

    await dataniverse.command({
      'action': 'INSERT',
      'table': 'actionhash',
      'data': data,
    });

    await api.query(
      "UPDATE actionhash SET "
      "idaction = '$idaction', "
      "executes = 'none', "
      "used = 'false' "
      "WHERE id = ${row['id']}",
      dtts: currentDtts,
    );

    log('SUCCESS', 'ActionHash CRIADO → idaction: $idaction');
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
      "UPDATE actionhash SET executes = 'none', used = 'true' WHERE idaction = '$idaction'",
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
      log('ERROR', 'ActionHash TRANSFER: novo owner não informado');
      return;
    }

    final obj = await _findInDataniverse(dataniverse, idaction, owner);
    if (obj == null) {
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
      "UPDATE actionhash SET owner = '$newOwner', executes = 'none' WHERE idaction = '$idaction'",
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
    required EnXApiProvider api,
    required DataniverseClient dataniverse,
    required String currentDtts,
    required EngineLog log,
  }) async {
    if (idaction == null || owner == null) return;

    final obj = await _findInDataniverse(dataniverse, idaction, owner);
    if (obj == null) {
      log('ERROR', 'ActionHash BURN: registro não encontrado ou owner inválido → $idaction');
      return;
    }

    await dataniverse.command({
      'action': 'DELETE',
      'table': 'actionhash',
      'id': obj['id'],
    });

    await api.query(
      "DELETE FROM actionhash WHERE idaction = '$idaction'",
      dtts: currentDtts,
    );

    log('SUCCESS', 'ActionHash QUEIMADO → $idaction');
  }

  // =================================================================
  // Helper
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
        (r) => r['idaction']?.toString() == idaction && r['owner']?.toString() == owner,
      );
    } catch (_) {
      return null;
    }
  }
}