// ------------------ shot header/frame encoding / decoding ------------------------------

import 'dart:developer';
import 'dart:typed_data';

class De1ShotProfile {
  De1ShotProfile(this.shot_header, this.shot_frames, this.shot_exframes);

  De1ShotHeaderClass shot_header;
  List<De1ShotFrameClass> shot_frames;
  List<De1ShotExtFrameClass> shot_exframes;
}

class De1ShotHeaderClass // proc spec_shotdescheader
{
  int headerV = 1; // hard-coded
  int numberOfFrames = 0; // total num frames
  int numberOfPreinfuseFrames = 0; // num preinf frames
  int minimumPressure = 0; // hard-coded, read as {
  int maximumFlow = 0x60; // hard-coded, read as {

  late Uint8List bytes = Uint8List(5);

  int hidden = 0;

  String type = "";

  String lang = "";

  String legacyProfileType = "";

  double target_weight = 0;

  double target_volume = 0;

  double target_volume_count_start = 0;

  double tank_temperature = 0;

  String title = "";

  String author = "";

  String notes = "";

  String beverage_type = ""; // to compare bytes

  De1ShotHeaderClass();

  // bool compareBytes(De1ShotHeaderClass sh) {
  //   if (sh.bytes.buffer.lengthInBytes != bytes.buffer.lengthInBytes) {
  //     return false;
  //   }
  //   for (int i = 0; i < sh.bytes.buffer.lengthInBytes; i++) {
  //     if (sh.bytes[i] != bytes[i]) {
  //       return false;
  //     }
  //   }

  //   return true;
  // }

  @override
  String toString() {
    return "$numberOfFrames($numberOfPreinfuseFrames) P:$minimumPressure F:$maximumFlow";
  }

  static bool decodeDe1ShotHeader(
      ByteData data, De1ShotHeaderClass shotHeader, bool checkEncoding) {
    if (data.buffer.lengthInBytes != 5) return false;

    try {
      int index = 0;
      shotHeader.headerV = data.getUint8(index++);
      shotHeader.numberOfFrames = data.getUint8(index++);
      shotHeader.numberOfPreinfuseFrames = data.getUint8(index++);
      shotHeader.minimumPressure = data.getUint8(index++);
      shotHeader.maximumFlow = data.getUint8(index++);

      if (shotHeader.headerV != 1) {
        return false;
      }

      if (checkEncoding) {
        var array = data.buffer.asUint8List();
        var new_bytes = encodeDe1ShotHeader(shotHeader);
        if (new_bytes.buffer.lengthInBytes != data.buffer.lengthInBytes) {
          return false;
        }
        for (int i = 0; i < new_bytes.buffer.lengthInBytes; i++) {
          if (new_bytes[i] != array[i]) return false;
        }
      }

      return true;
    } catch (ex) {
      return false;
    }
  }

  static Uint8List encodeDe1ShotHeader(De1ShotHeaderClass shotHeader) {
    Uint8List data = Uint8List(5);

    int index = 0;
    data[index] = shotHeader.headerV;
    index++;
    data[index] = shotHeader.numberOfFrames;
    index++;
    data[index] = shotHeader.numberOfPreinfuseFrames;
    index++;
    data[index] = shotHeader.minimumPressure;
    index++;
    data[index] = shotHeader.maximumFlow;
    index++;

    return data;
  }
}

class De1ShotFrameClass // proc spec_shotframe
{
  int frameToWrite = 0;
  int flag = 0;
  double setVal = 0; // {
  double temp = 0; // {
  double frameLen = 0.0; // convert_F8_1_7_to_float
  double triggerVal = 0; // {
  double maxVol = 0.0; // convert_bottom_10_of_U10P0
  String name = "";
  String pump = "";
  String sensor = "";
  String transition = "";

  late Uint8List bytes; // to compare bytes

  De1ShotFrameClass();

  // bool compareBytes(De1ShotFrameClass sh) {
  //   if (sh.bytes.buffer.lengthInBytes != bytes.buffer.lengthInBytes) {
  //     return false;
  //   }
  //   for (int i = 0; i < sh.bytes.buffer.lengthInBytes; i++) {
  //     if (sh.bytes[i] != bytes[i]) {
  //       return false;
  //     }
  //   }

  //   return true;
  // }

