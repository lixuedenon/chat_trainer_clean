// lib/features/chat/basic_chat_controller.dart

import 'package:flutter/foundation.dart';
import '../../core/models/character_model.dart';
import '../../core/models/conversation_model.dart';
import '../../core/models/user_model.dart';
import '../../core/utils/text_analyzer.dart';
import '../../core/utils/round_calculator.dart';
import '../../shared/services/mock_ai_service.dart';
import '../../shared/services/hive_service.dart';
import '../../shared/services/billing_service.dart';

class ChatController extends ChangeNotifier {
  final CharacterModel character;
  final UserModel initialUser;

  UserModel _currentUser;
  ConversationModel _currentConversation;
  bool _isTyping = false;
  String _statusMessage = '';
  RoundStatus _lastRoundStatus = RoundStatus.early;

  ChatController({
    required this.character,
    required UserModel currentUser,
  }) : initialUser = currentUser,
       _currentUser = currentUser,
       _currentConversation = ConversationModel.newConversation(
         userId: currentUser.id,
         characterId: character.id,
       );

  UserModel get currentUser => _currentUser;
  ConversationModel get currentConversation => _currentConversation;
  List<MessageModel> get messages => _currentConversation.messages;
  bool get isTyping => _isTyping;
  String get statusMessage => _statusMessage;

  int get actualRounds => _currentConversation.userMessageCount;
  int get effectiveRounds => TextAnalyzer.calculateEffectiveRounds(messages);
  double get averageCharsPerRound => _currentConversation.metrics.averageCharsPerRound;
  int get currentFavorability => _currentConversation.metrics.currentFavorability;
  List<FavorabilityPoint> get favorabilityHistory => _currentConversation.metrics.favorabilityHistory;

  RoundStatus get roundStatus {
    return RoundCalculator.getRoundStatus(effectiveRounds);
  }

  bool get canSendMessage => !_isTyping &&
                           _currentUser.credits > 0 &&
                           effectiveRounds < RoundCalculator.MAX_ROUNDS;

  bool get canEndConversation => messages.length >= 10;

  Future<void> sendMessage(String content) async {
    if (!canSendMessage) {
      throw Exception('当前无法发送消息');
    }

    try {
      if (content.length > 50) {
        throw Exception('消息长度不能超过50字');
      }

      _currentUser = await BillingService.consumeCredits(_currentUser, 1);

      final userMessage = MessageModel(
        id: 'msg_${DateTime.now().millisecondsSinceEpoch}',
        content: content,
        isUser: true,
        timestamp: DateTime.now(),
        characterCount: content.length,
        densityCoefficient: TextAnalyzer.calculateDensityCoefficient(content.length),
      );

      _currentConversation = _currentConversation.addMessage(userMessage);

      _isTyping = true;
      _updateStatusMessage();
      // notifyListeners(); // 注释掉以避免触发重建

      final aiResponse = await MockAIService.generateResponse(
        userInput: content,
        characterId: character.id,
        currentRound: actualRounds,
        conversationHistory: messages,
        currentFavorability: currentFavorability,
      );

      final aiMessage = MessageModel(
        id: 'msg_${DateTime.now().millisecondsSinceEpoch + 1}',
        content: aiResponse.message,
        isUser: false,
        timestamp: aiResponse.responseTime,
        characterCount: aiResponse.message.length,
        densityCoefficient: 1.0,
      );

      _currentConversation = _currentConversation.addMessage(aiMessage);

      await _updateFavorability(aiResponse.favorabilityChange, content);
      await _updateConversationMetrics();
      await HiveService.saveConversation(_currentConversation);

    } catch (e) {
      if (_currentUser.credits < initialUser.credits) {
        _currentUser = await BillingService.addCredits(_currentUser, 1, '消息发送失败回滚');
      }
      rethrow;
    } finally {
      _isTyping = false;
      _updateStatusMessage();
      notifyListeners();
    }
  }

