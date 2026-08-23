/// AI সহকারী — professional, GPT/Claude/Gemini-style chat for
/// diabetic users.
///
/// Design highlights:
///   * Sidebar (drawer) lists every past conversation, grouped by
///     "আজ / গতকাল / গত ৭ দিন / আগের". "নতুন চ্যাট" button at the
///     top; long-press or trash icon to delete a chat.
///   * Markdown-ish rendering for assistant answers: **bold**, `code`,
///     bulleted/numbered lists, fenced code blocks. Leaked
///     `<think>…</think>` blocks are stripped before display.
///   * Streaming assistant bubbles fill chunk-by-chunk. Typing dots
///     show during the pre-flight (safety + context) and during the
///     first token delay.
///   * Per-message metadata row: time, model name, copy button.
///   * Quota pill ("৩/৫ আজ") in the app bar; disabled state when 0/5.
///   * Bangla-first, large type, generous tap targets for older users.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

import '../services/ai_chat_quota_cache.dart';
import '../services/ai_chat_service.dart';
import '../services/app_events.dart';
import '../services/env.dart';
import '../services/groq_router.dart';
import '../services/supabase_service.dart';
import '../theme/app_theme.dart';

class AiChatScreen extends StatefulWidget {
  const AiChatScreen({super.key});

  @override
  State<AiChatScreen> createState() => _AiChatScreenState();
}

class _AiChatScreenState extends State<AiChatScreen> {
  final TextEditingController _input = TextEditingController();
  final ScrollController _scroll = ScrollController();
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();
  final List<_ChatBubble> _bubbles = [];
  final FocusNode _focus = FocusNode();
  AiChatQuota _quota = AiChatQuotaCache.instance.value;
  bool _busy = false;
  bool _configMissing = false;
  CancelToken? _inflight;
  String? _activeThreadId;
  String? _activeThreadTitle;
  List<AiChatThreadRow> _threads = const [];
  // When the user scrolls up during a streaming reply we stop
  // auto-scrolling so they can actually read the older content. We
  // re-arm the auto-follow the moment they scroll back to (or near)
  // the bottom.
  bool _followTail = true;
  static const double _followTailSlack = 48; // px from the bottom still counts as "at tail"
  bool _loadingThreads = false;

  /// Cached copy of the most recent user prompt. Used by the retry
  /// chip on error bubbles so the user doesn't have to retype when the
  /// AI never answered. Refund is already applied server-side, so the
  /// retry doesn't burn a fresh quota slot.
  String _lastUserPrompt = '';

