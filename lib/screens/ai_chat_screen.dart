/// আপন AI — professional, high-fidelity chat assistant for diabetic users.
library;

import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../services/ai_chat_quota_cache.dart';
import '../services/ai_chat_service.dart';
import '../services/ai_tools/groq_tool_call.dart';
import '../services/ai_tools/pending_actions_store.dart';
import '../services/ai_tools/tool_executor.dart';
import '../services/app_events.dart';
import '../services/env.dart';
import '../services/groq_router.dart';
import '../services/supabase_service.dart';
import '../theme/app_theme.dart';
import '../widgets/mono_widgets.dart';
import '../widgets/tab_history_mixin.dart';
import '../widgets/pending_action_card.dart';

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
  bool _followTail = true;
  static const double _followTailSlack = 48;
  bool _loadingThreads = false;
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
    } catch (_) {}
  }

  Future<void> _refreshThreads() async {
    setState(() => _loadingThreads = true);
    try {
      final list = await AiChatService.listThreads();
      if (!mounted) return;
      setState(() => _threads = list);
    } catch (_) {
    } finally {
      if (mounted) setState(() => _loadingThreads = false);
    }
  }

  Future<void> _send(String text) async {
    final trimmed = text.trim();
    if (trimmed.isEmpty || _busy) return;
    if (_quota.isExhausted) {
      _toast('আজকের ১০টি প্রশ্ন শেষ। কাল আবার নতুন ১০টি পাবেন।');
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
      String? capturedThreadId;
      String? capturedAssistantId;
      AiChatToolResult? captured;
      final result = await AiChatService.sendPromptWithTools(
        userText: trimmed,
        threadId: _activeThreadId,
        onDelta: (delta) {
          if (!mounted) return;
          _bubbles[placeholderIndex].append(delta);
          _scrollToEnd();
        },
        onPendingAction: (action) {
          if (!mounted) return;
          capturedThreadId ??= captured?.threadId ?? _activeThreadId;
          capturedAssistantId ??= captured?.assistantMessageId;
          setState(() {
            final cur = _bubbles[placeholderIndex];
            cur.pendingCallIds = [...cur.pendingCallIds, action.call.id];
            cur.threadId = capturedThreadId;
            cur.assistantMessageId = capturedAssistantId;
          });
          _scrollToEnd();
        },
        cancel: cancel,
      );
      captured = result;

      if (!mounted) return;

      if (result.pendingActions.isEmpty) {
        _replaceBubble(
          placeholderIndex,
          _ChatBubble.assistant(
            result.fullText,
            modelId: result.modelId,
            createdAt: DateTime.now(),
          ),
        );
      } else {
        final summary = await _awaitActionsThenStreamSummary(
          bubbleIndex: placeholderIndex,
          threadId: result.threadId,
          assistantMessageId: result.assistantMessageId,
          onDelta: (d) {
            if (!mounted) return;
            _bubbles[placeholderIndex].append(d);
            _scrollToEnd();
          },
          cancel: cancel,
        );
        if (!mounted) return;
        if (summary == null || summary.isEmpty) {
          _bubbles[placeholderIndex].modelId = result.modelId;
        } else {
          _bubbles[placeholderIndex].append('\n\n$summary');
          _bubbles[placeholderIndex].modelId = result.modelId;
        }
      }

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

  void _replaceBubble(int index, _ChatBubble next) {
    final old = _bubbles[index];
    _bubbles[index] = next;
    old.dispose();
    if (mounted) setState(() {});
  }

  Future<String?> _awaitActionsThenStreamSummary({
    required int bubbleIndex,
    required String? threadId,
    required String? assistantMessageId,
    required void Function(String delta) onDelta,
    required CancelToken cancel,
  }) async {
    final pendingCallIds = _bubbles[bubbleIndex].pendingCallIds;
    if (pendingCallIds.isEmpty) return null;

    while (mounted) {
      final map = PendingActionsStore.instance.actions.value;
      final allResolved = pendingCallIds.every((id) {
        final a = map[id];
        if (a == null) return true;
        return a.status != PendingActionStatus.awaiting &&
            a.status != PendingActionStatus.executing;
      });
      if (allResolved) break;
      await Future.delayed(const Duration(milliseconds: 250));
    }
    if (!mounted) return null;

    final resolvedByCallId = <String, ToolExecution>{};
    for (final id in pendingCallIds) {
      final action = PendingActionsStore.instance.actions.value[id];
      if (action == null) continue;
      resolvedByCallId[id] = ToolExecution(
        toolName: action.toolName,
        description: action.description,
        requiresConfirmation: true,
        toolArgs: action.toolArgs,
        inverseArgs: action.inverseArgs,
        auditId: action.auditId,
        errorMessage: action.status == PendingActionStatus.failed ||
                action.status == PendingActionStatus.cancelled
            ? 'user_${action.status.name}'
            : null,
      );
    }

    final toolCalls = <GroqToolCall>[
      for (final id in pendingCallIds)
        if (PendingActionsStore.instance.actions.value[id] != null)
          PendingActionsStore.instance.actions.value[id]!.call,
    ];
    if (toolCalls.isEmpty) return null;

    return resumeFinalSummary(
      round1Messages: const [],
      round1Text: _bubbles[bubbleIndex].currentText,
      round1ToolCalls: toolCalls,
      resolvedByCallId: resolvedByCallId,
      onDelta: onDelta,
      cancel: cancel,
      threadId: threadId,
    );
  }

  void _disposeAllBubbles() {
    for (final b in _bubbles) {
      b.dispose();
    }
    _bubbles.clear();
  }

  Future<void> _retryLastPrompt() async {
    if (_lastUserPrompt.isEmpty || _busy) return;
    if (_bubbles.isNotEmpty && _bubbles.last.isError) {
      _replaceBubble(_bubbles.length - 1, _ChatBubble.assistant(''));
    }
    await _send(_lastUserPrompt);
  }

  void _stopStream() {
    _inflight?.cancel();
  }

  String _deriveTitle(String raw) {
    var s = raw.replaceAll(RegExp(r'\s+'), ' ').trim();
    s = s.replaceAll(RegExp(r'[।.?!]+$'), '').trim();
    if (s.length <= 30) return s;
    return '${s.substring(0, 27)}…';
  }

  Future<void> _openThread(AiChatThreadRow t) async {
    if (_activeThreadId == t.id) {
      Scaffold.of(context).closeDrawer();
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
            return _ChatBubble.assistant(m.content, modelId: m.model, createdAt: m.createdAt);
          }
          return _ChatBubble.system(m.content);
        }));
      });
      Scaffold.of(context).closeDrawer();
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
    Scaffold.of(context).closeDrawer();
    _focus.requestFocus();
  }

  Future<void> _deleteThread(AiChatThreadRow t) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('চ্যাট মুছবেন?'),
        content: Text('"${t.title.isEmpty ? 'এই চ্যাট' : t.title}" মুছে যাবে।'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('বাতিল')),
          TextButton(style: TextButton.styleFrom(foregroundColor: AppColors.danger), onPressed: () => Navigator.pop(ctx, true), child: const Text('মুছুন')),
        ],
      ),
    );
    if (ok != true) return;
    final removed = await AiChatService.deleteThread(t.id);
    if (!mounted) return;
    if (removed) {
      if (_activeThreadId == t.id) {
        _disposeAllBubbles();
        setState(() { _activeThreadId = null; _activeThreadTitle = null; });
      }
      await _refreshThreads();
    }
  }

  void _onScrollChanged() {
    if (!_scroll.hasClients) return;
    final pos = _scroll.position;
    final distanceFromBottom = pos.maxScrollExtent - pos.pixels;
    _followTail = distanceFromBottom <= _followTailSlack;
  }

  void _scrollToEnd({bool forceFollowTail = false}) {
    if (forceFollowTail) _followTail = true;
    if (!_followTail) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_scroll.hasClients) return;
      _scroll.animateTo(_scroll.position.maxScrollExtent + 240, duration: const Duration(milliseconds: 220), curve: Curves.easeOut);
    });
  }

  void _handleBack() {
    if (Navigator.canPop(context)) {
      Navigator.pop(context);
    } else {
      TabHistory.maybePop();
    }
  }

  void _toast(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg), behavior: SnackBarBehavior.floating));
  }

  void _copyToClipboard(String text) {
    Clipboard.setData(ClipboardData(text: text));
    HapticFeedback.selectionClick();
    _toast('কপি হয়েছে।');
  }

  @override
  Widget build(BuildContext context) {
    if (_configMissing) return const _NotConfiguredScreen();

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        _handleBack();
      },
      child: Scaffold(
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
        body: Column(
          children: [
            Expanded(
              child: RefreshIndicator(
                onRefresh: () async { await _refreshQuota(); await _refreshThreads(); },
                color: AppColors.svcHero,
                child: CustomScrollView(
                  controller: _scroll,
                  physics: const AlwaysScrollableScrollPhysics(parent: BouncingScrollPhysics()),
                  slivers: [
                    _HeroSection(
                      activeThreadTitle: _activeThreadTitle,
                      quota: _quota,
                      onBack: _handleBack,
                      onHistory: () => _scaffoldKey.currentState?.openDrawer(),
                    ),
                    if (_bubbles.isEmpty)
                      SliverToBoxAdapter(child: _WelcomeSection(onSuggestion: _send, busy: _busy))
                    else
                      SliverPadding(
                        padding: const EdgeInsets.fromLTRB(16, 20, 16, 20),
                        sliver: SliverList.builder(
                          itemCount: _bubbles.length,
                          itemBuilder: (ctx, i) => _BubbleView(
                            bubble: _bubbles[i],
                            stackedAbove: i > 0 && _bubbles[i - 1].role == _bubbles[i].role,
                            onCopy: () => _copyToClipboard(_bubbles[i].currentText),
                            onRetry: _retryLastPrompt,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
            _ChatInput(
              controller: _input,
              focus: _focus,
              busy: _busy,
              disabled: _quota.isExhausted,
              onSend: _send,
              onStop: _stopStream,
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────
//  Components
// ─────────────────────────────────────────────────────────────────────────

class _HeroSection extends StatelessWidget {
  final String? activeThreadTitle;
  final AiChatQuota quota;
  final VoidCallback onBack;
  final VoidCallback onHistory;

  const _HeroSection({required this.activeThreadTitle, required this.quota, required this.onBack, required this.onHistory});

  @override
  Widget build(BuildContext context) {
    const url = 'https://aqfcmliaszqjikuszdlp.supabase.co/storage/v1/object/sign/app/photo-1564352969906-8b7f46ba4b8b.avif?token=eyJraWQiOiJhZGNmMmVjMC03YTE1LTQ0OTUtODQ1MC1mZDMwNDllYzMwMWYiLCJhbGciOiJIUzI1NiJ9.eyJ1cmwiOiJhcHAvcGhvdG8tMTU2NDM1Mjk2OTkwNi04YjdmNDZiYTRiOGIuYXZpZiIsInNjb3BlIjoiZG93bmxvYWQiLCJpYXQiOjE3ODc4Njg2MjksImV4cCI6MTgxOTQwNDYyOX0.Jdl-6cqT6wHh_nv8j-7oD3zjU2KcoR4e5ohJVnZgTNs';
    final hasActiveChat = activeThreadTitle != null;

    return SliverToBoxAdapter(
      child: Container(
        decoration: BoxDecoration(
          color: AppColors.svcHero,
          image: const DecorationImage(image: NetworkImage(url), fit: BoxFit.cover, opacity: 0.7),
        ),
        child: Stack(
          children: [
            Positioned.fill(child: Container(color: Colors.black.withValues(alpha: 0.4))),
            Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SafeArea(
                  bottom: false,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(14, 10, 20, 0),
                    child: Row(
                      children: [
                        IconButton(
                          icon: const Icon(Icons.arrow_back_ios_new_rounded, color: Colors.white, size: 20),
                          onPressed: onBack,
                        ),
                        Expanded(
                          child: Text(
                            hasActiveChat ? activeThreadTitle! : 'আপন AI',
                            style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w900, letterSpacing: -0.5),
                            maxLines: 1, overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        IconButton(
                          icon: const Icon(Icons.menu_open_rounded, color: Colors.white, size: 24),
                          onPressed: onHistory,
                        ),
                        _QuotaPill(quota: quota),
                      ],
                    ),
                  ),
                ),
                if (!hasActiveChat)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(24, 40, 24, 48),
                    child: Column(
                      children: [
                        Center(
                          child: Container(
                            width: 80, height: 80,
                            decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.15), borderRadius: BorderRadius.zero, border: Border.all(color: Colors.white30, width: 1.5)),
                            child: const Icon(Icons.auto_awesome_rounded, color: Colors.white, size: 40),
                          ),
                        ),
                        const SizedBox(height: 24),
                        const Text('আপন AI', textAlign: TextAlign.center, style: TextStyle(color: Colors.white, fontSize: 32, fontWeight: FontWeight.w900, letterSpacing: -1)),
                        const Text('আপনার ব্যক্তিগত ডায়াবেটিস সহকারী।', textAlign: TextAlign.center, style: TextStyle(color: Colors.white70, fontSize: 15, fontWeight: FontWeight.w700)),
                      ],
                    ),
                  )
                else
                  const SizedBox(height: 20),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _QuotaPill extends StatelessWidget {
  const _QuotaPill({required this.quota});
  final AiChatQuota quota;

  @override
  Widget build(BuildContext context) {
    final exhausted = quota.isExhausted;
    final color = exhausted ? AppColors.rose : AppColors.svcHeroAccent;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.15),
        borderRadius: BorderRadius.zero,
        border: Border.all(color: Colors.white24),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(exhausted ? Icons.timer_off_outlined : Icons.bolt_rounded, size: 14, color: color),
          const SizedBox(width: 4),
          Text('${quota.used}/${quota.limit}', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w900, color: color)),
        ],
      ),
    );
  }
}

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
    return Drawer(
      backgroundColor: AppColors.newsSurface,
      shape: const RoundedRectangleBorder(),
      width: math.min(MediaQuery.of(context).size.width * 0.85, 320),
      child: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(20),
              child: Row(
                children: [
                  Container(
                    width: 40, height: 40,
                    decoration: BoxDecoration(color: AppColors.svcHero, borderRadius: BorderRadius.zero),
                    child: const Icon(Icons.history_rounded, color: Colors.white, size: 20),
                  ),
                  const SizedBox(width: 12),
                  const Expanded(child: Text('চ্যাটের ইতিহাস', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900))),
                  IconButton(icon: const Icon(Icons.refresh_rounded, size: 20), onPressed: onRefresh),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: MonoButton(
                label: 'নতুন চ্যাট',
                leading: Icons.add_rounded,
                onPressed: onNewChat,
              ),
            ),
            const SizedBox(height: 10),
            const Divider(),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.symmetric(vertical: 10),
                children: [
                  for (final t in threads)
                    ListTile(
                      leading: Icon(Icons.chat_bubble_outline_rounded, size: 18, color: t.id == activeThreadId ? AppColors.svcHero : AppColors.smoke),
                      title: Text(t.title.isEmpty ? 'নতুন চ্যাট' : t.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 14, fontWeight: t.id == activeThreadId ? FontWeight.w900 : FontWeight.w700)),
                      selected: t.id == activeThreadId,
                      onTap: () => onSelect(t),
                      trailing: IconButton(icon: const Icon(Icons.delete_outline_rounded, size: 18), onPressed: () => onDelete(t)),
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

class _WelcomeSection extends StatelessWidget {
  const _WelcomeSection({required this.onSuggestion, required this.busy});
  final void Function(String) onSuggestion;
  final bool busy;

  static const List<(String, String)> _defaultChips = [
    ('আজকের ডায়েট চার্ট', 'আজকের জন্য আমার একটি পূর্ণাঙ্গ ডায়েট চার্ট তৈরি করে দিন।'),
    ('সুগার বাড়লে করণীয়', 'রক্তে শর্করা বা ব্লাড সুগার হঠাৎ বেড়ে গেলে দ্রুত কমানোর উপায় কী?'),
    ('সেরা ব্যায়াম কোনটি?', 'ডায়াবেটিস রোগীদের জন্য সবচেয়ে কার্যকর ও নিরাপদ ব্যায়াম কোনটি?'),
    ('ওষুধের সঠিক নিয়ম', 'ডায়াবেটিসের ওষুধ বা ইনসুলিন ব্যবহারের সঠিক সময় ও নিয়ম কী?'),
    ('HbA1c কমানোর উপায়', 'কিভাবে দ্রুত এবং প্রাকৃতিক উপায়ে HbA1c লেভেল নিয়ন্ত্রণে আনা সম্ভব?'),
    ('বেশি তৃষ্ণা পাওয়া কি খারাপ?', 'বারবার তৃষ্ণা পাওয়া এবং মুখ শুকিয়ে আসা কি গুরুতর ডায়াবেটিসের লক্ষণ?'),
  ];

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('আজকের জন্য প্রস্তাবিত', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w900, color: AppColors.smoke, letterSpacing: 0.5)),
          const SizedBox(height: 16),
          GridView.count(
            crossAxisCount: 2,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            mainAxisSpacing: 12,
            crossAxisSpacing: 12,
            childAspectRatio: 2.2, // Adjusted to balance low height and text wrapping
            children: [
              for (final chip in _defaultChips)
                _SuggestionCard(label: chip.$1, onTap: busy ? null : () => onSuggestion(chip.$2)),
            ],
          ),
        ],
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
    return Pressable(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.zero, border: Border.all(color: AppColors.line, width: 1.5)),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.bolt_rounded, size: 14, color: AppColors.svcHero),
            const SizedBox(height: 4),
            Expanded(
              child: Text(
                label,
                style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w800, height: 1.2),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ChatInput extends StatelessWidget {
  const _ChatInput({required this.controller, required this.focus, required this.busy, required this.disabled, required this.onSend, required this.onStop});
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
      // The host AppShellScaffold uses extendBody=false, so it already
      // reserves space for the floating AnimatedNotchBottomBar that
      // HomeShell mounts as its bottomBar. We only need to respect
      // the system bottom safe-area inset (gesture nav bar etc.).
      // Previously this added a magic +92 to "clear" the bar, which
      // doubled up with the scaffold's own reservation and left a
      // tall blank gap below the input on every screen.
      padding: EdgeInsets.fromLTRB(
        16,
        12,
        16,
        12 + MediaQuery.of(context).padding.bottom,
      ),
      decoration: const BoxDecoration(color: Colors.white, border: Border(top: BorderSide(color: AppColors.line))),
      child: Row(
        children: [
          Expanded(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              decoration: BoxDecoration(color: AppColors.surfaceHigh, borderRadius: BorderRadius.zero, border: Border.all(color: AppColors.line, width: 1.2)),
              child: TextField(
                controller: controller, focusNode: focus, maxLines: 5, minLines: 1,
                decoration: InputDecoration(hintText: busy ? 'উত্তর তৈরি হচ্ছে...' : 'আপনার প্রশ্ন লিখুন...', border: InputBorder.none, hintStyle: const TextStyle(fontWeight: FontWeight.w700, color: AppColors.smoke)),
                onSubmitted: (v) { if (canSend) onSend(v); },
              ),
            ),
          ),
          const SizedBox(width: 12),
          GestureDetector(
            onTap: busy ? onStop : (canSend ? () => onSend(controller.text) : null),
            child: Container(
              width: 52, height: 52,
              decoration: BoxDecoration(color: busy || canSend ? AppColors.svcHero : AppColors.surfaceHigh, borderRadius: BorderRadius.zero),
              child: Icon(busy ? Icons.stop_rounded : Icons.arrow_upward_rounded, color: Colors.white),
            ),
          ),
        ],
      ),
    );
  }
}

class _BubbleView extends StatelessWidget {
  const _BubbleView({required this.bubble, required this.stackedAbove, required this.onCopy, required this.onRetry});
  final _ChatBubble bubble;
  final bool stackedAbove;
  final VoidCallback onCopy;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    if (bubble.role == _BubbleRole.user) return _UserBubble(text: bubble.currentText);
    if (bubble.role == _BubbleRole.assistant) {
      return _AssistantColumn(bubble: bubble);
    }
    if (bubble.role == _BubbleRole.error) return _ErrorBubble(text: bubble.currentText, onRetry: onRetry);
    return const SizedBox.shrink();
  }
}

class _AssistantColumn extends StatelessWidget {
  const _AssistantColumn({required this.bubble});
  final _ChatBubble bubble;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _AssistantBubble(textNotifier: bubble.text, isStreaming: bubble.isStreaming),
        for (final callId in bubble.pendingCallIds)
          PendingActionCard(
            callId: callId,
            threadId: bubble.threadId,
            assistantMessageId: bubble.assistantMessageId,
          ),
      ],
    );
  }
}

class _UserBubble extends StatelessWidget {
  final String text;
  const _UserBubble({required this.text});
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Align(
        alignment: Alignment.centerRight,
        child: Container(
          padding: const EdgeInsets.all(16),
          constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.8),
          decoration: const BoxDecoration(color: AppColors.svcHero, borderRadius: BorderRadius.zero),
          child: Text(text, style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w700)),
        ),
      ),
    );
  }
}

