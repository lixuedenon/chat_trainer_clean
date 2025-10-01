// lib/features/chat/widgets/chat_input.dart

import 'package:flutter/material.dart';

class ChatInput extends StatefulWidget {
  final Function(String) onSendMessage;
  final bool enabled;
  final int maxLength;
  final int remainingCredits;

  const ChatInput({
    Key? key,
    required this.onSendMessage,
    this.enabled = true,
    this.maxLength = 50,
    required this.remainingCredits,
  }) : super(key: key);

  @override
  State<ChatInput> createState() => _ChatInputState();
}

class _ChatInputState extends State<ChatInput> {
  final TextEditingController _textController = TextEditingController();
  final FocusNode _focusNode = FocusNode();
  bool _isSending = false;

  @override
  void initState() {
    super.initState();
    _textController.addListener(_onTextChanged);
    Future.delayed(const Duration(milliseconds: 100), () {
      if (mounted) {
        _focusNode.requestFocus();
      }
    });
  }

  @override
  void didUpdateWidget(ChatInput oldWidget) {
    super.didUpdateWidget(oldWidget);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (widget.enabled && mounted && !_focusNode.hasFocus) {
        _focusNode.requestFocus();
      }
    });
  }

  @override
  void dispose() {
    _textController.removeListener(_onTextChanged);
    _textController.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _onTextChanged() {
    setState(() {});
  }

  Future<void> _sendMessage() async {
    final message = _textController.text.trim();
    if (message.isEmpty || !widget.enabled || _isSending) return;

    if (widget.remainingCredits <= 0) {
      _showInsufficientCreditsDialog();
      return;
    }

    setState(() {
      _isSending = true;
    });

    try {
      await widget.onSendMessage(message);
      _textController.clear();
    } catch (e) {
      rethrow;
    } finally {
      if (mounted) {
        setState(() {
          _isSending = false;
        });
      }
    }
  }

  void _showInsufficientCreditsDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('对话次数不足'),
        content: const Text('您的对话次数已用完，请购买套餐后继续使用。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('知道了'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.of(context).pop();
            },
            child: const Text('去充值'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final currentLength = _textController.text.length;
    final isNearLimit = currentLength > widget.maxLength * 0.8;
    final isOverLimit = currentLength > widget.maxLength;
    final canSend = currentLength > 0 &&
                   currentLength <= widget.maxLength &&
                   widget.enabled &&
                   !_isSending &&
                   widget.remainingCredits > 0;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (isNearLimit)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
              margin: const EdgeInsets.only(bottom: 8),
              decoration: BoxDecoration(
                color: isOverLimit ? Colors.red[50] : Colors.orange[50],
                borderRadius: BorderRadius.circular(16),
              ),
              child: Text(
                '${currentLength}/${widget.maxLength}字${isOverLimit ? ' (超出限制)' : ''}',
                style: TextStyle(
                  fontSize: 12,
                  color: isOverLimit ? Colors.red[700] : Colors.orange[700],
                ),
              ),
            ),
          Row(
            children: [
              Expanded(
                child: TextField(
                  key: const ValueKey('main_chat_input'),
                  controller: _textController,
                  focusNode: _focusNode,
                  enabled: widget.enabled && !_isSending,
                  maxLength: widget.maxLength,
                  maxLines: null,
                  textInputAction: TextInputAction.send,
                  onEditingComplete: () {}, // 阻止默认键盘关闭行为
                  onSubmitted: canSend ? (_) => _sendMessage() : null,
                  decoration: InputDecoration(
                    hintText: '输入消息...',
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(24),
                      borderSide: BorderSide.none,
                    ),
                    filled: true,
                    fillColor: Colors.grey[100],
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 12,
                    ),
                    counterText: '',
                  ),
                ),
              ),
              const SizedBox(width: 8),
              GestureDetector(
                onTap: canSend ? _sendMessage : null,
                child: Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    color: canSend ? Theme.of(context).primaryColor : Colors.grey[300],
                    shape: BoxShape.circle,
                  ),
                  child: Center(
                    child: _isSending
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                            ),
                          )
                        : const Icon(Icons.send, color: Colors.white, size: 20),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}