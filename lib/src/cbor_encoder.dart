/*
 * Package : Cbor
 * Author : S. Hamblett <steve.hamblett@linux.com>
 * Date   : 12/12/2016
 * Copyright :  S.Hamblett
 */

part of cbor;

// ignore_for_file: omit_local_variable_types
// ignore_for_file: unnecessary_final
// ignore_for_file: cascade_invocations
// ignore_for_file: avoid_print

/// The encoder class implements the CBOR decoder functionality as defined in
/// RFC7049.
class Encoder {
  /// Construction
  Encoder(Output out) {
    _out = out;
  }

  /// The output buffer
  Output _out;

  /// Indefinite sequence indicator, incremented on start
  /// decremented on stop.
  int _indefSequenceCount = 0;

  /// Clears the output buffer.
  void clear() {
    _out.clear();
  }

  /// Booleans.
  // ignore: avoid_positional_boolean_parameters
  void writeBool(bool value) {
    if (value) {
      _out.putByte(0xf5);
    } else {
      _out.putByte(0xf4);
    }
  }

  /// Positive and negative integers.
  void writeInt(int value) {
    if (value < 0) {
      _writeTypeValue(1, -(value + 1));
    } else {
      _writeTypeValue(0, value);
    }
  }

  /// Primitive byte writer.
  void writeBytes(typed.Uint8Buffer data) {
    _writeTypeValue(majorTypeBytes, data.length);
    _out.putBytes(data);
  }

  /// Raw byte buffer writer.
  /// No encoding is added to the buffer, it goes into the
  /// output stream as is.
  void writeRawBuffer(typed.Uint8Buffer buff) {
    _out.putBytes(buff);
  }

  /// Primitive string writer.
  // ignore: avoid_positional_boolean_parameters
  void writeString(String str, [bool indefinite = false]) {
    final typed.Uint8Buffer buff = strToByteString(str);
    if (indefinite) {
      startIndefinite(majorTypeString);
    }
    _writeTypeValue(majorTypeString, buff.length);
    _out.putBytes(buff);
  }

  /// Bytestring primitive.
  // ignore: avoid_positional_boolean_parameters
  void writeBuff(typed.Uint8Buffer data, [bool indefinite = false]) {
    if (indefinite) {
      startIndefinite(majorTypeBytes);
    }
    _writeTypeValue(majorTypeBytes, data.length);
    _out.putBytes(data);
  }

  /// Array primitive.
  /// Valid elements are string, integer, bool, float(any size), array
  /// or map. Returns true if the encoding has been successful.
  /// If you supply a length this will be used and not calculated from the
  /// array size, unless you are encoding certain indefinite sequences you
  /// do not need to do this.
  bool writeArray(List<dynamic> value,
      // ignore: avoid_positional_boolean_parameters
      [bool indefinite = false,
      int length]) {
    // Mark the output buffer, if we cannot encode
    // the whole array structure rewind so as to perform
    // no encoding.
    bool res = true;
    _out.mark();
    final bool ok = writeArrayImpl(value, indefinite, length);
    if (!ok) {
      _out.resetToMark();
      res = false;
    }
    return res;
  }

  /// Map primitive.
  /// Valid map keys are integer and string. RFC7049
  /// recommends keys be of a single type, we are more generous
  /// here.
  /// Valid map values are integer, string, bool, float(any size), array
  /// map or buffer. Returns true if the encoding has been successful.
  bool writeMap(Map<dynamic, dynamic> value,
      // ignore: avoid_positional_boolean_parameters
      [bool indefinite = false,
      int length]) {
    // Mark the output buffer, if we cannot encode
    // the whole map structure rewind so as to perform
    // no encoding.
    bool res = true;
    _out.mark();
    final bool ok = writeMapImpl(value, indefinite, length);
    if (!ok) {
      _out.resetToMark();
      res = false;
    }
    return res;
  }

  /// Tag primitive.
  void writeTag(int tag) {
    _writeTypeValue(majorTypeTag, tag);
  }

  /// Special(major type 7) primitive.
  void writeSpecial(int special) {
    int type = majorTypeSpecial;
    type <<= majorTypeShift;
    _out.putByte(type | special);
  }

