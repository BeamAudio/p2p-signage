import 'dart:typed_data';

import 'dht.dart';

Uint8List xorDistance(Uint8List a, Uint8List b) {
  final result = Uint8List(NODE_ID_LENGTH);
  for (int i = 0; i < NODE_ID_LENGTH; i++) {
    result[i] = a[i] ^ b[i];
  }
  return result;
}

int compareDistances(Uint8List a, Uint8List b) {
  for (int i = 0; i < NODE_ID_LENGTH; i++) {
    if (a[i] < b[i]) return -1;
    if (a[i] > b[i]) return 1;
  }
  return 0;
}