class _AssistantBubble extends StatelessWidget {
  final ValueNotifier<String> textNotifier;
  final bool isStreaming;
  const _AssistantBubble({required this.textNotifier, required this.isStreaming});
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(width: 32, height: 32, decoration: const BoxDecoration(color: AppColors.svcHero, borderRadius: BorderRadius.zero), child: const Icon(Icons.auto_awesome_rounded, color: Colors.white, size: 16)),
          const SizedBox(width: 12),
          Flexible(
            child: ValueListenableBuilder<String>(
              valueListenable: textNotifier,
              builder: (context, text, _) => Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.zero, border: Border.all(color: AppColors.line, width: 1.2)),
                child: text.isEmpty ? const _TypingDots() : Text(text, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700, height: 1.4)),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ErrorBubble extends StatelessWidget {
  final String text;
  final VoidCallback onRetry;
  const _ErrorBubble({required this.text, required this.onRetry});
  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: AppColors.rose.withValues(alpha: 0.1), border: Border.all(color: AppColors.rose), borderRadius: BorderRadius.zero),
      child: Column(
        children: [
          Text(text, style: const TextStyle(color: AppColors.rose, fontWeight: FontWeight.bold)),
          TextButton(onPressed: onRetry, child: const Text('আবার চেষ্টা করুন')),
        ],
      ),
    );
  }
}