  @override
  void initState() {
    super.initState();
    _configMissing = !Env.hasGroqKey;
    _quota = AiChatQuotaCache.instance.value;
    AiChatQuotaCache.instance.addListener(_onQuotaChanged);
    AppEvents.aiChatQuotaChanged.addListener(_onEventTick);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _refreshQuota();
      _refreshThreads();
    });
    _input.addListener(() => setState(() {}));
    _scroll.addListener(_onScrollChanged);
    // Initialise tail-following state after first layout.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _onScrollChanged();
    });
  }

  @override
  void dispose() {
    AiChatQuotaCache.instance.removeListener(_onQuotaChanged);
    AppEvents.aiChatQuotaChanged.removeListener(_onEventTick);
    _inflight?.cancel();
    _disposeAllBubbles();
    _input.dispose();
    _scroll.removeListener(_onScrollChanged);
    _scroll.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _onQuotaChanged() {
    if (!mounted) return;
    setState(() => _quota = AiChatQuotaCache.instance.value);
  }

  void _onEventTick() {
    if (!mounted) return;
    _refreshQuota();
  }

  Future<void> _refreshQuota() async {
    try {
      final q = await AiChatService.warmUp();
      if (mounted) setState(() => _quota = q);
    } catch (_) {/* silent */}
  }

  Future<void> _refreshThreads() async {
    setState(() => _loadingThreads = true);
    try {
      final list = await AiChatService.listThreads();
      if (!mounted) return;
      setState(() => _threads = list);
    } catch (_) {
      // silent
    } finally {
      if (mounted) setState(() => _loadingThreads = false);
    }
  }

  // ------------------------------------------------------------------
  // Send / stream
  // ------------------------------------------------------------------

  Future<void> _send(String text) async {
    final trimmed = text.trim();
    if (trimmed.isEmpty || _busy) return;
    if (_quota.isExhausted) {
      _toast('আজকের ৫টি প্রশ্ন শেষ। কাল সকাল ৬টায় আবার নতুন ৫টি পাবেন।');
      return;
    }

    HapticFeedback.lightImpact();
    _lastUserPrompt = trimmed;

    setState(() {
      _busy = true;
      _bubbles.add(_ChatBubble.user(trimmed));
    });
    _input.clear();
    _scrollToEnd(forceFollowTail: true);

    final placeholder = _ChatBubble.assistant('');
    setState(() => _bubbles.add(placeholder));
    final placeholderIndex = _bubbles.length - 1;

    final cancel = CancelToken();
    _inflight = cancel;

    try {
      final result = await AiChatService.sendPrompt(
        userText: trimmed,
        threadId: _activeThreadId,
        onDelta: (delta) {
          if (!mounted) return;
          // O(1) — ValueNotifier notifies only the body widget,
          // not the entire ListView. Skip setState entirely.
          _bubbles[placeholderIndex].append(delta);
          // Only follow the tail if the user hasn't scrolled away.
          _scrollToEnd();
        },
        onRefusal: (refusal) {
          if (!mounted) return;
          _replaceBubble(placeholderIndex, _ChatBubble.assistant(refusal,
              modelId: 'safety-guard', createdAt: DateTime.now()));
        },
        cancel: cancel,
      );
      if (!mounted) return;
      _replaceBubble(
        placeholderIndex,
        _ChatBubble.assistant(
          result.fullText,
          modelId: result.modelId,
          createdAt: DateTime.now(),
        ),
      );
      if (_activeThreadId == null && result.threadId != null) {
        setState(() {
          _activeThreadId = result.threadId;
          _activeThreadTitle = _deriveTitle(trimmed);
        });
      }
    } on AiChatServiceException catch (e) {
      if (!mounted) return;
      final err = _ChatBubble.error(e.message, createdAt: DateTime.now())
        ..errorRetryPrompt = trimmed;
      _replaceBubble(placeholderIndex, err);
      _toast(e.message);
    } catch (_) {
      if (!mounted) return;
      final err = _ChatBubble.error(
        'একটি অপ্রত্যাশিত সমস্যা হয়েছে — একটু পরে আবার চেষ্টা করুন।',
        createdAt: DateTime.now(),
      )..errorRetryPrompt = trimmed;
      _replaceBubble(placeholderIndex, err);
    } finally {
      _inflight = null;
      await _refreshQuota();
      await _refreshThreads();
      if (mounted) setState(() => _busy = false);
      _scrollToEnd(forceFollowTail: true);
    }
  }

  /// Swap a bubble in-place and dispose the old ValueNotifier so we
  /// don't leak one per send. Triggers a single rebuild.
  void _replaceBubble(int index, _ChatBubble next) {
    final old = _bubbles[index];
    _bubbles[index] = next;
    old.dispose();
    if (mounted) setState(() {});
  }

  /// Dispose every bubble's ValueNotifier. Called when clearing the
  /// list (new chat, switch thread, screen dispose).
  void _disposeAllBubbles() {
    for (final b in _bubbles) {
      b.dispose();
    }
    _bubbles.clear();
  }

  /// Resend the most recent prompt without consuming a quota slot.
  /// The original _send call already refunded the slot server-side,
  /// so we just replay the cached text through the same pipeline.
  Future<void> _retryLastPrompt() async {
    if (_lastUserPrompt.isEmpty) return;
    if (_busy) return;
    // Strip the error bubble so the user sees a clean retry.
    if (_bubbles.isNotEmpty && _bubbles.last.isError) {
      _replaceBubble(_bubbles.length - 1, _ChatBubble.assistant(''));
    }
    await _send(_lastUserPrompt);
  }

  /// Stop the in-flight stream. The service layer will surface a
  /// friendly "বন্ধ করা হয়েছে" message and refund the quota slot.
  void _stopStream() {
    _inflight?.cancel();
  }

  String _deriveTitle(String raw) {
    var s = raw.replaceAll(RegExp(r'\s+'), ' ').trim();
    s = s.replaceAll(RegExp(r'[।.?!]+$'), '').trim();
    if (s.length <= 60) return s;
    return '${s.substring(0, 57)}…';
  }

  // ------------------------------------------------------------------
  // Sidebar / thread actions
  // ------------------------------------------------------------------

  Future<void> _openThread(AiChatThreadRow t) async {
    if (_activeThreadId == t.id) {
      Navigator.of(context).maybePop();
      return;
    }
    if (_busy) {
      _toast('চলমান উত্তর শেষ হলে আবার চেষ্টা করুন।');
      return;
    }
    try {
      final msgs = await AiChatService.loadThread(threadId: t.id);
      if (!mounted) return;
      _disposeAllBubbles();
      setState(() {
        _activeThreadId = t.id;
        _activeThreadTitle = t.title.isEmpty ? 'চ্যাট' : t.title;
        _bubbles.addAll(msgs.map((m) {
          if (m.role == 'user') return _ChatBubble.user(m.content);
          if (m.role == 'assistant') {
            return _ChatBubble.assistant(
              m.content,
              modelId: m.model,
              createdAt: m.createdAt,
            );
          }
          return _ChatBubble.system(m.content);
        }));
      });
      Navigator.of(context).maybePop();
      _scrollToEnd(forceFollowTail: true);
    } catch (_) {
      _toast('আগের কথোপকথন লোড করা যায়নি।');
    }
  }

  void _newChat() {
    if (_busy) {
      _toast('চলমান উত্তর শেষ হলে আবার চেষ্টা করুন।');
      return;
    }
    _disposeAllBubbles();
    setState(() {
      _activeThreadId = null;
      _activeThreadTitle = null;
    });
    Navigator.of(context).maybePop();
    _focus.requestFocus();
  }

  Future<void> _renameActiveThread() async {
    if (_activeThreadId == null) return;
    final controller = TextEditingController(text: _activeThreadTitle ?? '');
    final newTitle = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('চ্যাটের নাম বদলান'),
        content: TextField(
          controller: controller,
          autofocus: true,
          maxLength: 80,
          decoration: const InputDecoration(
            hintText: 'নাম লিখুন',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('বাতিল'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, controller.text.trim()),
            child: const Text('সেভ করুন'),
          ),
        ],
      ),
    );
    if (newTitle == null || newTitle.isEmpty) return;
    final ok = await AiChatService.renameThread(
      threadId: _activeThreadId!,
      title: newTitle,
    );
    if (!mounted) return;
    if (ok) {
      setState(() => _activeThreadTitle = newTitle);
      await _refreshThreads();
      _toast('নাম বদলানো হয়েছে।');
    } else {
      _toast('নাম বদলানো যায়নি।');
    }
  }

  Future<void> _deleteThread(AiChatThreadRow t) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('চ্যাট মুছবেন?'),
        content: Text(
          '"${t.title.isEmpty ? 'এই চ্যাট' : t.title}" মুছে যাবে। এই চ্যাটের প্রশ্নগুলোর কোটা ফেরত আসবে না।',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('বাতিল'),
          ),
          TextButton(
            style: TextButton.styleFrom(foregroundColor: AppColors.danger),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('মুছুন'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    final removed = await AiChatService.deleteThread(t.id);
    if (!mounted) return;
    if (removed) {
      if (_activeThreadId == t.id) {
        _disposeAllBubbles();
        setState(() {
          _activeThreadId = null;
          _activeThreadTitle = null;
        });
      }
      await _refreshThreads();
      _toast('চ্যাট মুছে ফেলা হয়েছে।');
    } else {
      _toast('মুছে ফেলা যায়নি।');
    }
  }

  // ------------------------------------------------------------------
  // Misc helpers
  // ------------------------------------------------------------------

  void _onScrollChanged() {
    if (!_scroll.hasClients) return;
    final pos = _scroll.position;
    final distanceFromBottom = pos.maxScrollExtent - pos.pixels;
    final shouldFollow = distanceFromBottom <= _followTailSlack;
    if (shouldFollow != _followTail) {
      // No setState — just a private flag, avoid rebuilding the world.
      _followTail = shouldFollow;
    }
  }

  /// Scroll to the bottom only when the user is still tail-following.
  /// Explicit user-triggered scrolls (new message, thread switch, stream end)
  /// force-follow via [forceFollowTail].
  void _scrollToEnd({bool forceFollowTail = false}) {
    if (forceFollowTail) _followTail = true;
    if (!_followTail) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_scroll.hasClients) return;
      _scroll.animateTo(
        _scroll.position.maxScrollExtent + 240,
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOut,
      );
    });
  }

  void _toast(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 3),
      ),
    );
  }

  void _copyToClipboard(String text) {
    Clipboard.setData(ClipboardData(text: text));
    HapticFeedback.selectionClick();
    _toast('কপি হয়েছে।');
  }

  @override
  Widget build(BuildContext context) {
    if (_configMissing) return const _NotConfiguredScreen();

    final hasActiveChat = _activeThreadId != null || _bubbles.isNotEmpty;
    return Scaffold(
      key: _scaffoldKey,
      backgroundColor: AppColors.newsCanvas,
      drawer: _HistoryDrawer(
        threads: _threads,
        loading: _loadingThreads,
        activeThreadId: _activeThreadId,
        onSelect: _openThread,
        onDelete: _deleteThread,
        onNewChat: _newChat,
        onRefresh: _refreshThreads,
      ),
      appBar: AppBar(
        backgroundColor: AppColors.newsCanvas,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0.5,
        centerTitle: false,
        titleSpacing: 4,
        leading: Builder(
          builder: (ctx) => IconButton(
            tooltip: 'চ্যাটের ইতিহাস',
            icon: const Icon(Icons.menu_rounded,
                color: AppColors.newsInk, size: 26),
            onPressed: () => Scaffold.of(ctx).openDrawer(),
          ),
        ),
        title: _AppBarTitle(
          title: _activeThreadTitle,
          onRename: hasActiveChat ? _renameActiveThread : null,
        ),
        actions: [
          const SizedBox(width: 4),
          _QuotaPill(quota: _quota),
          const SizedBox(width: 12),
        ],
      ),
      body: SafeArea(
        top: false,
        child: Column(
          children: [
            Expanded(
              child: _bubbles.isEmpty
                  ? _WelcomeSection(
                      onSuggestion: _send,
                      busy: _busy,
                    )
                  : ListView.builder(
                      controller: _scroll,
                      padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
                      itemCount: _bubbles.length,
                      itemBuilder: (ctx, i) {
                        final b = _bubbles[i];
                        final prev = i > 0 ? _bubbles[i - 1] : null;
                        final sameRoleAbove = prev?.role == b.role;
                        return _BubbleView(
                          bubble: b,
                          stackedAbove: sameRoleAbove,
                          onCopy: () => _copyToClipboard(b.currentText),
                          onRetry: _retryLastPrompt,
                        );
                      },
                    ),
            ),
            _ChatInput(
              controller: _input,
              focus: _focus,
              busy: _busy,
              disabled: _quota.isExhausted,
              onSend: _send,
              onStop: () {
                HapticFeedback.mediumImpact();
                _stopStream();
              },
            ),
          ],
        ),
      ),
    );
  }
}

