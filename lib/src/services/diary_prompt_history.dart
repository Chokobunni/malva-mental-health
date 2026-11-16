import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import '../models/diary_achievements.dart';
import '../models/diary_catalog.dart';
import '../platform/contracts/ports.dart';

/// One instance shared by home/editor; persist before presenting a new hand.
class DiaryPromptHistory extends ChangeNotifier {
  DiaryPromptHistory(this.storage, this.key);
  final SecureStore storage;
  final String key;
  DiaryPromptDeck? _deck;
  Future<void> _queue = Future.value();
  Future<List<DiaryPrompt>>? _initialLoad;
  List<DiaryPrompt> _cards = const [];
  DiaryPrompt? _selected;
  bool _disposed = false;
  List<DiaryPrompt> get cards => _cards;
  DiaryPrompt? get selected => _selected;

  Future<List<DiaryPrompt>> current() {
    if (_cards.isNotEmpty) return Future.value(_cards);
    return _initialLoad ??= draw().whenComplete(() => _initialLoad = null);
  }

  void select(DiaryPrompt prompt) {
    if (!_cards.any((p) => p.id == prompt.id)) return;
    _selected = prompt;
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }

  Future<List<DiaryPrompt>> draw() {
    final result = Completer<List<DiaryPrompt>>();
    _queue = _queue.then((_) async {
      try {
        if (_deck == null) {
          final raw = await storage.read(key);
          _deck = DiaryPromptDeck(
              state: raw == null
                  ? null
                  : Map<String, dynamic>.from(jsonDecode(raw) as Map));
        } else {
          _deck!.refresh();
        }
        await storage.write(key, jsonEncode(_deck!.toJson()));
        _cards = List.unmodifiable(_deck!.cards);
        _selected = null;
        if (!_disposed) notifyListeners();
        result.complete(_cards);
      } on Object catch (e, stack) {
        _deck = null;
        result.completeError(e, stack);
      }
    });
    return result.future;
  }
}
