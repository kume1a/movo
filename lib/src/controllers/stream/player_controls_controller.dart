import 'dart:async';

import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:injectable/injectable.dart';
import 'package:rive/rive.dart';
import 'package:video_player/video_player.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import '../../data/local/preferences/settings_helper.dart';
import '../../ui/core/dialogs/core/dialog_manager.dart';
import '../../ui/stream/widgets/video_player/player.dart';
import '../core/base_controller_middle_man.dart';
import 'subtitle_controller.dart';

class PlayerControlsController extends GetxController with GetSingleTickerProviderStateMixin {
  PlayerControlsController(
    this._dialogManager,
    this._settingsHelper,
    this._subtitlesControllerMiddleMan,
  );

  final DialogManager _dialogManager;
  final SettingsHelper _settingsHelper;
  final SubtitlesControllerMiddleMan _subtitlesControllerMiddleMan;

  final Rxn<VideoPlayerValue> latestValue = Rxn<VideoPlayerValue>();
  final RxnDouble latestVolume = RxnDouble();

  final RxBool hideControls = true.obs;
  Timer? _hideTimer;
  Timer? _initTimer;
  Timer? _showAfterExpandCollapseTimer;
  final RxBool dragging = false.obs;
  final RxBool displayTapped = false.obs;
  final RxBool isLive = false.obs;
  final RxBool allowMuting = false.obs;
  final RxDouble playbackSpeed = 1.0.obs;

  final RxBool showForward = false.obs;
  final RxBool showRewind = false.obs;
  Timer? _forwardTimer;
  Timer? _rewindTimer;

  late RiveAnimationController<RuntimeArtboard> forwardController;
  late RiveAnimationController<RuntimeArtboard> rewindController;

  Rxn<VideoPlayerController> videoPlayerController = Rxn<VideoPlayerController>();
  ChewieController? chewieController;
  AnimationController? playPauseIconAnimController;

  int _doubleTapToSeekValue = 10;

  @override
  void onInit() {
    super.onInit();

    forwardController = OneShotAnimation('forward', autoplay: false);
    rewindController = OneShotAnimation('forward', autoplay: false);

    _settingsHelper.getDoubleTapToSeekValue().then((int value) => _doubleTapToSeekValue = value);
  }

  @override
  void onClose() {
    super.onClose();

    playPauseIconAnimController?.dispose();
    forwardController.dispose();
    rewindController.dispose();
    _dispose();
  }

  void onDidChangeDependencies(ChewieController? controller) {
    final ChewieController? oldController = chewieController;
    chewieController = controller;
    videoPlayerController.value = chewieController?.videoPlayerController;

    isLive.value = chewieController?.isLive ?? isLive.value;
    allowMuting.value = chewieController?.allowMuting ?? allowMuting.value;

    playPauseIconAnimController ??= AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
    );