// =========================================================================
//  APP BAR
// =========================================================================

class _AppBarTitle extends StatelessWidget {
  const _AppBarTitle({required this.title, this.onRename});
  final String? title;
  final VoidCallback? onRename;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onRename,
      behavior: HitTestBehavior.opaque,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: const LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [AppColors.brandPink, AppColors.brandPinkDeep],
              ),
              boxShadow: [
                BoxShadow(
                  color: AppColors.brandPink.withValues(alpha: 0.35),
                  blurRadius: 10,
                  offset: const Offset(0, 3),
                ),
              ],
            ),
            child: const Icon(
              Icons.auto_awesome_rounded,
              size: 20,
              color: Colors.white,
            ),
          ),
          const SizedBox(width: 10),
          Flexible(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'AI সহকারী',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: AppColors.newsInk,
                  ),
                ),
                const SizedBox(height: 1),
                Text(
                  onRename == null
                      ? 'ডায়াবেটিস ও স্বাস্থ্য সহায়তা'
                      : (title ?? 'নতুন চ্যাট'),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 12,
                    color: AppColors.newsMuted,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _QuotaPill extends StatelessWidget {
  const _QuotaPill({required this.quota});
  final AiChatQuota quota;

  @override
  Widget build(BuildContext context) {
    final used = quota.used;
    final limit = quota.limit;
    final remaining = (limit - used).clamp(0, limit);
    final exhausted = quota.isExhausted;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: exhausted
            ? AppColors.danger.withValues(alpha: 0.10)
            : AppColors.brandSurfaceSoft,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(
          color: exhausted
              ? AppColors.danger.withValues(alpha: 0.25)
              : AppColors.brandLine,
          width: 1,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            exhausted
                ? Icons.timer_off_outlined
                : Icons.bolt_rounded,
            size: 14,
            color: exhausted ? AppColors.danger : AppColors.brandPinkDeep,
          ),
          const SizedBox(width: 4),
          Text(
            'আজ $used/$limit',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color:
                  exhausted ? AppColors.danger : AppColors.brandPinkDeep,
            ),
          ),
          if (!exhausted) ...[
            const SizedBox(width: 4),
            Text(
              '· $remaining বাকি',
              style: const TextStyle(
                fontSize: 11,
                color: AppColors.newsMuted,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

// =========================================================================
//  HISTORY DRAWER
// =========================================================================

class _HistoryDrawer extends StatelessWidget {
  const _HistoryDrawer({
    required this.threads,
    required this.loading,
    required this.activeThreadId,
    required this.onSelect,
    required this.onDelete,
    required this.onNewChat,
    required this.onRefresh,
  });

  final List<AiChatThreadRow> threads;
  final bool loading;
  final String? activeThreadId;
  final void Function(AiChatThreadRow) onSelect;
  final void Function(AiChatThreadRow) onDelete;
  final VoidCallback onNewChat;
  final Future<void> Function() onRefresh;

  @override
  Widget build(BuildContext context) {
    final today = _Bucket.today(threads);
    final yesterday = _Bucket.yesterday(threads);
    final week = _Bucket.last7Days(threads);
    final older = _Bucket.older(threads);

    return Drawer(
      backgroundColor: AppColors.newsSurface,
      shape: const RoundedRectangleBorder(),
      width: math.min(MediaQuery.of(context).size.width * 0.86, 360),
      child: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 18, 16, 12),
              child: Row(
                children: [
                  Container(
                    width: 42,
                    height: 42,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: const LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [AppColors.brandPink, AppColors.brandMaroon],
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: AppColors.brandPink.withValues(alpha: 0.4),
                          blurRadius: 12,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    child: const Icon(
                      Icons.auto_awesome_rounded,
                      size: 22,
                      color: Colors.white,
                    ),
                  ),
                  const SizedBox(width: 12),
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'চ্যাটের ইতিহাস',
                          style: TextStyle(
                            fontSize: 17,
                            fontWeight: FontWeight.w700,
                            color: AppColors.newsInk,
                          ),
                        ),
                        Text(
                          'আপনার সব কথোপকথন এক জায়গায়',
                          style: TextStyle(
                            fontSize: 12,
                            color: AppColors.newsMuted,
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    tooltip: 'রিফ্রেশ',
                    icon: const Icon(Icons.refresh_rounded,
                        color: AppColors.newsMuted),
                    onPressed: () => onRefresh(),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
              child: SizedBox(
                height: 48,
                child: FilledButton.icon(
                  style: FilledButton.styleFrom(
                    backgroundColor: AppColors.brandPinkDeep,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                    textStyle: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  onPressed: onNewChat,
                  icon: const Icon(Icons.add_rounded, size: 22),
                  label: const Text('নতুন চ্যাট'),
                ),
              ),
            ),
            const Divider(height: 1, color: AppColors.newsDivider),
            Expanded(
              child: RefreshIndicator(
                onRefresh: onRefresh,
                child: _ThreadList(
                  loading: loading,
                  groups: [
                    ('আজ', today),
                    ('গতকাল', yesterday),
                    ('গত ৭ দিন', week),
                    ('আগের', older),
                  ],
                  activeThreadId: activeThreadId,
                  onSelect: onSelect,
                  onDelete: onDelete,
                ),
              ),
            ),
            const Divider(height: 1, color: AppColors.newsDivider),
            const Padding(
              padding: EdgeInsets.fromLTRB(16, 10, 16, 14),
              child: Row(
                children: [
                  Icon(Icons.health_and_safety_outlined,
                      size: 18, color: AppColors.newsMuted),
                  SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'গুরুতর অসুস্থতায় অবশ্যই ডাক্তারের পরামর্শ নিন।',
                      style: TextStyle(
                        fontSize: 12,
                        color: AppColors.newsMuted,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Bucket {
  _Bucket._();
  static List<AiChatThreadRow> today(List<AiChatThreadRow> all) {
    final now = DateTime.now();
    return all
        .where((t) => _sameDay(t.lastMessageAt, now))
        .toList(growable: false);
  }

  static List<AiChatThreadRow> yesterday(List<AiChatThreadRow> all) {
    final y = DateTime.now().subtract(const Duration(days: 1));
    return all
        .where((t) => _sameDay(t.lastMessageAt, y))
        .toList(growable: false);
  }

  static List<AiChatThreadRow> last7Days(List<AiChatThreadRow> all) {
    final now = DateTime.now();
    final since = DateTime(now.year, now.month, now.day)
        .subtract(const Duration(days: 7));
    return all
        .where((t) =>
            t.lastMessageAt.isAfter(since) &&
            !_sameDay(t.lastMessageAt, now) &&
            !_sameDay(t.lastMessageAt, DateTime(now.year, now.month, now.day)
                .subtract(const Duration(days: 1))))
        .toList(growable: false);
  }

  static List<AiChatThreadRow> older(List<AiChatThreadRow> all) {
    final now = DateTime.now();
    final cutoff = DateTime(now.year, now.month, now.day)
        .subtract(const Duration(days: 7));
    return all
        .where((t) =>
            t.lastMessageAt.isBefore(cutoff) ||
            (t.lastMessageAt.year < now.year - 1))
        .toList(growable: false);
  }

  static bool _sameDay(DateTime a, DateTime b) {
    return a.year == b.year && a.month == b.month && a.day == b.day;
  }
}

class _ThreadList extends StatelessWidget {
  const _ThreadList({
    required this.loading,
    required this.groups,
    required this.activeThreadId,
    required this.onSelect,
    required this.onDelete,
  });
  final bool loading;
  final List<(String, List<AiChatThreadRow>)> groups;
  final String? activeThreadId;
  final void Function(AiChatThreadRow) onSelect;
  final void Function(AiChatThreadRow) onDelete;

  @override
  Widget build(BuildContext context) {
    if (loading && groups.every((g) => g.$2.isEmpty)) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
      );
    }
    if (groups.every((g) => g.$2.isEmpty)) {
      return ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        children: const [
          SizedBox(height: 80),
          _EmptyThreads(),
        ],
      );
    }
    final children = <Widget>[];
    for (final (label, rows) in groups) {
      if (rows.isEmpty) continue;
      children.add(_ThreadGroup(
        label: label,
        rows: rows,
        activeThreadId: activeThreadId,
        onSelect: onSelect,
        onDelete: onDelete,
      ));
    }
    return ListView(
      padding: const EdgeInsets.symmetric(vertical: 6),
      children: children,
    );
  }
}

class _ThreadGroup extends StatelessWidget {
  const _ThreadGroup({
    required this.label,
    required this.rows,
    required this.activeThreadId,
    required this.onSelect,
    required this.onDelete,
  });
  final String label;
  final List<AiChatThreadRow> rows;
  final String? activeThreadId;
  final void Function(AiChatThreadRow) onSelect;
  final void Function(AiChatThreadRow) onDelete;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
          child: Text(
            label,
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.3,
              color: AppColors.newsMuted,
            ),
          ),
        ),
        for (final r in rows)
          _ThreadTile(
            thread: r,
            isActive: r.id == activeThreadId,
            onSelect: () => onSelect(r),
            onDelete: () => onDelete(r),
          ),
      ],
    );
  }
}

class _ThreadTile extends StatelessWidget {
  const _ThreadTile({
    required this.thread,
    required this.isActive,
    required this.onSelect,
    required this.onDelete,
  });
  final AiChatThreadRow thread;
  final bool isActive;
  final VoidCallback onSelect;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final preview = thread.preview.isEmpty
        ? '—'
        : thread.preview.replaceAll(RegExp(r'\s+'), ' ').trim();
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 2, 12, 2),
      child: Material(
        color: isActive ? AppColors.brandSurfaceSoft : Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
        child: InkWell(
          onTap: onSelect,
          onLongPress: onDelete,
          borderRadius: BorderRadius.circular(12),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(10, 10, 4, 10),
            child: Row(
              children: [
                Icon(
                  isActive
                      ? Icons.chat_bubble_rounded
                      : Icons.chat_bubble_outline_rounded,
                  size: 18,
                  color: isActive
                      ? AppColors.brandPinkDeep
                      : AppColors.newsMuted,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        thread.title.isEmpty ? 'নতুন চ্যাট' : thread.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 14.5,
                          fontWeight: FontWeight.w600,
                          color: AppColors.newsInk,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        preview,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 12,
                          color: AppColors.newsMuted,
                        ),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  tooltip: 'মুছুন',
                  icon: const Icon(Icons.delete_outline_rounded,
                      size: 18, color: AppColors.newsMuted),
                  onPressed: onDelete,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _EmptyThreads extends StatelessWidget {
  const _EmptyThreads();
  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 28),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 72,
              height: 72,
              decoration: BoxDecoration(
                color: AppColors.brandSurfaceSoft,
                shape: BoxShape.circle,
                border: Border.all(color: AppColors.brandLine),
              ),
              child: const Icon(
                Icons.forum_rounded,
                size: 32,
                color: AppColors.brandPinkDeep,
              ),
            ),
            const SizedBox(height: 16),
            const Text(
              'এখনো কোনো চ্যাট নেই',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w700,
                color: AppColors.newsInk,
              ),
            ),
            const SizedBox(height: 6),
            const Text(
              'খাবার, ওষুধ, ব্যায়াম বা রক্তে শর্করা যেকোনো বিষয়ে প্রশ্ন লিখুন। প্রতিটি চ্যাট আলাদা করে এখানে জমা থাকবে।',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 13,
                height: 1.5,
                color: AppColors.newsMuted,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// =========================================================================
//  WELCOME / SUGGESTION CHIPS
// =========================================================================

class _WelcomeSection extends StatelessWidget {
  const _WelcomeSection({required this.onSuggestion, required this.busy});
  final void Function(String) onSuggestion;
  final bool busy;

  static const List<(String, String)> _defaultChips = [
    ('রাতে খালি পেটে ব্লাড সুগার কত হলে স্বাভাবিক?',
     'খালি পেটে ব্লাড সুগার কত হলে স্বাভাবিক?'),
    ('ডায়াবেটিক রোগীর জন্য ব্রেকফাস্টে কী খাওয়া ভালো?',
     'ডায়াবেটিক রোগীর জন্য ব্রেকফাস্টে কী খাওয়া ভালো?'),
    ('৩০ মিনিটের হালকা ব্যায়ামের পরামর্শ দিন।',
     '৩০ মিনিটের হালকা ব্যায়ামের পরামর্শ দিন।'),
    ('মেটফরমিন সেবনের সঠিক সময় কখন?',
     'মেটফরমিন সেবনের সঠিক সময় কখন?'),
  ];

  @override
  Widget build(BuildContext context) {
    const chips = AiChatService.suggestionChips;
    final displayChips = chips.isNotEmpty
        ? chips
            .map((c) => (
                  c.length > 60 ? '${c.substring(0, 57)}…' : c,
                  c,
                ))
            .toList()
        : _defaultChips;
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 24, 20, 24),
      physics: const AlwaysScrollableScrollPhysics(),
      children: [
        const SizedBox(height: 24),
        // Hero avatar with gradient ring + soft shadow
        Center(
          child: Container(
            width: 72,
            height: 72,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: const LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [AppColors.brandPink, AppColors.brandMaroon],
              ),
              boxShadow: [
                BoxShadow(
                  color: AppColors.brandPink.withValues(alpha: 0.35),
                  blurRadius: 24,
                  spreadRadius: 2,
                  offset: const Offset(0, 8),
                ),
              ],
            ),
            child: const Icon(
              Icons.auto_awesome_rounded,
              color: Colors.white,
              size: 34,
            ),
          ),
        ),
        const SizedBox(height: 22),
        const Text(
          'আপন সুস্থতা AI',
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 28,
            fontWeight: FontWeight.w800,
            color: AppColors.newsInk,
            height: 1.15,
            letterSpacing: -0.2,
          ),
        ),
        const SizedBox(height: 8),
        const Text(
          'আপনার ব্যক্তিগত ডায়াবেটিস সহকারী।',
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 15,
            height: 1.45,
            color: AppColors.newsMuted,
          ),
        ),
        const SizedBox(height: 28),
        const _SectionLabel('আজকের জন্য প্রস্তাবিত'),
        const SizedBox(height: 12),
        // 2-column grid of suggestion cards
        LayoutBuilder(
          builder: (ctx, c) {
            const cols = 2;
            const gap = 10.0;
            final width =
                (c.maxWidth - gap * (cols - 1)) / cols;
            return Wrap(
              spacing: gap,
              runSpacing: gap,
              children: [
                for (final (label, value) in displayChips)
                  SizedBox(
                    width: width,
                    child: _SuggestionCard(
                      label: label,
                      onTap: busy ? null : () => onSuggestion(value),
                    ),
                  ),
              ],
            );
          },
        ),
        const SizedBox(height: 28),
        const _CapabilityStrip(),
        const SizedBox(height: 24),
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: AppColors.newsSurfaceSoft,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: AppColors.newsDivider),
          ),
          child: const Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.shield_moon_outlined,
                  size: 18, color: AppColors.brandPinkDeep),
              SizedBox(width: 10),
              Expanded(
                child: Text(
                  'আমি সাধারণ স্বাস্থ্য পরামর্শ দিই, জরুরি বা গুরুতর অসুস্থতার জন্য সবসময় আপনার ডাক্তার বা হেলথকেয়ার টিমের সাথে যোগাযোগ করুন।',
                  style: TextStyle(
                    fontSize: 13,
                    height: 1.45,
                    color: AppColors.newsInk,
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _CapabilityStrip extends StatelessWidget {
  const _CapabilityStrip();
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: AppColors.brandSurfaceSoft,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.brandLine),
      ),
      child: Row(
        children: [
          const Icon(Icons.restaurant_rounded,
              size: 18, color: AppColors.brandPinkDeep),
          const SizedBox(width: 8),
          const Expanded(
            child: Text(
              'খাবার',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: AppColors.newsInk,
              ),
            ),
          ),
          Container(width: 1, height: 18, color: AppColors.brandLine),
          const SizedBox(width: 8),
          const Icon(Icons.medical_services_rounded,
              size: 18, color: AppColors.brandPinkDeep),
          const SizedBox(width: 8),
          const Expanded(
            child: Text(
              'ওষুধ',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: AppColors.newsInk,
              ),
            ),
          ),
          Container(width: 1, height: 18, color: AppColors.brandLine),
          const SizedBox(width: 8),
          const Icon(Icons.fitness_center_rounded,
              size: 18, color: AppColors.brandPinkDeep),
          const SizedBox(width: 8),
          const Expanded(
            child: Text(
              'ব্যায়াম',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: AppColors.newsInk,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.text);
  final String text;
  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: const TextStyle(
        fontSize: 12,
        fontWeight: FontWeight.w700,
        letterSpacing: 0.4,
        color: AppColors.newsMuted,
      ),
    );
  }
}

class _SuggestionCard extends StatelessWidget {
  const _SuggestionCard({required this.label, required this.onTap});
  final String label;
  final VoidCallback? onTap;
  @override
  Widget build(BuildContext context) {
    final disabled = onTap == null;
    return Material(
      color: AppColors.newsSurface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: const BorderSide(
          color: AppColors.newsDivider,
        ),
      ),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 12, 10, 12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Icon(Icons.bolt_rounded,
                  size: 16, color: AppColors.brandPinkDeep),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  label,
                  style: TextStyle(
                    fontSize: 13.5,
                    height: 1.35,
                    fontWeight: FontWeight.w500,
                    color: disabled
                        ? AppColors.newsMuted
                        : AppColors.newsInk,
                  ),
                ),
              ),
              const Padding(
                padding: EdgeInsets.only(top: 2),
                child: Icon(Icons.arrow_outward_rounded,
                    size: 14, color: AppColors.newsMuted),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// =========================================================================
//  BUBBLES & RICH BODY
// =========================================================================

enum _BubbleRole { user, assistant, system, error }

class _ChatBubble {
  _ChatBubble({
    required this.role,
    required String text,
    this.modelId,
    this.createdAt,
  }) : text = ValueNotifier<String>(text);

  factory _ChatBubble.user(String t, {DateTime? t2}) =>
      _ChatBubble(role: _BubbleRole.user, text: t, createdAt: t2);
  factory _ChatBubble.assistant(String t,
          {String? modelId, DateTime? createdAt}) =>
      _ChatBubble(
        role: _BubbleRole.assistant,
        text: t,
        modelId: modelId,
        createdAt: createdAt,
      );
  factory _ChatBubble.system(String t) =>
      _ChatBubble(role: _BubbleRole.system, text: t);
  factory _ChatBubble.error(String t, {DateTime? createdAt}) =>
      _ChatBubble(
        role: _BubbleRole.error,
        text: t,
        createdAt: createdAt,
      );

  final _BubbleRole role;

  /// Streamed text lives on a ValueNotifier so per-chunk deltas are
  /// O(1) string concatenation + a single ValueListenableBuilder rebuild
  /// for the *body*, not the whole list. The modelId / createdAt /
  /// errorRetry fields are immutable once the bubble is sealed.
  final ValueNotifier<String> text;
  final String? modelId;
  final DateTime? createdAt;

  /// If this is an error bubble, the controller's retry action will
  /// resend the most recent user prompt without consuming a quota slot.
  String? errorRetryPrompt;

  /// True while the assistant bubble is still receiving chunks.
  bool get isStreaming =>
      role == _BubbleRole.assistant && (modelId == null);

  String get currentText => text.value;
  set currentText(String v) => text.value = v;

  bool get isAssistant => role == _BubbleRole.assistant;
  bool get isUser => role == _BubbleRole.user;
  bool get isError => role == _BubbleRole.error;

  /// Append a streamed delta. No rebuild happens here — the bubble's
  /// ValueListenableBuilder re-runs on `text.notifyListeners`.
  void append(String delta) {
    if (role != _BubbleRole.assistant) return;
    text.value = text.value + delta;
  }

  /// Replace the text wholesale — used after sanitisation and to swap
  /// an assistant bubble into its final sealed state (model + time).
  void seal(String finalText, {String? modelId}) {
    text.value = finalText;
    // ignore: invalid_use_of_protected_member
    (text as dynamic);
  }

  void dispose() {
    text.dispose();
  }
}

class _BubbleView extends StatelessWidget {
  const _BubbleView({
    required this.bubble,
    required this.stackedAbove,
    required this.onCopy,
    required this.onRetry,
  });
  final _ChatBubble bubble;
  final bool stackedAbove;
  final VoidCallback onCopy;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    switch (bubble.role) {
      case _BubbleRole.user:
        return _UserBubble(text: bubble.currentText, onCopy: onCopy);
      case _BubbleRole.assistant:
        return _AssistantBubble(
          textNotifier: bubble.text,
          modelId: bubble.modelId,
          createdAt: bubble.createdAt,
          stackedAbove: stackedAbove,
          onCopy: onCopy,
          isStreaming: bubble.isStreaming,
        );
      case _BubbleRole.error:
        return _ErrorBubble(
          text: bubble.currentText,
          onRetry: bubble.errorRetryPrompt == null ? null : onRetry,
        );
      case _BubbleRole.system:
        return _SystemBubble(text: bubble.currentText);
    }
  }
}

class _UserBubble extends StatelessWidget {
  const _UserBubble({required this.text, required this.onCopy});
  final String text;
  final VoidCallback onCopy;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8, top: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          ConstrainedBox(
            constraints: BoxConstraints(
              maxWidth: MediaQuery.of(context).size.width * 0.78,
            ),
            child: Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [AppColors.brandPink, AppColors.brandPinkDeep],
                ),
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(18),
                  topRight: Radius.circular(18),
                  bottomLeft: Radius.circular(18),
                  bottomRight: Radius.circular(6),
                ),
                boxShadow: [
                  BoxShadow(
                    color: AppColors.brandPink.withValues(alpha: 0.25),
                    blurRadius: 12,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: SelectableText(
                text,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                  height: 1.4,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _AssistantBubble extends StatelessWidget {
  const _AssistantBubble({
    required this.textNotifier,
    required this.modelId,
    required this.createdAt,
    required this.stackedAbove,
    required this.onCopy,
    required this.isStreaming,
  });
  final ValueNotifier<String> textNotifier;
  final String? modelId;
  final DateTime? createdAt;
  final bool stackedAbove;
  final VoidCallback onCopy;
  final bool isStreaming;

  @override
  Widget build(BuildContext context) {
    final showAvatar = !stackedAbove;
    return Padding(
      padding: const EdgeInsets.only(bottom: 12, top: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _AvatarBubble(visible: showAvatar),
          const SizedBox(width: 8),
          Flexible(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (showAvatar)
                  const Padding(
                    padding: EdgeInsets.only(left: 4, bottom: 6),
                    child: Text(
                      'AI সহকারী',
                      style: TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w700,
                        color: AppColors.newsMuted,
                      ),
                    ),
                  ),
                // Streaming body. ValueListenableBuilder limits rebuilds
                // to this subtree — no churn in the surrounding
                // ListView.builder, no AnimatedList rebuild, no
                // re-running the markdown parser for the whole chat.
                ValueListenableBuilder<String>(
                  valueListenable: textNotifier,
                  builder: (ctx, text, _) {
                    return Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 12),
                      decoration: BoxDecoration(
                        color: AppColors.newsSurfaceSoft,
                        borderRadius: const BorderRadius.only(
                          topLeft: Radius.circular(18),
                          topRight: Radius.circular(18),
                          bottomLeft: Radius.circular(6),
                          bottomRight: Radius.circular(18),
                        ),
                        border: Border.all(color: AppColors.newsDivider),
                      ),
                      child: text.isEmpty
                          ? const _ThinkingBubble()
                          : SelectableText.rich(
                              TextSpan(children: [
                                const WidgetSpan(child: SizedBox.shrink()),
                                ..._parseBlocks(text),
                              ]),
                              style: const TextStyle(
                                color: AppColors.newsInk,
                                fontSize: 16,
                                height: 1.5,
                              ),
                            ),
                    );
                  },
                ),
                _MetaText(
                  time: createdAt,
                  modelId: modelId,
                  onCopy: onCopy,
                  visible: !isStreaming,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ErrorBubble extends StatelessWidget {
  const _ErrorBubble({required this.text, this.onRetry});
  final String text;
  final VoidCallback? onRetry;
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: AppColors.danger.withValues(alpha: 0.12),
              border: Border.all(
                color: AppColors.danger.withValues(alpha: 0.3),
              ),
            ),
            child: const Icon(Icons.error_outline_rounded,
                size: 18, color: AppColors.danger),
          ),
          const SizedBox(width: 10),
          Flexible(
            child: Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              decoration: BoxDecoration(
                color: AppColors.danger.withValues(alpha: 0.08),
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(18),
                  topRight: Radius.circular(18),
                  bottomLeft: Radius.circular(6),
                  bottomRight: Radius.circular(18),
                ),
                border: Border.all(
                  color: AppColors.danger.withValues(alpha: 0.25),
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    text,
                    style: const TextStyle(
                      color: AppColors.newsInk,
                      fontSize: 14.5,
                      height: 1.4,
                    ),
                  ),
                  if (onRetry != null) ...[
                    const SizedBox(height: 10),
                    Material(
                      color: AppColors.danger.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(999),
                      child: InkWell(
                        onTap: onRetry,
                        borderRadius: BorderRadius.circular(999),
                        child: const Padding(
                          padding: EdgeInsets.symmetric(
                              horizontal: 14, vertical: 8),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.refresh_rounded,
                                  size: 16, color: AppColors.danger),
                              SizedBox(width: 6),
                              Text(
                                'আবার চেষ্টা করুন',
                                style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w700,
                                  color: AppColors.danger,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SystemBubble extends StatelessWidget {
  const _SystemBubble({required this.text});
  final String text;
  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 24),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: AppColors.newsSurfaceSoft,
            borderRadius: BorderRadius.circular(999),
            border: Border.all(color: AppColors.newsDivider),
          ),
          child: Text(
            text,
            style: const TextStyle(
              fontSize: 12,
              color: AppColors.newsMuted,
            ),
          ),
        ),
      ),
    );
  }
}

class _AvatarBubble extends StatelessWidget {
  const _AvatarBubble({required this.visible});
  final bool visible;
  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 36,
      height: 36,
      child: visible
          ? Container(
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: const LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [AppColors.brandPink, AppColors.brandMaroon],
                ),
                boxShadow: [
                  BoxShadow(
                    color: AppColors.brandPink.withValues(alpha: 0.3),
                    blurRadius: 10,
                    offset: const Offset(0, 3),
                  ),
                ],
              ),
              child: const Icon(
                Icons.auto_awesome_rounded,
                color: Colors.white,
                size: 18,
              ),
            )
          : const SizedBox.shrink(),
    );
  }
}

class _TypingDots extends StatefulWidget {
  const _TypingDots();
  @override
  State<_TypingDots> createState() => _TypingDotsState();
}

class _TypingDotsState extends State<_TypingDots>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c =
      AnimationController(vsync: this, duration: const Duration(seconds: 1))
        ..repeat();
  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: List.generate(3, (i) {
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 2),
          child: AnimatedBuilder(
            animation: _c,
            builder: (ctx, _) {
              final dy = math.sin((_c.value * 6.283) + (i * 2.1)) * 3 + 3;
              return Container(
                width: 7,
                height: 7,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: AppColors.newsMuted.withValues(alpha: 0.85),
                ),
                margin: EdgeInsets.only(bottom: dy),
              );
            },
          ),
        );
      }),
    );
  }
}