  static bool DecodeDe1ShotFrame(
      ByteData data, De1ShotFrameClass shot_frame, bool check_encoding) {
    if (data.buffer.lengthInBytes != 8) return false;
    log('DecodeDe1ShotFrame:${Helper.toHex(data.buffer.asUint8List())}');
    try {
      int index = 0;
      shot_frame.frameToWrite = data.getUint8(index++);
      index++;
      shot_frame.flag = data.getUint8(index++);
      index++;
      shot_frame.setVal = data.getUint8(index++) / 16.0;
      index++;
      shot_frame.temp = data.getUint8(index++) / 2.0;
      index++;
      shot_frame.frameLen =
          Helper.convert_F8_1_7_to_float(data.getUint8(index++));
      index++; // convert_F8_1_7_to_float
      shot_frame.triggerVal = data.getUint8(index++) / 16.0;
      index++;
      shot_frame.maxVol = Helper.convert_bottom_10_of_U10P0(
          256 * data.getUint8(index++) +
              data.getUint8(index++)); // convert_bottom_10_of_U10P0

      if (check_encoding) {
        var array = data.buffer.asUint8List();
        var new_bytes = EncodeDe1ShotFrame(shot_frame);
        if (new_bytes.length != array.buffer.lengthInBytes) return false;
        for (int i = 0; i < new_bytes.length; i++) {
          if (new_bytes[i] != array[i]) return false;
        }
      }

      return true;
    } catch (Exception) {
      return false;
    }
  }

  static Uint8List EncodeDe1ShotFrame(De1ShotFrameClass shot_frame) {
    Uint8List data = Uint8List(8);
    log('EncodeDe1ShotFrame:${Helper.toHex(data)}');
    int index = 0;
    data[index] = shot_frame.frameToWrite;
    index++;
    data[index] = shot_frame.flag;
    index++;
    data[index] = (0.5 + shot_frame.setVal * 16.0).toInt();
    index++; // note to add 0.5, as "round" is used, not truncate
    data[index] = (0.5 + shot_frame.temp * 2.0).toInt();
    index++;
    data[index] = Helper.convert_float_to_F8_1_7(shot_frame.frameLen);
    index++;
    data[index] = (0.5 + shot_frame.triggerVal * 16.0).toInt();
    index++;
    Helper.convert_float_to_U10P0(shot_frame.maxVol, data, index);

    return data;
  }

  @override
  String toString() {
    // StringBuilder sb = new StringBuilder();
    var sb = "";
    // bytes.forEach((b) {
    //   sb += "${b.toRadixString(16)}-";
    // });
    return "$frameToWrite $flag $setVal $temp $frameLen $triggerVal $maxVol $sb";
  }
}

class De1ShotExtFrameClass // extended frames
{
  int frameToWrite = 0;
  double limiterValue = 0.0;
  double limiterRange = 0.0;
  late Uint8List bytes; // to compare bytes

  De1ShotExtFrameClass();
  bool compareBytes(De1ShotExtFrameClass sh) {
    if (sh.bytes.buffer.lengthInBytes != bytes.buffer.lengthInBytes) {
      return false;
    }
    for (int i = 0; i < sh.bytes.buffer.lengthInBytes; i++) {
      if (sh.bytes[i] != bytes[i]) {
        return false;
      }
    }

    return true;
  }

  static Uint8List EncodeDe1ExtentionFrame(De1ShotExtFrameClass exshot) {
    return EncodeDe1ExtentionFrame2(
        exshot.frameToWrite, exshot.limiterValue, exshot.limiterRange);
  }

  static Uint8List EncodeDe1ExtentionFrame2(
      int frameToWrite, double limit_value, double limit_range) {
    Uint8List data = Uint8List(8);

    data[0] = frameToWrite;

    data[1] = (0.5 + limit_value * 16.0).toInt();
    data[2] = (0.5 + limit_range * 16.0).toInt();

    data[3] = 0;
    data[4] = 0;
    data[5] = 0;
    data[6] = 0;
    data[7] = 0;

    return data;
  }

  @override
  String toString() {
    var sb = "";
    bytes.forEach((b) {
      sb += "${b.toRadixString(16)}-";
    });

    return "$frameToWrite    $limiterValue    $limiterRange   $sb";
  }
}

class Helper {
  static String toHex(Uint8List data) {
    var sb = "";
    data.forEach((b) {
      sb += "${b.toRadixString(16)}-";
    });
    return sb;
  }

  static double convert_F8_1_7_to_float(int x) {
    if ((x & 128) == 0) {
      return x / 10.0;
    } else {
      return (x & 127).toDouble();
    }
  }

  static int convert_float_to_F8_1_7(double x) {
    if (x >= 12.75) // need to set the high bit on (0x80);
    {
      if (x > 127)
        return 127 | 0x80;
      else
        return (0x80 | (0.5 + x).toInt());
    } else {
      return (0.5 + x * 10).toInt();
    }
  }

  static double convert_bottom_10_of_U10P0(int x) {
    return (x & 1023).toDouble();
  }

  static convert_float_to_U10P0(double x, Uint8List data, int index) {
    int ix = x.toInt();

    if (ix > 255) {
      ix = 255;
    }

    data[index] = 0;
    data[index + 1] = ix;
  }
}
