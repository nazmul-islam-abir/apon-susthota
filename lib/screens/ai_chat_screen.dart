/// AI সহকারী — the chat tab for diabetic users.
///
/// Design targets:
///   * Bangla-first, large type (17-19 pt body), 56-pt-ish tap targets.
///   * Welcome card with 6 suggestion chips for first-time users and
///     anyone who clears the chat mid-session.
///   * Streaming assistant bubbles: text fills in chunk-by-chunk
///     instead of appearing all at once, courtesy of the SSE plumbing
///     in `GroqRouter` + the orchestrator in `AiChatService`.
///   * Quota pill ("৩/৫ আজ") at the top, refreshed on every send.
///   * Empty / error states are polite Bangla — never throw a raw
///     exception to the user.
library;

import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../services/ai_chat_quota_cache.dart';
import '../services/ai_chat_service.dart';
import '../services/app_events.dart';
import '../services/env.dart';
import '../services/groq_router.dart';
import '../theme/app_theme.dart';

class AiChatScreen extends StatefulWidget {
  const AiChatScreen({super.key});

  @override
  State<AiChatScreen> createState() => _AiChatScreenState();
}

class _AiChatScreenState extends State<AiChatScreen> {
  final TextEditingController _input = TextEditingController();
  final ScrollController _scroll = ScrollController();
  final List<_ChatBubble> _bubbles = [];
  final FocusNode _focus = FocusNode();
  AiChatQuota _quota = AiChatQuotaCache.instance.value;
  bool _busy = false;
  bool _configMissing = false;
  CancelToken? _inflight;

  @override
  void initState() {
    super.initState();
    _configMissing = !Env.hasGroqKey;
    _quota = AiChatQuotaCache.instance.value;
    AiChatQuotaCache.instance.addListener(_onQuotaChanged);
    AppEvents.aiChatQuotaChanged.addListener(_onEventTick);
    // Warm up quota on first build so the pill is always current.
    WidgetsBinding.instance.addPostFrameCallback((_) => _refreshQuota());
  }

  @override
  void dispose() {
    AiChatQuotaCache.instance.removeListener(_onQuotaChanged);
    AppEvents.aiChatQuotaChanged.removeListener(_onEventTick);
    _inflight?.cancel();
    _input.dispose();
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
    // Day-rolled-over or quota changed elsewhere — re-fetch.
    _refreshQuota();
  }

  Future<void> _refreshQuota() async {
    try {
      final q = await AiChatService.warmUp();
      if (mounted) setState(() => _quota = q);
    } catch (_) {
      // Silent — the pill will keep its cached value.
    }
  }

