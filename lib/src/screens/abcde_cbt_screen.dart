import 'package:flutter/material.dart';

import '../theme.dart';
import '../widgets/malva_components.dart';

// ============================================================
// ABCDE CBT — Activating event, Beliefs, Consequences,
// Disputation, Exchange. Karya: by carepatron (atribusi).
// ============================================================

class AbcdeCbtScreen extends StatefulWidget {
  const AbcdeCbtScreen({super.key});

  @override
  State<AbcdeCbtScreen> createState() => _AbcdeCbtScreenState();
}

class _AbcdeCbtScreenState extends State<AbcdeCbtScreen> {
  final _activating = TextEditingController();
  final _beliefs = TextEditingController();
  final _physical = TextEditingController();
  final _emotional = TextEditingController();
  final _forThought = TextEditingController();
  final _againstThought = TextEditingController();
  final _newThought = TextEditingController();
  bool _saved = false;

  @override
  void dispose() {
    _activating.dispose();
    _beliefs.dispose();
    _physical.dispose();
    _emotional.dispose();
    _forThought.dispose();
    _againstThought.dispose();
    _newThought.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('ABCDE CBT'),
        backgroundColor: MalvaColors.seed,
        foregroundColor: Colors.white,
      ),
      body: ListView(
        padding: const EdgeInsets.all(18),
        children: [
          const Text(
            'by carepatron',
            style: TextStyle(color: Colors.black54, fontSize: 12),
          ),
          const SizedBox(height: 10),
          _Section(
            letter: 'A',
            title: 'Activating Event',
            child: TextField(
              controller: _activating,
              maxLines: 3,
              decoration: const InputDecoration(
                labelText: 'What was it that triggered your negative thoughts?',
              ),
            ),
          ),
          _Section(
            letter: 'B',
            title: 'Beliefs',
            child: TextField(
              controller: _beliefs,
              maxLines: 3,
              decoration: const InputDecoration(
                labelText:
                    'What were your thoughts at the time? Find the most distressing one.',
              ),
            ),
          ),
          _Section(
            letter: 'C',
            title: 'Consequences',
            child: Column(
              children: [
                TextField(
                  controller: _physical,
                  maxLines: 2,
                  decoration:
                      const InputDecoration(labelText: 'Physical Feeling.'),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: _emotional,
                  maxLines: 2,
                  decoration:
                      const InputDecoration(labelText: 'Emotional Response'),
                ),
              ],
            ),
          ),
          _Section(
            letter: 'D',
            title: 'Disputation',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TextField(
                  controller: _forThought,
                  maxLines: 2,
                  decoration: const InputDecoration(
                      labelText: 'Factual Evidence FOR my thought'),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: _againstThought,
                  maxLines: 2,
                  decoration: const InputDecoration(
                      labelText: 'Factual Evidence AGAINST my thought'),
                ),
                const SizedBox(height: 10),
                const Text(
                  'Dispute the thought. Coba jawab:',
                  style: TextStyle(fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 6),
                const Text('• How realistic is this thought?'),
                const Text(
                    '• What other ways are there of viewing this situation?'),
                const Text(
                    '• What would I say to someone I care about if they thought this?'),
                const SizedBox(height: 4),
                const Text(
                  'Unhelpful thinking styles? Catat polanya di bawah.',
                  style: TextStyle(color: Colors.black54, fontSize: 12),
                ),
              ],
            ),
          ),
          _Section(
            letter: 'E',
            title: 'Exchange old thoughts for new effective ones',
            child: TextField(
              controller: _newThought,
              maxLines: 3,
              decoration: const InputDecoration(
                labelText: 'New balanced and helpful thought:',
              ),
            ),
          ),
          const SizedBox(height: 8),
          FilledButton.icon(
            onPressed: () {
              setState(() => _saved = true);
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                    content: Text('Latihan ABCDE tersimpan. Hebat!')),
              );
            },
            icon: const Icon(Icons.save_rounded),
            label: const Text('Save'),
          ),
          if (_saved) ...[
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: MalvaColors.mint.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(14),
              ),
              child: const Text(
                'Pikiran barumu tersimpan. Ulangi latihan ini saat pikiran negatif muncul lagi.',
                style: TextStyle(fontWeight: FontWeight.w700),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _Section extends StatelessWidget {
  const _Section({
    required this.letter,
    required this.title,
    required this.child,
  });

  final String letter;
  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: SoftCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                CircleAvatar(
                  backgroundColor: MalvaColors.seed.withValues(alpha: 0.12),
                  child: Text(
                    letter,
                    style: const TextStyle(
                      color: MalvaColors.seed,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    title,
                    style: const TextStyle(
                        fontWeight: FontWeight.w900, fontSize: 16),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            child,
          ],
        ),
      ),
    );
  }
}
