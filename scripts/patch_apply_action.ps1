$f = "c:\Users\Nazmul\StudioProjects\diabetics_meal-main\lib\screens\meal_plan_screen.dart"
$c = Get-Content $f -Raw
$oldStart = "  Future<void> _applyItemAction(MealSlotPlan item, _ItemSheetResult r) async {"
$oldEnd = "    }
  }

  void _showThankYou() {"
$start = $c.IndexOf($oldStart)
$end = $c.IndexOf($oldEnd, $start)
if ($start -lt 0 -or $end -lt 0) { throw "anchors not found" }

$replacement = @"
  Future<void> _applyItemAction(MealSlotPlan item, _ItemSheetResult r) async {
    bool overrideFailed = false;
    String? overrideError;
    try {
      await SupabaseService.logMeal(
        mealSlot: item.slot,
        foodId: r.food?.id,
        foodNameBn: r.food?.nameBn ?? r.customLabel ?? item.food.nameBn,
        status: r.status,
        impact: r.impact,
        planDay: _day,
        reason: r.reason,
        notes: r.notes,
      );

      // When the user picks a real alternative (swap) for an AI-suggested
      // tile, also persist it as a per-day override so the next _load()
      // refetches the merged plan and shows the new food in place of the
      // original papaya / rice / etc. Off-plan entries and free-text custom
      // labels don't need an override because the user is just recording
      // what they ate, not changing tomorrow's plan.
      if (r.status == 'swap' &&
          r.food != null &&
          r.food!.id.trim().isNotEmpty &&
          r.food!.id != item.food.id) {
        try {
          await SupabaseService.upsertAiPlanOverride(
            planDay: _day,
            slot: item.slot,
            role: item.role == 'main' ? null : item.role,
            foodId: r.food!.id,
          );
        } catch (e) {
          // Override is no longer silently swallowed — the swap looks
          // broken if the per-day override never lands, so surface a
          // snackbar so the user knows the analytics log was kept but
          // the AI plan won't change until the RPC is healthy again.
          debugPrint('upsertAiPlanOverride failed: $e');
          overrideFailed = true;
          overrideError = e.toString();
        }
      }

      if (!mounted) return;
      await _load();
      AppEvents.notifyMealLogged();
      HapticFeedback.lightImpact();
      if (!mounted) return;

      // Show the success toast only after the list has re-rendered so
      // the swapped tile is visible underneath the toast instead of the
      // toast covering the area where the change happens.
      _showThankYou();
      if (overrideFailed && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'লগ হয়েছে, কিন্তু AI পরামর্শ বদলানো যায়নি (${overrideError ?? ''}). পরে আবার চেষ্টা করুন।',
            ),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('লগ করা যায়নি')),
        );
      }
    }
  }

  void _showThankYou() {"
"@

$newContent = $c.Substring(0, $start) + $replacement + $c.Substring($end)
Set-Content -Path $f -Value $newContent -Encoding UTF8 -NoNewline
Write-Output ("wrote {0} chars" -f $newContent.Length)
