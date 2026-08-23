import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import '../../config/app_theme.dart';
import '../../services/app_state.dart';
import 'home_screen.dart';
import 'pharmacy_screen.dart';
import 'messages_screen.dart';
import 'profile_screen.dart';
import '../../widgets/network_or_asset_image.dart';

class MainPatientLayout extends StatelessWidget {

  const MainPatientLayout({super.key});

  Widget _buildProfileIcon(AppState appState, bool isActive) {

  final user = appState.currentUser;
  final String avatarUrl =
      (user?.avatarUrl != null && user!.avatarUrl.isNotEmpty)
      ? user.avatarUrl
      : '';


  return Container(
    width: 26,
    height: 26,
    decoration: BoxDecoration(
      shape: BoxShape.circle,
      border: Border.all(
        color: isActive ? AppTheme.primaryColor : const Color(0xFF9EA5B1),
        width: isActive ? 2 : 1,
      ),
    ),
    child: ClipRRect(
      borderRadius: BorderRadius.circular(13),
      child: NetworkOrAssetImage(
        imageUrl: avatarUrl,
        width: 24,
        height: 24,
        fit: BoxFit.cover,
      ),
    ),
  );
}


  @override
  Widget build(BuildContext context) {
    final appState = context.watch<AppState>();
    final currentIndex = appState.currentPatientNavIndex;

    final List<Widget> pages = const [
      HomeScreen(),
      PharmacyScreen(), // Replaced Appointment with Pharmacy as explicitly requested!
      MessagesScreen(),
      ProfileScreen(),
    ];

    return Scaffold(
      body: IndexedStack(index: currentIndex, children: pages),
      bottomNavigationBar: Container(
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
        child: BottomNavigationBar(
          currentIndex: currentIndex,
          onTap: (index) {
            context.read<AppState>().setPatientNavIndex(index);
          },
          type: BottomNavigationBarType.fixed,
          backgroundColor: Colors.white,
          selectedItemColor: AppTheme.primaryColor,
          unselectedItemColor: const Color(0xFF9EA5B1),
          selectedLabelStyle: GoogleFonts.plusJakartaSans(
            fontSize: 12,
            fontWeight: FontWeight.w700,
          ),
          unselectedLabelStyle: GoogleFonts.plusJakartaSans(
            fontSize: 12,
            fontWeight: FontWeight.w500,
          ),
          elevation: 0,
          items: [
            const BottomNavigationBarItem(
              icon: Icon(Icons.home_filled),
              activeIcon: Icon(Icons.home_filled, color: AppTheme.primaryColor),
              label: 'Home',
            ),
            const BottomNavigationBarItem(
              icon: Icon(Icons.local_pharmacy_outlined),
              activeIcon: Icon(
                Icons.local_pharmacy_rounded,
                color: AppTheme.primaryColor,
              ),
              label: 'Pharmacy',
            ),
            const BottomNavigationBarItem(
              icon: Icon(CupertinoIcons.chat_bubble),
              activeIcon: Icon(
                CupertinoIcons.chat_bubble_fill,
                color: AppTheme.primaryColor,
              ),
              label: 'Message',
            ),
            BottomNavigationBarItem(
              icon: _buildProfileIcon(appState, false),
              activeIcon: _buildProfileIcon(appState, true),
              label: 'Profile',
            ),
          ],
        ),
      ),
    );
  }
}

