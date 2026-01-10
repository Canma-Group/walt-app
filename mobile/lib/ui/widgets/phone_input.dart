import 'package:banking_app/shared/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Country data for phone input
class Country {
  final String name;
  final String code;
  final String dialCode;
  final String flag;

  const Country({
    required this.name,
    required this.code,
    required this.dialCode,
    required this.flag,
  });
}

/// Common countries for Indonesian fintech app
const List<Country> commonCountries = [
  Country(name: 'Indonesia', code: 'ID', dialCode: '+62', flag: '🇮🇩'),
  Country(name: 'Singapore', code: 'SG', dialCode: '+65', flag: '🇸🇬'),
  Country(name: 'Malaysia', code: 'MY', dialCode: '+60', flag: '🇲🇾'),
  Country(name: 'Thailand', code: 'TH', dialCode: '+66', flag: '🇹🇭'),
  Country(name: 'Philippines', code: 'PH', dialCode: '+63', flag: '🇵🇭'),
  Country(name: 'Vietnam', code: 'VN', dialCode: '+84', flag: '🇻🇳'),
  Country(name: 'Australia', code: 'AU', dialCode: '+61', flag: '🇦🇺'),
  Country(name: 'United States', code: 'US', dialCode: '+1', flag: '🇺🇸'),
  Country(name: 'United Kingdom', code: 'GB', dialCode: '+44', flag: '🇬🇧'),
  Country(name: 'Japan', code: 'JP', dialCode: '+81', flag: '🇯🇵'),
  Country(name: 'South Korea', code: 'KR', dialCode: '+82', flag: '🇰🇷'),
  Country(name: 'China', code: 'CN', dialCode: '+86', flag: '🇨🇳'),
  Country(name: 'India', code: 'IN', dialCode: '+91', flag: '🇮🇳'),
];

/// Modern phone input with country code picker
/// Designed for fintech applications with clean UX
class PhoneInputField extends StatefulWidget {
  final TextEditingController controller;
  final String? Function(String?)? validator;
  final void Function(String fullNumber)? onChanged;
  final String? initialCountryCode;
  final bool enabled;

  const PhoneInputField({
    Key? key,
    required this.controller,
    this.validator,
    this.onChanged,
    this.initialCountryCode = 'ID',
    this.enabled = true,
  }) : super(key: key);

  @override
  State<PhoneInputField> createState() => _PhoneInputFieldState();
}

class _PhoneInputFieldState extends State<PhoneInputField> {
  late Country _selectedCountry;
  bool _isFocused = false;
  final FocusNode _focusNode = FocusNode();

  @override
  void initState() {
    super.initState();
    _selectedCountry = commonCountries.firstWhere(
      (c) => c.code == widget.initialCountryCode,
      orElse: () => commonCountries.first,
    );
    _focusNode.addListener(_onFocusChange);
  }

  @override
  void dispose() {
    _focusNode.dispose();
    super.dispose();
  }

  void _onFocusChange() {
    setState(() => _isFocused = _focusNode.hasFocus);
  }

  String get fullPhoneNumber {
    final phone = widget.controller.text.trim();
    if (phone.isEmpty) return '';
    // Remove leading zero if present
    final cleanPhone = phone.startsWith('0') ? phone.substring(1) : phone;
    return '${_selectedCountry.dialCode}$cleanPhone';
  }

