import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import '../../config/app_theme.dart';
import '../../services/app_state.dart';
import 'review_confirm_screen.dart';

class PatientInfoScreen extends StatefulWidget {
  const PatientInfoScreen({super.key});

  @override
  State<PatientInfoScreen> createState() => _PatientInfoScreenState();
}

class _PatientInfoScreenState extends State<PatientInfoScreen> {
  late TextEditingController _nameController;
  late TextEditingController _phoneController;
  late TextEditingController _ageController;
  String? _sex; // Null by default so the user must select it!

  @override
  void initState() {
    super.initState();
    // Fields are empty by default so user types/selects themselves as requested!
    _nameController = TextEditingController();
    _phoneController = TextEditingController();
    _ageController = TextEditingController();
  }

  @override
  void dispose() {
    _nameController.dispose();
    _phoneController.dispose();
    _ageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, color: AppTheme.textPrimary, size: 20),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          'Patient Information', // Simplified header title
          style: GoogleFonts.plusJakartaSans(
            fontSize: 18,
            fontWeight: FontWeight.bold,
            color: AppTheme.textPrimary,
          ),
        ),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 20.0, vertical: 12.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Info Banner Header (Matching Image 2 Screen 3)
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: AppTheme.primaryLight,
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.notifications_active_outlined, color: AppTheme.primaryColor),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Please enter patient information',
                            style: GoogleFonts.plusJakartaSans(
                              fontSize: 13,
                              fontWeight: FontWeight.bold,
                              color: AppTheme.primaryDark,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            'This information will help the doctor provide better care.',
                            style: GoogleFonts.plusJakartaSans(
                              fontSize: 12,
                              color: AppTheme.primaryDark.withOpacity(0.8),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 28),

              // Full Name
              Text(
                'Full Name',
                style: GoogleFonts.plusJakartaSans(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: AppTheme.textPrimary,
                ),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _nameController,
                textCapitalization: TextCapitalization.words, // Automatically capitalizes first letter of names!
                style: GoogleFonts.plusJakartaSans(fontSize: 14),
                decoration: const InputDecoration(
                  prefixIcon: Icon(Icons.person_outline_rounded, color: AppTheme.primaryColor),
                  hintText: 'Enter patient full name',
                ),
              ),
              const SizedBox(height: 20),

              // Phone Number
              Text(
                'Phone Number',
                style: GoogleFonts.plusJakartaSans(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: AppTheme.textPrimary,
                ),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _phoneController,
                keyboardType: TextInputType.phone,
                style: GoogleFonts.plusJakartaSans(fontSize: 14),
                decoration: const InputDecoration(
                  prefixIcon: Icon(Icons.phone_android_rounded, color: AppTheme.primaryColor),
                  hintText: '+252 61 XXXXXXX',
                ),
              ),
              const SizedBox(height: 20),

              // Age
              Text(
                'Age',
                style: GoogleFonts.plusJakartaSans(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: AppTheme.textPrimary,
                ),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _ageController,
                keyboardType: TextInputType.number,
                inputFormatters: [
                  FilteringTextInputFormatter.digitsOnly,
                ],
                style: GoogleFonts.plusJakartaSans(fontSize: 14),
                decoration: const InputDecoration(
                  prefixIcon: Icon(Icons.calendar_today_rounded, color: AppTheme.primaryColor),
                  hintText: 'e.g. 24',
                ),
              ),
              const SizedBox(height: 20),

              // Sex Selector (Male / Female) - Renamed from Gender to Sex!
              Text(
                'Sex',
                style: GoogleFonts.plusJakartaSans(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: AppTheme.textPrimary,
                ),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Radio<String>(
                    value: 'Male',
                    groupValue: _sex,
                    activeColor: AppTheme.primaryColor,
                    onChanged: (val) => setState(() => _sex = val!),
                  ),
                  Text('Male', style: GoogleFonts.plusJakartaSans(fontSize: 14)),
                  const SizedBox(width: 24),
                  Radio<String>(
                    value: 'Female',
                    groupValue: _sex,
                    activeColor: AppTheme.primaryColor,
                    onChanged: (val) => setState(() => _sex = val!),
                  ),
                  Text('Female', style: GoogleFonts.plusJakartaSans(fontSize: 14)),
                ],
              ),

              const SizedBox(height: 36),

              SizedBox(
                width: double.infinity,
                height: 52,
                child: ElevatedButton(
                  onPressed: () {
                    final name = _nameController.text.trim();
                    final phone = _phoneController.text.trim();
                    final ageText = _ageController.text.trim();

                    if (name.isEmpty || phone.isEmpty || ageText.isEmpty || _sex == null) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('Please fill all required fields and select gender'),
                        ),
                      );
                      return;
                    }

                    final age = int.tryParse(ageText) ?? 24;
                    context.read<AppState>().updateDraftBooking(
                      patientName: name,
                      patientPhone: phone,
                      patientAge: age,
                      patientGender: _sex!, // Map Sex value to state
                    );

                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => const ReviewConfirmScreen(),
                      ),
                    );
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.primaryColor,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                  ),
                  child: Text(
                    'Continue',
                    style: GoogleFonts.plusJakartaSans(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