class _TypingDots extends StatefulWidget {
  const _TypingDots();
  @override
  State<_TypingDots> createState() => _TypingDotsState();
}

class _TypingDotsState extends State<_TypingDots> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: const Duration(seconds: 1))..repeat();
  @override
  void dispose() { _c.dispose(); super.dispose(); }
  @override
  Widget build(BuildContext context) {
    return Row(mainAxisSize: MainAxisSize.min, children: List.generate(3, (i) => Padding(padding: const EdgeInsets.symmetric(horizontal: 2), child: AnimatedBuilder(animation: _c, builder: (ctx, _) { final dy = math.sin((_c.value * 6.283) + (i * 2.1)) * 3 + 3; return Container(width: 6, height: 6, decoration: const BoxDecoration(shape: BoxShape.circle, color: AppColors.smoke), margin: EdgeInsets.only(bottom: dy)); }))));
  }
}

class _NotConfiguredScreen extends StatelessWidget {
  const _NotConfiguredScreen();
  @override
  Widget build(BuildContext context) {
    return const Scaffold(body: Center(child: Text('AI Key missing')));
  }
}

enum _BubbleRole { user, assistant, system, error }

class _ChatBubble {
  final _BubbleRole role;
  final ValueNotifier<String> text;
  String? modelId;
  final DateTime? createdAt;
  String? errorRetryPrompt;

