import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import '../../config/app_theme.dart';
import '../../models/doctor_model.dart';
import '../../services/app_state.dart';
import '../../widgets/network_or_asset_image.dart';
import 'doctor_profile_screen.dart';
import 'all_doctors_screen.dart';
import 'notifications_screen.dart';
import 'nurse_list_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final TextEditingController _searchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<AppState>().loadPatientProfileFromSupabase();
    });
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
    final user = appState.currentUser;
    final doctors = appState.doctors;
    final selectedSpecialty = appState.selectedSpecialty;

    final rawQuery = _searchController.text.trim().toLowerCase();
    final cleanQuery = _cleanSearchTerm(_searchController.text);

    final filteredDoctors = doctors.where((d) {
      final String rawName = d.name.toLowerCase();
      final String cleanName = _cleanSearchTerm(d.name);
      final String spec = d.specialty.toLowerCase();

      if (spec.contains('kalkaaliso') || spec.contains('nurse')) {
        return false;
      }
      // 1. Specialty Filter
      if (selectedSpecialty != 'All' &&
          !spec.contains(selectedSpecialty.toLowerCase())) {
        return false;
      }
      // 2. Search Text Filter
      if (rawQuery.isNotEmpty) {
        final matchesRaw = rawName.contains(rawQuery);
        final matchesClean = cleanQuery.isNotEmpty && cleanName.contains(cleanQuery);
        final matchesSpec = spec.contains(rawQuery);
        return matchesRaw || matchesClean || matchesSpec;
      }
      return true;
    }).toList();


    return Scaffold(
      backgroundColor: const Color(0xFFFAFAFC),
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: () async {
            await Future.wait([
              appState.fetchDoctors(),
              appState.loadPatientProfileFromSupabase(),
            ]);
          },
          child: SingleChildScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.symmetric(horizontal: 14.0, vertical: 10.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [

              // Profile Picture & Greeting Header Row
              Row(
                children: [
                  NetworkOrAssetImage(
                    imageUrl: (user?.avatarUrl != null && user!.avatarUrl.isNotEmpty)
                        ? user.avatarUrl
                        : '',
                    width: 48,
                    height: 48,
                    borderRadius: BorderRadius.circular(24),
                  ),
                  const SizedBox(width: 12),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Welcome Back',
                        style: GoogleFonts.plusJakartaSans(
                          fontSize: 13,
                          color: AppTheme.textSecondary,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      Text(
                        user?.fullName ?? 'Patient',
                        style: GoogleFonts.plusJakartaSans(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: AppTheme.textPrimary,
                        ),
                      ),
                    ],
                  ),
                  const Spacer(),
                  Builder(
                    builder: (context) {
                      final unreadCount = appState.unreadNotificationCount;
                      final String badgeText = unreadCount > 99 ? '99+' : '$unreadCount';

                      return GestureDetector(
                        onTap: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(builder: (_) => const NotificationsScreen()),
                          );
                        },
                        child: Container(
                          width: 44,
                          height: 44,
                          decoration: BoxDecoration(
                            color: Colors.white,
                            shape: BoxShape.circle,
                            border: Border.all(color: const Color(0xFFE2E8F0)),
                          ),
                          child: Stack(
                            clipBehavior: Clip.none,
                            alignment: Alignment.center,
                            children: [
                              const Icon(
                                Icons.notifications_none_rounded,
                                color: AppTheme.textPrimary,
                                size: 22,
                              ),
                              if (unreadCount > 0)
                                Positioned(
                                  top: 4,
                                  right: 4,
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1.5),
                                    constraints: const BoxConstraints(
                                      minWidth: 16,
                                      minHeight: 16,
                                    ),
                                    decoration: BoxDecoration(
                                      color: const Color(0xFFEF4444),
                                      borderRadius: BorderRadius.circular(10),
                                    ),
                                    child: Center(
                                      child: Text(
                                        badgeText,
                                        style: GoogleFonts.plusJakartaSans(
                                          color: Colors.white,
                                          fontSize: 9,
                                          fontWeight: FontWeight.bold,
                                          height: 1.1,
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                ],
              ),




              const SizedBox(height: 24),

              // Search Doctor Input Bar (Matching Image 1)
              TextField(
                controller: _searchController,
                onChanged: (_) => setState(() {}), // Instantly filter list on home screen!
                onSubmitted: (val) {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => AllDoctorsScreen(initialSearchQuery: val),
                    ),
                  );
                },
                style: GoogleFonts.plusJakartaSans(
                  fontSize: 15,
                  color: AppTheme.textPrimary,
                  fontWeight: FontWeight.w600,
                ),
                decoration: InputDecoration(
                  hintText: 'Search Doctor',
                  hintStyle: GoogleFonts.plusJakartaSans(
                    color: const Color(0xFF94A3B8),
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                  ),
                  prefixIcon: const Icon(
                    Icons.search_rounded,
                    color: AppTheme.primaryColor,
                    size: 22,
                  ),
                  fillColor: Colors.white,
                  filled: true,
                  contentPadding: const EdgeInsets.symmetric(vertical: 14),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(16),
                    borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
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

              const SizedBox(height: 28),

              // "Find your doctor" Section Header (Matching Image 1)
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Find your doctor',
                    style: GoogleFonts.plusJakartaSans(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: AppTheme.textPrimary,
                    ),
                  ),
                  GestureDetector(
                    onTap: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => const AllDoctorsScreen(),
                        ),
                      );
                    },
                    child: Row(
                      children: [
                        Text(
                          'See All',
                          style: GoogleFonts.plusJakartaSans(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: AppTheme.textSecondary,
                          ),
                        ),
                        const Icon(
                          Icons.chevron_right_rounded,
                          size: 18,
                          color: AppTheme.textSecondary,
                        ),
                      ],
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 16),

              // Specialty Cards Horizontal List (Dynamic from Supabase DB)
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    _buildSpecialtyCard(
                      title: 'Book a\nNurse',
                      iconAsset: Icons.medical_services_rounded,
                      iconColor: const Color(0xFFE53935),
                      isSelected: false,
                      onTap: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => const NurseListScreen(),
                          ),
                        );
                      },
                    ),
                    const SizedBox(width: 14),
                    // Dynamic Specialties from Database with doctor profile picture
                    ...((appState.specialties.isNotEmpty
                        ? appState.specialties.map((s) => s.name).toList()
                        : doctors.map((d) => d.specialty).where((s) => s.isNotEmpty && !s.toLowerCase().contains('kalkaaliso')).toSet().toList()
                    ).map((specName) {
                      final bool isSel = selectedSpecialty.toLowerCase() == specName.toLowerCase();
                      DoctorModel? matchingDoc;
                      for (final d in doctors) {
                        if (d.specialty.toLowerCase() == specName.toLowerCase() && d.imageUrl.isNotEmpty) {
                          matchingDoc = d;
                          break;
                        }
                      }
                      final String? docImg = matchingDoc?.imageUrl;

                      return Padding(
                        padding: const EdgeInsets.only(right: 14.0),
                        child: _buildSpecialtyCard(
                          title: '$specName\nSpecialist',
                          iconAsset: Icons.health_and_safety_rounded,
                          iconColor: isSel ? AppTheme.primaryColor : const Color(0xFF0288D1),
                          isSelected: isSel,
                          doctorImageUrl: docImg,
                          onTap: () => appState.setSelectedSpecialty(
                            isSel ? 'All' : specName,
                          ),
                        ),
                      );
                    })),
                  ],
                ),
              ),


              const SizedBox(height: 32),

              // "Top Doctors" Section Header (Matching Image 1)
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Top Doctors',
                    style: GoogleFonts.plusJakartaSans(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: AppTheme.textPrimary,
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 10),

              // Doctors List Cards (Dynamic from Supabase DB)

              ListView.separated(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: filteredDoctors.length,
                separatorBuilder: (_, _) => const SizedBox(height: 10),
                itemBuilder: (context, index) {
                  final doctor = filteredDoctors[index];
                  return _buildDoctorCard(context, doctor);
                },
              ),

              const SizedBox(height: 20),
            ],
          ),
        ),
      ),
    ),
  );
}



  Widget _buildSpecialtyCard({
    required String title,
    required IconData iconAsset,
    required Color iconColor,
    required bool isSelected,
    required VoidCallback onTap,
    String? doctorImageUrl,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 120,
        height: 146,
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
        decoration: BoxDecoration(
          color: isSelected ? AppTheme.primaryLight : Colors.white,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
            color: isSelected ? AppTheme.primaryColor : const Color(0xFFE2E8F0),
            width: isSelected ? 1.5 : 1,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.02),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (doctorImageUrl != null && doctorImageUrl.isNotEmpty)
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: isSelected ? AppTheme.primaryColor : const Color(0xFF0288D1),
                    width: 2,
                  ),
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(24),
                  child: NetworkOrAssetImage(
                    imageUrl: doctorImageUrl,
                    width: 48,
                    height: 48,
                    fit: BoxFit.cover,
                    alignment: Alignment.topCenter,
                  ),
                ),
              )
            else
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: iconColor.withOpacity(0.12),
                  shape: BoxShape.circle,
                ),
                child: Icon(iconAsset, color: iconColor, size: 26),
              ),
            const SizedBox(height: 8),
            Expanded(
              child: Center(
                child: Text(
                  title,
                  textAlign: TextAlign.center,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: AppTheme.textPrimary,
                    height: 1.2,
                  ),
                ),
              ),
            ),
          ],
        ),
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
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: const Color(0xFFE2E8F0)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.02),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Row(
          children: [
            // Doctor Avatar Circular Image
            NetworkOrAssetImage(
              imageUrl: doctor.imageUrl,
              width: 72,
              height: 72,
              borderRadius: BorderRadius.circular(36),
            ),
            const SizedBox(width: 16),

            // Doctor Details Column
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

            // Book Now Button Column (Removed consultation fee, button navigates to DoctorProfileScreen)
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
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
          ],
        ),
      ),
    );
  }
}
