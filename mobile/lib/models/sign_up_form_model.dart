class SignUpFormModel {
  final String? name;
  final String? phoneNumber;
  final String? email;
  final String? password;
  final String? pin;
  /// During signup: local file path to selected image.
  /// After upload: can be replaced with the Storage download URL.
  final String? profilePicture;

  /// Optional small base64 thumbnail (for fast UI display).
  /// Note: keep small to avoid Firestore document limits.
  final String? profilePictureThumbBase64;
  final String? ktp;

  SignUpFormModel({
    this.name,
    this.phoneNumber,
    this.email,
    this.password,
    this.pin,
    this.profilePicture,
    this.profilePictureThumbBase64,
    this.ktp,
  });

  Map<String, dynamic> toJson() {
    return {
      'name': name,
      'phone_number': phoneNumber,
      'email': email,
      'password': password,
      'pin': pin,
      'profile_picture': profilePicture,
      'profile_picture_thumb_base64': profilePictureThumbBase64,
      'ktp': ktp
    };
  }
  
  // Validate phone number format (Indonesian format: +62 or 08xx)
  bool isValidPhoneNumber() {
    if (phoneNumber == null || phoneNumber!.isEmpty) return false;
    final phone = phoneNumber!.replaceAll(RegExp(r'[\s-]'), '');
    // Indonesian phone: +62xxxxxxxxxxx or 08xxxxxxxxxx
    return RegExp(r'^(\+62|62|0)[0-9]{9,12}$').hasMatch(phone);
  }

  SignUpFormModel copyWith({
    String? name,
    String? phoneNumber,
    String? email,
    String? password,
    String? pin,
    String? profilePicture,
    String? profilePictureThumbBase64,
    String? ktp,
  }) =>
      SignUpFormModel(
        name: name ?? this.name,
        phoneNumber: phoneNumber ?? this.phoneNumber,
        email: email ?? this.email,
        password: password ?? this.password,
        pin: pin ?? this.pin,
        profilePicture: profilePicture ?? this.profilePicture,
        profilePictureThumbBase64:
            profilePictureThumbBase64 ?? this.profilePictureThumbBase64,
        ktp: ktp ?? this.ktp,
      );
}