    if (oldController != chewieController) {
      _dispose();
      _initialize();
    }
  }

  void onTappedOnScreen() => _cancelAndRestartTimer();

  void onScreenDoublePressed(double maxWidth, Offset localPosition) {
    final double leftThreshold = maxWidth / 2 - 64;
    final double rightThreshold = maxWidth - maxWidth / 2 + 64;

    final double x = localPosition.dx;
    if (x <= leftThreshold) {
      rewindController.isActive = true;
      showRewind.value = true;
      _rewindTimer = Timer(const Duration(milliseconds: 250), () {
        showRewind.value = false;
      });
      if (latestValue.value != null && chewieController != null) {
        chewieController!.seekTo(latestValue.value!.position - Duration(seconds: _doubleTapToSeekValue));
      }
    } else if (x >= rightThreshold) {
      forwardController.isActive = true;
      showForward.value = true;
      _forwardTimer = Timer(const Duration(milliseconds: 250), () {
        showForward.value = false;
      });
      if (latestValue.value != null && chewieController != null) {
        chewieController!.seekTo(latestValue.value!.position + Duration(seconds: _doubleTapToSeekValue));
      }
    } else {
      _playPause();
    }
  }

  void onSettingsPressed() => _dialogManager.showStreamSettingsDialog();

  void onPlaybackSpeedChanged(double playbackSpeed) {
    videoPlayerController.value?.setPlaybackSpeed(playbackSpeed);

    this.playbackSpeed.value = playbackSpeed;
  }

  void onHitAreaPressed() {
    if (latestValue.value != null && latestValue.value?.isPlaying == true) {
      if (displayTapped.value) {
        hideControls.value = true;
      } else {
        _cancelAndRestartTimer();
      }
    } else {
      _playPause();
      hideControls.value = true;
    }
  }

  void onProgressBarDragStart() {
    dragging.value = true;

    _hideTimer?.cancel();
  }

  void onPlayPausePressed() => _playPause();

  void onProgressBarDragEnd() {
    dragging.value = false;

    _startHideTimer();
  }

  void onMutePressed() {
    _cancelAndRestartTimer();

    if (latestValue.value?.volume == 0) {
      videoPlayerController.value?.setVolume(latestVolume.value ?? 0.5);
    } else {
      latestVolume.value = videoPlayerController.value?.value.volume;
      videoPlayerController.value?.setVolume(0);
    }
  }

  void _startHideTimer() {
    _hideTimer = Timer(const Duration(seconds: 2), () {
      hideControls.value = true;
    });
  }

  void _dispose() {
    videoPlayerController.value?.removeListener(_updateState);
    _hideTimer?.cancel();
    _initTimer?.cancel();
    _forwardTimer?.cancel();
    _rewindTimer?.cancel();
    _showAfterExpandCollapseTimer?.cancel();
  }

  Future<void> _updateState() async {
    latestValue.value = videoPlayerController.value?.value;
    if (latestValue.value?.isPlaying == true && playPauseIconAnimController?.isCompleted == false) {
      playPauseIconAnimController?.forward();
    }

    final bool isWakelockEnabled = await WakelockPlus.enabled;
    if (latestValue.value?.isPlaying == true) {
      if (!isWakelockEnabled) {
        WakelockPlus.enable();
      }
    } else {
      if (isWakelockEnabled) {
        WakelockPlus.disable();
      }
    }

    if (latestValue.value != null) {
      _subtitlesControllerMiddleMan.updateSubtitle(latestValue.value!.position);
    }
  }

  void _cancelAndRestartTimer() {
    _hideTimer?.cancel();
    _startHideTimer();

    hideControls.value = false;
    displayTapped.value = true;
  }

  Future<void> _initialize() async {
    videoPlayerController.value?.addListener(_updateState);

    _updateState();

    if ((videoPlayerController.value?.value != null &&
            videoPlayerController.value?.value.isPlaying == true) ||
        chewieController?.autoPlay == true) {
      _startHideTimer();
    }

    if (chewieController?.showControlsOnInitialize == true) {
      _initTimer = Timer(const Duration(milliseconds: 200), () {
        hideControls.value = false;
      });
    }
  }

  void _playPause() {
    bool isFinished;
    if (latestValue.value?.duration != null) {
      isFinished = latestValue.value!.position >= latestValue.value!.duration;
    } else {
      isFinished = false;
    }

    if (videoPlayerController.value?.value.isPlaying == true) {
      playPauseIconAnimController?.reverse();
      hideControls.value = false;
      _hideTimer?.cancel();
      videoPlayerController.value?.pause();
    } else {
      _cancelAndRestartTimer();

      if (videoPlayerController.value != null && !videoPlayerController.value!.value.isInitialized) {
        videoPlayerController.value?.initialize().then((_) {
          videoPlayerController.value?.play();
          playPauseIconAnimController?.forward();
        });
      } else {
        if (isFinished) {
          videoPlayerController.value?.seekTo(Duration.zero);
        }
        playPauseIconAnimController?.forward();
        videoPlayerController.value?.play();
      }
    }
  }
}

@injectable
class PlayerControlsControllerMiddleMan extends BaseControllerMiddleMan<PlayerControlsController> {
  void pausePlayer() {
    runIfRegistered((PlayerControlsController controller) {
      if (controller.latestValue.value?.isPlaying == true) {
        controller._playPause();
      }
    });
  }
}
