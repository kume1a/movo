import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:intl/intl.dart';

import '../../../controllers/main/statistics_controller.dart';
import '../../../core/enums/time_period.dart';
import '../../../data/model/models/watched_movies/watched_duration.dart';
import '../../../l10n/parameterized_translations.dart';
import '../../core/values/colors.dart';

class ChartDurations extends GetView<StatisticsController> {
  const ChartDurations({super.key});

  @override
  Widget build(BuildContext context) {
    return Obx(() {
      if (controller.watchedDurations.isEmpty) return const SizedBox.shrink();

      double minY = double.maxFinite;
      double maxY = double.minPositive;
      double minX = 0;
      double maxX = 0;
      double minY0 = 0;
      double maxY0 = 0;
      const int divider = 25;

      final int bottomTitlesCount = controller.timePeriod.value == TimePeriod.year ? 5 : 6;
      final List<FlSpot> values = controller.watchedDurations.map((WatchedDuration e) {
        if (e.durationInMillis.compareTo(BigInt.from(minY)) < 0) minY = e.durationInMillis.toDouble();
        if (e.durationInMillis.compareTo(BigInt.from(maxY)) > 0) maxY = e.durationInMillis.toDouble();

        return FlSpot(
          e.date.millisecondsSinceEpoch.toDouble(),
          e.durationInMillis.toDouble(),
        );
      }).toList();

      minX = values.first.x;
      maxX = values.last.x;
      minY0 = (minY / divider).floorToDouble() * divider;
      maxY0 = (maxY / divider).ceilToDouble() * divider;

      final double leftTitlesInterval = maxY - minY != 0 ? ((maxY0 - minY0) / 5).floorToDouble() : 100;
      final double bottomTitlesInterval = (maxX - minX) / bottomTitlesCount + .01;

      final DateFormat dateFormat = controller.timePeriod.value == TimePeriod.year
          ? DateFormat('MMM d yy', Localizations.localeOf(context).languageCode)
          : DateFormat.MMMd(Localizations.localeOf(context).languageCode);

      return AspectRatio(
        aspectRatio: 16 / 9,
        child: LineChart(
          LineChartData(
            lineTouchData: LineTouchData(enabled: false),
            gridData: FlGridData(show: false),
            titlesData: FlTitlesData(
              bottomTitles: AxisTitles(
                sideTitles: SideTitles(
                  showTitles: true,
                  getTitlesWidget: (double value, TitleMeta meta) => Text(
                    dateFormat.format(DateTime.fromMillisecondsSinceEpoch(value.toInt())),
                    style: const TextStyle(color: Colors.white54, fontSize: 12),
                  ),
                  reservedSize: 30,
                  interval: bottomTitlesInterval,
                ),
              ),
              leftTitles: AxisTitles(
                sideTitles: SideTitles(
                  showTitles: true,
                  getTitlesWidget: (double value, TitleMeta meta) {
                    final Duration duration = Duration(milliseconds: value.floor());
                    final String minutesFraction =
                        (duration.inMinutes / 60).toStringAsFixed(1).split('.').last;
                    return Text(
                      ParamTranslations.commonHours('${duration.inHours}.$minutesFraction'),
                      style: const TextStyle(color: Colors.white54, fontSize: 12),
                    );
                  },
                  reservedSize: 42,
                  interval: leftTitlesInterval,
                ),
              ),
              rightTitles: const AxisTitles(),
              topTitles: const AxisTitles(),
            ),
            borderData: FlBorderData(
              border: const Border(
                left: BorderSide(color: Colors.white12),
                bottom: BorderSide(color: Colors.white12),
              ),
            ),
            minX: minX,
            maxX: maxX,
            minY: minY0,
            maxY: maxY0,
            lineBarsData: <LineChartBarData>[
              LineChartBarData(
                spots: values,
                gradient: LinearGradient(
                  colors: <Color>[colorAccent, colorPrimary],
                  stops: const <double>[.6, .9],
                  begin: const Alignment(.1, 0),
                  end: const Alignment(.1, 1),
                ),
                isStrokeCapRound: true,
                dotData: const FlDotData(show: false),
                belowBarData: BarAreaData(
                  show: true,
                  gradient: LinearGradient(
                    colors: <Color>[colorAccent, colorPrimary],
                    stops: const <double>[0, 1],
                    begin: const Alignment(.1, 0),
                    end: const Alignment(.1, 1),
                  ),
                ),
              )
            ],
          ),
        ),
      );
    });
  }
}