  Future<void> _send(String text) async {
    final trimmed = text.trim();
    if (trimmed.isEmpty || _busy) return;
    if (_quota.isExhausted) {
      _toast('আজকের ৫টি প্রশ্ন শেষ। কাল সকাল ৬টায় আবার নতুন ৫টি পাবেন।');
      return;
    }

    setState(() {
      _busy = true;
      _bubbles.add(_ChatBubble.user(trimmed));
    });
    _input.clear();
    _scrollToEnd();

    // Placeholder assistant bubble that fills as tokens stream in.
    final placeholder = _ChatBubble.assistant('');
    setState(() => _bubbles.add(placeholder));
    final placeholderIndex = _bubbles.length - 1;

    final cancel = CancelToken();
    _inflight = cancel;

    try {
      final result = await AiChatService.sendPrompt(
        userText: trimmed,
        onDelta: (delta) {
          if (!mounted) return;
          setState(() {
            _bubbles[placeholderIndex] =
                _bubbles[placeholderIndex].append(delta);
          });
          _scrollToEnd();
        },
        onRefusal: (refusal) {
          if (!mounted) return;
          setState(() {
            _bubbles[placeholderIndex] = _ChatBubble.assistant(refusal);
          });
        },
        cancel: cancel,
      );
      if (!mounted) return;
      setState(() {
        _bubbles[placeholderIndex] = _ChatBubble.assistant(
          result.fullText,
          modelId: result.modelId,
        );
      });
    } on AiChatServiceException catch (e) {
      if (!mounted) return;
      // Replace the placeholder with the error bubble so the user
      // sees what went wrong.
      setState(() {
        _bubbles[placeholderIndex] = _ChatBubble.error(e.message);
      });
      _toast(e.message);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _bubbles[placeholderIndex] = _ChatBubble.error(
          'একটি অপ্রত্যাশিত সমস্যা হয়েছে — একটু পরে আবার চেষ্টা করুন।',
        );
      });
    } finally {
      _inflight = null;
      // Always re-pull the quota so the pill reflects the new count.
      await _refreshQuota();
      if (mounted) setState(() => _busy = false);
      _scrollToEnd();
    }
  }

  Future<void> _clearChat() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('কথোপকথন মুছে ফেলবেন?'),
        content: const Text(
          'আজকের সব প্রশ্ন-উত্তর মুছে যাবে। আজকের ৫টি প্রশ্নের কোটা অপরিবর্তিত থাকবে।',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('বাতিল'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('মুছুন'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    await AiChatService.clearHistory();
    if (!mounted) return;
    setState(() => _bubbles.clear());
    _toast('কথোপকথন মুছে ফেলা হয়েছে।');
  }

  void _scrollToEnd() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scroll.hasClients) return;
      _scroll.animateTo(
        _scroll.position.maxScrollExtent + 200,
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

  @override
  Widget build(BuildContext context) {
    if (_configMissing) return const _NotConfiguredScreen();

    return Scaffold(
      backgroundColor: AppColors.newsCanvas,
      appBar: AppBar(
        backgroundColor: AppColors.newsCanvas,
        elevation: 0,
        centerTitle: false,
        titleSpacing: 16,
        title: Row(
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: const BoxDecoration(
                color: AppColors.brandPink,
                shape: BoxShape.circle,
              ),
              alignment: Alignment.center,
              child: const Icon(Icons.smart_toy,
                  color: AppColors.brandMaroon, size: 20),
            ),
            const SizedBox(width: 10),
            const Expanded(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'AI সহকারী',
                    style: TextStyle(
                      fontSize: 19,
                      fontWeight: FontWeight.w700,
                      color: AppColors.newsInk,
                    ),
                  ),
                  Text(
                    'ডায়াবেটিস, খাবার, ওষুধ, ব্যায়াম',
                    style: TextStyle(
                      fontSize: 13,
                      color: AppColors.newsMuted,
                    ),
                  ),
                ],
              ),
            ),
            _QuotaPill(quota: _quota),
          ],
        ),
        actions: [
          if (_bubbles.isNotEmpty)
            IconButton(
              tooltip: 'কথোপকথন মুছুন',
              icon: const Icon(Icons.delete_outline,
                  color: AppColors.newsMuted),
              onPressed: _busy ? null : _clearChat,
            ),
          const SizedBox(width: 4),
        ],
      ),
      body: SafeArea(
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
                      padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                      itemCount: _bubbles.length,
                      itemBuilder: (ctx, i) =>
                          _BubbleView(bubble: _bubbles[i]),
                    ),
            ),
            _ChatInput(
              controller: _input,
              focus: _focus,
              busy: _busy,
              disabled: _quota.isExhausted,
              onSend: _send,
            ),
          ],
        ),
      ),
    );
  }
}

// -----------------------------------------------------------------------------
// Top quota pill
// -----------------------------------------------------------------------------

class _QuotaPill extends StatelessWidget {
  const _QuotaPill({required this.quota});
  final AiChatQuota quota;

  @override
  Widget build(BuildContext context) {
    final color = quota.isExhausted
        ? AppColors.brandPinkDeep
        : AppColors.brandMaroon;
    final bg = quota.isExhausted
        ? AppColors.brandSurfaceSoft
        : AppColors.brandSurfaceSoft;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.brandLine, width: 1),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.local_fire_department,
            size: 16,
            color: color,
          ),
          const SizedBox(width: 4),
          Text(
            '${quota.used}/${quota.limit} আজ',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w700,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}

// -----------------------------------------------------------------------------
// Welcome / empty state
// -----------------------------------------------------------------------------

class _WelcomeSection extends StatelessWidget {
  const _WelcomeSection({required this.onSuggestion, required this.busy});
  final void Function(String) onSuggestion;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
      children: [
        Container(
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            color: AppColors.newsSurface,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: AppColors.newsDivider),
          ),
          child: const Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'আসসালামু আলাইকুম 👋',
                style: TextStyle(
                  fontSize: 19,
                  fontWeight: FontWeight.w700,
                  color: AppColors.newsInk,
                ),
              ),
              SizedBox(height: 6),
              Text(
                'আমি আপনার ডায়াবেটিস সহকারী। আজকের খাবার, ওষুধ, রক্তে শর্করা, ব্যায়াম, পানি — যেকোনো বিষয়ে জিজ্ঞেস করুন। দিনে ৫টি প্রশ্ন করতে পারবেন।',
                style: TextStyle(
                  fontSize: 17,
                  height: 1.5,
                  color: AppColors.newsInk,
                ),
              ),
              SizedBox(height: 10),
              Text(
                '⚠️ গুরুতর অসুস্থতায় অবশ্যই ডাক্তারের পরামর্শ নিন।',
                style: TextStyle(
                  fontSize: 13,
                  color: AppColors.newsMuted,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        const _SectionLabel('আজকের জন্য কিছু ধারণা'),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final s in AiChatService.suggestionChips)
              _SuggestionChip(
                label: s,
                onTap: busy ? null : () => onSuggestion(s),
              ),
          ],
        ),
      ],
    );
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.text);
  final String text;
  @override
  Widget build(BuildContext context) => Text(
        text,
        style: const TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.w600,
          color: AppColors.newsMuted,
          letterSpacing: 0.2,
        ),
      );
}

