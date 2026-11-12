import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models.dart';
import '../services/malva_api_client.dart';

/// An accepted server write can update device schedules even when the following
/// refresh is offline. The publisher must still own the active screen session.
class GoalReminderMutation {
  const GoalReminderMutation.upsert(this.session, BackendGoal value)
      : goal = value,
        deletedId = null;
  const GoalReminderMutation.delete(this.session, String id)
      : goal = null,
        deletedId = id;

  final AuthSession session;
  final BackendGoal? goal;
  final String? deletedId;
}

final acceptedGoalMutationProvider =
    StateProvider<GoalReminderMutation?>((ref) => null);
