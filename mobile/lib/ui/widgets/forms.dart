import 'package:banking_app/shared/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Modern form field with floating label and proper styling
class CustomFormField extends StatefulWidget {
  final String title;
  final bool obscureText;
  final TextEditingController? controller;
  final bool isShowTitle;
  final TextInputType? keyboardType;
  final Function(String)? onFieldSubmitted;
  final String? Function(String?)? validator;
  final String? hintText;
  final IconData? prefixIcon;
  final Widget? suffixIcon;
  final bool enabled;
  final int? maxLines;
  final List<TextInputFormatter>? inputFormatters;
  final FocusNode? focusNode;
  final void Function(String)? onChanged;

  const CustomFormField({
    Key? key,
    required this.title,
    this.obscureText = false,
    this.controller,
    this.isShowTitle = true,
    this.keyboardType,
    this.onFieldSubmitted,
    this.validator,
    this.hintText,
    this.prefixIcon,
    this.suffixIcon,
    this.enabled = true,
    this.maxLines = 1,
    this.inputFormatters,
    this.focusNode,
    this.onChanged,
  }) : super(key: key);

  @override
  State<CustomFormField> createState() => _CustomFormFieldState();
}

class _CustomFormFieldState extends State<CustomFormField> {
  late FocusNode _focusNode;
  bool _isFocused = false;

  @override
  void initState() {
    super.initState();
    _focusNode = widget.focusNode ?? FocusNode();
    _focusNode.addListener(_onFocusChange);
  }

  @override
  void dispose() {
    if (widget.focusNode == null) {
      _focusNode.dispose();
    }
    super.dispose();
  }

  void _onFocusChange() {
    setState(() {
      _isFocused = _focusNode.hasFocus;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (widget.isShowTitle) ...[
          Text(
            widget.title,
            style: blackTextStyle.copyWith(
              fontSize: 14,
              fontWeight: medium,
              color: _isFocused ? primaryBlue : blackColor,
            ),
          ),
          const SizedBox(height: 8),
        ],
        TextFormField(
          focusNode: _focusNode,
          obscureText: widget.obscureText,
          controller: widget.controller,
          keyboardType: widget.keyboardType,
          validator: widget.validator,
          enabled: widget.enabled,
          maxLines: widget.maxLines,
          inputFormatters: widget.inputFormatters,
          onChanged: widget.onChanged,
          style: blackTextStyle.copyWith(
            fontSize: 15,
            fontWeight: regular,
          ),
          decoration: InputDecoration(
            hintText: widget.hintText ?? (!widget.isShowTitle ? widget.title : null),
            hintStyle: greyTextStyle.copyWith(
              fontSize: 14,
              fontWeight: regular,
            ),
            prefixIcon: widget.prefixIcon != null
                ? Icon(
                    widget.prefixIcon,
                    color: _isFocused ? primaryBlue : greyColor,
                    size: 20,
                  )
                : null,
            suffixIcon: widget.suffixIcon,
            filled: true,
            fillColor: widget.enabled ? whiteColor : greyColor.withOpacity(0.1),
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 16,
              vertical: 16,
            ),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: greyColor.withOpacity(0.2)),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: greyColor.withOpacity(0.2)),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: primaryBlue, width: 1.5),
            ),
            errorBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: redColor),
            ),
            focusedErrorBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: redColor, width: 1.5),
            ),
            errorStyle: errorTextStyle.copyWith(
              fontSize: 12,
              fontWeight: regular,
            ),
            disabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: greyColor.withOpacity(0.1)),
            ),
          ),
          onFieldSubmitted: widget.onFieldSubmitted,
        ),
      ],
    );
  }
}

/// Password form field with visibility toggle
class PasswordFormField extends StatefulWidget {
  final String title;
  final TextEditingController? controller;
  final String? Function(String?)? validator;
  final String? hintText;
  final Function(String)? onFieldSubmitted;

  const PasswordFormField({
    Key? key,
    this.title = 'Password',
    this.controller,
    this.validator,
    this.hintText,
    this.onFieldSubmitted,
  }) : super(key: key);

  @override
  State<PasswordFormField> createState() => _PasswordFormFieldState();
}

class _PasswordFormFieldState extends State<PasswordFormField> {
  bool _obscureText = true;

  @override
  Widget build(BuildContext context) {
    return CustomFormField(
      title: widget.title,
      controller: widget.controller,
      obscureText: _obscureText,
      validator: widget.validator,
      hintText: widget.hintText ?? 'Enter your password',
      prefixIcon: Icons.lock_outline,
      onFieldSubmitted: widget.onFieldSubmitted,
      suffixIcon: IconButton(
        icon: Icon(
          _obscureText ? Icons.visibility_off_outlined : Icons.visibility_outlined,
          color: greyColor,
          size: 20,
        ),
        onPressed: () {
          setState(() {
            _obscureText = !_obscureText;
          });
        },
      ),
    );
  }
}