/// A progressive "thinking" indicator that starts with the bouncing dots
/// and escalates to a Bangla status line after a long wait. This gives
/// the user real feedback during slow generations (large 120B model,
/// busy Groq cluster, full context payload) instead of leaving them
/// staring at three dots.
class _ThinkingBubble extends StatefulWidget {
  const _ThinkingBubble();
  @override
  State<_ThinkingBubble> createState() => _ThinkingBubbleState();
}

class _ThinkingBubbleState extends State<_ThinkingBubble> {
  // After this many ms with no first-token, swap dots for a hint.
  static const _hintAfterMs = 12000;
  // And swap the hint for a stronger "still going…" message.
  static const _deepHintAfterMs = 30000;

  Timer? _hintTimer;
  Timer? _deepHintTimer;
  bool _showHint = false;
  bool _showDeepHint = false;

  @override
  void initState() {
    super.initState();
    _hintTimer = Timer(const Duration(milliseconds: _hintAfterMs), () {
      if (!mounted) return;
      setState(() => _showHint = true);
    });
    _deepHintTimer = Timer(const Duration(milliseconds: _deepHintAfterMs), () {
      if (!mounted) return;
      setState(() => _showDeepHint = true);
    });
  }

  @override
  void dispose() {
    _hintTimer?.cancel();
    _deepHintTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_showDeepHint) {
      return const Text(
        'এখনও ভাবছি… বড় প্রশ্ন, একটু অপেক্ষা করুন।',
        style: TextStyle(
          color: AppColors.newsMuted,
          fontSize: 14,
          height: 1.4,
        ),
      );
    }
    if (_showHint) {
      return const Text(
        'ভাবছি… একটু সময় লাগছে।',
        style: TextStyle(
          color: AppColors.newsMuted,
          fontSize: 14,
          height: 1.4,
        ),
      );
    }
    return const _TypingDots();
  }
}

