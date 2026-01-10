import 'dart:convert';
import 'dart:io';

import 'package:banking_app/models/sign_up_form_model.dart';
import 'package:banking_app/shared/shared_methods.dart';
import 'package:banking_app/shared/theme.dart';
import 'package:banking_app/ui/pages/sign_up_set_pin_page.dart';
import 'package:banking_app/ui/widgets/buttons.dart';
import 'package:flutter/material.dart';
import 'package:image/image.dart' as img;
import 'package:image_picker/image_picker.dart';

/// Signup step: choose profile photo
/// - Stores local file path in SignUpFormModel.profilePicture
/// - Generates small base64 thumbnail for Firestore/UI
class SignUpSetPhotoPage extends StatefulWidget {
  final SignUpFormModel data;

  const SignUpSetPhotoPage({
    super.key,
    required this.data,
  });

  @override
  State<SignUpSetPhotoPage> createState() => _SignUpSetPhotoPageState();
}

class _SignUpSetPhotoPageState extends State<SignUpSetPhotoPage> {
  final _picker = ImagePicker();
  XFile? _selected;
  bool _isLoading = false;

  Future<void> _pickImage() async {
    try {
      final imgFile = await _picker.pickImage(
        source: ImageSource.gallery,
        imageQuality: 85,
      );
      if (imgFile == null) return;

      setState(() {
        _selected = imgFile;
      });
    } catch (e) {
      if (!mounted) return;
      showCustomSnackBar(context, 'Failed to pick image: $e');
    }
  }

  Future<String?> _makeThumbBase64(String path) async {
    try {
      final bytes = await File(path).readAsBytes();
      final decoded = img.decodeImage(bytes);
      if (decoded == null) return null;
      final resized = img.copyResize(decoded, width: 128);
      final jpg = img.encodeJpg(resized, quality: 70);
      return base64Encode(jpg);
    } catch (_) {
      return null;
    }
  }

  Future<void> _continue() async {
    setState(() => _isLoading = true);
    try {
      String? thumb;
      if (_selected != null) {
        thumb = await _makeThumbBase64(_selected!.path);
      }

      if (!mounted) return;
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => SignUpSetPINPage(
            data: widget.data.copyWith(
              profilePicture: _selected?.path,
              profilePictureThumbBase64: thumb,
            ),
          ),
        ),
      );
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = MediaQuery.of(context).size.width / 393;

    return Scaffold(
      backgroundColor: lightBackgroundColor,
      appBar: AppBar(
        title: const Text('Add Photo'),
        backgroundColor: lightBackgroundColor,
      ),
      body: ListView(
        padding: const EdgeInsets.symmetric(horizontal: 24),
        children: [
          const SizedBox(height: 30),
          Text(
            'Upload Profile Photo',
            style: blackTextStyle.copyWith(
              fontSize: 24,
              fontWeight: semiBold,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Optional. You can skip for now.',
            style: greyTextStyle.copyWith(fontSize: 14),
          ),
          const SizedBox(height: 30),
          Center(
            child: GestureDetector(
              onTap: _isLoading ? null : _pickImage,
              child: Container(
                width: 140 * s,
                height: 140 * s,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: whiteColor,
                  border: Border.all(color: greyColor.withOpacity(0.3)),
                ),
                child: ClipOval(
                  child: _selected == null
                      ? Icon(Icons.add_a_photo, color: greyColor, size: 36 * s)
                      : Image.file(
                          File(_selected!.path),
                          fit: BoxFit.cover,
                        ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 24),
          CustomFilledButton(
            title: _selected == null ? 'Pick Photo' : 'Change Photo',
            onPressed: _isLoading ? null : _pickImage,
          ),
          const SizedBox(height: 16),
          CustomFilledButton(
            title: 'Continue',
            onPressed: _isLoading ? null : _continue,
          ),
          const SizedBox(height: 20),
          Text(
            'We will upload your photo to Firebase Storage and store a small thumbnail in Firestore.',
            style: greyTextStyle.copyWith(fontSize: 12),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}