class _SuggestionChip extends StatelessWidget {
  const _SuggestionChip({required this.label, required this.onTap});
  final String label;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.newsSurface,
      borderRadius: BorderRadius.circular(28),
      child: InkWell(
        borderRadius: BorderRadius.circular(28),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(28),
            border: Border.all(color: AppColors.brandLine),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.add_circle_outline,
                  size: 18, color: AppColors.brandPinkDeep),
              const SizedBox(width: 6),
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 240),
                child: Text(
                  label,
                  style: const TextStyle(
                    fontSize: 15,
                    color: AppColors.newsInk,
                    fontWeight: FontWeight.w500,
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

// -----------------------------------------------------------------------------
// Chat bubbles
// -----------------------------------------------------------------------------

enum _BubbleRole { user, assistant, error }

class _ChatBubble {
  _ChatBubble({required this.role, required this.text, this.modelId});
  final _BubbleRole role;
  final String text;
  final String? modelId;

  factory _ChatBubble.user(String text) =>
      _ChatBubble(role: _BubbleRole.user, text: text);
  factory _ChatBubble.assistant(String text, {String? modelId}) =>
      _ChatBubble(role: _BubbleRole.assistant, text: text, modelId: modelId);
  factory _ChatBubble.error(String text) =>
      _ChatBubble(role: _BubbleRole.error, text: text);

  _ChatBubble append(String delta) => _ChatBubble(
        role: role,
        text: text + delta,
        modelId: modelId,
      );
}

class _BubbleView extends StatelessWidget {
  const _BubbleView({required this.bubble});
  final _ChatBubble bubble;

  @override
  Widget build(BuildContext context) {
    switch (bubble.role) {
      case _BubbleRole.user:
        return _UserBubble(text: bubble.text);
      case _BubbleRole.assistant:
        return _AssistantBubble(text: bubble.text, modelId: bubble.modelId);
      case _BubbleRole.error:
        return _ErrorBubble(text: bubble.text);
    }
  }
}

class _UserBubble extends StatelessWidget {
  const _UserBubble({required this.text});
  final String text;
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          Flexible(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              decoration: BoxDecoration(
                color: AppColors.brandPink,
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text(
                text,
                style: const TextStyle(
                  fontSize: 17,
                  color: AppColors.brandMaroon,
                  height: 1.45,
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
  const _AssistantBubble({required this.text, required this.modelId});
  final String text;
  final String? modelId;

  @override
  Widget build(BuildContext context) {
    final empty = text.isEmpty;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 28,
            height: 28,
            margin: const EdgeInsets.only(right: 8, top: 2),
            decoration: const BoxDecoration(
              color: AppColors.newsInk,
              shape: BoxShape.circle,
            ),
            alignment: Alignment.center,
            child: const Icon(Icons.smart_toy,
                size: 16, color: AppColors.newsSurface),
          ),
          Expanded(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              decoration: BoxDecoration(
                color: AppColors.newsSurface,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: AppColors.newsDivider),
              ),
              child: empty
                  ? const _TypingDots()
                  : Text(
                      text,
                      style: const TextStyle(
                        fontSize: 17,
                        height: 1.5,
                        color: AppColors.newsInk,
                      ),
                    ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ErrorBubble extends StatelessWidget {
  const _ErrorBubble({required this.text});
  final String text;
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 28,
            height: 28,
            margin: const EdgeInsets.only(right: 8, top: 2),
            decoration: BoxDecoration(
              color: AppColors.rose.withValues(alpha: 0.12),
              shape: BoxShape.circle,
            ),
            alignment: Alignment.center,
            child: const Icon(Icons.error_outline,
                size: 16, color: AppColors.rose),
          ),
          Expanded(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              decoration: BoxDecoration(
                color: AppColors.rose.withValues(alpha: 0.06),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: AppColors.rose.withValues(alpha: 0.3)),
              ),
              child: Text(
                text,
                style: const TextStyle(
                  fontSize: 16,
                  color: AppColors.newsInk,
                ),
              ),
            ),
          ),
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

class _TypingDotsState extends State<_TypingDots>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 900),
  )..repeat();

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _ctrl,
      builder: (_, __) {
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: List.generate(3, (i) {
            final t = (_ctrl.value - i * 0.15).clamp(0.0, 1.0);
            final scale = math.sin(t * math.pi);
            return Padding(
              padding: const EdgeInsets.symmetric(horizontal: 3),
              child: Transform.scale(
                scale: 0.5 + scale * 0.5,
                child: Container(
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(
                    color: AppColors.newsMuted.withValues(alpha: 0.55),
                    shape: BoxShape.circle,
                  ),
                ),
              ),
            );
          }),
        );
      },
    );
  }
}