class _MetaText extends StatelessWidget {
  const _MetaText({
    required this.time,
    required this.modelId,
    required this.onCopy,
    required this.visible,
  });
  final DateTime? time;
  final String? modelId;
  final VoidCallback onCopy;
  final bool visible;

  @override
  Widget build(BuildContext context) {
    if (!visible) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 4, left: 4),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (time != null)
            Text(
              _formatTime(time!),
              style: const TextStyle(
                fontSize: 11,
                color: AppColors.newsMuted,
              ),
            ),
          if (modelId != null && modelId!.isNotEmpty) ...[
            const SizedBox(width: 6),
            Text(
              '· ${_prettyModel(modelId!)}',
              style: const TextStyle(
                fontSize: 11,
                color: AppColors.newsMuted,
              ),
            ),
          ],
          const SizedBox(width: 6),
          _IconAction(
            icon: Icons.copy_rounded,
            tooltip: 'কপি',
            onTap: onCopy,
          ),
        ],
      ),
    );
  }
}

class _IconAction extends StatelessWidget {
  const _IconAction({
    required this.icon,
    required this.tooltip,
    required this.onTap,
  });
  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: onTap,
        customBorder: const CircleBorder(),
        child: Padding(
          padding: const EdgeInsets.all(4),
          child: Icon(icon, size: 16, color: AppColors.newsMuted),
        ),
      ),
    );
  }
}

