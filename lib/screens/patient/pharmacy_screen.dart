import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import '../../config/app_theme.dart';
import '../../models/medicine_model.dart';
import '../../services/app_state.dart';
import '../../widgets/network_or_asset_image.dart';
import 'cart_screen.dart';
import 'medicine_detail_screen.dart';

class PharmacyScreen extends StatefulWidget {
  const PharmacyScreen({super.key});

  @override
  State<PharmacyScreen> createState() => _PharmacyScreenState();
}

class _PharmacyScreenState extends State<PharmacyScreen> {
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';

  @override
  Widget build(BuildContext context) {
    final appState = context.watch<AppState>();
    final medicines = appState.medicines.where((m) =>
      m.title.toLowerCase().contains(_searchQuery.toLowerCase())
    ).toList();
    final cartCount = appState.cartCount;
    final orderCount = appState.orders.length;

    return Scaffold(
      backgroundColor: const Color(0xFFF2F5F8), // Soft contrasting background so white containers stand out!
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, color: AppTheme.textPrimary, size: 20),
          onPressed: () {
            context.read<AppState>().setPatientNavIndex(0); // Return to Home
          },
        ),
        title: Text(
          'Recommendation',
          style: GoogleFonts.plusJakartaSans(
            fontSize: 18,
            fontWeight: FontWeight.bold,
            color: AppTheme.textPrimary,
          ),
        ),
        actions: [
          // Top Right Shopping Cart Icon Button with Badge Counter
          GestureDetector(
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const CartScreen()),
              );
            },
            child: Container(
              margin: const EdgeInsets.only(right: 16),
              width: 44,
              height: 44,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  const Icon(
                    Icons.shopping_bag_outlined,
                    color: AppTheme.textPrimary,
                    size: 24,
                  ),
                  if (cartCount > 0)
                    Positioned(
                      top: 4,
                      right: 4,
                      child: Container(
                        padding: const EdgeInsets.all(4),
                        decoration: const BoxDecoration(
                          color: AppTheme.primaryColor,
                          shape: BoxShape.circle,
                        ),
                        child: Text(
                          '$cartCount',
                          style: GoogleFonts.plusJakartaSans(
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 12.0),
          child: Column(
            children: [
              // Search Medicine Input
              TextField(
                controller: _searchController,
                onChanged: (val) => setState(() => _searchQuery = val),
                style: GoogleFonts.plusJakartaSans(fontSize: 14),
                decoration: InputDecoration(
                  hintText: 'Search medicine',
                  hintStyle: GoogleFonts.plusJakartaSans(color: AppTheme.textLight, fontSize: 14),
                  prefixIcon: const Icon(Icons.search_rounded, color: AppTheme.textSecondary),
                  fillColor: Colors.white,
                  filled: true,
                  contentPadding: const EdgeInsets.symmetric(vertical: 12),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(16),
                    borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(16),
                    borderSide: const BorderSide(color: AppTheme.primaryColor),
                  ),
                ),
              ),

              const SizedBox(height: 16),

              // Medicine Products Grid (2 Columns)
              Expanded(
                child: GridView.builder(
                  itemCount: medicines.length,
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 2,
                    childAspectRatio: 0.70,
                    crossAxisSpacing: 14,
                    mainAxisSpacing: 14,
                  ),
                  itemBuilder: (context, index) {
                    final med = medicines[index];
                    return _buildMedicineCard(context, med);
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildMedicineCard(BuildContext context, MedicineModel med) {
    return GestureDetector(
      onTap: () {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => MedicineDetailScreen(medicine: med),
          ),
        );
      },
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.white, // Crisp white card popping against #F2F5F8
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: const Color(0xFFEAEFF4)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.03),
              blurRadius: 12,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Image Container inside card
            Stack(
              children: [
                Container(
                  width: double.infinity,
                  height: 110,
                  decoration: BoxDecoration(
                    color: const Color(0xFFF8FAFC),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(14),
                    child: NetworkOrAssetImage(
                      imageUrl: med.imageUrl,
                      width: double.infinity,
                      height: 110,
                      fit: BoxFit.cover,
                    ),
                  ),
                ),

              ],
            ),


            const SizedBox(height: 10),

            Text(
              med.title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: GoogleFonts.plusJakartaSans(
                fontSize: 13,
                fontWeight: FontWeight.bold,
                color: AppTheme.textPrimary,
              ),
            ),
            const SizedBox(height: 4),

            // Price Row
            Row(
              children: [
                Text(
                  '\$${med.price.toStringAsFixed(2)}',
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 13,
                    fontWeight: FontWeight.bold,
                    color: AppTheme.textPrimary,
                  ),
                ),
                if (med.originalPrice != null && med.originalPrice! > 0 && med.originalPrice! > med.price) ...[
                  const SizedBox(width: 4),
                  Text(
                    '\$${med.originalPrice!.toStringAsFixed(2)}',
                    style: GoogleFonts.plusJakartaSans(
                      fontSize: 11,
                      decoration: TextDecoration.lineThrough,
                      color: AppTheme.textLight,
                    ),
                  ),
                ],
              ],
            ),

            const Spacer(),

            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  '${med.soldCount} sold',
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 11,
                    color: AppTheme.textLight,
                  ),
                ),
                GestureDetector(
                  onTap: () {
                    context.read<AppState>().addToCart(med, 1);
                    ScaffoldMessenger.of(context).hideCurrentSnackBar();
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(
                          '${med.title} added to cart',
                          style: GoogleFonts.plusJakartaSans(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            color: Colors.white,
                          ),
                        ),
                        backgroundColor: AppTheme.primaryColor,
                        duration: const Duration(seconds: 2),
                        behavior: SnackBarBehavior.fixed,
                      ),
                    );
                  },
                  child: Container(
                    padding: const EdgeInsets.all(6),
                    decoration: BoxDecoration(
                      color: AppTheme.primaryLight,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(
                      Icons.add_shopping_cart_rounded,
                      color: AppTheme.primaryColor,
                      size: 16,
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
