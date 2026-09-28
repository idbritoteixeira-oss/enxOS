import 'package:enxcci/config/enxcci_config.dart';
import 'package:enxcci/dataniverse/dataniverse_client.dart';
import 'package:enxcci/database/enx_api_provider.dart';
import 'package:enxcci/engine/enxcci_engine.dart';
import 'package:enxcci/jobs/job_script.dart';

class OttsVisionHashScript extends EnXScript {
  @override
  String get id => 'ottsvision_hash';

  @override
  String get label => 'OttsVision — Hash & seeds';

  @override
  Future<void> run({
    required Map<String, EnXcciConfig> connections,
    required DataniverseClient dataniverse,
    required EnXcciEngine engine,
    required EngineLog log,
  }) async {
    final activeConnections =
        connections.values.where((connection) => connection.active).toList();
    if (activeConnections.isEmpty) {
      log('ERROR', 'OttsVision: nenhuma conexão externa ativa para gravar o DTTS');
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

      // ETAPA 2: gera hash EnX32 a partir do timestamp
      final hash64 = OttsVision.generateHash64();
      final seeds = OttsVision.sliceSeeds(hash64);
      final dtts = OttsVision.dttsFromSeeds(seeds);

      // ETAPA 3: soma os últimos 3 dígitos do timestamp ao hash
      final timestamp = DateTime.now().microsecondsSinceEpoch;
      final ultimos3 = BigInt.parse(timestamp.toString().substring(
            timestamp.toString().length - 3,
          ));
      final hashBig = BigInt.parse(hash64);
      final cripto = (hashBig + ultimos3)
          .toString()
          .padLeft(64, '0');
      final criptoFinal = cripto.substring(cripto.length - 64);

      // ETAPA 4: grava o novo DTTS no MySQL externo.
      // O DTTS anterior autentica a rotação; na primeira execução o gateway
      // aceita apenas o X-EnX-Token porque ainda não existe valor anterior.
      await api.storeDtts(
        dtts: dtts,
        previousDtts: previousDtts,
      );

      // ETAPA 5: grava o mesmo DTTS no Dataniverse.
      await dataniverse.command({
        'action': 'INSERT',
        'table': 'dtts',
        'data': {
          'dtts': dtts,
        },
      });

      // ETAPA 6: grava o hash e as oito seeds no Dataniverse.
      final chain = OttsChain(
        idModulo: 'ottsvision',
        seed: seeds.first,
        idPub: 'ottsvision-cron',
        content: [criptoFinal],
      ).seal();

      await dataniverse.command({
        'action': 'INSERT',
        'table': 'ottshash',
        'data': {
          ...chain.toDataniverse(),
          'ottshash': criptoFinal,
          'seed_1': seeds[0].toString(),
          'seed_2': seeds[1].toString(),
          'seed_3': seeds[2].toString(),
          'seed_4': seeds[3].toString(),
          'seed_5': seeds[4].toString(),
          'seed_6': seeds[5].toString(),
          'seed_7': seeds[6].toString(),
          'seed_8': seeds[7].toString(),
        },
      });

      log(
        'SUCCESS',
        'OttsVision: hash e DTTS gravados — ${criptoFinal.substring(0, 16)}...',
      );
    } catch (e) {
      log('ERROR', 'OttsVision hash: $e');
    } finally {
      api.dispose();
    }
  }
}