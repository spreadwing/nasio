import 'package:flutter/material.dart';
import '../models/chat_model.dart';
import '../services/api_service.dart';
import '../core/utils/formatters.dart';

class ChatProvider extends ChangeNotifier {
  List<ChatSessionSummary> _sessions = [];
  String? _currentSessionId;
  List<ChatMessageItem> _messages = [];
  List<ApprovalItem> _approvals = [];
  List<ActionTransactionItem> _transactions = [];

  bool _isLoading = false;
  bool _isSending = false;
  String? _error;

  List<ChatSessionSummary> get sessions => _sessions;
  String? get currentSessionId => _currentSessionId;
  List<ChatMessageItem> get messages => _messages;
  List<ApprovalItem> get approvals => _approvals;
  List<ApprovalItem> get pendingApprovals =>
      _approvals.where((a) => a.status == 'PENDING').toList();
  int get pendingApprovalsCount => pendingApprovals.length;
  List<ActionTransactionItem> get transactions => _transactions;

  bool get isLoading => _isLoading;
  bool get isSending => _isSending;
  String? get error => _error;

  Future<void> loadAll() async {
    await Future.wait([
      loadSessions(),
      loadApprovals(),
      loadTransactions(),
    ]);
  }

  Future<void> loadSessions() async {
    _isLoading = true;
    _error = null;
    notifyListeners();
    try {
      _sessions = await ApiService.instance.getChatSessions();
      if (_currentSessionId == null && _sessions.isNotEmpty) {
        _currentSessionId = _sessions.first.sessionId;
        _messages = await ApiService.instance.getChatSessionMessages(_currentSessionId!);
      } else if (_currentSessionId != null) {
        final exists = _sessions.any((s) => s.sessionId == _currentSessionId);
        if (exists) {
          _messages = await ApiService.instance.getChatSessionMessages(_currentSessionId!);
        } else {
          _currentSessionId = _sessions.isNotEmpty ? _sessions.first.sessionId : null;
          _messages = _currentSessionId != null
              ? await ApiService.instance.getChatSessionMessages(_currentSessionId!)
              : [];
        }
      }
    } catch (e) {
      _error = Formatters.formatErrorMessage(e);
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<void> selectSession(String sessionId) async {
    _currentSessionId = sessionId;
    _isLoading = true;
    _error = null;
    notifyListeners();
    try {
      _messages = await ApiService.instance.getChatSessionMessages(sessionId);
    } catch (e) {
      _error = Formatters.formatErrorMessage(e);
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  void startNewSession() {
    _currentSessionId = null;
    _messages = [];
    _error = null;
    notifyListeners();
  }

  Future<bool> deleteSession(String sessionId) async {
    try {
      final ok = await ApiService.instance.deleteChatSession(sessionId);
      if (ok) {
        _sessions.removeWhere((s) => s.sessionId == sessionId);
        if (_currentSessionId == sessionId) {
          _currentSessionId = _sessions.isNotEmpty ? _sessions.first.sessionId : null;
          _messages = _currentSessionId != null
              ? await ApiService.instance.getChatSessionMessages(_currentSessionId!)
              : [];
        }
        notifyListeners();
      }
      return ok;
    } catch (e) {
      _error = Formatters.formatErrorMessage(e);
      notifyListeners();
      return false;
    }
  }

  Future<bool> sendMessage(String content) async {
    final trimmed = content.trim();
    if (trimmed.isEmpty || _isSending) return false;

    _isSending = true;
    _error = null;

    // 乐观插入用户气泡
    final tempUserMsg = ChatMessageItem(
      id: 'temp_${DateTime.now().millisecondsSinceEpoch}',
      role: 'user',
      content: trimmed,
      createdAt: DateTime.now().millisecondsSinceEpoch / 1000.0,
    );
    _messages = [..._messages, tempUserMsg];
    notifyListeners();

    try {
      final res = await ApiService.instance.sendChatMessage(
        content: trimmed,
        sessionId: _currentSessionId,
      );
      final newSid = res['session_id']?.toString();
      if (newSid != null && newSid.isNotEmpty) {
        _currentSessionId = newSid;
      }
      final userJson = res['user_message'] as Map<String, dynamic>?;
      final assistantJson = res['assistant_message'] as Map<String, dynamic>?;

      // 替换临时消息并追加 AI 回复
      final updatedList = List<ChatMessageItem>.from(_messages);
      if (updatedList.isNotEmpty && updatedList.last.id == tempUserMsg.id && userJson != null) {
        updatedList.removeLast();
        updatedList.add(ChatMessageItem.fromJson(userJson));
      }
      if (assistantJson != null) {
        updatedList.add(ChatMessageItem.fromJson(assistantJson));
      }
      _messages = updatedList;

      // 刷新会话列表、事务与审批状态
      await Future.wait([
        _refreshSessionsListSilently(),
        loadApprovals(),
        loadTransactions(),
      ]);
      return true;
    } catch (e) {
      _error = Formatters.formatErrorMessage(e);
      return false;
    } finally {
      _isSending = false;
      notifyListeners();
    }
  }

  Future<void> _refreshSessionsListSilently() async {
    try {
      _sessions = await ApiService.instance.getChatSessions();
    } catch (_) {}
  }

  Future<void> loadApprovals() async {
    try {
      _approvals = await ApiService.instance.getApprovals();
      notifyListeners();
    } catch (_) {}
  }

  Future<bool> decideApproval({
    required String approvalId,
    required bool approved,
    String comment = '',
  }) async {
    try {
      final ok = await ApiService.instance.decideApproval(
        approvalId: approvalId,
        approved: approved,
        comment: comment,
      );
      if (ok) {
        await loadApprovals();
      }
      return ok;
    } catch (e) {
      _error = Formatters.formatErrorMessage(e);
      notifyListeners();
      return false;
    }
  }

  Future<void> loadTransactions() async {
    try {
      _transactions = await ApiService.instance.getTransactions();
      notifyListeners();
    } catch (_) {}
  }

  Future<Map<String, dynamic>> rollbackTransaction(String txId) async {
    try {
      final res = await ApiService.instance.rollbackTransaction(txId);
      await loadTransactions();
      return res;
    } catch (e) {
      return {'success': false, 'error': Formatters.formatErrorMessage(e)};
    }
  }
}
