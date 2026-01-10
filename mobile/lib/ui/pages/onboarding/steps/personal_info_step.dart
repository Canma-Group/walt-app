import 'package:banking_app/shared/theme.dart';
import 'package:banking_app/ui/widgets/phone_input.dart';
import 'package:flutter/material.dart';

/// Step 1: Personal Information
/// Clean, modern design with country code phone picker
class PersonalInfoStep extends StatefulWidget {
  final GlobalKey<FormState> formKey;
  final TextEditingController nameController;
  final TextEditingController phoneController;
  final String? googlePhotoUrl;

  const PersonalInfoStep({
    Key? key,
    required this.formKey,
    required this.nameController,
    required this.phoneController,
    this.googlePhotoUrl,
  }) : super(key: key);

  @override
  State<PersonalInfoStep> createState() => _PersonalInfoStepState();
}

class _PersonalInfoStepState extends State<PersonalInfoStep> {
  bool _isNameFocused = false;
  final FocusNode _nameFocusNode = FocusNode();

  @override
  void initState() {
    super.initState();
    _nameFocusNode.addListener(() {
      setState(() => _isNameFocused = _nameFocusNode.hasFocus);
    });
  }

  @override
  void dispose() {
    _nameFocusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Step header - lighter, more breathable
          Text(
            'Personal Information',
            style: blackTextStyle.copyWith(
              fontSize: 22,
              fontWeight: bold,
              letterSpacing: -0.3,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'Let\'s set up your profile to get started',
            style: greyTextStyle.copyWith(
              fontSize: 14,
              height: 1.4,
            ),
          ),
          const SizedBox(height: 28),

          // Profile photo - refined with subtle shadow
          Center(
            child: Stack(
              children: [
                Container(
                  width: 100,
                  height: 100,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: whiteColor,
                    border: Border.all(
                      color: primaryBlue,
                      width: 2.5,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: primaryBlue.withOpacity(0.15),
                        blurRadius: 20,
                        offset: const Offset(0, 6),
                      ),
                    ],
                    image: widget.googlePhotoUrl != null
                        ? DecorationImage(
                            image: NetworkImage(widget.googlePhotoUrl!),
                            fit: BoxFit.cover,
                          )
                        : null,
                  ),
                  child: widget.googlePhotoUrl == null
                      ? Icon(
                          Icons.person_rounded,
                          size: 44,
                          color: primaryBlue,
                        )
                      : null,
                ),
                Positioned(
                  bottom: 2,
                  right: 2,
                  child: Container(
                    width: 28,
                    height: 28,
                    decoration: BoxDecoration(
                      gradient: primaryGradient,
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: whiteColor,
                        width: 2,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: primaryBlue.withOpacity(0.3),
                          blurRadius: 6,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    child: const Icon(
                      Icons.check_rounded,
                      color: Colors.white,
                      size: 16,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 10),
          Center(
            child: Text(
              'Photo from Google account',
              style: greyTextStyle.copyWith(
                fontSize: 12,
                fontWeight: medium,
              ),
            ),
          ),
          const SizedBox(height: 28),

          // Form card - lighter shadow, more premium feel
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: whiteColor,
              borderRadius: BorderRadius.circular(16),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.04),
                  blurRadius: 16,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Form(
              key: widget.formKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Full Name field
                  Text(
                    'Full Name',
                    style: blackTextStyle.copyWith(
                      fontSize: 14,
                      fontWeight: medium,
                      color: _isNameFocused ? primaryBlue : blackColor,
                    ),
                  ),
                  const SizedBox(height: 8),
                  TextFormField(
                    controller: widget.nameController,
                    focusNode: _nameFocusNode,
                    style: blackTextStyle.copyWith(fontSize: 15),
                    textCapitalization: TextCapitalization.words,
                    decoration: InputDecoration(
                      hintText: 'Enter your full name',
                      hintStyle: greyTextStyle.copyWith(
                        fontSize: 14,
                        color: greyColor.withOpacity(0.6),
                      ),
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 14,
                      ),
                      filled: true,
                      fillColor: whiteColor,
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
                      prefixIcon: Icon(
                        Icons.person_outline_rounded,
                        color: _isNameFocused ? primaryBlue : greyColor,
                        size: 20,
                      ),
                      errorStyle: errorTextStyle.copyWith(fontSize: 12),
                    ),
                    validator: (value) {
                      if ((value ?? '').trim().isEmpty) {
                        return 'Full name is required';
                      }
                      if ((value ?? '').trim().length < 2) {
                        return 'Name must be at least 2 characters';
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 20),

                  // Phone Number field with country picker
                  Text(
                    'Phone Number',
                    style: blackTextStyle.copyWith(
                      fontSize: 14,
                      fontWeight: medium,
                    ),
                  ),
                  const SizedBox(height: 8),
                  PhoneInputField(
                    controller: widget.phoneController,
                    initialCountryCode: 'ID',
                    validator: (value) {
                      final v = (value ?? '').trim();
                      if (v.isEmpty) return 'Phone number is required';
                      if (v.length < 8) return 'Enter a valid phone number';
                      return null;
                    },
                  ),
                  const SizedBox(height: 8),
                  // Helper text
                  Row(
                    children: [
                      Icon(
                        Icons.info_outline_rounded,
                        size: 14,
                        color: greyColor.withOpacity(0.7),
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          'We\'ll use this to verify your identity',
                          style: greyTextStyle.copyWith(
                            fontSize: 12,
                            color: greyColor.withOpacity(0.8),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
