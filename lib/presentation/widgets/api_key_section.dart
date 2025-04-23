import 'package:flutter/material.dart';

class ApiKeySection extends StatelessWidget {
  final TextEditingController controller;
  final String? currentApiKey;
  final Function() onSave;
  final Function() onClear;

  const ApiKeySection({
    super.key,
    required this.controller,
    required this.currentApiKey,
    required this.onSave,
    required this.onClear,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Gemini API Key',
          style: TextStyle(fontSize: 18.0, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 8.0),
        TextField(
          controller: controller,
          obscureText: true,
          decoration: const InputDecoration(
            hintText: 'Enter your Gemini API Key',
            border: OutlineInputBorder(),
            suffixIcon: Icon(Icons.vpn_key),
          ),
          onSubmitted: (_) => onSave(),
        ),
        const SizedBox(height: 8.0),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            ElevatedButton.icon(
              icon: const Icon(Icons.save),
              label: const Text('Save Key'),
              onPressed: onSave,
            ),
            if (currentApiKey != null && currentApiKey!.isNotEmpty)
              TextButton.icon(
                icon: const Icon(Icons.clear),
                label: const Text('Clear Key'),
                onPressed: onClear,
                style: TextButton.styleFrom(
                  foregroundColor: theme.colorScheme.error,
                ),
              ),
          ],
        ),
        const SizedBox(height: 4.0),
        const Text(
          'Stored locally.',
          style: TextStyle(
            fontSize: 12.0,
            fontStyle: FontStyle.italic,
            color: Colors.grey,
          ),
        ),
      ],
    );
  }
}
