/// Timezone picker — bottom-sheet picker over a hardcoded list of
/// ~20 common IANA zones (default Asia/Dhaka).
///
/// We deliberately avoid pulling in the `timezone` package's full
/// database — the actual use case (caretaker abroad sending a voice
/// home at Bangladesh 8 PM) doesn't need 600+ zones, and a curated
/// list is easier for an older user to scan.
library;

import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// IANA timezone string (validated by `flutter_timezone` elsewhere).
class TimezoneOption {
  final String iana;
  final String labelBn; // Bangla display name (e.g. "বাংলাদেশ")
  final String cityEn; // English hint (e.g. "Dhaka")
  final Duration offset;
  const TimezoneOption({
    required this.iana,
    required this.labelBn,
    required this.cityEn,
    required this.offset,
  });
}

const List<TimezoneOption> kVoiceTimezones = [
  TimezoneOption(iana: 'Asia/Dhaka', labelBn: 'বাংলাদেশ', cityEn: 'Dhaka', offset: Duration(hours: 6)),
  TimezoneOption(iana: 'Asia/Kolkata', labelBn: 'ভারত', cityEn: 'Kolkata', offset: Duration(hours: 5, minutes: 30)),
  TimezoneOption(iana: 'Asia/Karachi', labelBn: 'পাকিস্তান', cityEn: 'Karachi', offset: Duration(hours: 5)),
  TimezoneOption(iana: 'Asia/Dubai', labelBn: 'সংযুক্ত আরব আমিরাত', cityEn: 'Dubai', offset: Duration(hours: 4)),
  TimezoneOption(iana: 'Asia/Riyadh', labelBn: 'সৌদি আরব', cityEn: 'Riyadh', offset: Duration(hours: 3)),
  TimezoneOption(iana: 'Asia/Tehran', labelBn: 'ইরান', cityEn: 'Tehran', offset: Duration(hours: 3, minutes: 30)),
  TimezoneOption(iana: 'Europe/Istanbul', labelBn: 'তুরস্ক', cityEn: 'Istanbul', offset: Duration(hours: 3)),
  TimezoneOption(iana: 'Europe/London', labelBn: 'যুক্তরাজ্য', cityEn: 'London', offset: Duration(hours: 0)),
  TimezoneOption(iana: 'Europe/Berlin', labelBn: 'জার্মানি', cityEn: 'Berlin', offset: Duration(hours: 1)),
  TimezoneOption(iana: 'Europe/Paris', labelBn: 'ফ্রান্স', cityEn: 'Paris', offset: Duration(hours: 1)),
  TimezoneOption(iana: 'Europe/Moscow', labelBn: 'রাশিয়া', cityEn: 'Moscow', offset: Duration(hours: 3)),
  TimezoneOption(iana: 'Africa/Cairo', labelBn: 'মিশর', cityEn: 'Cairo', offset: Duration(hours: 2)),
  TimezoneOption(iana: 'America/New_York', labelBn: 'পূর্ব আমেরিকা', cityEn: 'New York', offset: Duration(hours: -5)),
  TimezoneOption(iana: 'America/Chicago', labelBn: 'মধ্য আমেরিকা', cityEn: 'Chicago', offset: Duration(hours: -6)),
  TimezoneOption(iana: 'America/Denver', labelBn: 'পাহাড়ি আমেরিকা', cityEn: 'Denver', offset: Duration(hours: -7)),
  TimezoneOption(iana: 'America/Los_Angeles', labelBn: 'পশ্চিম আমেরিকা', cityEn: 'Los Angeles', offset: Duration(hours: -8)),
  TimezoneOption(iana: 'America/Toronto', labelBn: 'কানাডা', cityEn: 'Toronto', offset: Duration(hours: -5)),
  TimezoneOption(iana: 'Australia/Sydney', labelBn: 'অস্ট্রেলিয়া', cityEn: 'Sydney', offset: Duration(hours: 10)),
  TimezoneOption(iana: 'Pacific/Auckland', labelBn: 'নিউজিল্যান্ড', cityEn: 'Auckland', offset: Duration(hours: 12)),
  TimezoneOption(iana: 'Asia/Singapore', labelBn: 'সিঙ্গাপুর', cityEn: 'Singapore', offset: Duration(hours: 8)),
  TimezoneOption(iana: 'Asia/Kuala_Lumpur', labelBn: 'মালয়েশিয়া', cityEn: 'Kuala Lumpur', offset: Duration(hours: 8)),
  TimezoneOption(iana: 'Asia/Bangkok', labelBn: 'থাইল্যান্ড', cityEn: 'Bangkok', offset: Duration(hours: 7)),
];

