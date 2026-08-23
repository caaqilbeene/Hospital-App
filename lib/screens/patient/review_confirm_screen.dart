import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import '../../config/app_theme.dart';
import '../../services/app_state.dart';
import 'payment_screen.dart';

import '../../models/appointment_model.dart';
import '../../models/doctor_model.dart';

class ReviewConfirmScreen extends StatelessWidget {
  const ReviewConfirmScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final appState = context.watch<AppState>();
    final draft = appState.currentDraftBooking;

    if (draft == null) {
      return const Scaffold(
        body: Center(child: Text('No active booking draft.')),
      );
    }

    DoctorModel? selectedDoctor;
    try {
      selectedDoctor = appState.doctors.cast<DoctorModel?>().firstWhere(
        (d) => d?.id == draft.doctorId,
        orElse: () => null,
      );
    } catch (_) {}

    final double fee = (selectedDoctor != null && selectedDoctor.activePrice > 0)
        ? selectedDoctor.activePrice
        : (draft.amount > 0 ? draft.amount : (selectedDoctor?.consultationFee ?? 15.0));

    final finalBooking = (draft.amount != fee)
        ? AppointmentModel(
            id: draft.id,
            referenceId: draft.referenceId,
            doctorId: draft.doctorId,
            doctorName: draft.doctorName,
            doctorSpecialty: draft.doctorSpecialty,
            doctorImageUrl: draft.doctorImageUrl,
            hospitalName: draft.hospitalName,
            date: draft.date,
            time: draft.time,
            appointmentType: draft.appointmentType,
            patientName: draft.patientName,
            patientPhone: draft.patientPhone,
            patientAge: draft.patientAge,
            patientGender: draft.patientGender,
            patientImageUrl: draft.patientImageUrl,
            reasonForVisit: draft.reasonForVisit,
            paymentMethod: draft.paymentMethod,
            amount: fee,
            queueNumber: draft.queueNumber,
            status: draft.status,
            createdAt: draft.createdAt,
          )
        : draft;

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
          'Review & Confirm',
          style: GoogleFonts.plusJakartaSans(
            fontSize: 18,
            fontWeight: FontWeight.bold,
            color: AppTheme.textPrimary,
          ),
        ),
      ),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(horizontal: 20.0, vertical: 16.0),
                child: Column(
                  children: [
                    _buildSummaryItem(Icons.person_rounded, 'Doctor', finalBooking.doctorName),
                    _buildSummaryItem(Icons.local_hospital_rounded, 'Hospital', finalBooking.hospitalName),
                    _buildSummaryItem(Icons.calendar_month_rounded, 'Date', finalBooking.date),
                    _buildSummaryItem(Icons.access_time_rounded, 'Time', finalBooking.time),
                    _buildSummaryItem(Icons.medical_services_rounded, 'Appointment Type', finalBooking.appointmentType),
                    _buildSummaryItem(Icons.person_outline_rounded, 'Patient', finalBooking.patientName),
                    _buildSummaryItem(Icons.cake_rounded, 'Age', '${finalBooking.patientAge} years old'),
                    _buildSummaryItem(Icons.wc_rounded, 'Sex', finalBooking.patientGender),
                    if (finalBooking.reasonForVisit.isNotEmpty)
                      _buildSummaryItem(Icons.note_alt_outlined, 'Reason for Visit', finalBooking.reasonForVisit),
                    _buildSummaryItem(Icons.attach_money_rounded, 'Appointment Fee', '\$${fee.toStringAsFixed(2)}'),
                    _buildSummaryItem(Icons.format_list_numbered_rounded, 'Queue Number', '${finalBooking.queueNumber}'),

                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 16.0),
                      child: Divider(color: Color(0xFFEDF1F5), thickness: 1.5),
                    ),

                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          'Total Amount',
                          style: GoogleFonts.plusJakartaSans(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            color: AppTheme.textPrimary,
                          ),
                        ),
                        Text(
                          '\$${fee.toStringAsFixed(2)}',
                          style: GoogleFonts.plusJakartaSans(
                            fontSize: 22,
                            fontWeight: FontWeight.bold,
                            color: AppTheme.primaryColor,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),

            // Bottom CTA Confirm & Pay
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: Colors.white,
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.04),
                    blurRadius: 16,
                    offset: const Offset(0, -4),
                  ),
                ],
              ),
              child: SizedBox(
                width: double.infinity,
                height: 54,
                child: ElevatedButton(
                  onPressed: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => PaymentScreen(booking: finalBooking),
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
                    'Confirm & Pay',
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
      ),
    );
  }

  Widget _buildSummaryItem(IconData icon, String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10.0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: AppTheme.textSecondary, size: 20),
          const SizedBox(width: 14),
          Text(
            label,
            style: GoogleFonts.plusJakartaSans(
              fontSize: 14,
              color: AppTheme.textSecondary,
            ),
          ),
          const SizedBox(width: 20),
          Expanded(
            child: Text(
              value,
              textAlign: TextAlign.end,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: GoogleFonts.plusJakartaSans(
                fontSize: 14,
                fontWeight: FontWeight.bold,
                color: AppTheme.textPrimary,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
