import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import '../../config/app_theme.dart';
import '../../models/doctor_model.dart';
import '../../services/app_state.dart';
import '../../widgets/network_or_asset_image.dart';
import 'book_appointment_screen.dart';
import 'messages_screen.dart';

class DoctorProfileScreen extends StatelessWidget {
  final DoctorModel doctor;
  const DoctorProfileScreen({super.key, required this.doctor});

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
          'Doctor Profile',
          style: GoogleFonts.plusJakartaSans(
            fontSize: 18,
            fontWeight: FontWeight.bold,
            color: AppTheme.textPrimary,
          ),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.share_outlined, color: AppTheme.textPrimary, size: 20),
            onPressed: () {},
          ),
          IconButton(
            icon: const Icon(Icons.favorite_border_rounded, color: AppTheme.textPrimary, size: 20),
            onPressed: () {},
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 20.0, vertical: 12.0),
              child: Column(
                children: [
                  Center(
                    child: NetworkOrAssetImage(
                      imageUrl: doctor.imageUrl,
                      width: 140,
                      height: 140,
                      borderRadius: BorderRadius.circular(70),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        doctor.name,
                        style: GoogleFonts.plusJakartaSans(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                          color: AppTheme.textPrimary,
                        ),
                      ),
                      const SizedBox(width: 6),
                      const Icon(
                        Icons.check_circle_rounded,
                        color: Color(0xFF0F8CFF),
                        size: 15,
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '${doctor.specialty} • ${doctor.hospital}',
                    style: GoogleFonts.plusJakartaSans(
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                      color: AppTheme.primaryColor,
                    ),
                  ),

                  const SizedBox(height: 8),

                  // Active Status Indicator (Listens dynamically to AppState doctor status!)
                  const SizedBox.shrink(),
                  const SizedBox(height: 24),

                  // 3 Stat Cards Row (Experience, Patients, Working Hours)
                  Row(
                    children: [
                      Expanded(
                        child: _buildStatCard(
                          'Experience',
                          doctor.experience,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: _buildStatCard(
                          'Patients',
                          doctor.patientsCount,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: _buildStatCard(
                          'Working Hours',
                          doctor.workingHours,
                          isLongText: true,
                        ),
                      ),
                    ],
                  ),

                  const SizedBox(height: 28),

                  // About Doctor Header & Paragraph
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      'About Doctor',
                      style: GoogleFonts.plusJakartaSans(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: AppTheme.textPrimary,
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFAFCFD),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: const Color(0xFFE2E8F0), width: 1),
                    ),
                    child: Text(
                      doctor.about.trim().isNotEmpty
                          ? doctor.about
                          : 'Experienced and dedicated ${doctor.specialty} specialist providing expert medical care at ${doctor.hospital}.',
                      style: GoogleFonts.plusJakartaSans(
                        fontSize: 14,
                        color: AppTheme.textSecondary,
                        height: 1.5,
                      ),
                    ),

                  ),
                ],
              ),
            ),
          ),

          // Bottom Bar: Persistent Section with Consultation Fee and Book Appointment CTA
          Container(
            padding: EdgeInsets.only(
              left: 20,
              right: 20,
              top: 14,
              bottom: 16 + MediaQuery.of(context).padding.bottom,
            ),
            decoration: const BoxDecoration(
              color: Colors.white,
              boxShadow: [
                BoxShadow(
                  color: Color(0x0D000000),
                  blurRadius: 10,
                  offset: Offset(0, -4),
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Consultation Fee Row directly above Book Appointment button
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'Consultation Fee:',
                      style: GoogleFonts.plusJakartaSans(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: AppTheme.textSecondary,
                      ),
                    ),
                    Row(
                      children: [
                        if (doctor.discountFee != null &&
                            doctor.discountFee! > 0 &&
                            doctor.discountFee! < doctor.consultationFee) ...[
                          Text(
                            '\$${doctor.consultationFee.toStringAsFixed(2)}',
                            style: GoogleFonts.plusJakartaSans(
                              fontSize: 13,
                              color: Colors.grey,
                              decoration: TextDecoration.lineThrough,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            '\$${doctor.activePrice.toStringAsFixed(2)}',
                            style: GoogleFonts.plusJakartaSans(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                              color: const Color(0xFF10B981),
                            ),
                          ),
                        ] else
                          Text(
                            doctor.consultationFee > 0
                                ? '\$${doctor.consultationFee.toStringAsFixed(2)}'
                                : 'Free',
                            style: GoogleFonts.plusJakartaSans(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                              color: AppTheme.primaryColor,
                            ),
                          ),
                      ],
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    GestureDetector(
                      onTap: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => MessagesScreen(doctor: doctor),
                          ),
                        );
                      },
                      child: Container(
                        width: 52,
                        height: 52,
                        decoration: BoxDecoration(
                          color: const Color(0xFFEAF5F2),
                          shape: BoxShape.circle,
                          border: Border.all(color: AppTheme.primaryColor.withValues(alpha: 0.15), width: 1),
                        ),
                        child: const Icon(
                          CupertinoIcons.chat_bubble,
                          color: AppTheme.primaryColor,
                          size: 22,
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: SizedBox(
                        height: 52,
                        child: ElevatedButton(
                          onPressed: () {
                            context.read<AppState>().startDraftBooking(doctor);
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => BookAppointmentScreen(doctor: doctor),
                              ),
                            );
                          },
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppTheme.primaryColor,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(16),
                            ),
                            elevation: 0,
                          ),
                          child: Text(
                            'Book Appointment',
                            style: GoogleFonts.plusJakartaSans(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                              color: Colors.white,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatCard(String label, String value, {bool isLongText = false}) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 8),
      decoration: BoxDecoration(
        color: const Color(0xFFFAFCFD),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppTheme.primaryColor.withOpacity(0.2), width: 1.2),
      ),
      child: Column(
        children: [
          Text(
            label,
            textAlign: TextAlign.center,
            style: GoogleFonts.plusJakartaSans(
              fontSize: 11,
              color: AppTheme.textSecondary,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            value,
            textAlign: TextAlign.center,
            maxLines: isLongText ? 2 : 1,
            style: GoogleFonts.plusJakartaSans(
              fontSize: isLongText ? 11 : 14,
              fontWeight: FontWeight.bold,
              color: AppTheme.primaryColor,
            ),
          ),
        ],
      ),
    );
  }
}
