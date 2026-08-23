import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import '../../config/app_theme.dart';
import '../../models/doctor_model.dart';
import '../../services/app_state.dart';
import 'patient_info_screen.dart';

class BookAppointmentScreen extends StatefulWidget {
  final DoctorModel doctor;
  const BookAppointmentScreen({super.key, required this.doctor});

  @override
  State<BookAppointmentScreen> createState() => _BookAppointmentScreenState();
}

class _BookAppointmentScreenState extends State<BookAppointmentScreen> {
  DateTime _selectedDate = DateTime.now();
  String? _selectedTime; // Null by default so the user must select it!
  String? _appointmentType; // Null by default so the user must select it!
  final TextEditingController _reasonController = TextEditingController();

  final List<String> _times = [
    '08:00 AM',
    '09:00 AM',
    '10:00 AM',
    '11:00 AM',
    '02:00 PM',
    '03:00 PM',
    '04:00 PM',
    '05:00 PM',
    '06:00 PM',
    '07:00 PM',
  ];
  final List<String> _types = ['New Patient', 'Follow-up'];

  Future<void> _selectDate(BuildContext context) async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate,
      firstDate: DateTime.now(),
      lastDate: DateTime.now().add(const Duration(days: 90)),
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: ColorScheme.light(
              primary: AppTheme.primaryColor,
              onPrimary: Colors.white,
              onSurface: AppTheme.textPrimary,
            ),
          ),
          child: child!,
        );
      },
    );
    if (picked != null && picked != _selectedDate) {
      setState(() => _selectedDate = picked);
    }
  }

  @override
  Widget build(BuildContext context) {
    final formattedDate = DateFormat('EEEE, MMM d, yyyy').format(_selectedDate);

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(
            Icons.arrow_back_ios_new_rounded,
            color: AppTheme.textPrimary,
            size: 20,
          ),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          'Book Appointment',
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
              // Appointment Date Selector (Dynamic Date Picker)
              Text(
                'Appointment Date',
                style: GoogleFonts.plusJakartaSans(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: AppTheme.textPrimary,
                ),
              ),
              const SizedBox(height: 8),
              GestureDetector(
                onTap: () => _selectDate(context),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 14,
                  ),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFAFCFD),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: const Color(0xFFEDF1F5)),
                  ),
                  child: Row(
                    children: [
                      const Icon(
                        Icons.calendar_month_outlined,
                        color: AppTheme.primaryColor,
                        size: 20,
                      ),
                      const SizedBox(width: 12),
                      Text(
                        formattedDate,
                        style: GoogleFonts.plusJakartaSans(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: AppTheme.textPrimary,
                        ),
                      ),
                      const Spacer(),
                      const Icon(
                        Icons.chevron_right_rounded,
                        color: AppTheme.textSecondary,
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 20),

              // Appointment Time Slot Selector (Matching Image 2)
              Text(
                'Appointment Time',
                style: GoogleFonts.plusJakartaSans(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: AppTheme.textPrimary,
                ),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 10,
                runSpacing: 10,
                children: _times.map((t) {
                  final isSelected = t == _selectedTime;
                  return GestureDetector(
                    onTap: () => setState(() => _selectedTime = t),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 10,
                      ),
                      decoration: BoxDecoration(
                        color: isSelected
                            ? AppTheme.primaryLight
                            : Colors.white,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: isSelected
                              ? AppTheme.primaryColor
                              : const Color(0xFFEDF1F5),
                          width: isSelected ? 1.5 : 1,
                        ),
                      ),
                      child: Text(
                        t,
                        style: GoogleFonts.plusJakartaSans(
                          fontSize: 13,
                          fontWeight: isSelected
                              ? FontWeight.bold
                              : FontWeight.w500,
                          color: isSelected
                              ? AppTheme.primaryColor
                              : AppTheme.textPrimary,
                        ),
                      ),
                    ),
                  );
                }).toList(),
              ),
              const SizedBox(height: 20),

              // Appointment Type Dropdown (New Patient / Follow-up)
              Text(
                'Appointment Type',
                style: GoogleFonts.plusJakartaSans(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: AppTheme.textPrimary,
                ),
              ),
              const SizedBox(height: 8),
              DropdownButtonFormField<String>(
                initialValue: _appointmentType,
                hint: Text(
                  'Select Appointment Type',
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 14,
                    color: AppTheme.textSecondary,
                  ),
                ),
                decoration: InputDecoration(
                  prefixIcon: const Icon(
                    Icons.person_outline_rounded,
                    color: AppTheme.primaryColor,
                  ),
                  fillColor: const Color(0xFFFAFCFD),
                ),
                items: _types.map((type) {
                  return DropdownMenuItem(
                    value: type,
                    child: Text(
                      type,
                      style: GoogleFonts.plusJakartaSans(fontSize: 14),
                    ),
                  );
                }).toList(),
                onChanged: (val) {
                  if (val != null) setState(() => _appointmentType = val);
                },
              ),
              const SizedBox(height: 20),

              // Reason for Visit Input (0/200)
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Reason for Visit',
                    style: GoogleFonts.plusJakartaSans(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: AppTheme.textPrimary,
                    ),
                  ),
                  Text(
                    '${_reasonController.text.length}/200',
                    style: GoogleFonts.plusJakartaSans(
                      fontSize: 12,
                      color: AppTheme.textLight,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _reasonController,
                maxLines: 3,
                maxLength: 200,
                onChanged: (_) => setState(() {}),
                decoration: InputDecoration(
                  counterText: '',
                  hintText: 'Describe your symptoms...',
                  fillColor: const Color(0xFFFAFCFD),
                  filled: true,
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(16),
                    borderSide: const BorderSide(color: Color(0xFFE2E8F0), width: 1),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(16),
                    borderSide: const BorderSide(color: AppTheme.primaryColor, width: 1.5),
                  ),
                  contentPadding: const EdgeInsets.all(16),
                ),
              ),
              const SizedBox(height: 40),

              // Continue Button
              SizedBox(
                width: double.infinity,
                height: 52,
                child: ElevatedButton(
                  onPressed: () {
                    if (_selectedTime == null) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text(
                            'Please select an appointment time',
                          ),
                        ),
                      );
                      return;
                    }

                    if (_appointmentType == null) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text(
                            'Please select appointment type',
                          ),
                        ),
                      );
                      return;
                    }

                    // Save draft details (Payment method will default to EVC Plus)
                    context.read<AppState>().updateDraftBooking(
                      date: formattedDate,
                      time: _selectedTime!,
                      appointmentType: _appointmentType!,
                      reasonForVisit: _reasonController.text,
                      paymentMethod: 'EVC Plus',
                    );

                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => const PatientInfoScreen(),
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
