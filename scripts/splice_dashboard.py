"""Splice dashboard_screen.dart: remove the legacy DarkCard..DateDetail block
and inject the new news/blog widget set in its place.

Legacy block: lines 230..894 inclusive (1-based)
- 230: `/// (Local replacement for MonoCard's missing gradient/borderColor.)`
- 231: `class DarkCard extends StatelessWidget {`
- 894: closing `}` of `_DateDetailCard`
- 895: blank
- 896: `// ─── Error state ───`

The replacement block defines _TopBar, _BellButton, _CategoryPills, _SectionHeader,
_FeaturedCarousel, _FeaturedCard, _CategoryBadge, _AuthorRow, _PlanList, _PlanRow.
"""
from pathlib import Path

DASH = Path(r"c:\Users\Nazmul\StudioProjects\diabetics_meal-main\lib\screens\dashboard_screen.dart")

NEW_BLOCK = r'''/// News/blog dashboard widgets follow. The legacy magenta `DarkCard` /
/// `_HeroHeader` / `_ProfileCard` / `_FeatureGrid` / `_DateDetailCard` block
/// was removed during the v2 redesign — see commit notes for the diff.

// ───────────────────────────────── Top bar ─────────────────────────────────

/// Top row: large greeting + streak pill (left), circular bell with red
/// notification dot (right). Matches the reference design's header.
class _TopBar extends StatelessWidget {
  final UserProfile? profile;
  final int streakDays;
  final VoidCallback onBell;
  const _TopBar({
    required this.profile,
    required this.streakDays,
    required this.onBell,
  });

  @override
  Widget build(BuildContext context) {
    final name = profile?.fullName?.trim();
    final display = (name?.isNotEmpty ?? false) ? name! : 'বন্�ু';
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'স্বাগতম 👋',
                style: TextStyle(
                  color: AppColors.newsMuted,
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                display,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: AppColors.newsInk,
                  fontSize: 30,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -0.6,
                  height: 1.1,
                ),
              ),
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: AppColors.newsSurface,
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(
                      color: AppColors.newsDivider, width: 1),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.local_fire_department_rounded,
                        size: 14, color: AppColors.newsAccent),
                    const SizedBox(width: 6),
                    Text(
                      '$streakDays দিনের স্ট্রিক',
                      style: const TextStyle(
                        color: AppColors.newsInk,
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        _BellButton(onTap: onBell),
      ],
    );
  }
}

class _BellButton extends StatelessWidget {
  final VoidCallback onTap;
  const _BellButton({required this.onTap});
  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () {
        HapticFeedback.selectionClick();
        onTap();
      },
      behavior: HitTestBehavior.opaque,
      child: Container(
        width: 48,
        height: 48,
        decoration: BoxDecoration(
          color: AppColors.newsSurface,
          shape: BoxShape.circle,
          border: Border.all(color: AppColors.newsDivider, width: 1),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.04),
              blurRadius: 10,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        alignment: Alignment.center,
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            const Icon(Icons.notifications_none_rounded,
                size: 22, color: AppColors.newsInk),
            Positioned(
              top: -2,
              right: -2,
              child: Container(
                width: 10,
                height: 10,
                decoration: BoxDecoration(
                  color: AppColors.newsDot,
                  shape: BoxShape.circle,
                  border: Border.all(
                      color: AppColors.newsSurface, width: 1.6),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ────────────────────────────── Category pills ─────────────────────────────

/// Horizontal row of circular category pills (সকাল / দুপুর / সন্ধ্যা / রাত)
/// with category icon, label, and caption. Matches the reference design's
/// "Tech / Crypto / Business" chip row.
class _CategoryPills extends StatelessWidget {
  const _CategoryPills();

  static const _items = <_CategoryDef>[
    _CategoryDef(
      label: 'সকাল',
      caption: 'Breakfast',
      color: Color(0xFFFFE2C2),
      icon: Icons.wb_sunny_outlined,
    ),
    _CategoryDef(
      label: 'দুপুর',
      caption: 'Lunch',
      color: Color(0xFFCBE7C5),
      icon: Icons.rice_bowl_outlined,
    ),
    _CategoryDef(
      label: 'সন্ধ্যা',
      caption: 'Snack',
      color: Color(0xFFF5C9D2),
      icon: Icons.local_cafe_outlined,
    ),
    _CategoryDef(
      label: 'রাত',
      caption: 'Dinner',
      color: Color(0xFFCFD8EE),
      icon: Icons.nightlight_outlined,
    ),
  ];

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 110,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: EdgeInsets.zero,
        itemCount: _items.length,
        separatorBuilder: (_, __) => const SizedBox(width: 14),
        itemBuilder: (_, i) => _CategoryChip(def: _items[i]),
      ),
    );
  }
}

class _CategoryDef {
  final String label;
  final String caption;
  final Color color;
  final IconData icon;
  const _CategoryDef({
    required this.label,
    required this.caption,
    required this.color,
    required this.icon,
  });
}

class _CategoryChip extends StatelessWidget {
  final _CategoryDef def;
  const _CategoryChip({required this.def});
  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 72,
          height: 72,
          decoration: BoxDecoration(
            color: def.color,
            shape: BoxShape.circle,
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.05),
                blurRadius: 10,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          alignment: Alignment.center,
          child: Icon(def.icon, size: 30, color: AppColors.newsInk),
        ),
        const SizedBox(height: 8),
        Text(
          def.label,
          style: const TextStyle(
            color: AppColors.newsInk,
            fontSize: 14,
            fontWeight: FontWeight.w700,
          ),
        ),
        Text(
          def.caption,
          style: const TextStyle(
            color: AppColors.newsMuted,
            fontSize: 11,
            fontWeight: FontWeight.w500,
          ),
        ),
      ],
    );
  }
}

// ─────────────────────────────── Section header ────────────────────────────

/// Big bold header used for "আজকের বিশেষ" / "আজকের পরিকল্পনা" sections.
class _SectionHeader extends StatelessWidget {
  final String title;
  final String? subtitle;
  const _SectionHeader({required this.title, this.subtitle});
  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: const TextStyle(
            color: AppColors.newsInk,
            fontSize: 28,
            fontWeight: FontWeight.w800,
            letterSpacing: -0.6,
            height: 1.1,
          ),
        ),
        if (subtitle != null) ...[
          const SizedBox(height: 6),
          Text(
            subtitle!,
            style: const TextStyle(
              color: AppColors.newsMuted,
              fontSize: 14,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ],
    );
  }
}

// ───────────────────────────── Featured carousel ───────────────────────────

/// Horizontal carousel of full-bleed "news cards". Each card:
///   • 16:9 image (meal image URL → fallback gradient)
///   • Dark gradient overlay
///   • Category badge (top-left)
///   • Headline (bottom-left, large white)
///   • Author avatar + name (bottom row)
class _FeaturedCarousel extends StatelessWidget {
  final List<MealSlotPlan> plan;
  final VoidCallback onTapMeal;
  const _FeaturedCarousel({required this.plan, required this.onTapMeal});

  @override
  Widget build(BuildContext context) {
    final items = _buildItems();
    return SizedBox(
      height: 220,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: EdgeInsets.zero,
        itemCount: items.length,
        separatorBuilder: (_, __) => const SizedBox(width: 14),
        itemBuilder: (_, i) => _FeaturedCard(
          item: items[i],
          onTap: onTapMeal,
        ),
      ),
    );
  }

  List<_FeaturedItem> _buildItems() {
    if (plan.isNotEmpty) {
      return plan.take(3).map((p) {
        final slotLabel = _slotLabel(p.slot);
        return _FeaturedItem(
          slotLabel: slotLabel,
          title: p.food.nameBn,
          author: 'ডায়েট প্ল্যান',
          imageUrl: p.food.hasImage ? p.food.imageUrl : null,
          accent: _slotColor(p.slot),
        );
      }).toList();
    }
    return const [
      _FeaturedItem(
        slotLabel: 'সকাল',
        title: 'ডাল-ভাত ও সবজি',
        author: 'ডায়েট প্ল্যান',
        accent: Color(0xFFFFE2C2),
      ),
      _FeaturedItem(
        slotLabel: 'দুপুর',
        title: 'রুই মাছ ও সালাদ',
        author: 'ডায়েট প্ল্যান',
        accent: Color(0xFFCBE7C5),
      ),
      _FeaturedItem(
        slotLabel: 'রাত',
        title: 'মুরগির ঝোল ও সবজি',
        author: 'ডায়েট প্ল্যান',
        accent: Color(0xFFCFD8EE),
      ),
    ];
  }

  static String _slotLabel(String slot) {
    switch (slot) {
      case 'breakfast':
        return 'সকাল';
      case 'morning_snack':
        return 'সকালের স্ন্যাক';
      case 'lunch':
        return 'দুপুর';
      case 'evening_snack':
        return 'সন্ধ্যার স্ন্যাক';
      case 'dinner':
        return 'রাত';
      default:
        return slot;
    }
  }

  static Color _slotColor(String slot) {
    switch (slot) {
      case 'breakfast':
      case 'morning_snack':
        return const Color(0xFFFFE2C2);
      case 'lunch':
        return const Color(0xFFCBE7C5);
      case 'evening_snack':
        return const Color(0xFFF5C9D2);
      case 'dinner':
        return const Color(0xFFCFD8EE);
      default:
        return const Color(0xFFE2E0DC);
    }
  }
}

class _FeaturedItem {
  final String slotLabel;
  final String title;
  final String author;
  final String? imageUrl;
  final Color accent;
  const _FeaturedItem({
    required this.slotLabel,
    required this.title,
    required this.author,
    required this.accent,
    this.imageUrl,
  });
}

class _FeaturedCard extends StatelessWidget {
  final _FeaturedItem item;
  final VoidCallback onTap;
  const _FeaturedCard({required this.item, required this.onTap});
  @override
  Widget build(BuildContext context) {
    final radius = BorderRadius.circular(20);
    return GestureDetector(
      onTap: () {
        HapticFeedback.selectionClick();
        onTap();
      },
      behavior: HitTestBehavior.opaque,
      child: SizedBox(
        width: 280,
        child: ClipRRect(
          borderRadius: radius,
          child: Stack(
            fit: StackFit.expand,
            children: [
              _imageOrGradient(item),
              const DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      Color(0x00000000),
                      Color(0xCC0F1015),
                    ],
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    _CategoryBadge(label: item.slotLabel),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          item.title,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 19,
                            fontWeight: FontWeight.w800,
                            height: 1.15,
                            letterSpacing: -0.3,
                          ),
                        ),
                        const SizedBox(height: 10),
                        _AuthorRow(name: item.author),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _imageOrGradient(_FeaturedItem item) {
    final url = item.imageUrl;
    if (url != null && url.isNotEmpty) {
      return Image.network(
        url,
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) => _gradientFill(item.accent),
        loadingBuilder: (ctx, child, prog) =>
            prog == null ? child : _gradientFill(item.accent),
      );
    }
    return _gradientFill(item.accent);
  }

  Widget _gradientFill(Color base) {
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [base, Color.lerp(base, Colors.black, 0.35)!],
        ),
      ),
    );
  }
}

class _CategoryBadge extends StatelessWidget {
  final String label;
  const _CategoryBadge({required this.label});
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: AppColors.newsAccent,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 11,
          fontWeight: FontWeight.w800,
          letterSpacing: 0.3,
        ),
      ),
    );
  }
}

class _AuthorRow extends StatelessWidget {
  final String name;
  const _AuthorRow({required this.name});
  @override
  Widget build(BuildContext context) {
    final initial = name.isNotEmpty ? name.characters.first : 'আ';
    return Row(
      children: [
        Container(
          width: 26,
          height: 26,
          decoration: BoxDecoration(
            color: AppColors.newsSurface,
            shape: BoxShape.circle,
            border: Border.all(color: Colors.white, width: 1.5),
          ),
          alignment: Alignment.center,
          child: Text(
            initial,
            style: const TextStyle(
              color: AppColors.newsInk,
              fontSize: 12,
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
        const SizedBox(width: 8),
        Flexible(
          child: Text(
            name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 13,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ],
    );
  }
}

// ──────────────────────────────── Plan list ────────────────────────────────

/// Vertical list of "trending news" rows: 84×84 thumbnail + category
/// eyebrow + headline + caption + chevron. Matches the reference design's
/// "Trending news" list.
class _PlanList extends StatelessWidget {
  final List<MealSlotPlan> plan;
  final VoidCallback onTapAll;
  const _PlanList({required this.plan, required this.onTapAll});

  @override
  Widget build(BuildContext context) {
    final items = _buildItems();
    if (items.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: AppColors.newsSurface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppColors.newsDivider),
        ),
        child: const Text(
          'আজকের পরিকল্পনা এখনো তৈরি হয়নি। প্রোফাইল সেটআপ করলে প্ল্যান দেখতে পাবেন।',
          style: TextStyle(
            color: AppColors.newsMuted,
            fontSize: 14,
          ),
        ),
      );
    }
    return Column(
      children: [
        for (var i = 0; i < items.length; i++) ...[
          _PlanRow(
            item: items[i],
            onTap: onTapAll,
          ),
          if (i != items.length - 1) const SizedBox(height: 12),
        ],
      ],
    );
  }

  List<_PlanRowItem> _buildItems() {
    if (plan.isEmpty) return const [];
    return plan.take(5).map((p) {
      final slotLabel = _slotLabel(p.slot);
      return _PlanRowItem(
        title: p.food.nameBn,
        category: slotLabel,
        caption: '${p.food.kcal.toStringAsFixed(0)} কিলোক্যালরি · '
            '${p.food.carbG.toStringAsFixed(0)} গ্রাম কার্ব',
        imageUrl: p.food.hasImage ? p.food.imageUrl : null,
        accent: _slotColor(p.slot),
      );
    }).toList();
  }

  static String _slotLabel(String slot) {
    switch (slot) {
      case 'breakfast':
        return 'সকাল · ব্রেকফাস্ট';
      case 'morning_snack':
        return 'সকালের স্ন্যাক';
      case 'lunch':
        return 'দুপুর · লাঞ্চ';
      case 'evening_snack':
        return 'সন্ধ্যার স্ন্যাক';
      case 'dinner':
        return 'রাত · ডিনার';
      default:
        return slot;
    }
  }

  static Color _slotColor(String slot) {
    switch (slot) {
      case 'breakfast':
      case 'morning_snack':
        return const Color(0xFFFFE2C2);
      case 'lunch':
        return const Color(0xFFCBE7C5);
      case 'evening_snack':
        return const Color(0xFFF5C9D2);
      case 'dinner':
        return const Color(0xFFCFD8EE);
      default:
        return const Color(0xFFE2E0DC);
    }
  }
}

class _PlanRowItem {
  final String title;
  final String category;
  final String caption;
  final String? imageUrl;
  final Color accent;
  const _PlanRowItem({
    required this.title,
    required this.category,
    required this.caption,
    required this.accent,
    this.imageUrl,
  });
}

class _PlanRow extends StatelessWidget {
  final _PlanRowItem item;
  final VoidCallback onTap;
  const _PlanRow({required this.item, required this.onTap});
  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () {
        HapticFeedback.selectionClick();
        onTap();
      },
      behavior: HitTestBehavior.opaque,
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: AppColors.newsSurface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppColors.newsDivider, width: 1),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.04),
              blurRadius: 12,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Row(
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: SizedBox(
                width: 84,
                height: 84,
                child: _thumbOrGradient(item),
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    item.category,
                    style: const TextStyle(
                      color: AppColors.newsAccent,
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0.6,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    item.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: AppColors.newsInk,
                      fontSize: 17,
                      fontWeight: FontWeight.w700,
                      height: 1.2,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    item.caption,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: AppColors.newsMuted,
                      fontSize: 13,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            const Icon(Icons.arrow_forward_ios_rounded,
                size: 14, color: AppColors.newsMuted),
          ],
        ),
      ),
    );
  }

  Widget _thumbOrGradient(_PlanRowItem item) {
    final url = item.imageUrl;
    if (url != null && url.isNotEmpty) {
      return Image.network(
        url,
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) => _gradientFill(item.accent),
        loadingBuilder: (ctx, child, prog) =>
            prog == null ? child : _gradientFill(item.accent),
      );
    }
    return _gradientFill(item.accent);
  }

  Widget _gradientFill(Color base) {
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [base, Color.lerp(base, Colors.black, 0.3)!],
        ),
      ),
    );
  }
}

'''

src = DASH.read_text(encoding='utf-8')
lines = src.splitlines(keepends=True)

# Line numbers from inspection (1-based, inclusive of 230 and 894).
# Python indices: 229..893 inclusive → 894 lines.
START = 230 - 1  # 229
END = 894        # 894 (exclusive)

# Sanity check (line 230 is the docstring immediately above DarkCard)
assert 'Local replacement' in lines[START], lines[START]
assert 'class DarkCard' in lines[START + 1], lines[START + 1]
assert lines[END - 1].strip() == '}', lines[END - 1]
# Line END+1 (Python index END) should be the 'Error state' divider
assert 'Error state' in lines[END + 1], f"Expected Error state at line {END+2}, got: {lines[END+1]!r}"

new_src = ''.join(lines[:START]) + NEW_BLOCK + ''.join(lines[END:])
DASH.write_text(new_src, encoding='utf-8')

print(f"Old size: {len(lines)} lines")
new_lines = new_src.splitlines(keepends=True)
print(f"New size: {len(new_lines)} lines")
print("Splice complete.")