  List<String> pendingCallIds = const [];
  String? threadId;
  String? assistantMessageId;

  _ChatBubble({required this.role, required String text, this.modelId, this.createdAt}) : text = ValueNotifier<String>(text);

  factory _ChatBubble.user(String t) => _ChatBubble(role: _BubbleRole.user, text: t);
  factory _ChatBubble.assistant(String t, {String? modelId, DateTime? createdAt}) => _ChatBubble(role: _BubbleRole.assistant, text: t, modelId: modelId, createdAt: createdAt);
  factory _ChatBubble.system(String t) => _ChatBubble(role: _BubbleRole.system, text: t);
  factory _ChatBubble.error(String t, {DateTime? createdAt}) => _ChatBubble(role: _BubbleRole.error, text: t, createdAt: createdAt);

  bool get isStreaming => role == _BubbleRole.assistant && modelId == null;
  String get currentText => text.value;
  bool get isAssistant => role == _BubbleRole.assistant;
  bool get isError => role == _BubbleRole.error;

  void append(String delta) { if (role == _BubbleRole.assistant) text.value += delta; }

  void dispose() {
    for (final id in pendingCallIds) {
      final a = PendingActionsStore.instance.actions.value[id];
      if (a == null) continue;
      if (a.status == PendingActionStatus.succeeded) continue;
      PendingActionsStore.instance.remove(id);
    }
    text.dispose();
  }
}