  /// Null writer.
  void writeNull() {
    _out.putByte(0xf6);
  }

  /// Undefined writer.
  void writeUndefined() {
    _out.putByte(0xf7);
  }

  /// Indefinite item break primitive.
  void writeBreak() {
    writeSpecial(aiBreak);
    _indefSequenceCount--;
  }

  /// Indefinite item start.
  void startIndefinite(int majorType) {
    _out.putByte((majorType << 5) + aiBreak);
    _indefSequenceCount++;
  }

  /// Simple values, negative values, values over 255 or less
  /// than 0 will be encoded as an int.
  void writeSimple(int value) {
    if (!value.isNegative) {
      if ((value <= simpleLimitUpper) && (value >= simpleLimitLower)) {
        if (value <= ai23) {
          writeSpecial(value);
        } else {
          writeSpecial(ai24);
          _out.putByte(value);
        }
      } else {
        writeInt(value);
      }
    } else {
      writeInt(value);
    }
  }

  /// Generalised float encoder, picks the smallest encoding
  /// it can. If you want a specific precision use the more
  /// specialised methods.
  /// Note this can lead to encodings you may not expect in corner cases,
  /// if you want specific sized encodings don't use this.
  void writeFloat(double value) {
    if (canBeAHalf(value)) {
      writeHalf(value);
    } else if (canBeASingle(value)) {
      writeSingle(value);
    } else {
      writeDouble(value);
    }
  }

  /// Half precision float.
  void writeHalf(double value) {
    writeSpecial(ai25);
    // Special encodings
    if (value.isNaN) {
      _out.putByte(0x7e);
      _out.putByte(0x00);
    } else {
      final typed.Uint8Buffer valBuff = _singleToHalf(value);
      _out.putByte(valBuff[1]);
      _out.putByte(valBuff[0]);
    }
  }

  /// Single precision float.
  void writeSingle(double value) {
    writeSpecial(ai26);
    // Special encodings
    if (value.isNaN) {
      _out.putByte(0x7f);
      _out.putByte(0xc0);
      _out.putByte(0x00);
      _out.putByte(0x00);
    } else {
      final typed.Float32Buffer fBuff = typed.Float32Buffer(1);
      fBuff[0] = value;
      final ByteBuffer bBuff = fBuff.buffer;
      final Uint8List uList = bBuff.asUint8List();
      _out.putByte(uList[3]);
      _out.putByte(uList[2]);
      _out.putByte(uList[1]);
      _out.putByte(uList[0]);
    }
  }

  /// Double precision float.
  void writeDouble(double value) {
    writeSpecial(ai27);
    // Special encodings
    if (value.isNaN) {
      _out.putByte(0x7f);
      _out.putByte(0xf8);
      _out.putByte(0x00);
      _out.putByte(0x00);
      _out.putByte(0x00);
      _out.putByte(0x00);
      _out.putByte(0x00);
      _out.putByte(0x00);
    } else {
      final typed.Float64Buffer fBuff = typed.Float64Buffer(1);
      fBuff[0] = value;
      final ByteBuffer bBuff = fBuff.buffer;
      final Uint8List uList = bBuff.asUint8List();
      _out.putByte(uList[7]);
      _out.putByte(uList[6]);
      _out.putByte(uList[5]);
      _out.putByte(uList[4]);
      _out.putByte(uList[3]);
      _out.putByte(uList[2]);
      _out.putByte(uList[1]);
      _out.putByte(uList[0]);
    }
  }

  /// Tag based Date/Time encoding.
  /// Standard format as described in RFC339 et al.
  void writeDateTime(String dt) {
    writeTag(0);
    writeString(dt);
  }

  /// Tag based epoch encoding. Format can be a positive
  /// or negative integer or a floating point number for
  /// which you can chose the encoding.
  void writeEpoch(num epoch, [encodeFloatAs floatType = encodeFloatAs.single]) {
    writeTag(1);
    if (epoch.runtimeType == int) {
      writeInt(epoch);
    } else {
      if (floatType == encodeFloatAs.half) {
        writeHalf(epoch);
      } else if (floatType == encodeFloatAs.single) {
        writeSingle(epoch);
      } else {
        writeDouble(epoch);
      }
    }
  }