TimezoneOption findTimezone(String iana) =>
    kVoiceTimezones.firstWhere(
      (t) => t.iana == iana,
      orElse: () => kVoiceTimezones.first,
    );

/// Show the timezone bottom-sheet. Returns the picked [TimezoneOption]
/// or null if dismissed.
Future<TimezoneOption?> showTimezonePicker(
  BuildContext context, {
  TimezoneOption? selected,
}) {
  return showModalBottomSheet<TimezoneOption>(
    context: context,
    backgroundColor: AppColors.surface,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
    ),
    isScrollControlled: true,
    builder: (ctx) => _TimezoneSheet(selected: selected),
  );
}

class _TimezoneSheet extends StatefulWidget {
  final TimezoneOption? selected;
  const _TimezoneSheet({this.selected});

  @override
  State<_TimezoneSheet> createState() => _TimezoneSheetState();
}

class _TimezoneSheetState extends State<_TimezoneSheet> {
  late TimezoneOption _current;

  @override
  void initState() {
    super.initState();
    _current = widget.selected ?? kVoiceTimezones.first;
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.7,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 12),
            Container(
              width: 44,
              height: 4,
              decoration: BoxDecoration(
                color: AppColors.lineStrong,
                borderRadius: BorderRadius.circular(4),
              ),
            ),
            const SizedBox(height: 16),
            const Text(
              'টাইমজোন বাছাই করুন',
              style: TextStyle(
                fontSize: 19,
                fontWeight: FontWeight.w800,
                color: AppColors.text,
              ),
            ),
            const SizedBox(height: 12),
            Flexible(
              child: ListView.separated(
                shrinkWrap: true,
                itemCount: kVoiceTimezones.length,
                separatorBuilder: (_, __) => const Divider(
                  height: 1,
                  color: AppColors.line,
                ),
                itemBuilder: (ctx, i) {
                  final tz = kVoiceTimezones[i];
                  final selected = tz.iana == _current.iana;
                  return ListTile(
                    onTap: () => Navigator.of(ctx).pop(tz),
                    selected: selected,
                    selectedTileColor: AppColors.cyan.withValues(alpha: 0.06),
                    leading: Container(
                      width: 36,
                      height: 36,
                      decoration: BoxDecoration(
                        color: selected
                            ? AppColors.cyan
                            : AppColors.surfaceHigh,
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        Icons.public_rounded,
                        size: 18,
                        color: selected
                            ? AppColors.void1
                            : AppColors.textMuted,
                      ),
                    ),
                    title: Text(
                      tz.labelBn,
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: selected ? AppColors.cyan : AppColors.text,
                      ),
                    ),
                    subtitle: Text(
                      '${tz.cityEn}  •  ${_fmtOffset(tz.offset)}',
                      style: const TextStyle(
                        fontSize: 13,
                        color: AppColors.textMuted,
                      ),
                    ),
                    trailing: selected
                        ? const Icon(
                            Icons.check_rounded,
                            color: AppColors.cyan,
                          )
                        : null,
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

String _fmtOffset(Duration d) {
  final h = d.inHours;
  final m = (d.inMinutes - h * 60).abs();
  final sign = h >= 0 ? '+' : '-';
  return 'UTC $sign${h.abs().toString().padLeft(2, '0')}:${m.toString().padLeft(2, '0')}';
}
