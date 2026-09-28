import 'package:enxcci/config/enxcci_config.dart';
import 'package:enxcci/dataniverse/dataniverse_client.dart';
import 'package:enxcci/engine/enxcci_engine.dart';
import 'package:enxcci/engine/modules/enx_crypt.dart';
import 'package:enxcci/jobs/job_script.dart';
import 'package:mysql_client/mysql_client.dart';

class OttsSeedScript extends EnXScript {
  @override
  String get id => 'otts_seed';

  @override
  String get label => 'OttsSeed — Seal';

  @override
  Future<void> run({
    required Map<String, EnXcciConfig> connections,
    required DataniverseClient dataniverse,
    required EnXcciEngine engine,
    required EngineLog log,
  }) async {
    // Pega a primeira conexão MySQL disponível
    final config = connections.values.firstOrNull;
    if (config == null) {
      log('ERROR', 'OttsSeed: nenhuma conexão MySQL configurada');
      return;
    }

    MySQLConnection? conn;
    try {
      conn = await MySQLConnection.createConnection(
        host: config.host,
        port: config.port,
        userName: config.user,
        password: config.password,
        databaseName: config.database,
      );
      await conn.connect();

      for (int modulo = 1; modulo <= 8; modulo++) {
        await _processModulo(conn, modulo, log);
      }

      log('SUCCESS', 'OttsSeed: selagem concluída para módulos 1-8');
    } catch (e) {
      log('ERROR', 'OttsSeed fatal: $e');
    } finally {
      await conn?.close();
    }
  }

  Future<void> _processModulo(
    MySQLConnection conn,
    int moduloId,
    EngineLog log,
  ) async {
    final tabela = 'ottsseeds_$moduloId';
    final colunaFatia = 'seed_$moduloId';

    try {
      // ETAPA 1: limpa registros fechados anteriores
      await conn.execute('DELETE FROM $tabela WHERE seal = "closed"');

      // ETAPA 2: busca fila collecting (mais antigos primeiro)
      final resultCollecting = await conn.execute(
        'SELECT id, seed, inseed, content FROM $tabela '
        'WHERE seal = "collecting" ORDER BY id ASC LIMIT 500',
      );

      final coletas = resultCollecting.rows.toList();
      if (coletas.isEmpty) {
        return;
      }

      log('INFO', 'OttsSeed módulo $moduloId: ${coletas.length} registros na fila');

      for (final row in coletas) {
        final id = row.colByName('id');
        final seedBase = row.colByName('seed') ?? '';
        final inSeed = row.colByName('inseed') ?? '';
        final content = row.colByName('content') ?? '';

        // Cifra o content com EnXCrypt
        final inSeedBig = BigInt.tryParse(inSeed) ?? BigInt.zero;
        final hashCifrado = EnXCrypt.enXCrypt(content, inSeedBig);

        // Pega os primeiros 8 dígitos da seed
        final seedOitoDigitos = seedBase.length >= 8
            ? seedBase.substring(0, 8)
            : seedBase.padLeft(8, '0');

        // ETAPA 3: busca seed_1 e seed_2 no ottshash
        final resultHash = await conn.execute(
          'SELECT seed_1, seed_2 FROM ottshash '
          'WHERE $colunaFatia = :seed LIMIT 1',
          {'seed': seedOitoDigitos},
        );

        if (resultHash.rows.isEmpty) {
          log('WARN', 'OttsSeed módulo $moduloId: sem ottshash para seed $seedOitoDigitos');
          continue;
        }

        final rowHash = resultHash.rows.first;
        final seed1 = rowHash.colByName('seed_1') ?? '';
        final seed2 = rowHash.colByName('seed_2') ?? '';
        final chainHash = '$seed1$seed2';

        // ETAPA 4: insere em ottschain
        await conn.execute(
          'INSERT INTO ottschain (ottschain, seed, hash) '
          'VALUES (:chain, :seed, :hash)',
          {
            'chain': chainHash,
            'seed': seedOitoDigitos,
            'hash': hashCifrado,
          },
        );

        // ETAPA 5: fecha o registro
        await conn.execute(
          'UPDATE $tabela SET seal = "closed" WHERE id = :id',
          {'id': id},
        );
      }
    } catch (e) {
      log('ERROR', 'OttsSeed módulo $moduloId: $e');
    }
  }
}