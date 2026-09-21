import 'dart:convert';
import 'dart:typed_data';

/// Pure Dart SM4 (GB/T 32907-2016) — ECB mode with PKCS#7 padding.
///
/// No dependency on pointycastle.

const int _blockSize = 16;

/// SM4 S-box
const List<int> _sbox = [
  0xd6, 0x90, 0xe9, 0xfe, 0xcc, 0xe1, 0x3d, 0xb7, 0x16, 0xb6, 0x14, 0xc2, 0x28,
  0xfb, 0x2c, 0x05, 0x2b, 0x67, 0x9a, 0x76, 0x2a, 0xbe, 0x04, 0xc3, 0xaa, 0x44,
  0x13, 0x26, 0x49, 0x86, 0x06, 0x99, 0x9c, 0x42, 0x50, 0xf4, 0x91, 0xef, 0x98,
  0x7a, 0x33, 0x54, 0x0b, 0x43, 0xed, 0xcf, 0xac, 0x62, 0xe4, 0xb3, 0x1c, 0xa9,
  0xc9, 0x08, 0xe8, 0x95, 0x80, 0xdf, 0x94, 0xfa, 0x75, 0x8f, 0x3f, 0xa6, 0x47,
  0x07, 0xa7, 0xfc, 0xf3, 0x73, 0x17, 0xba, 0x83, 0x59, 0x3c, 0x19, 0xe6, 0x85,
  0x4f, 0xa8, 0x68, 0x6b, 0x81, 0xb2, 0x71, 0x64, 0xda, 0x8b, 0xf8, 0xeb, 0x0f,
  0x4b, 0x70, 0x56, 0x9d, 0x35, 0x1e, 0x24, 0x0e, 0x5e, 0x63, 0x58, 0xd1, 0xa2,
  0x25, 0x22, 0x7c, 0x3b, 0x01, 0x21, 0x78, 0x87, 0xd4, 0x00, 0x46, 0x57, 0x9f,
  0xd3, 0x27, 0x52, 0x4c, 0x36, 0x02, 0xe7, 0xa0, 0xc4, 0xc8, 0x9e, 0xea, 0xbf,
  0x8a, 0xd2, 0x40, 0xc7, 0x38, 0xb5, 0xa3, 0xf7, 0xf2, 0xce, 0xf9, 0x61, 0x15,
  0xa1, 0xe0, 0xae, 0x5d, 0xa4, 0x9b, 0x34, 0x1a, 0x55, 0xad, 0x93, 0x32, 0x30,
  0xf5, 0x8c, 0xb1, 0xe3, 0x1d, 0xf6, 0xe2, 0x2e, 0x82, 0x66, 0xca, 0x60, 0xc0,
  0x29, 0x23, 0xab, 0x0d, 0x53, 0x4e, 0x6f, 0xd5, 0xdb, 0x37, 0x45, 0xde, 0xfd,
  0x8e, 0x2f, 0x03, 0xff, 0x6a, 0x72, 0x6d, 0x6c, 0x5b, 0x51, 0x8d, 0x1b, 0xaf,
  0x92, 0xbb, 0xdd, 0xbc, 0x7f, 0x11, 0xd9, 0x5c, 0x41, 0x1f, 0x10, 0x5a, 0xd8,
  0x0a, 0xc1, 0x31, 0x88, 0xa5, 0xcd, 0x7b, 0xbd, 0x2d, 0x74, 0xd0, 0x12, 0xb8,
  0xe5, 0xb4, 0xb0, 0x89, 0x69, 0x97, 0x4a, 0x0c, 0x96, 0x77, 0x7e, 0x65, 0xb9,
  0xf1, 0x09, 0xc5, 0x6e, 0xc6, 0x84, 0x18, 0xf0, 0x7d, 0xec, 0x3a, 0xdc, 0x4d,
  0x20, 0x79, 0xee, 0x5f, 0x3e, 0xd7, 0xcb, 0x39, 0x48,
];

/// System parameter FK
const List<int> _fk = [
  0xa3b1bac6,
  0x56aa3350,
  0x677d9197,
  0xb27022dc,
];

/// Fixed parameter CK
const List<int> _ck = [
  0x00070e15, 0x1c232a31, 0x383f464d, 0x545b6269,
  0x70777e85, 0x8c939aa1, 0xa8afb6bd, 0xc4cbd2d9,
  0xe0e7eef5, 0xfc030a11, 0x181f262d, 0x343b4249,
  0x50575e65, 0x6c737a81, 0x888f969d, 0xa4abb2b9,
  0xc0c7ced5, 0xdce3eaf1, 0xf8ff060d, 0x141b2229,
  0x30373e45, 0x4c535a61, 0x686f767d, 0x848b9299,
  0xa0a7aeb5, 0xbcc3cad1, 0xd8dfe6ed, 0xf4fb0209,
  0x10171e25, 0x2c333a41, 0x484f565d, 0x646b7279,
];

int _rotl(int x, int n) =>
    ((x << n) | ((x & 0xffffffff) >> (32 - n))) & 0xffffffff;

int _tau(int a) {
  final b0 = _sbox[(a >> 24) & 0xff];
  final b1 = _sbox[(a >> 16) & 0xff];
  final b2 = _sbox[(a >> 8) & 0xff];
  final b3 = _sbox[a & 0xff];
  return ((b0 << 24) | (b1 << 16) | (b2 << 8) | b3) & 0xffffffff;
}

