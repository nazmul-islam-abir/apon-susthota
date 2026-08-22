$f = "c:\Users\Nazmul\StudioProjects\diabetics_meal-main\lib\screens\meal_plan_screen.dart"
$c = Get-Content $f -Raw
$start = $c.IndexOf("Widget _buildDateStrip(")
$endMarker = "  Map<String, List<MealSlotPlan>> _groupItemsForView()"
$end = $c.IndexOf($endMarker, $start)
if ($start -lt 0 -or $end -lt 0) { throw "anchors not found" }
$end = $end - 2  # back up to start of "  Map<String" — we want the date strip block to end with its own closing brace and a blank line

$replacement = @"
Widget _buildDateStrip(List<DateTime> dates) {
    final todaySlot = _todayDayIndex ?? 1;
    // activeIdx = offset from todaySlot to _day inside a 30-day cycle.
    final activeIdxClamped = ((_day - todaySlot) % 30 + 30) % 30; // 0..29
    final bnWeekdays = ['à¦¸à§‹à¦®', 'à¦®à¦™à§à¦—à¦²', 'à¦¬à§à¦§', 'à¦¬à§ƒà¦¹à¦ƒ', 'à¦¶à¦•à§à¦°', 'à¦¶à¦¨à¦¿', 'à¦°à¦¬à¦¿'];
    // Bangla month short forms for the date strip footer.
    final bnMonths = [
      'à¦œà¦¾à¦¨à§', 'à¦«à§à¦¬', 'à¦®à¦¾à¦°', 'à¦�à¦ªà§', 'à¦®à§‡',
      'à¦œà§�à¦¨', 'à¦œà§�à¦²', 'à¦†à¦—', 'à¦¸à§‡à¦ª', 'à¦…à¦•',
      'à¦¨à¦­', 'à¦¡à¦¿à¦¸',
    ];
    final today = DateTime.now();
    bool isToday(DateTime d) =>
        d.year == today.year && d.month == today.month && d.day == today.day;
    bool isWeekend(DateTime d) =>
        d.weekday == DateTime.friday || d.weekday == DateTime.saturday;
    return SizedBox(
      height: 78,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        physics: const BouncingScrollPhysics(),
        padding: const EdgeInsets.symmetric(horizontal: 18),
        itemCount: dates.length,
        separatorBuilder: (_, __) => const SizedBox(width: 10),
        itemBuilder: (_, i) {
          final d = dates[i];
          final selected = i == activeIdxClamped.clamp(0, dates.length - 1);
          final weekday = bnWeekdays[(d.weekday - 1) % 7];
          final weekend = isWeekend(d);
          final monthLabel = bnMonths[d.month - 1];
          return Pressable(
            onTap: () {
              // Map the calendar offset onto a plan day relative to
              // the server-reported "today" slot. We can't use `i+1`
              // directly because the strip's first pill is today's
              // *plan day*, not 1 â on the second cycle today maps to
              // plan day 1 again, but on the first cycle it may be any
              // 1..30. Centering on `progress.day` keeps both ends in
              // sync (yesterday / today / tomorrow snap correctly).
              final todaySlot = _todayDayIndex ?? 1;
              final newDay = ((todaySlot - 1 + i) % 30) + 1;
              if (newDay == _day) return;
              setState(() => _day = newDay);
              _load();
            },
            child: AnimatedContainer(
              duration: AppMotion.short,
              curve: AppMotion.emphasized,
              width: 60,
              decoration: BoxDecoration(
                gradient: selected
                    ? const LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [Color(0xFFF6A6C5), Color(0xFFEC7AA1)],
                      )
                    : null,
                color: selected ? null : const Color(0xFFFCE7EF),
                border: Border.all(
                  color: selected
                      ? const Color(0xFFEC7AA1)
                      : const Color(0x1A1F1018),
                  width: 1.0,
                ),
                borderRadius: BorderRadius.circular(22),
                boxShadow: selected
                    ? const [
                        BoxShadow(
                          color: Color(0x55EC7AA1),
                          blurRadius: 14,
                          offset: Offset(0, 6),
                        ),
                      ]
                    : const [],
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        weekday,
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 0.3,
                          color: selected
                              ? Colors.white.withValues(alpha: 0.85)
                              : (weekend
                                  ? const Color(0xFFEC7AA1)
                                  : _canvasInner.withValues(alpha: 0.55)),
                        ),
                      ),
                      if (isToday(d)) ...[
                        const SizedBox(width: 4),
                        Container(
                          width: 5,
                          height: 5,
                          decoration: BoxDecoration(
                            color: selected ? Colors.white : _brandPink,
                            shape: BoxShape.circle,
                          ),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '${d.day}',
                    style: TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.w900,
                      height: 1.0,
                      letterSpacing: -0.5,
                      color: selected ? Colors.white : _canvasInner,
                    ),
                  ),
                  const SizedBox(height: 1),
                  Text(
                    monthLabel,
                    style: TextStyle(
                      fontSize: 9,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.2,
                      color: selected
                          ? Colors.white.withValues(alpha: 0.78)
                          : _canvasInner.withValues(alpha: 0.45),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

"@

$newContent = $c.Substring(0, $start) + $replacement + $c.Substring($end)
Set-Content -Path $f -Value $newContent -Encoding UTF8 -NoNewline
Write-Output ("wrote {0} chars" -f $newContent.Length)
