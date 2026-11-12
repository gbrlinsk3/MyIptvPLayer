/// SHA-256 em Dart puro (sem pacote). Usado para conferir o arquivo de
/// atualização baixado. Entrada em partes não é necessária: o arquivo é lido
/// em blocos pelo chamador via [Sha256.add] e finalizado com [close].
class Sha256 {
  static const _k = <int>[
    0x428a2f98, 0x71374491, 0xb5c0fbcf, 0xe9b5dba5, 0x3956c25b, 0x59f111f1,
    0x923f82a4, 0xab1c5ed5, 0xd807aa98, 0x12835b01, 0x243185be, 0x550c7dc3,
    0x72be5d74, 0x80deb1fe, 0x9bdc06a7, 0xc19bf174, 0xe49b69c1, 0xefbe4786,
    0x0fc19dc6, 0x240ca1cc, 0x2de92c6f, 0x4a7484aa, 0x5cb0a9dc, 0x76f988da,
    0x983e5152, 0xa831c66d, 0xb00327c8, 0xbf597fc7, 0xc6e00bf3, 0xd5a79147,
    0x06ca6351, 0x14292967, 0x27b70a85, 0x2e1b2138, 0x4d2c6dfc, 0x53380d13,
    0x650a7354, 0x766a0abb, 0x81c2c92e, 0x92722c85, 0xa2bfe8a1, 0xa81a664b,
    0xc24b8b70, 0xc76c51a3, 0xd192e819, 0xd6990624, 0xf40e3585, 0x106aa070,
    0x19a4c116, 0x1e376c08, 0x2748774c, 0x34b0bcb5, 0x391c0cb3, 0x4ed8aa4a,
    0x5b9cca4f, 0x682e6ff3, 0x748f82ee, 0x78a5636f, 0x84c87814, 0x8cc70208,
    0x90befffa, 0xa4506ceb, 0xbef9a3f7, 0xc67178f2,
  ];

  final List<int> _h = [
    0x6a09e667, 0xbb67ae85, 0x3c6ef372, 0xa54ff53a,
    0x510e527f, 0x9b05688c, 0x1f83d9ab, 0x5be0cd19,
  ];
  final List<int> _buf = [];
  int _length = 0;
  bool _closed = false;

  static const _m = 0xFFFFFFFF;
  static int _rotr(int x, int n) => ((x >> n) | (x << (32 - n))) & _m;

  void add(List<int> data) {
    assert(!_closed);
    _length += data.length;
    _buf.addAll(data);
    while (_buf.length >= 64) {
      _block(_buf, 0);
      _buf.removeRange(0, 64);
    }
  }

  /// Devolve o hash em hexadecimal minúsculo.
  String close() {
    _closed = true;
    final bits = _length * 8;
    _buf.add(0x80);
    while (_buf.length % 64 != 56) {
      _buf.add(0);
    }
    for (var i = 7; i >= 0; i--) {
      _buf.add((bits >> (i * 8)) & 0xFF);
    }
    for (var o = 0; o < _buf.length; o += 64) {
      _block(_buf, o);
    }
    return _h.map((v) => v.toRadixString(16).padLeft(8, '0')).join();
  }

  void _block(List<int> d, int o) {
    final w = List<int>.filled(64, 0);
    for (var i = 0; i < 16; i++) {
      w[i] = (d[o + i * 4] << 24) |
          (d[o + i * 4 + 1] << 16) |
          (d[o + i * 4 + 2] << 8) |
          d[o + i * 4 + 3];
    }
    for (var i = 16; i < 64; i++) {
      final s0 = _rotr(w[i - 15], 7) ^ _rotr(w[i - 15], 18) ^ (w[i - 15] >> 3);
      final s1 = _rotr(w[i - 2], 17) ^ _rotr(w[i - 2], 19) ^ (w[i - 2] >> 10);
      w[i] = (w[i - 16] + s0 + w[i - 7] + s1) & _m;
    }
    var a = _h[0], b = _h[1], c = _h[2], d0 = _h[3];
    var e = _h[4], f = _h[5], g = _h[6], h = _h[7];
    for (var i = 0; i < 64; i++) {
      final s1 = _rotr(e, 6) ^ _rotr(e, 11) ^ _rotr(e, 25);
      final ch = (e & f) ^ ((~e & _m) & g);
      final t1 = (h + s1 + ch + _k[i] + w[i]) & _m;
      final s0 = _rotr(a, 2) ^ _rotr(a, 13) ^ _rotr(a, 22);
      final maj = (a & b) ^ (a & c) ^ (b & c);
      final t2 = (s0 + maj) & _m;
      h = g;
      g = f;
      f = e;
      e = (d0 + t1) & _m;
      d0 = c;
      c = b;
      b = a;
      a = (t1 + t2) & _m;
    }
    _h[0] = (_h[0] + a) & _m;
    _h[1] = (_h[1] + b) & _m;
    _h[2] = (_h[2] + c) & _m;
    _h[3] = (_h[3] + d0) & _m;
    _h[4] = (_h[4] + e) & _m;
    _h[5] = (_h[5] + f) & _m;
    _h[6] = (_h[6] + g) & _m;
    _h[7] = (_h[7] + h) & _m;
  }

  static String ofBytes(List<int> data) => (Sha256()..add(data)).close();
}
