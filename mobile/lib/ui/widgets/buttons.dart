import 'package:banking_app/shared/theme.dart';
import 'package:flutter/material.dart';

/// Primary filled button with gradient background
class CustomFilledButton extends StatelessWidget {
  final String title;
  final double width;
  final double height;
  final VoidCallback? onPressed;
  final bool isLoading;
  final IconData? icon;

  const CustomFilledButton({
    Key? key,
    required this.title,
    this.width = double.infinity,
    this.height = 54,
    this.onPressed,
    this.isLoading = false,
    this.icon,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Container(
      height: height,
      width: width,
      decoration: BoxDecoration(
        gradient: onPressed != null && !isLoading ? primaryGradient : null,
        color: onPressed == null || isLoading ? greyColor.withOpacity(0.3) : null,
        borderRadius: BorderRadius.circular(12),
        boxShadow: onPressed != null && !isLoading
            ? [
                BoxShadow(
                  color: primaryBlue.withOpacity(0.3),
                  blurRadius: 12,
                  offset: const Offset(0, 4),
                ),
              ]
            : null,
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: isLoading ? null : onPressed,
          borderRadius: BorderRadius.circular(12),
          child: Center(
            child: isLoading
                ? SizedBox(
                    width: 24,
                    height: 24,
                    child: CircularProgressIndicator(
                      color: whiteColor,
                      strokeWidth: 2.5,
                    ),
                  )
                : Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      if (icon != null) ...[
                        Icon(icon, color: whiteColor, size: 20),
                        const SizedBox(width: 8),
                      ],
                      Text(
                        title,
                        style: whiteTextStyle.copyWith(
                          fontSize: 16,
                          fontWeight: semiBold,
                        ),
                      ),
                    ],
                  ),
          ),
        ),
      ),
    );
  }
}

/// Secondary outlined button
class CustomOutlinedButton extends StatelessWidget {
  final String title;
  final double width;
  final double height;
  final VoidCallback? onPressed;
  final bool isLoading;
  final IconData? icon;

  const CustomOutlinedButton({
    Key? key,
    required this.title,
    this.width = double.infinity,
    this.height = 54,
    this.onPressed,
    this.isLoading = false,
    this.icon,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Container(
      height: height,
      width: width,
      decoration: BoxDecoration(
        color: whiteColor,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: onPressed != null ? primaryBlue : greyColor.withOpacity(0.3),
          width: 1.5,
        ),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: isLoading ? null : onPressed,
          borderRadius: BorderRadius.circular(12),
          child: Center(
            child: isLoading
                ? SizedBox(
                    width: 24,
                    height: 24,
                    child: CircularProgressIndicator(
                      color: primaryBlue,
                      strokeWidth: 2.5,
                    ),
                  )
                : Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      if (icon != null) ...[
                        Icon(icon, color: primaryBlue, size: 20),
                        const SizedBox(width: 8),
                      ],
                      Text(
                        title,
                        style: primaryTextStyle.copyWith(
                          fontSize: 16,
                          fontWeight: semiBold,
                        ),
                      ),
                    ],
                  ),
          ),
        ),
      ),
    );
  }
}

/// Text button for links
class CustomTextButton extends StatelessWidget {
  final String title;
  final double width;
  final double height;
  final VoidCallback? onPressed;
  final Color? textColor;

  const CustomTextButton({
    Key? key,
    required this.title,
    this.width = double.infinity,
    this.height = 40,
    this.onPressed,
    this.textColor,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: height,
      width: width,
      child: TextButton(
        onPressed: onPressed,
        style: TextButton.styleFrom(
          padding: EdgeInsets.zero,
        ),
        child: Text(
          title,
          style: (textColor != null
                  ? TextStyle(color: textColor)
                  : primaryTextStyle)
              .copyWith(
            fontSize: 14,
            fontWeight: medium,
          ),
        ),
      ),
    );
  }
}

/// Social login button (Google, etc.)
class SocialLoginButton extends StatelessWidget {
  final String title;
  final String? iconPath;
  final IconData? icon;
  final VoidCallback? onPressed;
  final bool isLoading;

  const SocialLoginButton({
    Key? key,
    required this.title,
    this.iconPath,
    this.icon,
    this.onPressed,
    this.isLoading = false,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 54,
      width: double.infinity,
      decoration: BoxDecoration(
        color: whiteColor,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: greyColor.withOpacity(0.2)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: isLoading ? null : onPressed,
          borderRadius: BorderRadius.circular(12),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: isLoading
                ? Center(
                    child: SizedBox(
                      width: 24,
                      height: 24,
                      child: CircularProgressIndicator(
                        color: primaryBlue,
                        strokeWidth: 2.5,
                      ),
                    ),
                  )
                : Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      if (iconPath != null)
                        Image.asset(
                          iconPath!,
                          width: 24,
                          height: 24,
                          errorBuilder: (_, __, ___) => Icon(
                            icon ?? Icons.login,
                            size: 24,
                            color: blackColor,
                          ),
                        )
                      else if (icon != null)
                        Icon(icon, size: 24, color: blackColor),
                      const SizedBox(width: 12),
                      Text(
                        title,
                        style: blackTextStyle.copyWith(
                          fontSize: 15,
                          fontWeight: medium,
                        ),
                      ),
                    ],
                  ),
          ),
        ),
      ),
    );
  }
}

/// PIN input button
class CustomInputButton extends StatelessWidget {
  final String title;
  final VoidCallback? onTap;

  const CustomInputButton({
    Key? key,
    required this.title,
    required this.onTap,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 70,
        height: 70,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: numberBackgroundColor,
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.2),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Center(
          child: Text(
            title,
            style: whiteTextStyle.copyWith(
              fontSize: 28,
              fontWeight: semiBold,
            ),
          ),
        ),
      ),
    );
  }
}
