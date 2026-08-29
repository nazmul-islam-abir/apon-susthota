/// One-off generator: emits a SQL INSERT INTO blog_posts block from
/// lib/blog/blog_articles.dart (parsed as text). Output:
/// tools/blog_seed.sql. Run with:
///   dart run tools/gen_blog_seed.dart
library;

import 'dart:io';
import 'dart:convert';

/// Escape a string for inclusion in a PostgreSQL standard-conforming
/// SQL string literal (`'…'`). Only `'` itself needs escaping (`''`).
/// Backslashes are NOT processed by standard SQL strings, so they are
/// passed through verbatim — otherwise they would corrupt JSON literals
/// that already contain escape sequences like `\"`.
String esc(String s) => s.replaceAll("'", "''");

String q(String? s) => s == null || s.isEmpty ? 'null' : "'" + esc(s) + "'";

List<Map<String, dynamic>> extractArticles(String source) {
  final articles = <Map<String, dynamic>>[];
  final startRe = RegExp(r'\bBlogArticle\(', multiLine: true);
  for (final startMatch in startRe.allMatches(source)) {
    var depth = 1;
    var i = startMatch.end;
    final startBody = i;
    while (i < source.length && depth > 0) {
      final c = source[i];
      if (c == '(') depth++;
      if (c == ')') depth--;
      i++;
    }
    if (depth != 0) continue;
    final body = source.substring(startBody, i - 1);
    final fields = <String, String>{};
    final fieldRe = RegExp(
        r"^\s*(id|titleEn|titleBn|summaryBn|dekBn|badge|dateLabel|readTimeLabel)\s*:\s*'((?:[^'\\]|\\.)*)',?\s*$",
        multiLine: true);
    for (final fm in fieldRe.allMatches(body)) {
      fields[fm.group(1)!] =
          (fm.group(2) ?? '').replaceAll(r"\'", "'").replaceAll(r'\\', r'\');
    }
    final canDo = <String>[];
    final canDoRe =
        RegExp(r"canDo:\s*\[([\s\S]*?)\],?\s*$", multiLine: true);
    final canDoMatch = canDoRe.firstMatch(body);
    if (canDoMatch != null) {
      final canDoBody = canDoMatch.group(1) ?? '';
      final itemRe = RegExp(r"'((?:[^'\\]|\\.)*)'");
      for (final im in itemRe.allMatches(canDoBody)) {
        canDo.add((im.group(1) ?? '')
            .replaceAll(r"\'", "'")
            .replaceAll(r'\\', r'\'));
      }
    }
    final sections = <Map<String, String>>[];
    final secRe = RegExp(
        r"BlogSection\(\s*heading:\s*'((?:[^'\\]|\\.)*)',\s*body:\s*'((?:[^'\\]|\\.)*)',\s*\),",
        multiLine: true);
    for (final sm in secRe.allMatches(body)) {
      sections.add({
        'heading': (sm.group(1) ?? '')
            .replaceAll(r"\'", "'")
            .replaceAll(r'\\', r'\'),
        'body': (sm.group(2) ?? '')
            .replaceAll(r"\'", "'")
            .replaceAll(r'\\', r'\'),
      });
    }
    if (fields['id'] == null) continue;
    articles.add({
      'id': fields['id']!,
      'titleEn': fields['titleEn'] ?? '',
      'titleBn': fields['titleBn'] ?? '',
      'summaryBn': fields['summaryBn'] ?? '',
      'dekBn': fields['dekBn'] ?? '',
      'badge': fields['badge'] ?? '',
      'dateLabel': fields['dateLabel'] ?? '',
      'readTimeLabel': fields['readTimeLabel'] ?? '',
      'sections': sections,
      'canDo': canDo,
    });
  }
  return articles;
}

String renderRow(int i, int total, Map<String, dynamic> a) {
  final sectionsJson = jsonEncode(a['sections']);
  final canDoJson = jsonEncode(a['canDo']);
  final isFeatured = i == 0;
  final terminator =
      i == total - 1 ? '  )\non conflict (slug) do nothing;' : '  ),';
  final parts = <String>[
    '  (',
    '    gen_random_uuid(),',
    '    ' + q(a['id'] as String) + ',',
    '    ' + q(a['titleEn'] as String) + ',',
    '    ' + q(a['titleBn'] as String) + ',',
    '    ' + q(a['summaryBn'] as String) + ',',
    '    ' + q(a['dekBn'] as String) + ',',
    '    ' + q(a['badge'] as String) + ',',
    '    ' + q(a['dateLabel'] as String) + ',',
    '    ' + q(a['readTimeLabel'] as String) + ',',
    '    true,',
    '    $isFeatured,',
    '    $i,',
    "    '" + esc(sectionsJson) + "'::jsonb,",
    "    '" + esc(canDoJson) + "'::jsonb",
    terminator,
  ];
  return parts.join('\n');
}

void main(List<String> argv) {
  final outPath = argv.isNotEmpty ? argv[0] : 'tools/blog_seed.sql';
  final sourceFile = File('lib/blog/blog_articles.dart');
  if (!sourceFile.existsSync()) {
    stderr.writeln(
        'Cannot find lib/blog/blog_articles.dart - run from project root.');
    exit(2);
  }
  final articles = extractArticles(sourceFile.readAsStringSync());
  if (articles.isEmpty) {
    stderr.writeln('No articles found - check the regex.');
    exit(3);
  }

  final buf = StringBuffer();
  buf.writeln('-- AUTO-GENERATED from lib/blog/blog_articles.dart.');
  buf.writeln('-- Regenerate with: dart run tools/gen_blog_seed.dart');
  buf.writeln('-- Total: ' + articles.length.toString() + ' rows.');
  buf.writeln('');
  buf.writeln('insert into public.blog_posts (');
  buf.writeln('  id, slug, title_en, title_bn, summary_bn, dek_bn,');
  buf.writeln('  badge, date_label, read_time_label, is_active,');
  buf.writeln('  is_featured, sort_order, sections, can_do');
  buf.writeln(') values');
  for (var i = 0; i < articles.length; i++) {
    buf.writeln(renderRow(i, articles.length, articles[i]));
  }
  buf.writeln('');

  File(outPath).writeAsStringSync(buf.toString());
  stdout.writeln('Wrote ' + outPath + ' - ' +
      articles.length.toString() +
      ' rows, ' +
      buf.length.toString() +
      ' bytes.');
}
