import 'package:get/get.dart';
import 'package:injectable/injectable.dart';

import '../../core/enums/favorites_page_state.dart';
import '../../data/local/favorite_movie/favorite_movie_dao.dart';
import '../../data/local/movie_group/movie_group_dao.dart';
import '../../data/local/preferences/preferences_helper.dart';
import '../../data/model/core/either.dart';
import '../../data/model/core/fetch_failure.dart';
import '../../data/model/models/movie_groups/movie_group.dart';
import '../../data/model/models/movies/movie_data.dart';
import '../../data/network/services/movie_service.dart';
import '../../l10n/parameterized_translations.dart';
import '../../l10n/translation_keys.dart';
import '../../ui/core/bottom_sheets/core/bottom_sheet_manager.dart';
import '../../ui/core/dialogs/core/dialog_manager.dart';
import '../../ui/core/enums/option_movie_group.dart';
import '../../ui/core/routes/screens_navigator.dart';
import '../core/base_controller_middle_man.dart';

@injectable
class FavoritesController extends GetxController {
  FavoritesController(
    this._favoriteMovieDao,
    this._movieGroupDao,
    this._preferencesHelper,
    this._dialogManager,
    this._bottomSheetManager,
  );

  final FavoriteMovieDao _favoriteMovieDao;
  final MovieGroupDao _movieGroupDao;
  final PreferencesHelper _preferencesHelper;
  final DialogManager _dialogManager;
  final BottomSheetManager _bottomSheetManager;

  final RxList<MovieData> movies = <MovieData>[].obs;
  final RxList<MovieGroup> movieGroups = <MovieGroup>[].obs;
  final Rxn<FavoritesPageState> pageState = Rxn<FavoritesPageState>();
  final RxBool isLoading = false.obs;

  @override
  Future<void> onInit() async {
    super.onInit();

    final FavoritesPageState favoritesPageState = await _preferencesHelper.readFavoritesPageState();
    switch (favoritesPageState) {
      case FavoritesPageState.seeAll:
        onSwitchedToSeeAll();
        break;
      case FavoritesPageState.groups:
        onSwitchedToMovieGroups();
        break;
    }
  }

  Future<void> onSwitchedToSeeAll() async {
    if (pageState.value != FavoritesPageState.seeAll) {
      pageState.value = FavoritesPageState.seeAll;
      await _preferencesHelper.writeFavoritesPageState(FavoritesPageState.seeAll);
      await _fetchFavoriteMovies();
    }
  }

  Future<void> onSwitchedToMovieGroups() async {
    if (pageState.value != FavoritesPageState.groups) {
      pageState.value = FavoritesPageState.groups;
      await _preferencesHelper.writeFavoritesPageState(FavoritesPageState.groups);
      await _fetchMovieGroups();
    }
  }

  void onFavoriteMoviePressed(MovieData movie) => ScreensNavigator.pushDetailsPage(movie.movieId);

  void onMovieGroupPressed(MovieGroup movieGroup) {
    if (movieGroup.groupId != null && movieGroup.movieNamesEn.isNotEmpty) {
      ScreensNavigator.pushMovieGroupPage(movieGroup.groupId!);
    }
  }

  Future<void> onAddMovieGroupPressed() async {
    final String? groupName = await _dialogManager.showFieldInputDialog(
      header: trFavoritesHeaderAddGroup.tr,
      inputHint: trCommonName.tr,
    );
    if (groupName == null) {
      return;
    }

    final int groupId = await _movieGroupDao.saveMovieGroup(groupName);
    if (pageState.value == FavoritesPageState.groups) {
      final MovieGroup? insertedGroup = await _movieGroupDao.getMovieGroup(groupId);
      if (insertedGroup != null) {
        movieGroups.insert(0, insertedGroup);
      }
    }
  }

  Future<void> onGroupLongPressed(MovieGroup movieGroup) async {
    if (movieGroup.groupId == null) {
      return;
    }

    final OptionMovieGroup? selectedOption =
        await _bottomSheetManager.showOptionsSelector<OptionMovieGroup>(
      OptionMovieGroup.values,
      (OptionMovieGroup option) => option.translate(),
    );
    if (selectedOption == null) {
      return;
    }

    switch (selectedOption) {
      case OptionMovieGroup.editName:
        final String? newGroupName = await _dialogManager.showFieldInputDialog(
          header: trFavoritesHeaderEditMovieGroupName.tr,
          inputHint: trCommonName.tr,
          initialValue: movieGroup.name,
        );
        if (newGroupName == null) {
          return;
        }

        await _movieGroupDao.updateMovieGroupName(movieGroup.groupId!, newGroupName);
        if (pageState.value == FavoritesPageState.groups) {
          await _fetchMovieGroups();
        }
        break;
      case OptionMovieGroup.delete:
        final bool didConfirm = await _dialogManager.showConfirmationDialog(
          title: ParamTranslations.favoritesHeaderDeleteGroup(movieGroup.name),
          content: ParamTranslations.favoritesContentDeleteGroup(movieGroup.name),
        );
        if (!didConfirm) {
          return;
        }

        await _movieGroupDao.deleteMovieGroup(movieGroup.groupId!);
        if (pageState.value == FavoritesPageState.groups) {
          movieGroups.remove(movieGroup);
        }
        break;
    }
  }

  Future<void> _fetchMovieGroups() async {
    isLoading.value = true;
    final List<MovieGroup> movieGroups = await _movieGroupDao.getMovieGroups();
    isLoading.value = false;

    movies.clear();
    this.movieGroups.assignAll(movieGroups);
  }

  Future<void> _fetchFavoriteMovies() async {
    isLoading.value = true;
    final List<MovieData> favoriteMovies = await _favoriteMovieDao.getFavoritedMovies();
    isLoading.value = false;

    movies.assignAll(favoriteMovies);
    movieGroups.clear();
  }
}

@injectable
class FavoritesControllerMiddleMan extends BaseControllerMiddleMan<FavoritesController> {
  FavoritesControllerMiddleMan(
    this._movieService,
  );

  final MovieService _movieService;

  // TODO: 18/09/2021 refactor to optimize groups
  void onFavoriteMovieAddedToGroup(int movieId, int? movieGroupId) {
    runIfRegistered((FavoritesController controller) async {
      switch (controller.pageState.value) {
        case FavoritesPageState.seeAll:
          final Either<FetchFailure, MovieData> movie = await _movieService.getMovie(movieId);
          movie.fold(
            (_) {},
            (MovieData r) => controller.movies.insert(0, r),
          );
          break;
        case FavoritesPageState.groups:
          controller._fetchMovieGroups();
          break;
        default:
          break;
      }
    });
  }

  void onFavoriteMovieGroupSwitched(
    int movieId,
    MovieGroup? from,
    MovieGroup to,
  ) {
    runIfRegistered((FavoritesController controller) {
      if (controller.pageState.value == FavoritesPageState.groups) {
        controller._fetchMovieGroups();
      }
    });
  }

  void onFavoriteMovieSwitchedToNoGroup(int movieId) {
    runIfRegistered((FavoritesController controller) {
      if (controller.pageState.value == FavoritesPageState.groups) {
        controller._fetchMovieGroups();
      }
    });
  }

  void onFavoriteMovieRemoved(int movieId) {
    runIfRegistered((FavoritesController controller) {
      switch (controller.pageState.value) {
        case FavoritesPageState.seeAll:
          controller.movies.removeWhere((MovieData e) => e.movieId == movieId);
          break;
        case FavoritesPageState.groups:
          controller._fetchMovieGroups();
          break;
        default:
          break;
      }
    });
  }
}
