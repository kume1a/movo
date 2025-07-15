import 'dart:async';

import 'package:collection/collection.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';
import 'package:video_player/video_player.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import '../../core/enums/language.dart';
import '../../core/enums/quality.dart';
import '../../data/local/preferences/preferences_helper.dart';
import '../../data/local/preferences/settings_helper.dart';
import '../../data/local/saved_movies/saved_movie_dao.dart';
import '../../data/local/watched_movies/watched_movie_dao.dart';
import '../../data/model/core/either.dart';
import '../../data/model/core/fetch_failure.dart';
import '../../data/model/models/movies/movie_data.dart';
import '../../data/model/models/movies/movie_position.dart';
import '../../data/model/models/movies/movies.dart';
import '../../data/model/models/seasons/episode.dart';
import '../../data/model/models/seasons/episode_file.dart';
import '../../data/model/models/seasons/season_files.dart';
import '../../data/model/models/watched_movies/watched_movie.dart';
import '../../data/network/services/movie_service.dart';
import '../../ui/core/routes/route_args.dart';
import '../../ui/core/values/default_settings.dart';
import '../../ui/stream/widgets/video_player/player.dart';
import '../../ui/stream/widgets/video_player/video_player_controls.dart';
import 'subtitle_controller.dart';

class StreamSettings {
  const StreamSettings({
    required this.autoPlayEnabled,
    required this.recordWatchHistoryEnabled,
    required this.doubleTapToSeekValue,
  });

  factory StreamSettings.initial() {
    return const StreamSettings(
      autoPlayEnabled: DefaultSettings.isAutoPlayEnabled,
      recordWatchHistoryEnabled: DefaultSettings.recordWatchHistoryEnabled,
      doubleTapToSeekValue: DefaultSettings.doubleTapToSeekValue,
    );
  }

  final bool autoPlayEnabled;
  final bool recordWatchHistoryEnabled;
  final int doubleTapToSeekValue;

  @override
  String toString() {
    return 'StreamSettings{autoPlayEnabled: $autoPlayEnabled, recordWatchHistoryEnabled: $recordWatchHistoryEnabled, doubleTapToSeekValue: $doubleTapToSeekValue}';
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is StreamSettings &&
          runtimeType == other.runtimeType &&
          autoPlayEnabled == other.autoPlayEnabled &&
          recordWatchHistoryEnabled == other.recordWatchHistoryEnabled &&
          doubleTapToSeekValue == other.doubleTapToSeekValue;

  @override
  int get hashCode =>
      autoPlayEnabled.hashCode ^ recordWatchHistoryEnabled.hashCode ^ doubleTapToSeekValue.hashCode;
}

class StreamController extends GetxController {
  StreamController(
    this._movieService,
    this._savedMovieDao,
    this._watchedMovieDao,
    this._settingsHelper,
    this._preferencesHelper,
    this._subtitlesControllerMiddleMan,
  );

  final MovieService _movieService;
  final SavedMovieDao _savedMovieDao;
  final WatchedMovieDao _watchedMovieDao;
  final SettingsHelper _settingsHelper;
  final PreferencesHelper _preferencesHelper;
  final SubtitlesControllerMiddleMan _subtitlesControllerMiddleMan;

  final Rxn<ChewieController> chewieController = Rxn<ChewieController>();
  VideoPlayerController? _videoPlayerController;
  Timer? _ticker;

  final Rx<StreamSettings> settings = StreamSettings.initial().obs;
  final Rxn<MovieData> movie = Rxn<MovieData>();
  final Rxn<SeasonFiles> seasonFiles = Rxn<SeasonFiles>();
  final Rxn<Movies> related = Rxn<Movies>();
  final Rx<Duration> startPosition = Duration.zero.obs;
  final Rx<Duration> currentPosition = Duration.zero.obs;
  final RxInt season = 1.obs;
  final RxInt episode = 1.obs;
  final RxInt episodeSeason = 1.obs;
  final Rx<Quality> quality = Quality.high.obs;
  final Rx<Language> language = Language.eng.obs;
  final RxList<Language> availableLanguages = <Language>[].obs;
  final RxList<Quality> availableQualities = <Quality>[].obs;

  bool firstEpisodePassed = false;
  String? videoSrc;

  MovieData get getMovieOrCrash => movie.value!;

