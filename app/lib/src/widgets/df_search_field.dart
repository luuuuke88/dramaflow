import 'package:flutter/material.dart';

import '../theme/theme.dart';
import '../theme/tokens.dart';

class DFSearchField extends StatefulWidget {
  final String hint;
  final ValueChanged<String> onSearch;
  final double width;

  const DFSearchField({
    super.key,
    required this.hint,
    required this.onSearch,
    this.width = 260,
  });

  @override
  State<DFSearchField> createState() => _DFSearchFieldState();
}

class _DFSearchFieldState extends State<DFSearchField> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: widget.width,
      child: TextField(
        controller: _controller,
        textInputAction: TextInputAction.search,
        onSubmitted: widget.onSearch,
        style: DFTokens.body14.copyWith(color: context.df.textPrimary),
        decoration: InputDecoration(
          hintText: widget.hint,
          prefixIcon: Icon(
            Icons.search_rounded,
            color: context.df.textTertiary,
            size: 20,
          ),
          suffixIcon: ValueListenableBuilder<TextEditingValue>(
            valueListenable: _controller,
            builder: (context, value, _) {
              if (value.text.isEmpty) return const SizedBox.shrink();
              return IconButton(
                tooltip: '清除',
                onPressed: () {
                  _controller.clear();
                  widget.onSearch('');
                },
                icon: const Icon(Icons.close_rounded, size: 18),
              );
            },
          ),
        ),
      ),
    );
  }
}
