import 'package:flutter_test/flutter_test.dart';

import 'package:enxcci/engine/enxcci_engine.dart';
import 'package:enxcci/engine/modules/enx_crypt.dart';

void main() {
  test('OttsVision gera 64 dígitos e oito seeds', () {
    final hash = OttsVision.generateHash64();
    expect(hash.length, 64);
    expect(OttsVision.sliceSeeds(hash), hasLength(8));
  });

  test('EnXCrypt cifra e decifra o conteúdo', () {
    const content = 'registro enxOS';
    final encrypted = EnXCrypt.enXCrypt(content, BigInt.from(12345678));
    expect(EnXCrypt.enXDecrypt(encrypted, BigInt.from(12345678)), content);
  });
}