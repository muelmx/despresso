import 'dart:async';
import 'dart:developer';
import 'dart:typed_data';

import 'package:despresso/devices/abstract_scale.dart';
import 'package:despresso/model/services/ble/scale_service.dart';
import 'package:despresso/service_locator.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter_reactive_ble/flutter_reactive_ble.dart';

class EurekaScale extends ChangeNotifier implements AbstractScale {
  // ignore: non_constant_identifier_names
  static Uuid ServiceUUID = Uuid.parse('0000fff0-0000-1000-8000-00805f9b34fb');
  // ignore: non_constant_identifier_names
  static Uuid CharateristicUUID =
      Uuid.parse('0000fff1-0000-1000-8000-00805f9b34fb');
  // ignore: non_constant_identifier_names
  static Uuid CommandUUID = Uuid.parse('0000fff2-0000-1000-8000-00805f9b34fb');

  late ScaleService scaleService;

  static const int cmdHeader = 0xAA;
  static const int cmdBase = 0x02;
  static const int cmdStartTimer = 0x33;
  static const int cmdStopTimer = 0x34;
  static const int cmdResetTimer = 0x35;
  static const int cmdTare = 0x31;

  final DiscoveredDevice device;

  late DeviceConnectionState _state;

  List<int> commandBuffer = [];
  final flutterReactiveBle = FlutterReactiveBle();

  late StreamSubscription<ConnectionStateUpdate> _deviceListener;

  late StreamSubscription<List<int>> _characteristicsSubscription;

  EurekaScale(this.device) {
    scaleService = getIt<ScaleService>();
    log("Connect to Acaia");
    scaleService.setScaleInstance(this);
    _deviceListener = flutterReactiveBle.connectToDevice(id: device.id).listen(
        (connectionState) {
      // Handle connection state updates
      log('Peripheral ${device.name} connection state is $connectionState');
      _onStateChange(connectionState.connectionState);
    }, onError: (Object error) {
      // Handle a possible error
    });
  }

  void _notificationCallback(List<int> data) {
    var isNeg = (data[6] == 0 ? false : true);
    var weight = (data[7] + (data[8] << 8));

    weight = isNeg ? weight * -1 : weight;
    scaleService.setWeight((weight / 10).toDouble());
  }

  writeTare() {
    return writeToEureka([cmdHeader, cmdBase, cmdTare, cmdTare]);
  }

  Future<void> startTimer() {
    return writeToEureka([cmdHeader, cmdBase, cmdStartTimer, cmdStartTimer]);
  }

  Future<void> stopTimer() {
    return writeToEureka([cmdHeader, cmdBase, cmdStopTimer, cmdStopTimer]);
  }

  Future<void> resetTimer() {
    return writeToEureka([cmdHeader, cmdBase, cmdResetTimer, cmdResetTimer]);
  }

  Future<void> writeToEureka(List<int> payload) async {
    log("Sending to Eureka");
    final characteristic = QualifiedCharacteristic(
        serviceId: ServiceUUID,
        characteristicId: CommandUUID,
        deviceId: device.id);
    return await flutterReactiveBle.writeCharacteristicWithoutResponse(
        characteristic,
        value: Uint8List.fromList(payload));
  }

  void _onStateChange(DeviceConnectionState state) async {
    log('SCALE State changed to $state');
    _state = state;

    switch (state) {
      case DeviceConnectionState.connecting:
        log('Connecting');
        scaleService.setState(ScaleState.connecting);
        break;

      case DeviceConnectionState.connected:
        log('Connected');
        scaleService.setState(ScaleState.connected);
        // await device.discoverAllServicesAndCharacteristics();
        final characteristic = QualifiedCharacteristic(
            serviceId: ServiceUUID,
            characteristicId: CharateristicUUID,
            deviceId: device.id);

        _characteristicsSubscription = flutterReactiveBle
            .subscribeToCharacteristic(characteristic)
            .listen((data) {
          // code to handle incoming data
          _notificationCallback(data);
        }, onError: (dynamic error) {
          // code to handle errors
        });

        return;
      case DeviceConnectionState.disconnected:
        scaleService.setState(ScaleState.disconnected);
        log('Eureka Scale disconnected. Destroying');
        // await device.disconnectOrCancelConnection();
        _characteristicsSubscription.cancel();

        _deviceListener.cancel();
        notifyListeners();
        return;
      default:
        return;
    }
  }
}