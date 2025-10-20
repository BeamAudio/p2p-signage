abstract class ISecurity {
  Future<String> sign(String data);
  Future<bool> verify(String data, String signature, String publicKey);
  Future<String> get publicKey;
}