  Future<void> _updateFavorability(int change, String reason) async {
    final newFavorability = (currentFavorability + change).clamp(0, 100);

    final favorabilityPoint = FavorabilityPoint(
      round: actualRounds,
      score: newFavorability,
      reason: reason,
      timestamp: DateTime.now(),
    );

    final updatedHistory = [...favorabilityHistory, favorabilityPoint];
    final updatedMetrics = _currentConversation.metrics.copyWith(
      currentFavorability: newFavorability,
      favorabilityHistory: updatedHistory,
    );

    _currentConversation = _currentConversation.copyWith(
      metrics: updatedMetrics,
      updatedAt: DateTime.now(),
    );
  }

  Future<void> _updateConversationMetrics() async {
    final userMessages = messages.where((m) => m.isUser).toList();
    final totalChars = userMessages.fold<int>(0, (sum, msg) => sum + msg.characterCount);
    final avgCharsPerRound = userMessages.isNotEmpty ? totalChars / userMessages.length : 0.0;

    final updatedMetrics = _currentConversation.metrics.copyWith(
      actualRounds: actualRounds,
      effectiveRounds: effectiveRounds,
      averageCharsPerRound: avgCharsPerRound,
    );

    _currentConversation = _currentConversation.copyWith(
      metrics: updatedMetrics,
    );

    await HiveService.saveConversation(_currentConversation);
  }

  void _updateStatusMessage() {
    final currentStatus = roundStatus;

    if (RoundCalculator.shouldShowPrompt(effectiveRounds, _lastRoundStatus)) {
      _statusMessage = RoundCalculator.getStatusMessage(currentStatus);
      _lastRoundStatus = currentStatus;
    } else if (_statusMessage.isNotEmpty && currentStatus != _lastRoundStatus) {
      _statusMessage = '';
      _lastRoundStatus = currentStatus;
    }

    if (BillingService.shouldShowTopUpReminder(_currentUser)) {
      _statusMessage = BillingService.getTopUpSuggestion(_currentUser);
    }
  }

  Future<void> endConversation() async {
    if (!canEndConversation) {
      throw Exception('对话轮数不足，无法结束');
    }

    try {
      _currentConversation = _currentConversation.copyWith(
        status: ConversationStatus.completed,
        updatedAt: DateTime.now(),
      );

      await HiveService.saveConversation(_currentConversation);

      _currentUser = _currentUser.addConversationHistory(_currentConversation.id);
      await HiveService.updateCurrentUser(_currentUser);

      notifyListeners();
    } catch (e) {
      throw Exception('结束对话失败: ${e.toString()}');
    }
  }

  List<String> getImprovementSuggestions() {
    final suggestions = <String>[];

    final recentUserMessages = messages
        .where((m) => m.isUser)
        .toList()
        .reversed
        .take(5)
        .toList();

    for (final message in recentUserMessages) {
      final messageSuggestions = MockAIService.generateImprovementSuggestions(
        message.content,
        character.id,
        0,
      );
      suggestions.addAll(messageSuggestions);
    }

    return suggestions.toSet().take(5).toList();
  }

  Map<String, dynamic> getConversationStats() {
    return {
      'totalMessages': messages.length,
      'userMessages': messages.where((m) => m.isUser).length,
      'aiMessages': messages.where((m) => !m.isUser).length,
      'averageMessageLength': messages.isNotEmpty
          ? messages.map((m) => m.characterCount).reduce((a, b) => a + b) / messages.length
          : 0.0,
      'conversationDuration': _currentConversation.durationInMinutes,
      'finalFavorability': currentFavorability,
      'favorabilityGain': currentFavorability - 10,
    };
  }

  Future<void> resetConversation() async {
    _currentConversation = ConversationModel.newConversation(
      userId: _currentUser.id,
      characterId: character.id,
    );
    _isTyping = false;
    _statusMessage = '';
    _lastRoundStatus = RoundStatus.early;

    notifyListeners();
  }

  void continueFromConversation(ConversationModel conversation) {
    _currentConversation = conversation;
    _updateStatusMessage();
    notifyListeners();
  }

  @override
  void dispose() {
    if (messages.isNotEmpty) {
      HiveService.saveConversation(_currentConversation);
    }
    super.dispose();
  }
}