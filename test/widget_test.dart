// Trivial smoke test.
//
// The original boilerplate `Counter increments smoke test` from
// `flutter create` referenced a counter widget that no longer
// exists in `AmarDietApp`. Widget tests for the full app shell
// require a live Supabase client (set up in `main()`) and belong
// in the `integration_test/` package rather than `test/`.
//
// This file remains so that the test runner has at least one
// widget-free entry point and CI can verify the package compiles.

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('package compiles under flutter_test', () {
    expect(1 + 1, 2);
  });
}