/// Linear transform L for round function
int _l(int b) =>
    (b ^ _rotl(b, 2) ^ _rotl(b, 10) ^ _rotl(b, 18) ^ _rotl(b, 24)) & 0xffffffff;

/// Linear transform L' for key expansion
int _lPrime(int b) =>
    (b ^ _rotl(b, 13) ^ _rotl(b, 23)) & 0xffffffff;

int _t(int x) => _l(_tau(x));

int _tPrime(int x) => _lPrime(_tau(x));

List<int> _expandKey(Uint8List key) {
  if (key.length != 16) {
    throw ArgumentError('SM4 key must be 16 bytes, got ${key.length}');
  }
  final mk = List<int>.generate(
    4,
    (i) =>
        ((key[4 * i] << 24) |
            (key[4 * i + 1] << 16) |
            (key[4 * i + 2] << 8) |
            key[4 * i + 3]) &
        0xffffffff,
  );
  final k = List<int>.filled(36, 0);
  for (var i = 0; i < 4; i++) {
    k[i] = (mk[i] ^ _fk[i]) & 0xffffffff;
  }
  final rk = List<int>.filled(32, 0);
  for (var i = 0; i < 32; i++) {
    k[i + 4] =
        (k[i] ^ _tPrime(k[i + 1] ^ k[i + 2] ^ k[i + 3] ^ _ck[i])) & 0xffffffff;
    rk[i] = k[i + 4];
  }
  return rk;
}

void _cryptBlock(Uint8List input, int offset, List<int> rk, Uint8List output,
    int outOffset) {
  final x = List<int>.filled(36, 0);
  for (var i = 0; i < 4; i++) {
    x[i] = ((input[offset + 4 * i] << 24) |
            (input[offset + 4 * i + 1] << 16) |
            (input[offset + 4 * i + 2] << 8) |
            input[offset + 4 * i + 3]) &
        0xffffffff;
  }
  for (var i = 0; i < 32; i++) {
    x[i + 4] =
        (x[i] ^ _t(x[i + 1] ^ x[i + 2] ^ x[i + 3] ^ rk[i])) & 0xffffffff;
  }
  for (var i = 0; i < 4; i++) {
    final v = x[35 - i];
    output[outOffset + 4 * i] = (v >> 24) & 0xff;
    output[outOffset + 4 * i + 1] = (v >> 16) & 0xff;
    output[outOffset + 4 * i + 2] = (v >> 8) & 0xff;
    output[outOffset + 4 * i + 3] = v & 0xff;
  }
}

Uint8List _pkcs7Pad(Uint8List data) {
  final pad = _blockSize - (data.length % _blockSize);
  final out = Uint8List(data.length + pad);
  out.setRange(0, data.length, data);
  for (var i = data.length; i < out.length; i++) {
    out[i] = pad;
  }
  return out;
}

Uint8List _pkcs7Unpad(Uint8List data) {
  if (data.isEmpty || data.length % _blockSize != 0) {
    throw ArgumentError('Invalid PKCS#7 padded data length');
  }
  final pad = data.last;
  if (pad < 1 || pad > _blockSize) {
    throw ArgumentError('Invalid PKCS#7 padding');
  }
  for (var i = data.length - pad; i < data.length; i++) {
    if (data[i] != pad) {
      throw ArgumentError('Invalid PKCS#7 padding');
    }
  }
  return Uint8List.sublistView(data, 0, data.length - pad);
}

List<int> _reverseRk(List<int> rk) => List<int>.generate(32, (i) => rk[31 - i]);

/// SM4-ECB encrypt. [key] must be 16 bytes. Applies PKCS#7 padding.
Uint8List sm4EcbEncrypt(Uint8List key, Uint8List plaintext) {
  final rk = _expandKey(key);
  final padded = _pkcs7Pad(plaintext);
  final out = Uint8List(padded.length);
  for (var i = 0; i < padded.length; i += _blockSize) {
    _cryptBlock(padded, i, rk, out, i);
  }
  return out;
}

/// SM4-ECB decrypt. [key] must be 16 bytes. Strips PKCS#7 padding.
Uint8List sm4EcbDecrypt(Uint8List key, Uint8List ciphertext) {
  if (ciphertext.length % _blockSize != 0) {
    throw ArgumentError('Ciphertext length must be a multiple of 16');
  }
  final rk = _reverseRk(_expandKey(key));
  final out = Uint8List(ciphertext.length);
  for (var i = 0; i < ciphertext.length; i += _blockSize) {
    _cryptBlock(ciphertext, i, rk, out, i);
  }
  return _pkcs7Unpad(out);
}

/// Encrypt UTF-8 plaintext and return Base64 ciphertext.
String sm4EcbEncryptToBase64(Uint8List key, String utf8Plaintext) {
  final cipher = sm4EcbEncrypt(key, Uint8List.fromList(utf8.encode(utf8Plaintext)));
  return base64Encode(cipher);
}

/// Decrypt Base64 ciphertext and return UTF-8 plaintext.
String sm4EcbDecryptFromBase64(Uint8List key, String base64Cipher) {
  final plain = sm4EcbDecrypt(key, base64Decode(base64Cipher));
  return utf8.decode(plain);
}
