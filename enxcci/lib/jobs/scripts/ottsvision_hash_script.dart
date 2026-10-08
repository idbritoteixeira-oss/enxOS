import 'package:enxcci/config/enxcci_config.dart';
import 'package:enxcci/dataniverse/dataniverse_client.dart';
import 'package:enxcci/database/enx_api_provider.dart';
import 'package:enxcci/engine/enxcci_engine.dart';
import 'package:enxcci/jobs/job_script.dart';

class OttsVisionHashScript extends EnXScript {
  @override
  String get id => 'ottsvision_hash';

  @override
  String get label => 'B`reishit';

  @override
  Future<void> run({
    required Map<String, EnXcciConfig> connections,
    required DataniverseClient dataniverse,
    required EnXcciEngine engine,
    required EngineLog log,
  }) async {
    final activeConnections = connections.values
        .where((connection) => connection.active)
        .toList();
    if (activeConnections.isEmpty) {
      log('ERROR', 'OttsVision: no active external connection to record the DTTS');
      return;
    }

    final config = activeConnections.first;
    final previousDtts = await OttsVision.currentDtts(dataniverse);
    final api = EnXApiProvider(config: config);

    try {
      // ETAPA 1: limpeza — remove registros com mais de 12 minutos
      final records = await dataniverse.command({
        'action': 'LIST_RECORDS',
        'table': 'ottshash',
      });

      final data = records['data'];
      if (data is List) {
        final cutoff = DateTime.now().subtract(const Duration(minutes: 12));
        for (final record in data) {
          final createdAt = DateTime.tryParse(record['created_at'] ?? '');
          if (createdAt != null && createdAt.isBefore(cutoff)) {
            await dataniverse.command({
              'action': 'DELETE',
              'table': 'ottshash',
              'id': record['id'],
            });
          }
        }
      }

      // ETAPA 2: gera hash EnX32 a partir do timestamp e deriva DTTS
      final hash64 = OttsVision.generateHash64();
      final seeds = OttsVision.sliceSeeds(hash64);
      final dtts = OttsVision.dttsFromSeeds(seeds);

      // ETAPA 3: soma os últimos 3 dígitos do timestamp ao hash
      final timestamp = DateTime.now().microsecondsSinceEpoch;
      final ultimos3 = BigInt.parse(
        timestamp.toString().substring(timestamp.toString().length - 3),
      );
      final hashBig = BigInt.parse(hash64);
      final cripto = (hashBig + ultimos3).toString().padLeft(64, '0');
      final criptoFinal = cripto.substring(cripto.length - 64);

      // ETAPA 4: grava o novo DTTS no Dataniverse PRIMEIRO
      await dataniverse.command({
        'action': 'INSERT',
        'table': 'dtts',
        'data': {
          'dtts': dtts,
        },
      });

      // ETAPA 5: grava o hash e as oito seeds no Dataniverse
      final chain = OttsChain(
        idModulo: 'ottsvision',
        seed: seeds.first,
        idPub: 'ottsvision-cron',
        content: [criptoFinal],
      ).seal();

      final s1 = seeds[0].toString().padLeft(8, '0');
      final s2 = seeds[1].toString().padLeft(8, '0');
      final s3 = seeds[2].toString().padLeft(8, '0');
      final s4 = seeds[3].toString().padLeft(8, '0');
      final s5 = seeds[4].toString().padLeft(8, '0');
      final s6 = seeds[5].toString().padLeft(8, '0');
      final s7 = seeds[6].toString().padLeft(8, '0');
      final s8 = seeds[7].toString().padLeft(8, '0');

      await dataniverse.command({
        'action': 'INSERT',
        'table': 'ottshash',
        'data': {
          ...chain.toDataniverse(),
          'ottshash': criptoFinal,
          'seed_1': s1,
          'seed_2': s2,
          'seed_3': s3,
          'seed_4': s4,
          'seed_5': s5,
          'seed_6': s6,
          'seed_7': s7,
          'seed_8': s8,
        },
      });

      // ETAPA 6: grava o DTTS no MySQL via Gateway
      await api.storeDtts(
        dtts: dtts,
        previousDtts: previousDtts,
      );

      // ETAPA 6b: grava o hash e as oito seeds no MySQL
      final sql = 'INSERT INTO ottshash '
          '(ottshash, seed_1, seed_2, seed_3, seed_4, seed_5, seed_6, seed_7, seed_8) '
          'VALUES '
          '("$criptoFinal", "$s1", "$s2", "$s3", "$s4", "$s5", "$s6", "$s7", "$s8")';

      await api.query(sql, dtts: dtts);

      log(
        'SUCCESS',
        'OttsVision: hash and DTTS consolidated in Dataniverse and MySQL — ${criptoFinal.substring(0, 16)}...',
      );
    } catch (e) {
      log('ERROR', 'OttsVision failed to rotate the keys: $e');
    } finally {
      api.dispose();
    }
  }
}