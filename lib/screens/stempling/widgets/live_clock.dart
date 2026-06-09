import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

/// Alltid-oppdatert klokke for kiosk og stempling.
class LiveClock extends StatefulWidget {
  const LiveClock({
    super.key,
    this.style,
    this.showSeconds = false,
    this.showDate = false,
  });

  final TextStyle? style;
  final bool showSeconds;
  final bool showDate;

  @override
  State<LiveClock> createState() => _LiveClockState();
}

class _LiveClockState extends State<LiveClock> {
  late Timer _timer;
  DateTime _now = DateTime.now();

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() => _now = DateTime.now());
    });
  }

  @override
  void dispose() {
    _timer.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final format = widget.showSeconds ? 'HH:mm:ss' : 'HH:mm';
    final time = DateFormat(format).format(_now);
    final defaultStyle = widget.style ??
        Theme.of(context).textTheme.headlineMedium?.copyWith(
              fontWeight: FontWeight.w600,
              letterSpacing: 1.2,
            );

    if (!widget.showDate) {
      return Text(time, style: defaultStyle);
    }

    final date = DateFormat('EEEE d. MMMM', 'nb').format(_now);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Text(time, style: defaultStyle),
        Text(
          date,
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Colors.black54,
              ),
        ),
      ],
    );
  }
}
