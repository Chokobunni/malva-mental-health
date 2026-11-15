import 'dart:async';
import 'dart:convert';
import '../models/diary_achievements.dart';
import '../models/diary_catalog.dart';
import '../platform/contracts/ports.dart';

/// One instance shared by home/editor; persist before presenting a new hand.
class DiaryPromptHistory {
  DiaryPromptHistory(this.storage, this.key);
  final SecureStore storage;
  final String key;
  DiaryPromptDeck? _deck;
  Future<void> _queue = Future.value();

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
        result.complete(List.unmodifiable(_deck!.cards));
      } on Object catch (e, stack) {
        _deck = null;
        result.completeError(e, stack);
      }
    });
    return result.future;
  }
}
