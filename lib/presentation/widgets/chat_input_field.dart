import 'package:flutter/material.dart';

class ChatInputField extends StatelessWidget {
  final TextEditingController controller;
  final FocusNode focusNode;
  final bool enabled;
  final bool isLoading;
  final bool isApiKeySet;
  final VoidCallback onSend;

  const ChatInputField({
    super.key,
    required this.controller,
    required this.focusNode,
    required this.enabled,
    required this.isLoading,
    required this.isApiKeySet,
    required this.onSend,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        if (isLoading)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 8.0),
            child: LinearProgressIndicator(),
          ),
        Padding(
          padding: const EdgeInsets.all(8.0),
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  focusNode: focusNode,
                  controller: controller,
                  enabled: enabled,
                  decoration: InputDecoration(
                    hintText:
                        isApiKeySet
                            ? (isLoading
                                ? 'Waiting for response...'
                                : 'Enter your message...')
                            : 'Set API Key in Settings...',
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(20.0),
                    ),
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 16.0,
                      vertical: 12.0,
                    ),
                  ),
                  textInputAction: TextInputAction.send,
                  onSubmitted: enabled ? (_) => onSend() : null,
                  minLines: 1,
                  maxLines: 5,
                ),
              ),
              const SizedBox(width: 8.0),
              IconButton(
                icon: const Icon(Icons.send),
                onPressed: enabled ? onSend : null,
                tooltip: 'Send Message',
              ),
            ],
          ),
        ),
        if (!isApiKeySet)
          Padding(
            padding: const EdgeInsets.only(
              bottom: 8.0,
              left: 16.0,
              right: 16.0,
            ),
            child: Text(
              'Please set your Gemini API Key in the Settings menu (⚙️) to start chatting.',
              style: TextStyle(color: Theme.of(context).colorScheme.error),
              textAlign: TextAlign.center,
            ),
          ),
      ],
    );
  }
}