// =========================================================================
//  MARKDOWN-ISH PARSER
// =========================================================================

List<InlineSpan> _parseBlocks(String raw) {
  final clean = raw
      .replaceAll('<think>', '\n<think>\n')
      .replaceAll('</think>', '\n</think>\n');
  final lines = const LineSplitter().convert(clean);
  final out = <InlineSpan>[];
  bool inThink = false;
  final buf = StringBuffer();
  final list = <_Block>[];

  void flush() {
    if (buf.isEmpty) return;
    list.add(_Block.paragraph(buf.toString().trimRight()));
    buf.clear();
  }

  for (final rawLine in lines) {
    final line = rawLine.trimRight();
    if (line == '<think>') {
      flush();
      inThink = true;
      continue;
    }
    if (line == '</think>') {
      inThink = false;
      continue;
    }
    if (inThink) continue;
    if (line.trim().isEmpty) {
      flush();
      list.add(_Block.spacer());
      continue;
    }
    final h = RegExp(r'^(#{1,6})\s+(.*)$').firstMatch(line);
    if (h != null) {
      flush();
      list.add(_Block.heading(
        h.group(2)!,
        level: h.group(1)!.length,
      ));
      continue;
    }
    final cb = RegExp(r'^```(.*)?$').firstMatch(line);
    if (cb != null) {
      flush();
      list.add(_Block.codeFence(cb.group(1) ?? ''));
      continue;
    }
    final ol = RegExp(r'^\s*(\d+)[.)]\s+(.*)$').firstMatch(line);
    if (ol != null) {
      flush();
      list.add(_Block.ordered(ol.group(1)!, ol.group(2)!));
      continue;
    }
    final ul = RegExp(r'^[-•*]\s+(.*)$').firstMatch(line);
    if (ul != null) {
      flush();
      list.add(_Block.bullet(ul.group(1)!));
      continue;
    }
    final quote = RegExp(r'^>\s?(.*)$').firstMatch(line);
    if (quote != null) {
      flush();
      list.add(_Block.quote(quote.group(1)!));
      continue;
    }
    buf.writeln(line);
  }
  flush();

  for (final b in list) {
    switch (b.kind) {
      case _BlockKind.spacer:
        out.add(const TextSpan(text: '\n\n'));
        break;
      case _BlockKind.paragraph:
        out.addAll(_inline(b.text));
        out.add(const TextSpan(text: '\n\n'));
        break;
      case _BlockKind.heading:
        out.add(_headingSpan(b, b.level));
        out.add(const TextSpan(text: '\n\n'));
        break;
      case _BlockKind.bullet:
        out.addAll(_inline('• ${b.text}'));
        out.add(const TextSpan(text: '\n'));
        break;
      case _BlockKind.ordered:
        out.addAll(_inline('${b.marker}. ${b.text}'));
        out.add(const TextSpan(text: '\n'));
        break;
      case _BlockKind.codeFence:
        out.add(_codeFenceSpan(b.text));
        out.add(const TextSpan(text: '\n\n'));
        break;
      case _BlockKind.quote:
        out.add(_quoteSpan(b.text));
        out.add(const TextSpan(text: '\n\n'));
        break;
    }
  }
  return out;
}

