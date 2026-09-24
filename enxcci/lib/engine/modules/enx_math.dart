class EnXMath {
  // TODO: lógica EnX1 em cada um.
  static BigInt enX1(BigInt seed) => seed;

  // TODO: lógica EnX3 em cada um.
  static BigInt enX3(BigInt seed) => (seed * BigInt.from(3)) + BigInt.from(17);

  // TODO: lógica EnX6 em cada um.
  static BigInt enX6(BigInt seed) => (seed * BigInt.from(6)) + BigInt.from(31);

  // TODO: lógica EnX9 em cada um.
  static BigInt enX9(BigInt seed) => (seed * BigInt.from(9)) + BigInt.from(47);

  // TODO: lógica EnX18 em cada um.
  static BigInt enX18(BigInt seed) => (seed * BigInt.from(18)) + BigInt.from(97);

  // TODO: lógica EnX32 em cada um.
  static BigInt enX32(BigInt seed) => (seed * BigInt.from(32)) + BigInt.from(193);

  // TODO: lógica EnX64 em cada um.
  static BigInt enX64(BigInt seed) => (seed * BigInt.from(64)) + BigInt.from(389);

  // TODO: lógica EnX302 em cada um.
  static BigInt enX302(BigInt seed) => (seed * BigInt.from(302)) + BigInt.from(1801);

  // TODO: lógica EnX609 em cada um.
  static BigInt enX609(BigInt seed) => (seed * BigInt.from(609)) + BigInt.from(3607);
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