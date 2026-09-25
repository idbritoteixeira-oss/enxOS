class _EnXBase {
  static String toStringPad(BigInt n, int width) {
    String s = n.toString().replaceAll(RegExp(r'[^0-9]'), '');
    if (s.isEmpty) s = '0';
    if (s.length < width) {
      s = s.padLeft(width, '0');
    }
    return s.substring(s.length - width);
  }

  static String expandir(String base, int alvo) {
    String res = base;
    if (res.isEmpty) res = '0';

    while (res.length < alvo) {
      BigInt n = BigInt.zero;
      int len = res.length;
      
      for (int i = 0; i < len; i++) {
        BigInt charCode = BigInt.from(res.codeUnitAt(i));
        BigInt pesoPosicao = BigInt.from(i + 1);
        BigInt term = charCode * BigInt.from(31) * pesoPosicao;
        n += term;
      }
      
      BigInt multiplicador = BigInt.from(len + 1);
      BigInt blocoCalculado = n * multiplicador;
      res += toStringPad(blocoCalculado, 3);
    }
    
    return res.substring(0, alvo);
  }
}

class EnXMath {
  static BigInt enX1(BigInt seed) {
    return ((seed * BigInt.from(137)) + BigInt.from(11)) % BigInt.from(1000);
  }

  static BigInt enX3(BigInt seed) {
    return ((enX1(seed) * BigInt.from(827)) + BigInt.from(97)) % BigInt.from(1000000);
  }

  static BigInt enX6(BigInt seed) {
    return ((enX3(seed) * BigInt.from(1000003)) + BigInt.from(7)) % BigInt.from(1000000000);
  }

  static BigInt enX9(BigInt seed) {
    return ((enX6(seed) * BigInt.from(1234567)) + BigInt.from(1)) % BigInt.from(1000000000000);
  }

  static BigInt enX18(BigInt seed) {
    String base9 = _EnXBase.toStringPad(enX9(seed), 12);
    return BigInt.parse(_EnXBase.expandir(base9, 36));
  }

  static BigInt enX32(BigInt seed) {
    String base36 = _EnXBase.toStringPad(enX18(seed), 36);
    return BigInt.parse(_EnXBase.expandir(base36, 64));
  }

  static BigInt enX64(BigInt seed) {
    String base64 = _EnXBase.toStringPad(enX32(seed), 64);
    return BigInt.parse(_EnXBase.expandir(base64, 128));
  }

  static BigInt enX302(BigInt seed) {
    String base32 = _EnXBase.toStringPad(enX32(seed), 64);
    return BigInt.parse(_EnXBase.expandir(base32, 640));
  }

  static BigInt enX609(BigInt seed) {
    String base64 = _EnXBase.toStringPad(enX64(seed), 128);
    return BigInt.parse(_EnXBase.expandir(base64, 1280));
  }
}

BigInt enX1(BigInt seed) => EnXMath.enX1(seed);
BigInt enX3(BigInt seed) => EnXMath.enX3(seed);
BigInt enX6(BigInt seed) => EnXMath.enX6(seed);
BigInt enX9(BigInt seed) => EnXMath.enX9(seed);
BigInt enX18(BigInt seed) => EnXMath.enX18(seed);
BigInt enX32(BigInt seed) => EnXMath.enX32(seed);
BigInt enX64(BigInt seed) => EnXMath.enX64(seed);
BigInt enX302(BigInt seed) => EnXMath.enX302(seed);
BigInt enX609(BigInt seed) => EnXMath.enX609(seed);
