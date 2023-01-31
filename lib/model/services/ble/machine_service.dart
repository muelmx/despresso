import 'dart:async';
import 'dart:convert';

import 'package:despresso/devices/decent_de1.dart';
import 'package:despresso/model/services/state/coffee_service.dart';
import 'package:despresso/model/services/state/settings_service.dart';
import 'package:despresso/model/settings.dart';
import 'package:despresso/model/de1shotclasses.dart';
import 'package:despresso/objectbox.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'dart:developer';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wakelock/wakelock.dart';

import 'package:battery_plus/battery_plus.dart';

import '../../../service_locator.dart';
import '../../shot.dart';
import '../../shotstate.dart';
import '../state/profile_service.dart';
import 'scale_service.dart';

class WaterLevel {
  WaterLevel(this.waterLevel, this.waterLimit);

  int waterLevel = 0;
  int waterLimit = 0;

  int getLevelPercent() {
    var l = waterLevel - waterLimit;
    return l * 100 ~/ 8300;
  }

  int getLevelML() {
    var l = waterLevel - waterLimit;
    return (l / 10.0).round();
  }
}

class MachineState {
  MachineState(this.shot, this.coffeeState);
  ShotState? shot;
  De1ShotHeaderClass? shotHeader;
  De1ShotFrameClass? shotFrame;

  WaterLevel? water;
  EspressoMachineState coffeeState;
  String subState = "";
}

enum EspressoMachineState { idle, espresso, water, steam, sleep, disconnected, connecting, refill, flush }

class EspressoMachineFullState {
  EspressoMachineState state = EspressoMachineState.idle;
  String subState = "";
}

class EspressoMachineService extends ChangeNotifier {
  final MachineState _state = MachineState(null, EspressoMachineState.disconnected);

  DE1? de1;

  Settings settings = Settings();

  late SharedPreferences prefs;

  late ProfileService profileService;

  bool refillAnounced = false;

  bool inShot = false;

  String lastSubstate = "";

  late ScaleService scaleService;
  late CoffeeService coffeeService;
  late SettingsService settingsService;

  ShotList shotList = ShotList([]);
  double baseTime = 0;

  DateTime baseTimeDate = DateTime.now();

  Duration timer = const Duration(seconds: 0);

  var _count = 0;

  DateTime t1 = DateTime.now();

  int idleTime = 0;
  int sleepTime = 0;

  double pourTimeStart = 0;
  bool isPouring = false;

  double lastPourTime = 0;
  late ObjectBox objectBox;

  Shot currentShot = Shot();

  late StreamController<ShotState> _controllerShotState;
  late Stream<ShotState> _streamShotState;

  EspressoMachineState lastState = EspressoMachineState.disconnected;

  Battery _battery = Battery();
  Stream<ShotState> get streamShotState => _streamShotState;

  late StreamController<WaterLevel> _controllerWaterLevel;
  late Stream<WaterLevel> _streamWaterLevel;
  Stream<WaterLevel> get streamWaterLevel => _streamWaterLevel;

  late StreamController<EspressoMachineFullState> _controllerEspressoMachineState;
  late Stream<EspressoMachineFullState> _streamState;
  Stream<EspressoMachineFullState> get streamState => _streamState;

  EspressoMachineFullState currentFullState = EspressoMachineFullState();

