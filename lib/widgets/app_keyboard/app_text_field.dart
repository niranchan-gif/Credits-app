import 'package:flutter/material.dart';
import 'app_keyboard_controller.dart';
import 'app_keyboard_types.dart';

/// Extension to quickly bind any standard FocusNode + TextEditingController
/// to the app's custom in-app keyboard.
extension AppKeyboardBindingExtension on FocusNode {
  void bindAppKeyboard({
    required TextEditingController controller,
    AppKeyboardType type = AppKeyboardType.text,
    AppKeyboardAction action = AppKeyboardAction.done,
    VoidCallback? onAction,
    void Function(String)? onChanged,
    String? label,
  }) {
    addListener(() {
      if (AppKeyboardController.instance.useNativeKeyboard) return;
      if (hasFocus) {
        AppKeyboardController.instance.attach(
          controller: controller,
          focusNode: this,
          type: type,
          action: action,
          onAction: onAction,
          onChanged: onChanged,
          label: label,
        );
      } else {
        AppKeyboardController.instance.detach(this);
      }
    });
  }
}

/// A drop-in replacement for TextFormField that automatically connects
/// to the custom in-app keyboard or allows native OS keyboard based on settings.
class AppTextFormField extends StatefulWidget {
  final TextEditingController? controller;
  final FocusNode? focusNode;
  final String? labelText;
  final String? hintText;
  final IconData? prefixIcon;
  final Widget? suffixIcon;
  final AppKeyboardType keyboardType;
  final AppKeyboardAction textInputAction;
  final String? Function(String?)? validator;
  final void Function(String)? onChanged;
  final VoidCallback? onFieldSubmitted;
  final int maxLines;
  final bool readOnly;
  final bool autofocus;
  final TextStyle? style;
  final InputDecoration? decoration;

  const AppTextFormField({
    super.key,
    this.controller,
    this.focusNode,
    this.labelText,
    this.hintText,
    this.prefixIcon,
    this.suffixIcon,
    this.keyboardType = AppKeyboardType.text,
    this.textInputAction = AppKeyboardAction.done,
    this.validator,
    this.onChanged,
    this.onFieldSubmitted,
    this.maxLines = 1,
    this.readOnly = false,
    this.autofocus = false,
    this.style,
    this.decoration,
  });

  @override
  State<AppTextFormField> createState() => _AppTextFormFieldState();
}

class _AppTextFormFieldState extends State<AppTextFormField> {
  late TextEditingController _controller;
  late FocusNode _focusNode;
  bool _ownsController = false;
  bool _ownsFocusNode = false;

  @override
  void initState() {
    super.initState();
    if (widget.controller != null) {
      _controller = widget.controller!;
    } else {
      _controller = TextEditingController();
      _ownsController = true;
    }

    if (widget.focusNode != null) {
      _focusNode = widget.focusNode!;
    } else {
      _focusNode = FocusNode();
      _ownsFocusNode = true;
    }

    _focusNode.addListener(_handleFocusChange);
  }

  void _handleFocusChange() {
    if (AppKeyboardController.instance.useNativeKeyboard) return;
    if (_focusNode.hasFocus && !widget.readOnly) {
      AppKeyboardController.instance.attach(
        controller: _controller,
        focusNode: _focusNode,
        type: widget.keyboardType,
        action: widget.textInputAction,
        onAction: widget.onFieldSubmitted,
        onChanged: widget.onChanged,
        label: widget.labelText ?? widget.hintText,
      );
    } else if (!_focusNode.hasFocus) {
      AppKeyboardController.instance.detach(_focusNode);
    }
  }

  @override
  void dispose() {
    _focusNode.removeListener(_handleFocusChange);
    AppKeyboardController.instance.detach(_focusNode);
    if (_ownsController) _controller.dispose();
    if (_ownsFocusNode) _focusNode.dispose();
    super.dispose();
  }

  TextInputType _resolveNativeKeyboardType(AppKeyboardType type) {
    switch (type) {
      case AppKeyboardType.number:
        return const TextInputType.numberWithOptions(decimal: true);
      case AppKeyboardType.phone:
        return TextInputType.phone;
      case AppKeyboardType.email:
        return TextInputType.emailAddress;
      case AppKeyboardType.multiline:
        return TextInputType.multiline;
      case AppKeyboardType.text:
        return TextInputType.text;
    }
  }

  TextInputAction _resolveNativeAction(AppKeyboardAction action) {
    switch (action) {
      case AppKeyboardAction.next:
        return TextInputAction.next;
      case AppKeyboardAction.done:
        return TextInputAction.done;
      case AppKeyboardAction.search:
        return TextInputAction.search;
      case AppKeyboardAction.send:
        return TextInputAction.send;
      case AppKeyboardAction.newLine:
        return TextInputAction.newline;
    }
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: AppKeyboardController.instance,
      builder: (context, _) {
        final useNative = AppKeyboardController.instance.useNativeKeyboard;

        return TextFormField(
          controller: _controller,
          focusNode: _focusNode,
          readOnly: widget.readOnly,
          showCursor: !widget.readOnly,
          keyboardType: useNative ? _resolveNativeKeyboardType(widget.keyboardType) : TextInputType.none,
          textInputAction: useNative ? _resolveNativeAction(widget.textInputAction) : null,
          enableInteractiveSelection: true,
          maxLines: widget.maxLines,
          autofocus: widget.autofocus,
          style: widget.style,
          validator: widget.validator,
          onChanged: widget.onChanged,
          onFieldSubmitted: widget.onFieldSubmitted != null ? (_) => widget.onFieldSubmitted!() : null,
          onTap: () {
            if (!widget.readOnly && !useNative) {
              AppKeyboardController.instance.attach(
                controller: _controller,
                focusNode: _focusNode,
                type: widget.keyboardType,
                action: widget.textInputAction,
                onAction: widget.onFieldSubmitted,
                onChanged: widget.onChanged,
                label: widget.labelText ?? widget.hintText,
              );
            }
          },
          decoration: widget.decoration ??
              InputDecoration(
                labelText: widget.labelText,
                hintText: widget.hintText,
                prefixIcon: widget.prefixIcon != null ? Icon(widget.prefixIcon, size: 20) : null,
                suffixIcon: widget.suffixIcon,
              ),
        );
      },
    );
  }
}
