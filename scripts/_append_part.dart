// Helper script: writes a single Dart source fragment to a target file.
// Created at scripts/_append_part.dart and run via:
//   dart run scripts/_append_part.dart <part-name>
//
// Each part is a self-contained chunk that, when concatenated in order
// (a..h), forms the new lib/screens/analytics_screen.dart body after the
// header. This avoids the inline-here-string corruption that happens when
// PowerShell tries to parse multi-line Dart code in a one-shot command.
//
// Run order: a b c d e f g h
//
// This file is temporary scaffolding — delete it after the rebuild.
library;

import 'dart:io';

void main(List<String> args) {
  if (args.isEmpty) {
    stderr.writeln('Usage: dart run scripts/_append_part.dart <part>');
    exit(1);
  }
  // No-op placeholder; the actual content lives inline in shell commands
  // because dart cannot easily embed non-ASCII content reliably here.
  stdout.writeln('part: ${args[0]} (placeholder)');
}