  void _showCountryPicker() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (context) => _CountryPickerSheet(
        countries: commonCountries,
        selectedCountry: _selectedCountry,
        onSelect: (country) {
          setState(() => _selectedCountry = country);
          Navigator.pop(context);
          widget.onChanged?.call(fullPhoneNumber);
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final borderColor = _isFocused ? primaryBlue : greyColor.withOpacity(0.2);
    final borderWidth = _isFocused ? 1.5 : 1.0;

    return Container(
      decoration: BoxDecoration(
        color: widget.enabled ? whiteColor : greyColor.withOpacity(0.05),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: borderColor, width: borderWidth),
      ),
      child: Row(
        children: [
          // Country code selector
          InkWell(
            onTap: widget.enabled ? _showCountryPicker : null,
            borderRadius: const BorderRadius.horizontal(left: Radius.circular(12)),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 16),
              decoration: BoxDecoration(
                border: Border(
                  right: BorderSide(color: greyColor.withOpacity(0.2)),
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    _selectedCountry.flag,
                    style: const TextStyle(fontSize: 20),
                  ),
                  const SizedBox(width: 6),
                  Text(
                    _selectedCountry.dialCode,
                    style: blackTextStyle.copyWith(
                      fontSize: 15,
                      fontWeight: medium,
                    ),
                  ),
                  const SizedBox(width: 4),
                  Icon(
                    Icons.keyboard_arrow_down_rounded,
                    size: 18,
                    color: greyColor,
                  ),
                ],
              ),
            ),
          ),
          // Phone number input
          Expanded(
            child: TextFormField(
              controller: widget.controller,
              focusNode: _focusNode,
              enabled: widget.enabled,
              keyboardType: TextInputType.phone,
              inputFormatters: [
                FilteringTextInputFormatter.digitsOnly,
                LengthLimitingTextInputFormatter(13),
              ],
              style: blackTextStyle.copyWith(
                fontSize: 15,
                fontWeight: regular,
              ),
              decoration: InputDecoration(
                hintText: '812 3456 7890',
                hintStyle: greyTextStyle.copyWith(
                  fontSize: 14,
                  color: greyColor.withOpacity(0.6),
                ),
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 16,
                ),
                border: InputBorder.none,
                enabledBorder: InputBorder.none,
                focusedBorder: InputBorder.none,
                errorBorder: InputBorder.none,
                focusedErrorBorder: InputBorder.none,
              ),
              onChanged: (_) => widget.onChanged?.call(fullPhoneNumber),
              validator: widget.validator,
            ),
          ),
        ],
      ),
    );
  }
}

/// Bottom sheet for country selection
class _CountryPickerSheet extends StatefulWidget {
  final List<Country> countries;
  final Country selectedCountry;
  final void Function(Country) onSelect;

  const _CountryPickerSheet({
    required this.countries,
    required this.selectedCountry,
    required this.onSelect,
  });

  @override
  State<_CountryPickerSheet> createState() => _CountryPickerSheetState();
}

class _CountryPickerSheetState extends State<_CountryPickerSheet> {
  late List<Country> _filteredCountries;
  final _searchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _filteredCountries = widget.countries;
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _filterCountries(String query) {
    setState(() {
      if (query.isEmpty) {
        _filteredCountries = widget.countries;
      } else {
        _filteredCountries = widget.countries
            .where((c) =>
                c.name.toLowerCase().contains(query.toLowerCase()) ||
                c.dialCode.contains(query) ||
                c.code.toLowerCase().contains(query.toLowerCase()))
            .toList();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      height: MediaQuery.of(context).size.height * 0.7,
      decoration: BoxDecoration(
        color: whiteColor,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: Column(
        children: [
          // Handle bar
          Container(
            margin: const EdgeInsets.only(top: 12),
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: greyColor.withOpacity(0.3),
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          // Title
          Padding(
            padding: const EdgeInsets.all(20),
            child: Text(
              'Select Country',
              style: blackTextStyle.copyWith(
                fontSize: 18,
                fontWeight: semiBold,
              ),
            ),
          ),
          // Search field
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: TextField(
              controller: _searchController,
              onChanged: _filterCountries,
              style: blackTextStyle.copyWith(fontSize: 15),
              decoration: InputDecoration(
                hintText: 'Search country...',
                hintStyle: greyTextStyle.copyWith(fontSize: 14),
                prefixIcon: Icon(Icons.search, color: greyColor, size: 20),
                filled: true,
                fillColor: lightBackgroundColor,
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 12,
                ),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
          ),
          const SizedBox(height: 12),
          // Country list
          Expanded(
            child: ListView.builder(
              itemCount: _filteredCountries.length,
              padding: const EdgeInsets.symmetric(horizontal: 8),
              itemBuilder: (context, index) {
                final country = _filteredCountries[index];
                final isSelected = country.code == widget.selectedCountry.code;
                return ListTile(
                  onTap: () => widget.onSelect(country),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  selected: isSelected,
                  selectedTileColor: primaryBlue.withOpacity(0.08),
                  leading: Text(
                    country.flag,
                    style: const TextStyle(fontSize: 24),
                  ),
                  title: Text(
                    country.name,
                    style: blackTextStyle.copyWith(
                      fontSize: 15,
                      fontWeight: isSelected ? semiBold : regular,
                    ),
                  ),
                  trailing: Text(
                    country.dialCode,
                    style: (isSelected ? primaryTextStyle : greyTextStyle).copyWith(
                      fontSize: 14,
                      fontWeight: medium,
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
