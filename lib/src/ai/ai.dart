/// AI-based mental health screening engine using Forward Chaining
/// and Certainty Factor reasoning.
///
/// This package provides a clinical decision support system for
/// PHQ-9 (depression) and GAD-7 (anxiety) screening.
///
/// Usage:
/// ```dart
/// final engine = ForwardChainingEngine();
/// final result = engine.infer(
///   questionIds: KnowledgeBase.phq9QuestionIds,
///   answers: [1, 2, 1, 0, 1, 2, 0, 0, 0],
///   rules: KnowledgeBase.phq9Rules,
/// );
/// print(result.level);      // 'mild'
/// print(result.certaintyFactor); // 0.76
/// ```
library ai;

export 'models.dart';
export 'certainty_factor.dart';
export 'knowledge_base.dart';
export 'forward_chaining_engine.dart';
