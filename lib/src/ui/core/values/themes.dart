import 'package:flutter/material.dart';

import 'colors.dart';

class AppThemes {
  AppThemes._();

  static final ThemeData dark = ThemeData.dark().copyWith(
    scaffoldBackgroundColor: colorPrimary,
    splashColor: colorAccent,
    textButtonTheme: TextButtonThemeData(
      style: ButtonStyle(
        foregroundColor: WidgetStateProperty.resolveWith<Color>(
          (Set<WidgetState> states) =>
              states.contains(WidgetState.disabled) ? colorTextSecondary : colorTextPrimary,
        ),
        overlayColor: WidgetStateProperty.all<Color>(colorAccent.withOpacity(.5)),
      ),
    ),
    dialogTheme: DialogThemeData(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
      ),
    ),
    popupMenuTheme: PopupMenuThemeData(
      elevation: 4,
      textStyle: const TextStyle(color: colorTextPrimary),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
      ),
    ),
    snackBarTheme: const SnackBarThemeData(
      backgroundColor: colorPrimaryLight,
      actionTextColor: colorAccent,
      contentTextStyle: TextStyle(color: colorTextPrimary),
      elevation: 12,
    ),
    sliderTheme: SliderThemeData(
      trackShape: LessMarginTrackShape(),
    ),
    checkboxTheme: CheckboxThemeData(
      fillColor: WidgetStateProperty.resolveWith<Color?>((Set<WidgetState> states) {
        if (states.contains(WidgetState.disabled)) {
          return null;
        }
        if (states.contains(WidgetState.selected)) {
          return colorAccent;
        }
        return null;
      }),
    ),
    radioTheme: RadioThemeData(
      fillColor: WidgetStateProperty.resolveWith<Color?>((Set<WidgetState> states) {
        if (states.contains(WidgetState.disabled)) {
          return null;
        }
        if (states.contains(WidgetState.selected)) {
          return colorAccent;
        }
        return null;
      }),
    ),
    switchTheme: SwitchThemeData(
      thumbColor: WidgetStateProperty.resolveWith<Color?>((Set<WidgetState> states) {
        if (states.contains(WidgetState.disabled)) {
          return null;
        }
        if (states.contains(WidgetState.selected)) {
          return colorAccent;
        }
        return null;
      }),
      trackColor: WidgetStateProperty.resolveWith<Color?>((Set<WidgetState> states) {
        if (states.contains(WidgetState.disabled)) {
          return null;
        }
        if (states.contains(WidgetState.selected)) {
          return colorAccent;
        }
        return null;
      }),
    ),
    colorScheme: const ColorScheme.dark()
        .copyWith(
          primary: colorAccent,
          secondary: colorAccent,
        )
        .copyWith(surface: colorPrimary),
  );

  static final ThemeData darkLocaleKa = dark.copyWith(
    textTheme: const TextTheme(
      headlineSmall: TextStyle(fontSize: 21),
      titleLarge: TextStyle(fontSize: 18),
      bodyMedium: TextStyle(color: colorTextSecondary, fontSize: 14),
      bodyLarge: TextStyle(color: colorTextSecondary, fontSize: 12),
    ),
  );
}

class LessMarginTrackShape extends RoundedRectSliderTrackShape {
  @override
  Rect getPreferredRect({
    required RenderBox parentBox,
    Offset offset = Offset.zero,
    required SliderThemeData sliderTheme,
    bool isEnabled = false,
    bool isDiscrete = false,
  }) {
    final double trackHeight = sliderTheme.trackHeight ?? 0;
    final double trackLeft = offset.dx + 12;
    final double trackTop = offset.dy + (parentBox.size.height - trackHeight) / 2;
    final double trackWidth = parentBox.size.width - 24;
    return Rect.fromLTWH(trackLeft, trackTop, trackWidth, trackHeight);
  }
}
