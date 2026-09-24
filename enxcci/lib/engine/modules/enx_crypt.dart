import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';

class EnXCrypt {
  static String enXCrypt(String content, BigInt seed) {
    final source = utf8.encode(content);
    final key = sha256.convert(utf8.encode(seed.toString())).bytes;
    final encrypted = List<int>.generate(
      source.length,
      (index) => source[index] ^ key[index % key.length],
    );
    return base64UrlEncode(encrypted);
  }

  static String enXDecrypt(String encrypted, BigInt seed) {
    final source = base64Url.decode(encrypted);
    final key = sha256.convert(utf8.encode(seed.toString())).bytes;
    final decrypted = Uint8List.fromList(List<int>.generate(
      source.length,
      (index) => source[index] ^ key[index % key.length],
    ));
    return utf8.decode(decrypted);
  }
}

String enXCrypt(String content, BigInt seed) => EnXCrypt.enXCrypt(content, seed);

String enXDecrypt(String encrypted, BigInt seed) =>
    EnXCrypt.enXDecrypt(encrypted, seed);