  /// Tag based Base64 byte string encoding. The encoder does not
  /// itself perform the base encoding as stated in RFC7049,
  /// it just indicates to the decoder that the following byte
  /// string maybe base encoded.
  void writeBase64(typed.Uint8Buffer data) {
    writeTag(22);
    writeBytes(data);
  }

  /// Cbor data item encoder, refer to tyhe RFC for details.
  void writeCborDi(typed.Uint8Buffer data) {
    writeTag(24);
    writeBytes(data);
  }

  /// Tag based Base64 URL byte string encoding. The encoder does not
  /// itself perform the base encoding as stated in RFC7049,
  /// it just indicates to the decoder that the following byte
  /// string maybe base encoded.
  void writeBase64URL(typed.Uint8Buffer data) {
    writeTag(21);
    writeBytes(data);
  }

  /// Tag based Base16 byte string encoding. The encoder does not
  /// itself perform the base encoding as stated in RFC7049,
  /// it just indicates to the decoder that the following byte
  /// string maybe base encoded.
  void writeBase16(typed.Uint8Buffer data) {
    writeTag(23);
    writeBytes(data);
  }

  /// Tag based URI writer
  void writeURI(String uri) {
    writeTag(32);
    writeString(uri);
  }

  /// Helper functions

  /// Lookup table based single to half precision conversion.
  /// Rounding is indeterminate.
  typed.Uint8Buffer _singleToHalf(double value) {
    final int hBits = getHalfPrecisionInt(value);
    final typed.Uint16Buffer hBuff = typed.Uint16Buffer(1);
    hBuff[0] = hBits;
    final ByteBuffer lBuff = hBuff.buffer;
    final Uint8List hList = lBuff.asUint8List();
    final typed.Uint8Buffer valBuff = typed.Uint8Buffer();
    valBuff.addAll(hList);
    return valBuff;
  }

  /// Encoding helper for type encoding.
  void _writeTypeValue(int majorType, int value) {
    int type = majorType;
    type <<= majorTypeShift;
    if (value < ai24) {
      // Value
      _out.putByte(type | value);
    } else if (value < two8) {
      // Uint8
      _out.putByte(type | ai24);
      _out.putByte(value);
    } else if (value < two16) {
      // Uint16
      _out.putByte(type | ai25);
      final typed.Uint16Buffer buff = typed.Uint16Buffer(1);
      buff[0] = value;
      final Uint8List ulist = Uint8List.view(buff.buffer);
      final typed.Uint8Buffer data = typed.Uint8Buffer();
      data.addAll(ulist.toList().reversed);
      _out.putBytes(data);
    } else if (value < two32) {
      // Uint32
      _out.putByte(type | ai26);
      final typed.Uint32Buffer buff = typed.Uint32Buffer(1);
      buff[0] = value;
      final Uint8List ulist = Uint8List.view(buff.buffer);
      final typed.Uint8Buffer data = typed.Uint8Buffer();
      data.addAll(ulist.toList().reversed);
      _out.putBytes(data);
    } else if (value < two64) {
      // Uint64
      _out.putByte(type | ai27);
      final typed.Uint64Buffer buff = typed.Uint64Buffer(1);
      buff[0] = value;
      final Uint8List ulist = Uint8List.view(buff.buffer);
      final typed.Uint8Buffer data = typed.Uint8Buffer();
      data.addAll(ulist.toList().reversed);
      _out.putBytes(data);
    } else {
      // Bignum - not supported, use tags
      print('Bignums not supported');
    }
  }

  /// String to byte string helper.
  typed.Uint8Buffer strToByteString(String str) {
    final typed.Uint8Buffer buff = typed.Uint8Buffer();
    const convertor.Utf8Encoder utf = convertor.Utf8Encoder();
    final List<int> codes = utf.convert(str);
    buff.addAll(codes);
    return buff;
  }