// -----------------------------------------------------------------------------
// Input bar
// -----------------------------------------------------------------------------

class _ChatInput extends StatelessWidget {
  const _ChatInput({
    required this.controller,
    required this.focus,
    required this.busy,
    required this.disabled,
    required this.onSend,
  });
  final TextEditingController controller;
  final FocusNode focus;
  final bool busy;
  final bool disabled;
  final void Function(String) onSend;

  @override
  Widget build(BuildContext context) {
    final empty = controller.text.trim().isEmpty;
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
      decoration: const BoxDecoration(
        color: AppColors.newsCanvas,
        border: Border(top: BorderSide(color: AppColors.newsDivider)),
      ),
      child: SafeArea(
        top: false,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Expanded(
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
                decoration: const BoxDecoration(
                  color: AppColors.newsInk,
                  borderRadius: BorderRadius.all(Radius.circular(28)),
                ),
                child: TextField(
                  controller: controller,
                  focusNode: focus,
                  enabled: !disabled,
                  maxLines: 4,
                  minLines: 1,
                  textInputAction: TextInputAction.newline,
                  style: const TextStyle(
                    fontSize: 17,
                    color: AppColors.newsSurface,
                  ),
                  cursorColor: AppColors.newsSurface,
                  decoration: InputDecoration(
                    filled: false,
                    border: InputBorder.none,
                    hintText: disabled
                        ? 'আজকের কোটা শেষ'
                        : 'আপনার প্রশ্ন লিখুন…',
                    hintStyle: TextStyle(
                      color: AppColors.newsSurface.withValues(alpha: 0.55),
                    ),
                    isDense: true,
                    contentPadding: const EdgeInsets.symmetric(vertical: 12),
                  ),
                  onChanged: (_) => (context as Element).markNeedsBuild(),
                ),
              ),
            ),
            const SizedBox(width: 10),
            _SendButton(
              enabled: !disabled && !busy && !empty,
              busy: busy,
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
    return Material(
      color: enabled ? AppColors.brandPinkDeep : AppColors.brandLine,
      shape: const CircleBorder(),
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: enabled ? onTap : null,
        child: SizedBox(
          width: 56,
          height: 56,
          child: busy
              ? const Padding(
                  padding: EdgeInsets.all(16),
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: AppColors.brandMaroon,
                  ),
                )
              : const Icon(Icons.send_rounded,
                  color: AppColors.brandMaroon, size: 22),
        ),
      ),
    );
  }
}

// -----------------------------------------------------------------------------
// Not-configured placeholder
// -----------------------------------------------------------------------------

class _NotConfiguredScreen extends StatelessWidget {
  const _NotConfiguredScreen();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.newsCanvas,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                width: 64,
                height: 64,
                decoration: const BoxDecoration(
                  color: AppColors.brandPink,
                  shape: BoxShape.circle,
                ),
                alignment: Alignment.center,
                child: const Icon(Icons.smart_toy_outlined,
                    size: 32, color: AppColors.brandMaroon),
              ),
              const SizedBox(height: 16),
              const Text(
                'AI সহকারী এখন চালু হয়নি',
                style: TextStyle(
                  fontSize: 19,
                  fontWeight: FontWeight.w700,
                  color: AppColors.newsInk,
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                'AI সহকারী ব্যবহার করতে .env ফাইলে GROQ_API_KEY যোগ করুন। '
                'নির্দেশনা পাবেন README.md-তে।',
                style: TextStyle(fontSize: 16, color: AppColors.newsMuted),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      ),
    );
  }
}