  EspressoMachineService() {
    _controllerShotState = StreamController<ShotState>();
    _streamShotState = _controllerShotState.stream.asBroadcastStream();

    _controllerEspressoMachineState = StreamController<EspressoMachineFullState>();
    _streamState = _controllerEspressoMachineState.stream.asBroadcastStream();

    _controllerWaterLevel = StreamController<WaterLevel>();
    _streamWaterLevel = _controllerWaterLevel.stream.asBroadcastStream();

    init();
  }
  void init() async {
    profileService = getIt<ProfileService>();
    settingsService = getIt<SettingsService>();
    objectBox = getIt<ObjectBox>();
    profileService.addListener(updateProfile);
    scaleService = getIt<ScaleService>();
    coffeeService = getIt<CoffeeService>();
    prefs = await SharedPreferences.getInstance();

    log('Preferences loaded');
    loadSettings();
    notifyListeners();
    loadShotData();

    handleBattery();

    Timer.periodic(const Duration(seconds: 10), (timer) async {
      if (state.coffeeState == EspressoMachineState.sleep) {
        try {
          log("Machine is still sleeping $sleepTime ${settingsService.screenLockTimer * 60}");
          sleepTime += 10;

          if (sleepTime > settingsService.screenLockTimer * 60 && settingsService.screenLockTimer > 0.1) {
            try {
              if (await Wakelock.enabled) {
                log('Disable WakeLock');
                Wakelock.disable();
              }
            } on MissingPluginException catch (e) {
              log('Failed to set wakelock: $e');
            }
          }
        } catch (e) {
          log("Error $e");
        }
      } else {
        sleepTime = 0;
        try {
          if ((await Wakelock.enabled) == false) {
            log('enable WakeLock');
            Wakelock.enable();
          } else {
            // log('is enabled WakeLock');
          }
        } on MissingPluginException catch (e) {
          log('Failed to set wakelock enable: $e');
        }
      }

      if (state.coffeeState == EspressoMachineState.idle) {
        try {
          log("Machine is still idle $idleTime ${settingsService.sleepTimer * 60}");
          idleTime += 10;

          if (idleTime > settingsService.sleepTimer * 60 && settingsService.sleepTimer > 0.1) {
            de1?.switchOff();
          }
        } catch (e) {
          {}
          log("Error $e");
        }
      } else {
        idleTime = 0;
      }
    });
  }

  handleBattery() async {
// Access current battery level
    var state = await _battery.batteryLevel;
    log("Battery: $state");

// Be informed when the state (full, charging, discharging) changes
    _battery.onBatteryStateChanged.listen((BatteryState state) async {
      // Do something with new state
      final batteryLevel = await _battery.batteryLevel;
      log("Battery: changed: $state $batteryLevel");
      if (de1 == null) {
        log("DE1 not connected yet");
        return;
      }
      if (settingsService.smartCharging) {
        if (batteryLevel < 80) {
          if (await de1!.getUsbChargerMode() == 0) {
            log("Battery: Charging is off, switching it on");
            de1!.setUsbChargerMode(1);
          } else {
            log("Battery: Charging is already on");
          }
        } else if (batteryLevel > 90) {
          if (await de1!.getUsbChargerMode() == 1) {
            log("Battery: Charging is on, switching it off");
            de1!.setUsbChargerMode(0);
          } else {
            log("Battery: Charging is already off");
          }
        }
      }
    });
  }

  loadSettings() {
    var settingsString = prefs.getString("de1Setting");
    if (settingsString != null) {
      settings = Settings.fromJson((jsonDecode(settingsString)));
    }
  }

  saveSettings() {
    var jsonString = jsonEncode(settings.toJson());
    prefs.setString("de1Setting", jsonString);
  }

  loadShotData() async {
    currentShot = coffeeService.getLastShot() ?? Shot();
    shotList.entries = currentShot.shotstates;
    // await shotList.load("testshot.json");
    log("Lastshot loaded ${shotList.entries.length}");
    notifyListeners();
  }

  updateProfile() {}

  void setShot(ShotState shot) {
    _state.shot = shot;
    _count++;
    if (_count % 10 == 0) {
      var t = DateTime.now();
      var ms = t.difference(t1).inMilliseconds;
      var hz = 10 / ms * 1000.0;
      if (_state.coffeeState == EspressoMachineState.espresso || _count & 50 == 0) log("Hz: $ms $hz");
      t1 = t;
    }
    handleShotData();
    notifyListeners();
    _controllerShotState.add(shot);
  }

  void setWaterLevel(WaterLevel water) {
    _state.water = water;
    notifyListeners();
    _controllerWaterLevel.add(water);
  }

  void setState(EspressoMachineState state) {
    _state.coffeeState = state;

    if (lastState != state &&
        (_state.coffeeState == EspressoMachineState.espresso || _state.coffeeState == EspressoMachineState.water)) {
      if (settingsService.shotAutoTare) {
        scaleService.tare();
      }
    }
    if (state == EspressoMachineState.idle) {}
    notifyListeners();
    currentFullState.state = state;
    _controllerEspressoMachineState.add(currentFullState);
    lastState = state;
  }

  void setSubState(String state) {
    _state.subState = state;
    notifyListeners();
    currentFullState.subState = state;
    _controllerEspressoMachineState.add(currentFullState);
  }

  MachineState get state => _state;

  void setDecentInstance(DE1 de1) {
    this.de1 = de1;
  }

  void setShotHeader(De1ShotHeaderClass sh) {
    _state.shotHeader = sh;
    log("Shotheader:$sh");
    notifyListeners();
  }