  @override
  Future<void> onInit() async {
    super.onInit();

    SystemChrome.setPreferredOrientations(<DeviceOrientation>[
      DeviceOrientation.portraitUp,
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);

    final bool isAutoPlayEnabled = await _settingsHelper.isAutoPlayEnabled();
    final bool recordWatchHistoryEnabled = await _settingsHelper.isRecordWatchHistoryEnabled();
    final int doubleTapToSeekValue = await _settingsHelper.getDoubleTapToSeekValue();

    settings.value = StreamSettings(
      autoPlayEnabled: isAutoPlayEnabled,
      recordWatchHistoryEnabled: recordWatchHistoryEnabled,
      doubleTapToSeekValue: doubleTapToSeekValue,
    );

    final StreamPageArgs args = Get.arguments as StreamPageArgs;

    startPosition.value = args.startAt;
    currentPosition.value = args.startAt;

    await _fetchAndSetMovie(args.movieId);
    await _fetchAndSetSeason(args.season);
    await _fetchAndSetEpisode(args.episode);
    await _fetchAndSetRelated(args.movieId);

    final int saveMovieInterval = await _settingsHelper.getSaveMovieInterval();

    _ticker = Timer.periodic(
      Duration(seconds: saveMovieInterval),
      (Timer timer) async {
        if (_videoPlayerController != null &&
            chewieController.value != null &&
            chewieController.value?.isPlaying == true) {
          final Duration? position = await _videoPlayerController!.position;
          if (position != null) {
            _onPositionTick(position);
          }
        }
      },
    );
  }

  @override
  Future<void> onClose() async {
    WakelockPlus.disable();

    await _videoPlayerController?.dispose();
    chewieController.value?.dispose();
    _ticker?.cancel();

    await SystemChrome.setPreferredOrientations(<DeviceOrientation>[
      DeviceOrientation.portraitUp,
    ]);
    await SystemChrome.setEnabledSystemUIMode(
      SystemUiMode.manual,
      overlays: <SystemUiOverlay>[
        SystemUiOverlay.top,
        SystemUiOverlay.bottom,
      ],
    );
  }

  Future<void> onRelatedMoviePressed(int movieId) async {
    await _fetchAndSetMovie(movieId);
    await _fetchAndSetSeason(1);
    await _fetchAndSetEpisode(1);
    await _fetchAndSetRelated(movieId);
  }

  Future<void> onSeasonChanged(int season) async => _fetchAndSetSeason(season);

  Future<void> onEpisodeChanged(int episodeNumber) async => _fetchAndSetEpisode(episodeNumber);

  Future<void> onLanguageChanged(Language language) async {
    if (seasonFiles.value != null) {
      final Episode? episode = seasonFiles.value!.data.isNotEmpty
          ? seasonFiles.value!.data.firstWhere(
              (Episode element) => element.episode == this.episode.value,
              orElse: () => seasonFiles.value!.data.first,
            )
          : null;

      final List<EpisodeFile>? selectedLanguageEpisodes = episode?.episodes[language];
      final EpisodeFile? episodeFile =
          selectedLanguageEpisodes?.firstWhereOrNull((EpisodeFile e) => e.quality == quality.value) ??
              episode?.episodes[language]?.first;

      if (episodeFile != null) {
        videoSrc = episodeFile.src;
      }

      final List<Quality>? newQualities =
          selectedLanguageEpisodes?.map((EpisodeFile e) => e.quality).toList();
      if (newQualities != null) {
        availableQualities.value = newQualities;
      }
    }

    startPosition.value = currentPosition.value;
    this.language.value = language;

    _initControllers();

    await _preferencesHelper.writePreferredLanguage(language);
  }

  Future<void> onQualityChanged(Quality quality) async {
    String? videoSrc;

    if (seasonFiles.value != null) {
      final Episode? episode = seasonFiles.value!.data.isNotEmpty
          ? seasonFiles.value!.data.firstWhere(
              (Episode element) => element.episode == this.episode.value,
              orElse: () => seasonFiles.value!.data.first,
            )
          : null;

      videoSrc = episode?.episodes[language.value]
          ?.firstWhere((EpisodeFile element) => element.quality == quality)
          .src;
    }

    this.videoSrc = videoSrc;
    startPosition.value = currentPosition.value;
    this.quality.value = quality;

    _initControllers();

    await _preferencesHelper.writePreferredQuality(quality);
  }

  Future<void> onFetchRelatedRequested(int movieId) async => _fetchAndSetRelated(movieId);

  Future<void> _onPositionTick(Duration position) async {
    if (settings.value.recordWatchHistoryEnabled && seasonFiles.value != null) {
      final MovieData movie = getMovieOrCrash;
      final int durationInMillis = seasonFiles.value!.data
              .firstWhere(
                (Episode element) => element.episode == episode.value,
                orElse: () => seasonFiles.value!.data.first,
              )
              .episodes
              .values
              .first
              .first
              .duration *
          1000;

      // TODO: 03/07/2021 refactor insert or update logic to SavedMovieDao method
      if (await _savedMovieDao.positionForMovieExists(
        movie.movieId,
        episodeSeason.value,
        episode.value,
      )) {
        await _savedMovieDao.updateMoviePosition(movie.movieId, position.inMilliseconds);
      } else {
        _savedMovieDao.insertMoviePosition(
          MoviePosition(
            movieId: movie.movieId,
            durationInMillis: durationInMillis,
            leftAt: position.inMilliseconds,
            isTvShow: movie.isTvShow,
            season: season.value,
            episode: episode.value,
            timestamp: DateTime.now().millisecondsSinceEpoch,
          ),
        );

        if (movie.genres.isNotEmpty) {
          await _savedMovieDao.saveMovieGenres(movie.movieId, movie.genres);
        }
      }

      await _watchedMovieDao.insertOrUpdateWatchedMovie(
        WatchedMovie(
          movieId: movie.movieId,
          watchedDurationInMillis: position.inMilliseconds,
          durationInMillis: durationInMillis,
          isTvShow: movie.isTvShow,
          season: episodeSeason.value,
          episode: episode.value,
        ),
      );
    }
    currentPosition.value = position;
  }

  Future<void> _fetchAndSetMovie(int movieId) async {
    final Either<FetchFailure, MovieData> movie = await _movieService.getMovie(movieId);
    this.movie.value = movie.get;
  }

  Future<void> _fetchAndSetSeason(int season) async {
    this.season.value = season;

    final Either<FetchFailure, SeasonFiles> seasonFiles = await _movieService.getSeasonFiles(
      getMovieOrCrash.id,
      season,
      getMovieOrCrash.seasons.length,
    );

    this.seasonFiles.value = seasonFiles.get;
  }

  Future<void> _fetchAndSetEpisode(int episodeNumber) async {
    List<Language> languages = List<Language>.of(availableLanguages);
    List<Quality> qualities = List<Quality>.of(availableQualities);

    if (seasonFiles.value != null) {
      final Episode? episode = seasonFiles.value!.data.isNotEmpty
          ? seasonFiles.value!.data.firstWhere(
              (Episode element) => element.episode == episodeNumber,
              orElse: () => seasonFiles.value!.data.first,
            )
          : null;

      final List<Language> episodeLanguages = episode?.episodes.keys.toList() ?? <Language>[];
      if (!const DeepCollectionEquality().equals(languages, episodeLanguages)) {
        languages = episodeLanguages;
        final Language preferredLanguage = await _preferencesHelper.readPreferredLanguage();
        language.value =
            languages.firstWhere((Language e) => e == preferredLanguage, orElse: () => languages.first);

        final List<Quality> episodeQualities =
            episode?.episodes[language.value]?.map((EpisodeFile e) => e.quality).toList() ?? <Quality>[];

        if (!const DeepCollectionEquality().equals(qualities, episodeQualities)) {
          qualities = episodeQualities;
          final Quality preferredQuality = await _preferencesHelper.readPreferredQuality();
          quality.value = qualities.firstWhere(
            (Quality e) => e == preferredQuality,
            orElse: () => qualities.first,
          );
        }
      }

      final List<EpisodeFile>? episodeFiles = episode?.episodes[language.value];
      if (episodeFiles != null && episodeFiles.isNotEmpty) {
        videoSrc = episodeFiles
            .firstWhere(
              (EpisodeFile e) => e.quality == quality.value,
              orElse: () => episodeFiles.first,
            )
            .src;
      }
    }

    startPosition.value = firstEpisodePassed ? Duration.zero : startPosition.value;
    episode.value = episodeNumber;
    episodeSeason.value = season.value;
    availableLanguages.value = languages;
    availableQualities.value = qualities;
    firstEpisodePassed = true;

    _initControllers();
    _subtitlesControllerMiddleMan.removeCurrentSubtitles();
  }

  Future<void> _fetchAndSetRelated(int movieId) async {
    final Either<FetchFailure, Movies> related = await _movieService.getRelatedMovies(movieId, 1);

    this.related.value = related.map((Movies r) {
      r.data.removeWhere((MovieData element) => !element.canBePlayed);
      return r;
    }).get;
  }

  void _initControllers() {
    _videoPlayerController?.dispose();
    chewieController.value?.dispose();

    if (videoSrc != null) {
      _videoPlayerController = VideoPlayerController.network(videoSrc!);
      chewieController.value = ChewieController(
        videoPlayerController: _videoPlayerController!,
        autoInitialize: true,
        looping: true,
        autoPlay: settings.value.autoPlayEnabled,
        startAt: startPosition.value,
        allowFullScreen: false,
        customControls: const VideoPlayerControls(),
      );
    }
  }
}
