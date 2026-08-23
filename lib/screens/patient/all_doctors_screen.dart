import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import '../../config/app_theme.dart';
import '../../models/doctor_model.dart';
import '../../services/app_state.dart';
import '../../widgets/network_or_asset_image.dart';
import 'doctor_profile_screen.dart';

class AllDoctorsScreen extends StatefulWidget {
  final String initialSearchQuery;
  const AllDoctorsScreen({super.key, this.initialSearchQuery = ''});

  @override
  State<AllDoctorsScreen> createState() => _AllDoctorsScreenState();
}

class _AllDoctorsScreenState extends State<AllDoctorsScreen> {
  late TextEditingController _searchController;

  @override
  void initState() {
    super.initState();
    _searchController = TextEditingController(text: widget.initialSearchQuery);
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  // Smart search helper to remove common prefixes like "dr.", "dr", "doctor"
  String _cleanSearchTerm(String s) {
    return s
        .toLowerCase()
        .replaceAll('dr.', '')
        .replaceAll('dr', '')
        .replaceAll('doctor', '')
        .trim();
  }

  @override
  Widget build(BuildContext context) {
    final appState = context.watch<AppState>();
    final doctors = appState.doctors;
    final rawQuery = _searchController.text.trim().toLowerCase();
    final cleanQuery = _cleanSearchTerm(_searchController.text);

    final filteredDoctors = doctors.where((d) {
      final String rawName = d.name.toLowerCase();
      final String cleanName = _cleanSearchTerm(d.name);
      final String spec = d.specialty.toLowerCase();

      if (spec.contains('kalkaaliso') || spec.contains('nurse')) {
        return false;
      }
      if (rawQuery.isEmpty) return true;
      final matchesRaw = rawName.contains(rawQuery);
      final matchesClean = cleanQuery.isNotEmpty && cleanName.contains(cleanQuery);
      final matchesSpec = spec.contains(rawQuery);
      return matchesRaw || matchesClean || matchesSpec;
    }).toList();


    return Scaffold(
      backgroundColor: const Color(0xFFF4F6F8), // Contrasting light grey background
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
          'Find Your Doctor',
          style: GoogleFonts.plusJakartaSans(
            fontSize: 18,
            fontWeight: FontWeight.bold,
            color: AppTheme.textPrimary,
          ),
        ),
      ),
      body: Column(
        children: [
          // Search Input Bar at top of list
          Container(
            color: Colors.white,
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
            child: TextField(
              controller: _searchController,
              onChanged: (_) => setState(() {}), // Instantly filter list on change!
              style: GoogleFonts.plusJakartaSans(fontSize: 15),
              decoration: InputDecoration(
                hintText: 'Search Doctor (e.g. Mukhtar or Dentist)',
                hintStyle: GoogleFonts.plusJakartaSans(
                  color: AppTheme.textLight,
                  fontSize: 14,
                ),
                prefixIcon: const Icon(
                  Icons.search_rounded,
                  color: AppTheme.primaryColor,
                  size: 22,
                ),
                fillColor: const Color(0xFFFAFCFD),
                filled: true,
                contentPadding: const EdgeInsets.symmetric(vertical: 14),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(16),
                  borderSide: const BorderSide(color: Color(0xFFEFF3F6)),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(16),
                  borderSide: const BorderSide(
                    color: AppTheme.primaryColor,
                    width: 1.5,
                  ),
                ),
              ),
            ),
          ),

          // Stacked Doctors List
          Expanded(
            child: RefreshIndicator(
              onRefresh: () async {
                await appState.fetchDoctors();
              },
              child: filteredDoctors.isEmpty
                  ? SingleChildScrollView(
                      physics: const AlwaysScrollableScrollPhysics(),
                      child: Container(
                        height: 300,
                        alignment: Alignment.center,
                        child: Text(
                          'Dhaqtar lama helin (No doctors found)',
                          style: GoogleFonts.plusJakartaSans(
                            color: AppTheme.textSecondary,
                            fontSize: 15,
                          ),
                        ),
                      ),
                    )
                  : ListView.separated(
                      physics: const AlwaysScrollableScrollPhysics(),
                      padding: const EdgeInsets.all(20),
                      itemCount: filteredDoctors.length,
                      separatorBuilder: (_, _) => const SizedBox(height: 16),
                      itemBuilder: (context, index) {
                        final doc = filteredDoctors[index];
                        return _buildDoctorCard(context, doc);
                      },
                    ),
            ),
          ),
        ],
      ),
    );
  }


  Widget _buildDoctorCard(BuildContext context, DoctorModel doctor) {
    return GestureDetector(
      onTap: () {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => DoctorProfileScreen(doctor: doctor),
          ),
        );
      },
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: const Color(0xFFF0F3F6)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.02),
              blurRadius: 10,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Row(
          children: [
            // Circular Avatar Image
            NetworkOrAssetImage(
              imageUrl: doctor.imageUrl,
              width: 72,
              height: 72,
              borderRadius: BorderRadius.circular(36),
            ),
            const SizedBox(width: 16),

            // Details
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          doctor.name,
                          style: GoogleFonts.plusJakartaSans(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            color: AppTheme.textPrimary,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    doctor.specialty,
                    style: GoogleFonts.plusJakartaSans(
                      fontSize: 13,
                      color: AppTheme.textSecondary,
                    ),
                  ),

                  if (doctor.consultationFee > 0) ...[
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        if (doctor.discountFee != null && doctor.discountFee! > 0 && doctor.discountFee! < doctor.consultationFee) ...[
                          Text(
                            '\$${doctor.consultationFee.toStringAsFixed(2)}',
                            style: GoogleFonts.plusJakartaSans(
                              fontSize: 12,
                              color: Colors.grey,
                              decoration: TextDecoration.lineThrough,
                            ),
                          ),
                          const SizedBox(width: 6),
                          Text(
                            '\$${doctor.activePrice.toStringAsFixed(2)}',
                            style: GoogleFonts.plusJakartaSans(
                              fontSize: 13,
                              color: const Color(0xFF10B981),
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ] else
                          Text(
                            '\$${doctor.consultationFee.toStringAsFixed(2)}',
                            style: GoogleFonts.plusJakartaSans(
                              fontSize: 13,
                              color: AppTheme.primaryColor,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                      ],
                    ),
                  ],

                ],
              ),
            ),

            // Book Now (Always goes to DoctorProfileScreen first!)
            SizedBox(
              height: 36,
              child: ElevatedButton(
                onPressed: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => DoctorProfileScreen(doctor: doctor),
                    ),
                  );
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.primaryColor,
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: Text(
                  'Book Now',
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