  void setShotFrame(De1ShotFrameClass sh) {
    _state.shotFrame = sh;
    log("ShotFrame:$sh");
    notifyListeners();
  }

  Future<String> uploadProfile(De1ShotProfile profile) async {
    log("Save profile $profile");
    var header = profile.shotHeader;

    try {
      log("Write Header: $header");
      await de1!.writeWithResult(Endpoint.headerWrite, header.bytes);
    } catch (ex) {
      log("Save profile $profile");
      return "Error writing profile header $ex";
    }

    for (var fr in profile.shotFrames) {
      try {
        log("Write Frame: $fr");
        await de1!.writeWithResult(Endpoint.frameWrite, fr.bytes);
      } catch (ex) {
        return "Error writing shot frame $fr";
      }
    }

    for (var exFrame in profile.shotExframes) {
      try {
        log("Write ExtFrame: $exFrame");
        await de1!.writeWithResult(Endpoint.frameWrite, exFrame.bytes);
      } catch (ex) {
        return "Error writing ex shot frame $exFrame";
      }
    }

    // stop at volume in the profile tail
    if (true) {
      var tailBytes = De1ShotHeaderClass.encodeDe1ShotTail(profile.shotFrames.length, 0);

      try {
        log("Write Tail: $tailBytes");
        await de1!.writeWithResult(Endpoint.frameWrite, tailBytes);
      } catch (ex) {
        return "Error writing shot frame tail $tailBytes";
      }
    }

    // check if we need to send the new water temp
    if (settings.targetGroupTemp != profile.shotFrames[0].temp) {
      profile.shotHeader.targetGroupTemp = profile.shotFrames[0].temp;
      var bytes = Settings.encodeDe1OtherSetn(settings);

      try {
        log("Write Shot Settings: $bytes");
        await de1!.writeWithResult(Endpoint.shotSettings, bytes);
      } catch (ex) {
        return "Error writing shot settings $bytes";
      }
    }
    return Future.value("");
  }

