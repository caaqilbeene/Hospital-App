import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import '../../config/app_theme.dart';
import '../../models/appointment_model.dart';
import '../../services/app_state.dart';

class NurseOrdersScreen extends StatefulWidget {
  const NurseOrdersScreen({super.key});

  @override
  State<NurseOrdersScreen> createState() => _NurseOrdersScreenState();
}

class _NurseOrdersScreenState extends State<NurseOrdersScreen> {
  String _selectedFilter = 'All'; // 'All', 'Pending', 'Completed'

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<AppState>().fetchAppointmentsAndNurseOrders();
    });
  }

  bool _isNurseItem(AppointmentModel apt) {
    final docId = apt.doctorId.toLowerCase();
    final docSpec = apt.doctorSpecialty.toLowerCase();
    final docName = apt.doctorName.toLowerCase();
    final aptType = apt.appointmentType.toLowerCase();
    return docId.startsWith('nurse') ||
        docSpec.contains('home care') ||
        docName.contains('nurse') ||
        aptType.contains('home care');
  }

  DateTime _parseDateSafe(String raw) {
    if (raw.trim().isEmpty) return DateTime.fromMillisecondsSinceEpoch(0);
    final dt = DateTime.tryParse(raw.trim());
    if (dt != null) return dt;
    final intVal = int.tryParse(raw.trim());
    if (intVal != null) return DateTime.fromMillisecondsSinceEpoch(intVal);
    return DateTime.fromMillisecondsSinceEpoch(0);
  }

  @override
  Widget build(BuildContext context) {
    final appState = context.watch<AppState>();
    final allAppointments = appState.appointments;

    // Filter only Nurse Home Care visits
    final nurseVisits = allAppointments.where(_isNurseItem).toList()
      ..sort((a, b) => _parseDateSafe(b.createdAt).compareTo(_parseDateSafe(a.createdAt)));

    final List<AppointmentModel> displayedVisits;
    if (_selectedFilter == 'Pending') {
      displayedVisits = nurseVisits.where((v) => v.status.toLowerCase() != 'completed' && v.status.toLowerCase() != 'cancelled').toList();
    } else if (_selectedFilter == 'Completed') {
      displayedVisits = nurseVisits.where((v) => v.status.toLowerCase() == 'completed').toList();
    } else {
      displayedVisits = nurseVisits;
    }

    final totalSpent = nurseVisits.fold<double>(0.0, (sum, v) => sum + v.amount);

    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0.5,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, color: Color(0xFF0F172A), size: 20),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          'Nurse Home Visits',
          style: GoogleFonts.plusJakartaSans(
            color: const Color(0xFF0F172A),
            fontWeight: FontWeight.bold,
            fontSize: 18,
          ),
        ),
        centerTitle: true,
      ),
      body: SafeArea(
        child: RefreshIndicator(
          color: const Color(0xFF059669),
          onRefresh: () async {
            await context.read<AppState>().fetchAppointmentsAndNurseOrders();
          },
          child: Column(
            children: [
              // 1. Header Overview Summary Card
              Container(
                margin: const EdgeInsets.fromLTRB(16, 16, 16, 12),
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [Color(0xFF065F46), Color(0xFF059669), Color(0xFF0D9488)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(20),
                  boxShadow: [
                    BoxShadow(
                      color: const Color(0xFF059669).withValues(alpha: 0.25),
                      blurRadius: 16,
                      offset: const Offset(0, 6),
                    ),
                  ],
                ),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.2),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(Icons.medical_services_rounded, color: Colors.white, size: 28),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Kalkaalisada Guriga (Home Care)',
                            style: GoogleFonts.plusJakartaSans(
                              color: Colors.white.withValues(alpha: 0.9),
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            '${nurseVisits.length} Dalab oo Kalkaaliye',
                            style: GoogleFonts.plusJakartaSans(
                              color: Colors.white,
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.2),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        '\$${totalSpent.toStringAsFixed(2)}',
                        style: GoogleFonts.plusJakartaSans(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 14,
                        ),
                      ),
                    ),
                  ],
                ),
              ),

              // 2. Filter Pills
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                child: Row(
                  children: [
                    _buildFilterChip('All', 'Dhammaan (${nurseVisits.length})'),
                    const SizedBox(width: 8),
                    _buildFilterChip('Pending', 'Socda / Pending'),
                    const SizedBox(width: 8),
                    _buildFilterChip('Completed', 'Dhamaystiran'),
                  ],
                ),
              ),
              const SizedBox(height: 8),

              // 3. Nurse Visits List
              Expanded(
                child: displayedVisits.isEmpty
                    ? _buildEmptyState()
                    : ListView.separated(
                        physics: const AlwaysScrollableScrollPhysics(),
                        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                        itemCount: displayedVisits.length,
                        separatorBuilder: (_, _) => const SizedBox(height: 12),
                        itemBuilder: (context, index) {
                          final visit = displayedVisits[index];
                          return _buildNurseVisitCard(context, visit);
                        },
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildFilterChip(String filterKey, String label) {
    final isSelected = _selectedFilter == filterKey;
    return GestureDetector(
      onTap: () {
        setState(() => _selectedFilter = filterKey);
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: isSelected ? const Color(0xFF059669) : Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isSelected ? const Color(0xFF059669) : const Color(0xFFE2E8F0),
          ),
          boxShadow: isSelected
              ? [
                  BoxShadow(
                    color: const Color(0xFF059669).withValues(alpha: 0.2),
                    blurRadius: 8,
                    offset: const Offset(0, 3),
                  ),
                ]
              : [],
        ),
        child: Text(
          label,
          style: GoogleFonts.plusJakartaSans(
            fontSize: 12,
            fontWeight: isSelected ? FontWeight.bold : FontWeight.w600,
            color: isSelected ? Colors.white : const Color(0xFF64748B),
          ),
        ),
      ),
    );
  }

  Widget _buildNurseVisitCard(BuildContext context, AppointmentModel visit) {
    final statusColor = _getStatusColor(visit.status);
    final formattedStatus = _formatStatus(visit.status);

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE2E8F0)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.02),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Top Row: Nurse details and Status Badge
            Row(
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: Image.network(
                    visit.doctorImageUrl.isNotEmpty
                        ? visit.doctorImageUrl
                        : 'https://images.unsplash.com/photo-1559839734-2b71ea197ec2?w=500',
                    width: 48,
                    height: 48,
                    fit: BoxFit.cover,
                    errorBuilder: (_, _, _) => Container(
                      width: 48,
                      height: 48,
                      color: const Color(0xFFDCFCE7),
                      child: const Icon(Icons.person, color: Color(0xFF059669)),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        visit.doctorName,
                        style: GoogleFonts.plusJakartaSans(
                          fontWeight: FontWeight.bold,
                          fontSize: 15,
                          color: const Color(0xFF0F172A),
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'Nasiib Home Care Nurse',
                        style: GoogleFonts.plusJakartaSans(
                          fontSize: 12,
                          color: const Color(0xFF64748B),
                        ),
                      ),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: statusColor.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    formattedStatus,
                    style: GoogleFonts.plusJakartaSans(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      color: statusColor,
                    ),
                  ),
                ),
              ],
            ),
            const Divider(height: 24, color: Color(0xFFF1F5F9)),

            // Service details
            _buildDetailRow(
              icon: Icons.tag_rounded,
              title: 'Ref Number',
              value: visit.referenceId,
              valueColor: const Color(0xFF059669),
              isBold: true,
            ),
            const SizedBox(height: 8),
            _buildDetailRow(
              icon: Icons.person_outline_rounded,
              title: 'Bukaanka',
              value: '${visit.patientName} (${visit.patientPhone})',
            ),
            const SizedBox(height: 8),
            _buildDetailRow(
              icon: Icons.location_on_outlined,
              title: 'Goobta / Cinwaanka',
              value: visit.reasonForVisit.replaceAll('Nurse Request: ', '').replaceAll('Delivery: ', ''),
            ),
            const SizedBox(height: 8),
            _buildDetailRow(
              icon: Icons.payment_rounded,
              title: 'Lacagta & Qaabka',
              value: '\$${visit.amount.toStringAsFixed(2)} • ${visit.paymentMethod}',
            ),
            const SizedBox(height: 12),

            // Action Row: Cancel / Delete & Call Support
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton.icon(
                  onPressed: () {
                    _showDeleteConfirmDialog(context, visit.id);
                  },
                  icon: const Icon(Icons.delete_outline_rounded, size: 16, color: Color(0xFFEF4444)),
                  label: Text(
                    'Tirtir',
                    style: GoogleFonts.plusJakartaSans(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: const Color(0xFFEF4444),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDetailRow({
    required IconData icon,
    required String title,
    required String value,
    Color? valueColor,
    bool isBold = false,
  }) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 16, color: const Color(0xFF94A3B8)),
        const SizedBox(width: 8),
        Text(
          '$title: ',
          style: GoogleFonts.plusJakartaSans(
            fontSize: 12,
            color: const Color(0xFF64748B),
            fontWeight: FontWeight.w500,
          ),
        ),
        Expanded(
          child: Text(
            value,
            style: GoogleFonts.plusJakartaSans(
              fontSize: 12,
              color: valueColor ?? const Color(0xFF1E293B),
              fontWeight: isBold ? FontWeight.bold : FontWeight.w600,
            ),
          ),
        ),
      ],
    );
  }

  Color _getStatusColor(String status) {
    final s = status.toLowerCase();
    if (s.contains('completed') || s.contains('arrived')) return const Color(0xFF10B981);
    if (s.contains('cancel')) return const Color(0xFFEF4444);
    if (s.contains('dispatched') || s.contains('confirmed')) return const Color(0xFF0284C7);
    return const Color(0xFFF59E0B); // Pending / Yellow
  }

  String _formatStatus(String status) {
    final s = status.toLowerCase();
    if (s == 'pending') return 'Socda (Pending)';
    if (s == 'completed') return 'Dhamaystiran';
    if (s == 'cancelled') return 'La Kansalay';
    if (s == 'dispatched') return 'Waa lasoo diray';
    if (s == 'confirmed') return 'La Aqbalay';
    return status;
  }

  void _showDeleteConfirmDialog(BuildContext context, String id) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(
          'Ma hubtaa inaad tirtirto?',
          style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.bold),
        ),
        content: Text(
          'Dalabkan kalkaalisada waxaa laga saari doonaa taariikhdaada.',
          style: GoogleFonts.plusJakartaSans(),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Maya'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(ctx);
              context.read<AppState>().deleteAppointment(id);
            },
            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFEF4444)),
            child: const Text('Haa, Tirtir', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(24),
              decoration: const BoxDecoration(
                color: Color(0xFFDCFCE7),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.medical_services_outlined,
                color: Color(0xFF059669),
                size: 48,
              ),
            ),
            const SizedBox(height: 16),
            Text(
              'Ma jiro dalab kalkaaliso',
              style: GoogleFonts.plusJakartaSans(
                fontSize: 17,
                fontWeight: FontWeight.bold,
                color: const Color(0xFF0F172A),
              ),
            ),
            const SizedBox(height: 6),
            Text(
              'Dalabaadka kalkaalisada guriga ee aad samayso halkan ayay toos uga soo muuqan doonaan.',
              textAlign: TextAlign.center,
              style: GoogleFonts.plusJakartaSans(
                fontSize: 13,
                color: const Color(0xFF64748B),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