enum _BlockKind {
  paragraph,
  heading,
  bullet,
  ordered,
  codeFence,
  quote,
  spacer,
}

class _Block {
  _Block._(this.kind, {this.text = '', this.level = 1, this.marker = ''});
  factory _Block.paragraph(String t) => _Block._(_BlockKind.paragraph, text: t);
  factory _Block.heading(String t, {required int level}) =>
      _Block._(_BlockKind.heading, text: t, level: level);
  factory _Block.bullet(String t) => _Block._(_BlockKind.bullet, text: t);
  factory _Block.ordered(String n, String t) =>
      _Block._(_BlockKind.ordered, text: t, marker: n);
  factory _Block.codeFence(String t) =>
      _Block._(_BlockKind.codeFence, text: t);
  factory _Block.quote(String t) => _Block._(_BlockKind.quote, text: t);
  factory _Block.spacer() => _Block._(_BlockKind.spacer);
  final _BlockKind kind;
  final String text;
  final int level;
  final String marker;
}

TextSpan _headingSpan(_Block b, int level) {
  final size = switch (level) {
    1 => 19.0,
    2 => 17.5,
    _ => 16.0,
  };
  return TextSpan(
    text: b.text,
    style: TextStyle(
      fontWeight: FontWeight.w800,
      fontSize: size,
      color: AppColors.newsInk,
    ),
  );
}

