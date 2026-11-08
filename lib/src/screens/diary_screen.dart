import 'package:flutter/material.dart';
import '../models.dart';
import '../services/malva_api_client.dart';
import 'diary_history_screen.dart';
export 'diary_form_sheet.dart';

class DiaryScreen extends StatelessWidget {
  const DiaryScreen({super.key, this.session, this.apiClient});
  final AuthSession? session;
  final MalvaApiClient? apiClient;
  @override
  Widget build(BuildContext context) =>
      DiaryHistoryScreen(session: session, apiClient: apiClient);
}
