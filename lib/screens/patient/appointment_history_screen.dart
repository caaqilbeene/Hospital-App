import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import '../../config/app_theme.dart';
import '../../models/appointment_model.dart';
import '../../services/app_state.dart';

class AppointmentHistoryScreen extends StatefulWidget {
  const AppointmentHistoryScreen({super.key});

  @override
  State<AppointmentHistoryScreen> createState() => _AppointmentHistoryScreenState();
}

class _AppointmentHistoryScreenState extends State<AppointmentHistoryScreen> {
  String _selectedFilter = 'All'; // 'All', 'Doctors', 'Nurses'

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<AppState>().fetchAppointmentsAndNurseOrders();
    });
  }

  bool _isNurseApt(AppointmentModel apt) {
    final docId = apt.doctorId.toLowerCase();
    final docSpec = apt.doctorSpecialty.toLowerCase();
    final docName = apt.doctorName.toLowerCase();
    final aptType = apt.appointmentType.toLowerCase();
    return docId.startsWith('nurse') ||
        docSpec.contains('home care') ||
        docName.contains('nurse') ||
        aptType.contains('home care');
  }

  @override
  Widget build(BuildContext context) {
    final appState = context.watch<AppState>();
    final allAppointments = appState.appointments;

    DateTime parseDateSafe(String raw) {
      if (raw.trim().isEmpty) return DateTime.fromMillisecondsSinceEpoch(0);
      final dt = DateTime.tryParse(raw.trim());
      if (dt != null) return dt;
      final intVal = int.tryParse(raw.trim());
      if (intVal != null) return DateTime.fromMillisecondsSinceEpoch(intVal);
      return DateTime.fromMillisecondsSinceEpoch(0);
    }

    final sortedAppointments = List<AppointmentModel>.from(allAppointments)
      ..sort((a, b) => parseDateSafe(b.createdAt).compareTo(parseDateSafe(a.createdAt)));

    final doctorAppointments = sortedAppointments.where((a) => !_isNurseApt(a)).toList();
    final nurseAppointments = sortedAppointments.where((a) => _isNurseApt(a)).toList();

    final List<AppointmentModel> displayedAppointments;
    if (_selectedFilter == 'Doctors') {
      displayedAppointments = doctorAppointments;
    } else if (_selectedFilter == 'Nurses') {
      displayedAppointments = nurseAppointments;
    } else {
      displayedAppointments = sortedAppointments;
    }

    final totalPaid = displayedAppointments.fold<double>(0.0, (sum, apt) => sum + apt.amount);

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
        child: RefreshIndicator(
          onRefresh: () async {
            await context.read<AppState>().fetchAppointmentsAndNurseOrders();
          },
          child: Column(
            children: [
            // 1. Overview Summary Card
            Container(
              margin: const EdgeInsets.fromLTRB(20, 10, 20, 16),
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
                          _selectedFilter == 'Doctors'
                              ? 'Doctor Bookings'
                              : (_selectedFilter == 'Nurses' ? 'Nurse Orders' : 'Total Bookings'),
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
                              '${displayedAppointments.length}',
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

            // 2. Filter Category Tabs (All / Doctors / Nurses)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20.0),
              child: Row(
                children: [
                  _buildFilterTab(
                    title: 'Dhammaan',
                    count: allAppointments.length,
                    filterKey: 'All',
                    icon: Icons.grid_view_rounded,
                  ),
                  const SizedBox(width: 8),
                  _buildFilterTab(
                    title: 'Dhaqaatiirta',
                    count: doctorAppointments.length,
                    filterKey: 'Doctors',
                    icon: Icons.medical_services_rounded,
                  ),
                  const SizedBox(width: 8),
                  _buildFilterTab(
                    title: 'Kalkaalisada',
                    count: nurseAppointments.length,
                    filterKey: 'Nurses',
                    icon: Icons.healing_rounded,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),

            // 3. Scrollable List View
            Expanded(
              child: displayedAppointments.isEmpty
                  ? Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            Icons.calendar_today_outlined,
                            size: 56,
                            color: AppTheme.textLight.withOpacity(0.5),
                          ),
                          const SizedBox(height: 16),
                          Text(
                            _selectedFilter == 'Doctors'
                                ? 'Wax ballan dhaqtar ah kuma jiraan.'
                                : (_selectedFilter == 'Nurses'
                                    ? 'Wax dalab kalkaaliso ah kuma jiraan.'
                                    : 'Wax ballamo ah kuma jiraan.'),
                            style: GoogleFonts.plusJakartaSans(
                              color: AppTheme.textSecondary,
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    )
                  : ListView.builder(
                      padding: const EdgeInsets.symmetric(horizontal: 20.0),
                      itemCount: displayedAppointments.length,
                      itemBuilder: (context, index) {
                        final apt = displayedAppointments[index];
                        final bool isNurse = _isNurseApt(apt);
                        return Container(
                          margin: const EdgeInsets.only(bottom: 14),
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(
                              color: isNurse ? const Color(0xFFE2E8F0) : const Color(0xFFEDF1F5),
                            ),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withOpacity(0.02),
                                blurRadius: 10,
                                offset: const Offset(0, 4),
                              ),
                            ],
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              // Top Tag: Service Category Badge (Doctor vs Nurse)
                              Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                    decoration: BoxDecoration(
                                      color: isNurse ? const Color(0xFFF0FDF4) : const Color(0xFFEFF6FF),
                                      borderRadius: BorderRadius.circular(8),
                                      border: Border.all(
                                        color: isNurse ? const Color(0xFFBBF7D0) : const Color(0xFFBFDBFE),
                                      ),
                                    ),
                                    child: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Icon(
                                          isNurse ? Icons.healing_rounded : Icons.medical_services_rounded,
                                          size: 13,
                                          color: isNurse ? const Color(0xFF15803D) : const Color(0xFF1D4ED8),
                                        ),
                                        const SizedBox(width: 5),
                                        Text(
                                          isNurse ? '👩‍⚕️ Nurse Home Care' : '🩺 Doctor Appointment',
                                          style: GoogleFonts.plusJakartaSans(
                                            fontSize: 11,
                                            fontWeight: FontWeight.bold,
                                            color: isNurse ? const Color(0xFF15803D) : const Color(0xFF1D4ED8),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  if (apt.referenceId.isNotEmpty)
                                    Text(
                                      apt.referenceId,
                                      style: GoogleFonts.plusJakartaSans(
                                        fontSize: 11,
                                        fontWeight: FontWeight.w600,
                                        color: AppTheme.textSecondary,
                                      ),
                                    ),
                                ],
                              ),
                              const SizedBox(height: 12),

                              // Row 1: Doctor / Nurse Info
                              Row(
                                children: [
                                  CircleAvatar(
                                    radius: 22,
                                    backgroundColor: isNurse ? const Color(0xFFDCFCE7) : AppTheme.primaryLight,
                                    backgroundImage: apt.doctorImageUrl.isNotEmpty
                                        ? NetworkImage(apt.doctorImageUrl)
                                        : null,
                                    child: apt.doctorImageUrl.isEmpty
                                        ? Icon(
                                            isNurse ? Icons.healing_rounded : Icons.medical_services_outlined,
                                            color: isNurse ? const Color(0xFF15803D) : AppTheme.primaryColor,
                                            size: 22,
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
                                            fontSize: 15,
                                            color: AppTheme.textPrimary,
                                          ),
                                        ),
                                        Text(
                                          apt.doctorSpecialty,
                                          style: GoogleFonts.plusJakartaSans(
                                            fontSize: 12,
                                            fontWeight: FontWeight.w500,
                                            color: isNurse ? const Color(0xFF16A34A) : AppTheme.textSecondary,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                    decoration: BoxDecoration(
                                      color: isNurse ? const Color(0xFFF3E8FF) : const Color(0xFFE3F2FD),
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                    child: Text(
                                      'Queue #${apt.queueNumber}',
                                      style: GoogleFonts.plusJakartaSans(
                                        fontSize: 11,
                                        fontWeight: FontWeight.bold,
                                        color: isNurse ? const Color(0xFF7E22CE) : Colors.blue.shade700,
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
                                padding: EdgeInsets.symmetric(vertical: 10),
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
                                  // Payment info & Amount
                                  Row(
                                    children: [
                                      const Icon(Icons.payment_rounded, size: 14, color: AppTheme.successGreen),
                                      const SizedBox(width: 6),
                                      Text(
                                        '\$${apt.amount.toStringAsFixed(2)} • ${apt.paymentMethod}',
                                        style: GoogleFonts.plusJakartaSans(
                                          fontSize: 12,
                                          fontWeight: FontWeight.bold,
                                          color: AppTheme.successGreen,
                                        ),
                                      ),
                                    ],
                                  ),
                                  // Dynamic Status Badge
                                  Builder(
                                    builder: (context) {
                                      final st = apt.status.toLowerCase();
                                      Color bgColor;
                                      Color textColor;
                                      String displayStatus;

                                      if (st.contains('cancel')) {
                                        bgColor = const Color(0xFFFEE2E2);
                                        textColor = const Color(0xFFDC2626);
                                        displayStatus = 'Cancelled';
                                      } else if (st.contains('confirm')) {
                                        bgColor = const Color(0xFFDBEAFE);
                                        textColor = const Color(0xFF2563EB);
                                        displayStatus = 'Confirmed';
                                      } else if (st.contains('complete')) {
                                        bgColor = const Color(0xFFDCFCE7);
                                        textColor = const Color(0xFF15803D);
                                        displayStatus = 'Completed';
                                      } else {
                                        bgColor = const Color(0xFFFEF3C7);
                                        textColor = const Color(0xFFD97706);
                                        displayStatus = 'Pending';
                                      }

                                      return Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                        decoration: BoxDecoration(
                                          color: bgColor,
                                          borderRadius: BorderRadius.circular(10),
                                        ),
                                        child: Text(
                                          displayStatus,
                                          style: GoogleFonts.plusJakartaSans(
                                            fontSize: 11,
                                            fontWeight: FontWeight.bold,
                                            color: textColor,
                                          ),
                                        ),
                                      );
                                    },
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
      ),
    );
  }

  Widget _buildFilterTab({
    required String title,
    required int count,
    required String filterKey,
    required IconData icon,
  }) {
    final bool isSelected = _selectedFilter == filterKey;
    return Expanded(
      child: InkWell(
        onTap: () => setState(() => _selectedFilter = filterKey),
        borderRadius: BorderRadius.circular(14),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
          decoration: BoxDecoration(
            color: isSelected ? AppTheme.primaryColor : Colors.white,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: isSelected ? AppTheme.primaryColor : const Color(0xFFE2E8F0),
            ),
            boxShadow: [
              if (isSelected)
                BoxShadow(
                  color: AppTheme.primaryColor.withOpacity(0.25),
                  blurRadius: 8,
                  offset: const Offset(0, 3),
                ),
            ],
          ),
          child: Column(
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    icon,
                    size: 14,
                    color: isSelected ? Colors.white : AppTheme.textSecondary,
                  ),
                  const SizedBox(width: 4),
                  Text(
                    title,
                    style: GoogleFonts.plusJakartaSans(
                      fontSize: 12,
                      fontWeight: isSelected ? FontWeight.bold : FontWeight.w600,
                      color: isSelected ? Colors.white : AppTheme.textPrimary,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: isSelected ? Colors.white.withOpacity(0.2) : const Color(0xFFF1F5F9),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  '$count',
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                    color: isSelected ? Colors.white : AppTheme.primaryColor,
                  ),
                ),
              ),
            ],
          ),
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