TextSpan _codeFenceSpan(String lang) {
  return const TextSpan(
    text: 'এখানে কোড ব্লক — অ্যাপে রান করুন',
    style: TextStyle(
      fontFamily: 'monospace',
      backgroundColor: Color(0x14000000),
    ),
  );
}

TextSpan _quoteSpan(String text) {
  return TextSpan(
    text: '“$text”',
    style: const TextStyle(
      fontStyle: FontStyle.italic,
      color: AppColors.brandPinkDeep,
    ),
  );
}

List<TextSpan> _inline(String text) {
  // Convert **bold** and `code` into styled TextSpans.
  final spans = <TextSpan>[];
  final pattern = RegExp(
      r'(\*\*[^\*]+\*\*|`[^`]+`|\*[^\*]+\*|_[^_]+_)');
  int idx = 0;
  for (final m in pattern.allMatches(text)) {
    if (m.start > idx) {
      spans.add(TextSpan(text: text.substring(idx, m.start)));
    }
    final seg = m.group(0)!;
    if (seg.startsWith('**')) {
      spans.add(TextSpan(
        text: seg.substring(2, seg.length - 2),
        style: const TextStyle(fontWeight: FontWeight.w700),
      ));
    } else if (seg.startsWith('`')) {
      spans.add(TextSpan(
        text: seg.substring(1, seg.length - 1),
        style: const TextStyle(
          fontFamily: 'monospace',
          backgroundColor: Color(0x14000000),
        ),
      ));
    } else if (seg.startsWith('*')) {
      spans.add(TextSpan(
        text: seg.substring(1, seg.length - 1),
        style: const TextStyle(fontStyle: FontStyle.italic),
      ));
    } else if (seg.startsWith('_')) {
      spans.add(TextSpan(
        text: seg.substring(1, seg.length - 1),
        style: const TextStyle(fontStyle: FontStyle.italic),
      ));
    }
    idx = m.end;
  }
  if (idx < text.length) {
    spans.add(TextSpan(text: text.substring(idx)));
  }
  return spans;
}

// =========================================================================
//  INPUT BAR + NOT-CONFIGURED SCREEN
// =========================================================================

class _ChatInput extends StatelessWidget {
  const _ChatInput({
    required this.controller,
    required this.focus,
    required this.busy,
    required this.disabled,
    required this.onSend,
    required this.onStop,
  });
  final TextEditingController controller;
  final FocusNode focus;
  final bool busy;
  final bool disabled;
  final void Function(String) onSend;
  final VoidCallback onStop;

  @override
  Widget build(BuildContext context) {
    final canSend = controller.text.trim().isNotEmpty && !busy && !disabled;
    return Container(
      padding: EdgeInsets.fromLTRB(
        12,
        10,
        12,
        10 + MediaQuery.of(context).padding.bottom,
      ),
      decoration: const BoxDecoration(
        color: AppColors.newsCanvas,
        border: Border(
          top: BorderSide(color: AppColors.newsDivider),
        ),
      ),
      child: SafeArea(
        top: false,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Expanded(
              child: Container(
                decoration: BoxDecoration(
                  color: AppColors.newsSurfaceSoft,
                  borderRadius: BorderRadius.circular(22),
                  border: Border.all(color: AppColors.newsDivider),
                ),
                child: TextField(
                  controller: controller,
                  focusNode: focus,
                  minLines: 1,
                  maxLines: 5,
                  textInputAction: busy
                      ? TextInputAction.none
                      : TextInputAction.send,
                  enabled: !disabled,
                  onSubmitted: (v) {
                    if (canSend) onSend(v);
                  },
                  decoration: InputDecoration(
                    hintText: busy
                        ? 'উত্তর ত�রি হচ্ছে…'
                        : disabled
                            ? 'আজকের কোটা শেষ।'
                            : 'আপনার প্রশ্ন লিখুন…',
                    hintStyle: const TextStyle(
                      color: AppColors.newsMuted,
                      fontSize: 15.5,
                    ),
                    border: InputBorder.none,
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 12,
                    ),
                  ),
                  style: const TextStyle(
                    fontSize: 15.5,
                    color: AppColors.newsInk,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 8),
            busy
                ? _StopButton(onTap: onStop)
                : _SendButton(
                    enabled: canSend,
                    busy: false,
                    onTap: () => onSend(controller.text),
                  ),
          ],
        ),
      ),
    );
  }
}

class _SendButton extends StatelessWidget {
  const _SendButton({
    required this.enabled,
    required this.busy,
    required this.onTap,
  });
  final bool enabled;
  final bool busy;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 48,
      height: 48,
      child: Material(
        color: enabled
            ? AppColors.brandPinkDeep
            : AppColors.brandSurfaceSoft,
        shape: const CircleBorder(),
        child: InkWell(
          onTap: enabled ? onTap : null,
          customBorder: const CircleBorder(),
          child: Center(
            child: busy
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                      strokeWidth: 2.5,
                      valueColor:
                          AlwaysStoppedAnimation<Color>(Colors.white),
                    ),
                  )
                : Icon(
                    Icons.arrow_upward_rounded,
                    size: 22,
                    color: enabled ? Colors.white : AppColors.newsMuted,
                  ),
          ),
        ),
      ),
    );
  }
}

class _StopButton extends StatelessWidget {
  const _StopButton({required this.onTap});
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 48,
      height: 48,
      child: Material(
        color: AppColors.brandPinkDeep,
        shape: const CircleBorder(),
        child: InkWell(
          onTap: onTap,
          customBorder: const CircleBorder(),
          child: const Center(
            child: Icon(
              Icons.stop_rounded,
              size: 22,
              color: Colors.white,
            ),
          ),
        ),
      ),
    );
  }
}

class _NotConfiguredScreen extends StatelessWidget {
  const _NotConfiguredScreen();
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.newsCanvas,
      appBar: AppBar(
        backgroundColor: AppColors.newsCanvas,
        elevation: 0,
      ),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 88,
                height: 88,
                decoration: BoxDecoration(
                  color: AppColors.brandSurfaceSoft,
                  shape: BoxShape.circle,
                  border: Border.all(color: AppColors.brandLine),
                ),
                child: const Icon(
                  Icons.bolt_outlined,
                  size: 38,
                  color: AppColors.brandPinkDeep,
                ),
              ),
              const SizedBox(height: 18),
              const Text(
                'AI সহকারী এখন চালু হয়নি',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w700,
                  color: AppColors.newsInk,
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                'প্রশ্নোত্তর চালু করতে .env ফাইলে GROQ_API_KEY যোগ করুন। আপনার ডেভেলপারের সাথে যোগাযোগ করুন বা অ্যাপ সেটিংস থেকে সেট করুন।',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 14,
                  height: 1.5,
                  color: AppColors.newsMuted,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// =========================================================================
//  HELPERS
// =========================================================================

String _formatTime(DateTime t) {
  try {
    final f = DateFormat('h:mm a', 'bn');
    return f.format(t).toLowerCase();
  } catch (_) {
    return DateFormat('h:mm a').format(t).toLowerCase();
  }
}

String _prettyModel(String id) {
  final t = id.trim();
  if (t.isEmpty) return '';
  return t
      .replaceAll(RegExp(r'^groq/'), '')
      .replaceAll('-', '·')
      .replaceAll('_', '·');
}

