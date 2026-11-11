import 'package:flutter/material.dart';

/// The same control appears above both home screens for verified owners.
class PartnerModeToggle extends StatelessWidget {
  const PartnerModeToggle({
    super.key,
    required this.partnerMode,
    required this.onChanged,
  });

  final bool partnerMode;
  final ValueChanged<bool>? onChanged;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        child: MergeSemantics(
          child: Row(children: [
            const Expanded(
              child: Text('파트너 모드',
                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
            ),
            Tooltip(
              message: partnerMode ? '일반 모드로 전환' : '파트너 모드로 전환',
              child: Switch.adaptive(
                value: partnerMode,
                activeTrackColor: const Color(0xFF050072),
                onChanged: onChanged,
              ),
            ),
          ]),
        ),
      );
}
