import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import '../../config/app_theme.dart';
import '../../services/app_state.dart';

class AppointmentHistoryScreen extends StatelessWidget {
  const AppointmentHistoryScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final appState = context.watch<AppState>();
    final appointments = appState.appointments;
    final totalPaid = appointments.fold<double>(0.0, (sum, apt) => sum + apt.amount);

    return Scaffold(
      backgroundColor: const Color(0xFFF4F6F8),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, color: AppTheme.textPrimary, size: 20),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          'Appointment History',
          style: GoogleFonts.plusJakartaSans(
            color: AppTheme.textPrimary,
            fontWeight: FontWeight.bold,
            fontSize: 18,
          ),
        ),
        centerTitle: true,
      ),
      body: SafeArea(
        child: Column(
          children: [
            // 1. Overview Summary Card
            Container(
              margin: const EdgeInsets.all(20.0),
              padding: const EdgeInsets.all(20.0),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [AppTheme.primaryColor, Color(0xFF1E88E5)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(24),
                boxShadow: [
                  BoxShadow(
                    color: AppTheme.primaryColor.withOpacity(0.3),
                    blurRadius: 16,
                    offset: const Offset(0, 8),
                  ),
                ],
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Total Bookings',
                          style: GoogleFonts.plusJakartaSans(
                            color: Colors.white70,
                            fontSize: 13,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Row(
                          children: [
                            const Icon(Icons.calendar_month_rounded, color: Colors.white, size: 20),
                            const SizedBox(width: 8),
                            Text(
                              '${appointments.length}',
                              style: GoogleFonts.plusJakartaSans(
                                color: Colors.white,
                                fontSize: 24,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  Container(
                    width: 1,
                    height: 50,
                    color: Colors.white24,
                  ),
                  const SizedBox(width: 20),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Total Amount Paid',
                          style: GoogleFonts.plusJakartaSans(
                            color: Colors.white70,
                            fontSize: 13,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Row(
                          children: [
                            const Icon(Icons.payments_rounded, color: Colors.white, size: 20),
                            const SizedBox(width: 8),
                            Text(
                              '\$${totalPaid.toStringAsFixed(2)}',
                              style: GoogleFonts.plusJakartaSans(
                                color: Colors.white,
                                fontSize: 24,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),

            // 2. Bookings List Title
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24.0),
              child: Row(
                children: [
                  Text(
                    'All Bookings List',
                    style: GoogleFonts.plusJakartaSans(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: AppTheme.textPrimary,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),

            // 3. Scrollable List View
            Expanded(
              child: appointments.isEmpty
                  ? Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            Icons.calendar_today_outlined,
                            size: 64,
                            color: AppTheme.textLight.withOpacity(0.5),
                          ),
                          const SizedBox(height: 16),
                          Text(
                            'No appointments booked yet.',
                            style: GoogleFonts.plusJakartaSans(
                              color: AppTheme.textSecondary,
                              fontSize: 14,
                            ),
                          ),
                        ],
                      ),
                    )
                  : ListView.builder(
                      padding: const EdgeInsets.symmetric(horizontal: 20.0),
                      itemCount: appointments.length,
                      itemBuilder: (context, index) {
                        final apt = appointments[index];
                        return Container(
                          margin: const EdgeInsets.only(bottom: 14),
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(color: const Color(0xFFEDF1F5)),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withOpacity(0.015),
                                blurRadius: 10,
                                offset: const Offset(0, 4),
                              ),
                            ],
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              // Row 1: Doctor Info
                              Row(
                                children: [
                                  CircleAvatar(
                                    radius: 20,
                                    backgroundColor: AppTheme.primaryLight,
                                    backgroundImage: apt.doctorImageUrl.isNotEmpty
                                        ? NetworkImage(apt.doctorImageUrl)
                                        : null,
                                    child: apt.doctorImageUrl.isEmpty
                                        ? const Icon(
                                            Icons.medical_services_outlined,
                                            color: AppTheme.primaryColor,
                                            size: 20,
                                          )
                                        : null,
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          apt.doctorName,
                                          style: GoogleFonts.plusJakartaSans(
                                            fontWeight: FontWeight.bold,
                                            fontSize: 14,
                                            color: AppTheme.textPrimary,
                                          ),
                                        ),
                                        Text(
                                          apt.doctorSpecialty,
                                          style: GoogleFonts.plusJakartaSans(
                                            fontSize: 12,
                                            color: AppTheme.textSecondary,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                    decoration: BoxDecoration(
                                      color: const Color(0xFFE3F2FD),
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                    child: Text(
                                      'Queue #${apt.queueNumber}',
                                      style: GoogleFonts.plusJakartaSans(
                                        fontSize: 11,
                                        fontWeight: FontWeight.bold,
                                        color: Colors.blue.shade700,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 4),
                                  IconButton(
                                    icon: const Icon(
                                      Icons.delete_outline_rounded,
                                      color: Color(0xFFEF4444),
                                      size: 20,
                                    ),
                                    padding: EdgeInsets.zero,
                                    constraints: const BoxConstraints(),
                                    tooltip: 'Tirtir Ballanta',
                                    onPressed: () {
                                      _confirmDeleteDialog(context, appState, apt.id);
                                    },
                                  ),
                                ],
                              ),
                              const SizedBox(height: 10),
                              // Patient Info Row with Exact Patient Photo Avatar
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                decoration: BoxDecoration(
                                  color: const Color(0xFFEFF6FF),
                                  borderRadius: BorderRadius.circular(12),
                                  border: Border.all(color: const Color(0xFFDBEAFE)),
                                ),
                                child: Row(
                                  children: [
                                    CircleAvatar(
                                      radius: 14,
                                      backgroundColor: const Color(0xFF2563EB),
                                      backgroundImage: (apt.patientImageUrl != null && apt.patientImageUrl!.trim().isNotEmpty)
                                          ? NetworkImage(apt.patientImageUrl!.trim())
                                          : null,
                                      child: (apt.patientImageUrl == null || apt.patientImageUrl!.trim().isEmpty)
                                          ? const Icon(Icons.person_rounded, size: 16, color: Colors.white)
                                          : null,
                                    ),
                                    const SizedBox(width: 10),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            'Patient: ${apt.patientName}',
                                            style: GoogleFonts.plusJakartaSans(
                                              fontSize: 12,
                                              fontWeight: FontWeight.bold,
                                              color: const Color(0xFF1E3A8A),
                                            ),
                                          ),
                                          if (apt.patientPhone.isNotEmpty)
                                            Text(
                                              'Phone: ${apt.patientPhone}',
                                              style: GoogleFonts.plusJakartaSans(
                                                fontSize: 11,
                                                color: const Color(0xFF3B82F6),
                                              ),
                                            ),
                                        ],
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              const Padding(
                                padding: EdgeInsets.symmetric(vertical: 12),
                                child: Divider(height: 1, color: Color(0xFFEDF1F5)),
                              ),
                              // Row 2: Date & Time Info
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                decoration: BoxDecoration(
                                  color: const Color(0xFFF8FAFC),
                                  borderRadius: BorderRadius.circular(12),
                                  border: Border.all(color: const Color(0xFFF1F5F9)),
                                ),
                                child: Row(
                                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                  children: [
                                    Row(
                                      children: [
                                        const Icon(Icons.calendar_today_rounded, size: 14, color: AppTheme.primaryColor),
                                        const SizedBox(width: 8),
                                        Text(
                                          apt.date,
                                          style: GoogleFonts.plusJakartaSans(
                                            fontSize: 12,
                                            fontWeight: FontWeight.bold,
                                            color: AppTheme.textPrimary,
                                          ),
                                        ),
                                      ],
                                    ),
                                    Row(
                                      children: [
                                        const Icon(Icons.access_time_rounded, size: 14, color: AppTheme.primaryColor),
                                        const SizedBox(width: 8),
                                        Text(
                                          apt.time,
                                          style: GoogleFonts.plusJakartaSans(
                                            fontSize: 12,
                                            fontWeight: FontWeight.bold,
                                            color: AppTheme.textPrimary,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(height: 12),
                              // Row 3: Payment & Status Badge
                              Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  // Payment info
                                  Row(
                                    children: [
                                      const Icon(Icons.payment_rounded, size: 14, color: AppTheme.successGreen),
                                      const SizedBox(width: 6),
                                      Text(
                                        'Paid via ${apt.paymentMethod}',
                                        style: GoogleFonts.plusJakartaSans(
                                          fontSize: 12,
                                          fontWeight: FontWeight.w600,
                                          color: AppTheme.successGreen,
                                        ),
                                      ),
                                    ],
                                  ),
                                  // Status Badge
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                    decoration: BoxDecoration(
                                      color: const Color(0xFFDCFCE7),
                                      borderRadius: BorderRadius.circular(10),
                                    ),
                                    child: Text(
                                      apt.status,
                                      style: GoogleFonts.plusJakartaSans(
                                        fontSize: 11,
                                        fontWeight: FontWeight.bold,
                                        color: const Color(0xFF15803D),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }

  void _confirmDeleteDialog(BuildContext context, AppState appState, String id) {
    showDialog(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: Text(
            'Tirtir Ballanta (Permanently Delete)',
            style: GoogleFonts.plusJakartaSans(
              fontWeight: FontWeight.bold,
              fontSize: 16,
              color: const Color(0xFF0F172A),
            ),
          ),
          content: Text(
            'Ma hubtaa inaad ballantan si joogto ah uga tirtirto nidaamka iyo Supabase?',
            style: GoogleFonts.plusJakartaSans(
              fontSize: 13,
              color: const Color(0xFF475569),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: Text(
                'Kanoqo',
                style: GoogleFonts.plusJakartaSans(
                  color: const Color(0xFF64748B),
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            ElevatedButton(
              onPressed: () async {
                Navigator.pop(ctx);
                await appState.deleteAppointment(id);
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFEF4444),
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
              child: Text(
                'Tirtir',
                style: GoogleFonts.plusJakartaSans(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}
