import 'dart:math';
import 'package:enxcci/engine/modules/enx_math.dart'; // Importe o seu arquivo de matemática

class EnXCrypt {
  static String enXCrypt(String content, BigInt seed) {
    if (content.isEmpty) return '';

    // Recupera a keystream de 640 caracteres do EnX302
    // O padLeft garante que zeros à esquerda não sejam perdidos na conversão de volta para String
    String keystream = EnXMath.enX302(seed).toString().padLeft(640, '0');
    int keyLen = keystream.length;
    
    StringBuffer hexOutput = StringBuffer();

    for (int i = 0; i < content.length; i++) {
      int byte = content.codeUnitAt(i);
      int offset = (i * 3) % max(1, keyLen - 3);
      int keyChunk = int.parse(keystream.substring(offset, offset + 3));

      int cifrado = (byte + keyChunk) % 256;
      hexOutput.write(cifrado.toRadixString(16).padLeft(2, '0'));
    }

    return hexOutput.toString();
  }

  static String enXDecrypt(String encrypted, BigInt seed) {
    if (encrypted.isEmpty) return '';

    String keystream = EnXMath.enX302(seed).toString().padLeft(640, '0');
    int keyLen = keystream.length;
    
    StringBuffer plainText = StringBuffer();
    String cleanHex = encrypted.replaceAll(RegExp(r'[^0-9a-fA-F]'), '');

    for (int i = 0; i < cleanHex.length; i += 2) {
      if (i + 1 >= cleanHex.length) break;
      
      String hex = cleanHex.substring(i, i + 2);
      int byteCifrado = int.parse(hex, radix: 16);

      int charIndex = i ~/ 2;
      int offset = (charIndex * 3) % max(1, keyLen - 3);
      int keyChunk = int.parse(keystream.substring(offset, offset + 3));

      int shift = keyChunk % 256;
      int byteOriginal = (byteCifrado - shift + 256) % 256;

      plainText.writeCharCode(byteOriginal);
    }

    return plainText.toString();
  }
}

String enXCrypt(String content, BigInt seed) => EnXCrypt.enXCrypt(content, seed);

String enXDecrypt(String encrypted, BigInt seed) => EnXCrypt.enXDecrypt(encrypted, seed);
