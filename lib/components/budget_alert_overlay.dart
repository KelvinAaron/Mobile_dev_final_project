import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../utils/budget_utils.dart';


class BudgetAlertOverlay extends StatelessWidget {
  final List<BudgetAlert> alerts;
  final bool visible;
  final VoidCallback onClose;

  const BudgetAlertOverlay({
    super.key,
    required this.alerts,
    required this.visible,
    required this.onClose,
  });

  @override
  Widget build(BuildContext context) {
    if (!visible || alerts.isEmpty) return const SizedBox.shrink();

    final numberFormat = NumberFormat.decimalPattern();

    return Positioned(
      top: 0,
      left: 0,
      right: 0,
      child: SafeArea(
        child: Container(
          margin: const EdgeInsets.only(top: 8),
          decoration: const BoxDecoration(
            color: Color(0xFFFEE2E2),
            border: Border(
              bottom: BorderSide(color: Color(0xFFEF4444), width: 2),
            ),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Padding(
                padding: EdgeInsets.only(top: 2),
                child: Icon(
                  Icons.warning_amber_rounded,
                  size: 20,
                  color: Color(0xFFDC2626),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    for (final alert in alerts)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 4),
                        child: Text(
                          '${alert.category} budget exceeded by ${numberFormat.format(alert.exceeded)} RWF',
                          style: const TextStyle(
                            fontSize: 12,
                            color: Color(0xFFDC2626),
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              InkWell(
                onTap: onClose,
                child: const Padding(
                  padding: EdgeInsets.all(8),
                  child: Icon(
                    Icons.close,
                    size: 18,
                    color: Color(0xFFDC2626),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