  void handleShotData() {
    // checkForRefill();

    if (state.coffeeState == EspressoMachineState.sleep ||
        state.coffeeState == EspressoMachineState.disconnected ||
        state.coffeeState == EspressoMachineState.refill) {
      return;
    }
    var shot = state.shot;
    // if (machineService.state.subState.isNotEmpty) {
    //   subState = machineService.state.subState;
    // }
    if (shot == null) {
      log('Shot null');
      return;
    }
    if (state.coffeeState == EspressoMachineState.idle && inShot == true) {
      baseTimeDate = DateTime.now();
      refillAnounced = false;
      inShot = false;
      if (shotList.saved == false &&
          shotList.entries.isNotEmpty &&
          shotList.saving == false &&
          shotList.saved == false) {
        shotFinished();
      }

      return;
    }
    if (!inShot && state.coffeeState == EspressoMachineState.espresso) {
      log('Not Idle and not in Shot');
      inShot = true;
      isPouring = false;
      shotList.clear();
      baseTime = DateTime.now().millisecondsSinceEpoch / 1000.0;
      log("basetime $baseTime");
      lastPourTime = 0;
    }
    if (state.coffeeState == EspressoMachineState.espresso &&
        lastSubstate != state.subState &&
        state.subState == "pour") {
      pourTimeStart = DateTime.now().millisecondsSinceEpoch / 1000.0;
      isPouring = true;
    } else if (state.coffeeState == EspressoMachineState.espresso &&
        lastSubstate != state.subState &&
        state.subState != "pour") {
      isPouring = false;
    }

    if (state.coffeeState == EspressoMachineState.water && lastSubstate != state.subState && state.subState == "pour") {
      log('Startet water pour');
      baseTime = DateTime.now().millisecondsSinceEpoch / 1000.0;
      baseTimeDate = DateTime.now();
      log("basetime $baseTime");
    }

    if (state.coffeeState == EspressoMachineState.steam && lastSubstate != state.subState && state.subState == "pour") {
      log('Startet steam pour');
      baseTime = DateTime.now().millisecondsSinceEpoch / 1000.0;
      baseTimeDate = DateTime.now();
      log("basetime $baseTime");
    }
    if (state.coffeeState == EspressoMachineState.flush && lastSubstate != state.subState && state.subState == "pour") {
      log('Startet flush pour');
      baseTime = DateTime.now().millisecondsSinceEpoch / 1000.0;
      baseTimeDate = DateTime.now();
      log("basetime $baseTime");
    }

    var subState = state.subState;
    timer = DateTime.now().difference(baseTimeDate);
    if (!(shot.sampleTimeCorrected > 0)) {
      if (lastSubstate != subState && subState.isNotEmpty) {
        log("SubState: $subState");
        lastSubstate = state.subState;
        shot.subState = lastSubstate;
      }

      shot.weight = scaleService.weight;
      shot.flowWeight = scaleService.flow;
      shot.sampleTimeCorrected = shot.sampleTime - baseTime;
      if (isPouring) {
        shot.pourTime = shot.sampleTime - pourTimeStart;
        lastPourTime = shot.pourTime;
      }

      switch (state.coffeeState) {
        case EspressoMachineState.espresso:
          if (scaleService.state == ScaleState.connected) {
            if (profileService.currentProfile!.shotHeader.targetWeight > 1 &&
                shot.weight + 1 > profileService.currentProfile!.shotHeader.targetWeight) {
              log("Shot Weight reached ${shot.weight} > ${profileService.currentProfile!.shotHeader.targetWeight}");

              if (settingsService.shotStopOnWeight) {
                triggerEndOfShot();
              }
            }
          }
          break;
        case EspressoMachineState.water:
          if (scaleService.state == ScaleState.connected) {
            if (settings.targetHotWaterWeight > 1 && scaleService.weight + 1 > settings.targetHotWaterWeight) {
              log("Water Weight reached ${shot.weight} > ${profileService.currentProfile!.shotHeader.targetWeight}");

              if (settingsService.shotStopOnWeight) {
                triggerEndOfShot();
              }
            }
          }
          if (state.subState == "pour" &&
              settings.targetHotWaterLength > 1 &&
              timer.inSeconds > settings.targetHotWaterLength) {
            log("Water Timer reached ${timer.inSeconds} > ${settings.targetHotWaterLength}");

            triggerEndOfShot();
          }

          break;
        case EspressoMachineState.steam:
          if (state.subState == "pour" &&
              settings.targetSteamLength > 1 &&
              timer.inSeconds > settings.targetSteamLength) {
            log("Steam Timer reached ${timer.inSeconds} > ${settings.targetSteamLength}");

            triggerEndOfShot();
          }

          break;
        case EspressoMachineState.flush:
          if (state.subState == "pour" && settings.targetFlushTime > 1 && timer.inSeconds > settings.targetFlushTime) {
            log("Flush Timer reached ${timer.inSeconds} > ${settings.targetFlushTime}");

            triggerEndOfShot();
          }

          break;
        case EspressoMachineState.idle:
          break;
        case EspressoMachineState.sleep:
          break;
        case EspressoMachineState.disconnected:
          break;
        case EspressoMachineState.connecting:
          break;
        case EspressoMachineState.refill:
          break;
      }

      //if (profileService.currentProfile.shot_header.target_weight)
      // log("Sample ${shot!.sampleTimeCorrected} ${shot.weight}");
      if (inShot == true) {
        shotList.add(shot);
      }
    }
  }

  void triggerEndOfShot() {
    log("Idle mode initiated because of weight", error: {DateTime.now()});

    de1?.requestState(De1StateEnum.idle);
    // Future.delayed(const Duration(milliseconds: 5000), () {
    //   log("Idle mode initiated finished", error: {DateTime.now()});
    //   stopTriggered = false;
    // });
  }

  shotFinished() async {
    log("Save last shot");
    try {
      currentShot = Shot();
      currentShot.coffee.targetId = coffeeService.selectedCoffee;
      log("AddAll");
      currentShot.shotstates.addAll(shotList.entries);
      log("AddAll done");
      currentShot.pourTime = lastPourTime;
      currentShot.profileId = profileService.currentProfile?.id ?? "";
      currentShot.pourWeight = shotList.entries.last.flowWeight;
      log("Putting shot to db");
      var id = coffeeService.shotBox.put(currentShot);
      log("Sent shot to db");
      await coffeeService.setLastShotId(id);
      log("Cleaning cache");
      shotList.saveData();
      // currentShot = Shot();
    } catch (ex) {
      log("Error writing file: $ex");
    }
  }

  Future<void> updateSettings(Settings settings) async {
    this.settings = settings;
    saveSettings();
    notifyListeners();

    var bytes = Settings.encodeDe1OtherSetn(settings);
    try {
      log("Write Shot Settings: $bytes");
      await de1!.writeWithResult(Endpoint.shotSettings, bytes);
    } catch (ex) {
      log("Error writing shot settings $bytes");
    }
  }
}