  /// Array write implementation method.
  /// If the array cannot be fully encoded no encoding occurs,
  /// ie false is returned.
  bool writeArrayImpl(List<dynamic> value,
      // ignore: avoid_positional_boolean_parameters
      [bool indefinite = false,
      int length]) {
    // Check for empty
    if (value.isEmpty) {
      if (!indefinite) {
        _writeTypeValue(majorTypeArray, 0);
      } else {
        startIndefinite(majorTypeArray);
      }
      return true;
    }

    // Build the encoded array.
    if (!indefinite) {
      if (length != null) {
        _writeTypeValue(majorTypeArray, length);
      } else {
        _writeTypeValue(majorTypeArray, value.length);
      }
    } else {
      startIndefinite(majorTypeArray);
    }

    bool ok = true;
    for (final dynamic element in value) {
      String valType = element.runtimeType.toString();
      if (valType.contains('List')) {
        valType = 'List';
      }
      if (valType.contains('Map')) {
        valType = 'Map';
      }
      switch (valType) {
        case 'int':
          writeInt(element);
          break;
        case 'String':
          writeString(element);
          break;
        case 'double':
          writeFloat(element);
          break;
        case 'List':
          if (!indefinite) {
            final bool res = writeArrayImpl(element, indefinite);
            if (!res) {
              // Fail the whole encoding
              ok = false;
            }
          } else {
            element.forEach(_out.putByte);
          }
          break;
        case 'Map':
          if (!indefinite) {
            final bool res = writeMapImpl(element, indefinite);
            if (!res) {
              // Fail the whole encoding
              ok = false;
            }
          } else {
            element.forEach(_out.putByte);
          }
          break;
        case 'bool':
          writeBool(element);
          break;
        case 'Null':
          writeNull();
          break;
        case 'Uint8Buffer':
          writeRawBuffer(element);
          break;
        default:
          print('writeArrayImpl::RT is ${element.runtimeType.toString()}');
          ok = false;
      }
    }
    return ok;
  }

  /// Map write implementation method.
  /// If the map cannot be fully encoded no encoding occurs,
  /// ie false is returned.
  bool writeMapImpl(Map<dynamic, dynamic> value,
      // ignore: avoid_positional_boolean_parameters
      [bool indefinite = false,
      int length]) {
    // Check for empty
    if (value.isEmpty) {
      if (!indefinite) {
        _writeTypeValue(majorTypeMap, 0);
      }
      return true;
    }

    // Check the keys are integers or strings.
    final dynamic keys = value.keys;
    bool keysValid = true;
    for (final dynamic element in keys) {
      if (!(element.runtimeType.toString() == 'int') &&
          !(element.runtimeType.toString() == 'String')) {
        keysValid = false;
        break;
      }
    }
    if (!keysValid) {
      return false;
    }
    // Build the encoded map.
    if (!indefinite) {
      if (_indefSequenceCount == 0) {
        if (length != null) {
          _writeTypeValue(majorTypeMap, length);
        } else {
          _writeTypeValue(majorTypeMap, value.length);
        }
      }
    } else {
      startIndefinite(majorTypeMap);
    }

    bool ok = true;
    // ignore: always_specify_types
    value.forEach((key, val) {
      // Encode the key, can now only be ints or strings.
      if (key.runtimeType.toString() == 'int') {
        writeInt(key);
      } else {
        writeString(key);
      }
      // Encode the value
      String valType = val.runtimeType.toString();
      if (valType.contains('List')) {
        valType = 'List';
      }
      if (valType.contains('Map')) {
        valType = 'Map';
      }
      switch (valType) {
        case 'int':
          writeInt(val);
          break;
        case 'String':
          writeString(val);
          break;
        case 'double':
          writeFloat(val);
          break;
        case 'List':
          if (!indefinite) {
            final bool res = writeArrayImpl(val, indefinite);
            if (!res) {
              // Fail the whole encoding
              ok = false;
            }
          } else {
            val.forEach(_out.putByte);
          }
          break;
        case 'Map':
          if (!indefinite) {
            final bool res = writeMapImpl(val, indefinite);
            if (!res) {
              // Fail the whole encoding
              ok = false;
            }
          } else {
            val.forEach(_out.putByte);
          }
          break;
        case 'bool':
          writeBool(val);
          break;
        case 'Null':
          writeNull();
          break;
        case 'Uint8Buffer':
          writeRawBuffer(val);
          break;
        default:
          print('writeMapImpl::RT is ${val.runtimeType.toString()}');
          ok = false;
      }
    });
    return ok;
  }
}
