import 'dart:math';

import 'package:p2p_signage/src/security/i_security.dart';

class AuthService {
  final ISecurity _security;

  AuthService(this._security);

  String createChallenge() {
    const chars = 'AaBbCcDdEeFfGgHhIiJjKkLlMmNnOoPpQqRrSsTtUuVvWwXxYyZz1234567890';
    final rnd = Random();
    return String.fromCharCodes(Iterable.generate(
        32, (_) => chars.codeUnitAt(rnd.nextInt(chars.length))));
  }

  Future<bool> verifyResponse(String challenge, String response, String publicKey) async { // Made async
    return await _security.verify(challenge, response, publicKey); // Await verify
  }
}
