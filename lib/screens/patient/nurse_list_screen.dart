import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../config/app_theme.dart';
import '../../models/appointment_model.dart';
import '../../models/nurse_model.dart';
import '../../services/app_state.dart';
import '../../services/supabase_service.dart';
import '../../widgets/network_or_asset_image.dart';
import 'delivery_details_screen.dart';

class NurseListScreen extends StatefulWidget {
  const NurseListScreen({super.key});

  @override
  State<NurseListScreen> createState() => _NurseListScreenState();
}

class _NurseListScreenState extends State<NurseListScreen> {
  Stream<List<Map<String, dynamic>>>? _nursesStream;

  @override
  void initState() {
    super.initState();
    final client = SupabaseService.instance.client ?? Supabase.instance.client;
    try {
      _nursesStream = client
          .from('nurses')
          .stream(primaryKey: ['id'])
          .order('created_at', ascending: false);
    } catch (e) {
      debugPrint("Nurse stream init error: $e");
    }
  }

  @override
  Widget build(BuildContext context) {
    final appState = context.watch<AppState>();
    final client = SupabaseService.instance.client ?? Supabase.instance.client;

    return Scaffold(
      backgroundColor: const Color(0xFFF4F6F8),
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
          'Dalbo Kalkaaliso',
          style: GoogleFonts.plusJakartaSans(
            fontSize: 18,
            fontWeight: FontWeight.bold,
            color: AppTheme.textPrimary,
          ),
        ),
      ),
      body: SafeArea(
        child: StreamBuilder<List<Map<String, dynamic>>>(
          stream: _nursesStream ?? client.from('nurses').stream(primaryKey: ['id']),
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting && !snapshot.hasData) {
              return const Center(
                child: CircularProgressIndicator(color: AppTheme.primaryColor),
              );
            }

            final data = snapshot.data ?? [];
            final List<NurseModel> nurses = data.isNotEmpty
                ? data.map((json) => NurseModel.fromJson(json)).toList()
                : appState.nurses;

            if (nurses.isEmpty) {
              return Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(20),
                      decoration: BoxDecoration(
                        color: AppTheme.primaryColor.withOpacity(0.08),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(
                        Icons.medical_services_outlined,
                        size: 48,
                        color: AppTheme.primaryColor,
                      ),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'Waqtigan ma jiraan kalkaaliyeyaal.',
                      style: GoogleFonts.plusJakartaSans(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: AppTheme.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Faahfaahinta kalkaalisada ee database-ka Supabase halkaan ayay ku soo baxayaan.',
                      textAlign: TextAlign.center,
                      style: GoogleFonts.plusJakartaSans(
                        fontSize: 13,
                        color: AppTheme.textSecondary,
                      ),
                    ),
                  ],
                ),
              );
            }

            return ListView.separated(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
              itemCount: nurses.length,
              separatorBuilder: (_, _) => const SizedBox(height: 12),
              itemBuilder: (context, index) {
                final nurse = nurses[index];
                return _buildNurseCard(context, nurse, appState);
              },
            );
          },
        ),
      ),
    );
  }

  Widget _buildNurseCard(BuildContext context, NurseModel nurse, AppState appState) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFEDF1F5)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.02),
            blurRadius: 8,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Row(
        children: [
          // Nurse Image
          NetworkOrAssetImage(
            imageUrl: nurse.imageUrl,
            width: 54,
            height: 54,
            borderRadius: BorderRadius.circular(27),
          ),
          const SizedBox(width: 14),

          // Nurse Details
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        nurse.name,
                        style: GoogleFonts.plusJakartaSans(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: AppTheme.textPrimary,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 6,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: nurse.isAvailable
                            ? const Color(0xFFDCFCE7)
                            : const Color(0xFFFEE2E2),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        nurse.isAvailable ? '🟢 Diyaar' : '🔴 Mashquul',
                        style: GoogleFonts.plusJakartaSans(
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
                          color: nurse.isAvailable
                              ? const Color(0xFF16A34A)
                              : const Color(0xFFDC2626),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  nurse.specialty,
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 13,
                    color: AppTheme.textSecondary,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 4),
                Row(
                  children: [
                    if (nurse.discountFee != null && nurse.discountFee! > 0) ...[
                      Text(
                        '\$${nurse.fee.toStringAsFixed(2)}',
                        style: GoogleFonts.plusJakartaSans(
                          fontSize: 12,
                          color: Colors.grey,
                          decoration: TextDecoration.lineThrough,
                        ),
                      ),
                      const SizedBox(width: 6),
                      Text(
                        '\$${nurse.discountFee!.toStringAsFixed(2)}',
                        style: GoogleFonts.plusJakartaSans(
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                          color: const Color(0xFF00897B),
                        ),
                      ),
                    ] else ...[
                      Text(
                        '\$${nurse.fee.toStringAsFixed(2)}',
                        style: GoogleFonts.plusJakartaSans(
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                          color: const Color(0xFF00897B),
                        ),
                      ),
                    ],
                  ],
                ),
              ],
            ),
          ),

          const SizedBox(width: 10),

          // Dalbo / Mashquul Button
          ElevatedButton(
            onPressed: nurse.isAvailable
                ? () {
                    final double nursePrice = (nurse.discountFee != null && nurse.discountFee! > 0)
                        ? nurse.discountFee!
                        : nurse.visitFee;

                    final customOrder = AppointmentModel(
                      id: 'nurse_${DateTime.now().millisecondsSinceEpoch}',
                      referenceId: '#NRS${10000 + DateTime.now().millisecond}',
                      doctorId: nurse.id,
                      doctorName: nurse.name,
                      doctorSpecialty: 'Kalkaaliso (Home Care)',
                      doctorImageUrl: nurse.imageUrl,
                      hospitalName: 'Nasiib Hospital - Home Care',
                      date: 'Today',
                      time: 'As Soon As Possible',
                      appointmentType: 'Home Nursing Care',
                      patientName: appState.currentUser?.fullName ?? 'Patient',
                      patientPhone: appState.currentUser?.phoneNumber ?? '+252 61 1234567',
                      patientAge: 24,
                      patientGender: 'Male',
                      reasonForVisit: 'Nurse Request: ${nurse.name}',
                      paymentMethod: 'EVC Plus',
                      amount: nursePrice,
                      queueNumber: 1,
                      status: 'Confirmed',
                      createdAt: DateTime.now().toIso8601String(),
                    );

                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => DeliveryDetailsScreen(customOrder: customOrder),
                      ),
                    );
                  }
                : () {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(
                          'Kalkaalisada ${nurse.name} hadda waxay ku jirtaa shaqo kale (Mashquul). Fadlan dooro kalkaaliso kale oo diyaar ah.',
                          style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.w600),
                        ),
                        backgroundColor: const Color(0xFFD97706),
                      ),
                    );
                  },
            style: ElevatedButton.styleFrom(
              backgroundColor: nurse.isAvailable
                  ? AppTheme.primaryColor
                  : const Color(0xFFE2E8F0),
              elevation: 0,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              padding: const EdgeInsets.symmetric(
                horizontal: 18,
                vertical: 10,
              ),
            ),
            child: Text(
              nurse.isAvailable ? 'Dalbo' : 'Mashquul',
              style: GoogleFonts.plusJakartaSans(
                fontSize: 13,
                fontWeight: FontWeight.bold,
                color: nurse.isAvailable
                    ? Colors.white
                    : const Color(0xFF64748B),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
