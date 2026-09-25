import 'dart:convert';
import 'package:intl/intl.dart';
import 'package:uuid/uuid.dart';
import 'package:enxcci/config/enxcci_config.dart';
import 'package:enxcci/dataniverse/dataniverse_client.dart';
import 'package:enxcci/engine/modules/enx_crypt.dart';
import 'package:enxcci/engine/modules/enx_math.dart';

class OttsVision {
  static String generateHash64() {
    final timestamp = DateTime.now().microsecondsSinceEpoch;
    final bigResult = EnXMath.enX32(BigInt.from(timestamp));
    // Converte e garante os 64 dígitos no padrão EnX OS
    final normalized = bigResult.toString().replaceAll(RegExp(r'[^0-9]'), '');
    return normalized.padLeft(64, '0').substring(normalized.length > 64 ? normalized.length - 64 : 0);
  }

  static List<int> sliceSeeds(String hash64) {
    final normalized = hash64.replaceAll(RegExp(r'[^0-9]'), '').padLeft(64, '0');
    return List<int>.generate(
      8,
      (index) => int.tryParse(normalized.substring(index * 8, index * 8 + 8)) ?? 0,
    );
  }

  static bool isExpired(DateTime createdAt) =>
      DateTime.now().difference(createdAt).inSeconds > 60;
}

class OttsChain {
  OttsChain({
    required this.idModulo,
    required this.seed,
    required this.idPub,
    required this.content,
    this.sealed = false,
    this.sealHash,
    DateTime? createdAt,
    String? id,
  })  : createdAt = createdAt ?? DateTime.now(),
        id = id ?? const Uuid().v4();

  final String id;
  final String idModulo;
  final int seed;
  final String idPub;
  final List<String> content;
  final bool sealed;
  final String? sealHash;
  final DateTime createdAt;

  OttsChain seal() {
  final encryptedContent = EnXCrypt.enXCrypt(content.join(), BigInt.from(seed));
  final input = '$seed|$encryptedContent|${content.join()}';
  
  // Soma dos codeUnits do input como BigInt base
  final inputBig = input.codeUnits
      .fold<BigInt>(BigInt.zero, (acc, c) => acc + BigInt.from(c));
  
  // Assinatura via EnX18 — 36 dígitos, puro enxOS
  final sealHash = EnXMath.enX9(inputBig).toString().padLeft(12, '0');

  return OttsChain(
    id: id,
    idModulo: idModulo,
    seed: seed,
    idPub: idPub,
    content: content,
    sealed: true,
    sealHash: sealHash,
    createdAt: createdAt,
  );
  }

  Map<String, dynamic> toDataniverse() => {
        'id': id,
        'ottshash': sealHash ?? id,
        'idModulo': idModulo,
        'seed': seed,
        'idPub': idPub,
        'content': content,
        'sealed': sealed,
        'sealHash': sealHash,
        'createdAt': createdAt.toIso8601String(),
      };
}

typedef EngineLog = void Function(String level, String message);

class EnXcciEngine {
  EnXcciEngine({
    required this.dataniverse,
    this.onLog,
  });

  final DataniverseClient dataniverse;
  final EngineLog? onLog;

  Future<int> processRows({
    required EnXJob job,
    required List<Map<String, dynamic>> rows,
  }) async {
    if (rows.isEmpty) {
      onLog?.call('INFO', '${job.label}: consulta sem registros');
      return 0;
    }

    final hash64 = OttsVision.generateHash64();
    final seeds = OttsVision.sliceSeeds(hash64);
    
    // Processamento da semente usando o novo EnXMath.enX3
    final BigInt enx3Result = EnXMath.enX3(BigInt.from(seeds.first));
    final seed = (enx3Result.abs().toInt() % 90000000) + 10000000;

    final chunks = <String>[];
    for (final row in rows) {
      final content = jsonEncode(row);
      for (var offset = 0; offset < content.length; offset += 640) {
        chunks.add(content.substring(
          offset,
          (offset + 640).clamp(0, content.length).toInt(),
        ));
      }
    }

    final chain = OttsChain(
      idModulo: 'enxcci',
      seed: seed,
      idPub: 'enxcci-server',
      content: chunks,
    ).seal();

    final response = await dataniverse.command({
      'action': 'INSERT',
      'table': job.targetTable,
      'seedShard': job.seedShard,
      'data': chain.toDataniverse(),
    });

    final status = response['status']?.toString() ?? 'UNKNOWN';
    onLog?.call(
      status == 'SUCCESS' || status == 'QUEUED' ? 'SUCCESS' : 'ERROR',
      '${job.label}: ${rows.length} registros processados → $status',
    );

    return rows.length;
  }

  String formatTimestamp(DateTime? value) =>
      value == null ? '—' : DateFormat('yyyy-MM-ddTHH:mm:ss').format(value.toLocal());
}
