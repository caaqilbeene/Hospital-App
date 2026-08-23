import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import '../../config/app_theme.dart';
import '../../models/appointment_model.dart';
import '../../services/app_state.dart';
import 'main_patient_layout.dart';

class AppointmentConfirmedScreen extends StatelessWidget {
  final AppointmentModel booking;
  const AppointmentConfirmedScreen({super.key, required this.booking});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 20.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Spacer(),

              // Big Green Checkmark Icon (Matching Image 2 Screen 6/10)
              Container(
                width: 96,
                height: 96,
                decoration: const BoxDecoration(
                  color: AppTheme.primaryColor,
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.check_rounded,
                  color: Colors.white,
                  size: 56,
                ),
              ),

              const SizedBox(height: 28),

              Text(
                'Appointment Confirmed!',
                style: GoogleFonts.plusJakartaSans(
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                  color: AppTheme.textPrimary,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Your appointment has been booked successfully.',
                textAlign: TextAlign.center,
                style: GoogleFonts.plusJakartaSans(
                  fontSize: 14,
                  color: AppTheme.textSecondary,
                ),
              ),

              const SizedBox(height: 36),

              // Details Summary Container (Queue Number, Reference ID, Payment)
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: const Color(0xFFFAFCFD),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: const Color(0xFFEDF1F5)),
                ),
                child: Column(
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Row(
                          children: [
                            const Icon(Icons.format_list_numbered_rounded, size: 18, color: AppTheme.textSecondary),
                            const SizedBox(width: 8),
                            Text('Queue Number', style: GoogleFonts.plusJakartaSans(fontSize: 14, color: AppTheme.textSecondary)),
                          ],
                        ),
                        Text(
                          '${booking.queueNumber}',
                          style: GoogleFonts.plusJakartaSans(fontSize: 14, fontWeight: FontWeight.bold, color: AppTheme.primaryColor),
                        ),
                      ],
                    ),
                    const Divider(height: 24, color: Color(0xFFEDF1F5)),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Row(
                          children: [
                            const Icon(Icons.qr_code_rounded, size: 18, color: AppTheme.textSecondary),
                            const SizedBox(width: 8),
                            Text('Reference ID', style: GoogleFonts.plusJakartaSans(fontSize: 14, color: AppTheme.textSecondary)),
                          ],
                        ),
                        Text(
                          booking.referenceId,
                          style: GoogleFonts.plusJakartaSans(fontSize: 14, fontWeight: FontWeight.bold, color: AppTheme.textPrimary),
                        ),
                      ],
                    ),
                    const Divider(height: 24, color: Color(0xFFEDF1F5)),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Row(
                          children: [
                            const Icon(Icons.check_circle_outline_rounded, size: 18, color: AppTheme.textSecondary),
                            const SizedBox(width: 8),
                            Text('Payment', style: GoogleFonts.plusJakartaSans(fontSize: 14, color: AppTheme.textSecondary)),
                          ],
                        ),
                        const SizedBox(width: 12),
                        Flexible(
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.end,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              _buildCardLogo(booking.paymentMethod),
                              if (booking.paymentMethod.toLowerCase().contains('visa') ||
                                  booking.paymentMethod.toLowerCase().contains('mastercard'))
                                const SizedBox(width: 6),
                              Flexible(
                                child: Text(
                                  booking.paymentMethod.toLowerCase().contains('visa') ||
                                  booking.paymentMethod.toLowerCase().contains('master')
                                      ? 'Paid'
                                      : 'Paid (${booking.paymentMethod})',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: GoogleFonts.plusJakartaSans(fontSize: 14, fontWeight: FontWeight.bold, color: AppTheme.successGreen),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),

              const Spacer(),

              // Add to Calendar Outlined Button
              SizedBox(
                width: double.infinity,
                height: 50,
                child: OutlinedButton.icon(
                  onPressed: () {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Appointment added to your calendar!')),
                    );
                  },
                  icon: const Icon(Icons.calendar_today_rounded, size: 18, color: AppTheme.primaryColor),
                  label: Text(
                    'Add to Calendar',
                    style: GoogleFonts.plusJakartaSans(
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                      color: AppTheme.primaryColor,
                    ),
                  ),
                  style: OutlinedButton.styleFrom(
                    side: const BorderSide(color: AppTheme.borderColor),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                  ),
                ),
              ),

              const SizedBox(height: 12),

              // Go to Home Solid Green Button
              SizedBox(
                width: double.infinity,
                height: 52,
                child: ElevatedButton.icon(
                  onPressed: () {
                    context.read<AppState>().setPatientNavIndex(0); // Redirect to Home Dashboard!
                    Navigator.pushAndRemoveUntil(
                      context,
                      MaterialPageRoute(builder: (_) => const MainPatientLayout()),
                      (route) => false,
                    );
                  },
                  icon: const Icon(Icons.home_outlined, color: Colors.white),
                  label: Text(
                    'Go to Home',
                    style: GoogleFonts.plusJakartaSans(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.primaryColor,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                  ),
                ),
              ),

              const SizedBox(height: 16),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildCardLogo(String method) {
    if (method.toLowerCase().contains('visa')) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
        decoration: BoxDecoration(
          color: const Color(0xFF1A1F71), // Visa Blue
          borderRadius: BorderRadius.circular(4),
        ),
        child: Text(
          'VISA',
          style: GoogleFonts.merriweather(
            color: Colors.white,
            fontWeight: FontWeight.w900,
            fontSize: 10,
            fontStyle: FontStyle.italic,
          ),
        ),
      );
    } else if (method.toLowerCase().contains('mastercard')) {
      return SizedBox(
        width: 24,
        height: 14,
        child: Stack(
          children: [
            Positioned(
              left: 0,
              child: Container(
                width: 12,
                height: 12,
                decoration: const BoxDecoration(
                  color: Color(0xFFEB001B), // Mastercard Red
                  shape: BoxShape.circle,
                ),
              ),
            ),
            Positioned(
              left: 8,
              child: Container(
                width: 12,
                height: 12,
                decoration: BoxDecoration(
                  color: const Color(0xFFFF5F00).withOpacity(0.85), // Mastercard Orange
                  shape: BoxShape.circle,
                ),
              ),
            ),
          ],
        ),
      );
    }
    return const SizedBox.shrink();
  }
}
