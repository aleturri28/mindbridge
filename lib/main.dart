import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app.dart';

void main() {
  // Riverpod scelto in Fase 0 come state management unico (CLAUDE.md).
  runApp(const ProviderScope(child: MindBridgeApp()));
}
