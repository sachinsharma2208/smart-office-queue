import 'package:flutter/material.dart';

class ChartGroup {
  const ChartGroup(this.label, this.values);
  final String label;
  final List<double> values; // one value per series
}

/// Minimal grouped bar chart (no chart dependency).
class SimpleBarChart extends StatelessWidget {
  const SimpleBarChart({
    super.key,
    required this.groups,
    required this.seriesLabels,
    required this.seriesColors,
    this.height = 150,
  });

  final List<ChartGroup> groups;
  final List<String> seriesLabels;
  final List<Color> seriesColors;
  final double height;

  @override
  Widget build(BuildContext context) {
    var maxValue = 1.0;
    for (final g in groups) {
      for (final v in g.values) {
        if (v > maxValue) maxValue = v;
      }
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 16,
          children: [
            for (var i = 0; i < seriesLabels.length; i++)
              Row(mainAxisSize: MainAxisSize.min, children: [
                Container(width: 12, height: 12, decoration: BoxDecoration(color: seriesColors[i], borderRadius: BorderRadius.circular(3))),
                const SizedBox(width: 6),
                Text(seriesLabels[i], style: Theme.of(context).textTheme.bodySmall),
              ]),
          ],
        ),
        const SizedBox(height: 12),
        SizedBox(
          height: height + 44,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              for (final g in groups)
                Expanded(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          for (var i = 0; i < g.values.length; i++)
                            Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 3),
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.end,
                                children: [
                                  Text(g.values[i].toStringAsFixed(0), style: Theme.of(context).textTheme.labelSmall),
                                  const SizedBox(height: 2),
                                  Container(
                                    width: 16,
                                    height: (g.values[i] / maxValue * height).clamp(2.0, height),
                                    decoration: BoxDecoration(
                                      color: seriesColors[i],
                                      borderRadius: const BorderRadius.vertical(top: Radius.circular(4)),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Text(g.label, style: Theme.of(context).textTheme.bodySmall, overflow: TextOverflow.ellipsis),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }
}
