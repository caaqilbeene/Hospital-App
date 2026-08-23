import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import '../../config/app_theme.dart';
import '../../models/medicine_model.dart';
import '../../services/app_state.dart';
import '../../widgets/network_or_asset_image.dart';
import 'cart_screen.dart';

class MedicineDetailScreen extends StatefulWidget {
  final MedicineModel medicine;
  const MedicineDetailScreen({super.key, required this.medicine});

  @override
  State<MedicineDetailScreen> createState() => _MedicineDetailScreenState();
}

class _MedicineDetailScreenState extends State<MedicineDetailScreen> {
  int _quantity = 1;

  @override
  Widget build(BuildContext context) {
    final appState = context.watch<AppState>();
    final cartCount = appState.cartCount;
    final med = widget.medicine;
    final totalPrice = med.price * _quantity; // Price updates dynamically

    return Scaffold(
      backgroundColor: const Color(0xFF0F172A), // Slate Dark Header Background
      body: Stack(
        children: [
          // 1. Top Large Hero Image Area (Fills entire top area edge-to-edge!)
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            height: MediaQuery.of(context).size.height * 0.40,
            child: Container(
              color: const Color(0xFF0F172A),
              child: NetworkOrAssetImage(
                imageUrl: med.imageUrl,
                fit: BoxFit
                    .cover, // Fills the entire top container space completely!
                width: double.infinity,
                height: double.infinity,
              ),
            ),
          ),

          // 2. Top Header Navigation Buttons
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: SafeArea(
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16.0,
                  vertical: 8.0,
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    GestureDetector(
                      onTap: () => Navigator.pop(context),
                      child: Container(
                        width: 44,
                        height: 44,
                        decoration: BoxDecoration(
                          color: const Color(0xFF1E293B),
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: Colors.white.withOpacity(0.2),
                            width: 1.5,
                          ),
                        ),
                        child: const Icon(
                          Icons.arrow_back_ios_new_rounded,
                          color: Colors.white,
                          size: 18,
                        ),
                      ),
                    ),

                    GestureDetector(
                      onTap: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(builder: (_) => const CartScreen()),
                        );
                      },
                      child: Container(
                        width: 44,
                        height: 44,
                        decoration: BoxDecoration(
                          color: const Color(0xFF1E293B),
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: Colors.white.withOpacity(0.2),
                            width: 1.5,
                          ),
                        ),
                        child: Stack(
                          alignment: Alignment.center,
                          children: [
                            const Icon(
                              Icons.shopping_bag_outlined,
                              color: Colors.white,
                              size: 20,
                            ),
                            if (cartCount > 0)
                              Positioned(
                                top: 2,
                                right: 2,
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
              ),
            ),
          ),

          // 3. Curved White Content Sheet (Matches Image 3 details perfectly!)
          Positioned(
            top: MediaQuery.of(context).size.height * 0.36,
            left: 0,
            right: 0,
            bottom: 0,
            child: Container(
              width: double.infinity,
              decoration: const BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.vertical(top: Radius.circular(36)),
              ),
              child: Column(
                children: [
                  Expanded(
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 24.0,
                        vertical: 28.0,
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // Rating Display (e.g. 4.7/5)
                          Row(
                            children: [
                              const Icon(
                                Icons.star_rounded,
                                color: Color(0xFFFFB800),
                                size: 20,
                              ),
                              const SizedBox(width: 4),
                              Text(
                                '${med.rating}/5',
                                style: GoogleFonts.plusJakartaSans(
                                  fontSize: 14,
                                  fontWeight: FontWeight.bold,
                                  color: AppTheme.textPrimary,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),

                          // Title & Quantity Selector Row (Matches Image 3!)
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Expanded(
                                child: Text(
                                  med.title,
                                  style: GoogleFonts.plusJakartaSans(
                                    fontSize: 20,
                                    fontWeight: FontWeight.bold,
                                    color: AppTheme.textPrimary,
                                    height: 1.25,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 16),

                              // Quantity Selector Box (- 2 +) without any "Qty:" text!
                              Container(
                                height: 38,
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 4,
                                ),
                                decoration: BoxDecoration(
                                  color: const Color(0xFFF3F4F6),
                                  borderRadius: BorderRadius.circular(20),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    IconButton(
                                      padding: EdgeInsets.zero,
                                      constraints: const BoxConstraints(),
                                      icon: const Icon(
                                        Icons.remove,
                                        size: 16,
                                        color: AppTheme.textSecondary,
                                      ),
                                      onPressed: () {
                                        if (_quantity > 1) {
                                          setState(() => _quantity--);
                                        }
                                      },
                                    ),
                                    Padding(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 10.0,
                                      ),
                                      child: Text(
                                        '$_quantity',
                                        style: GoogleFonts.plusJakartaSans(
                                          fontSize: 14,
                                          fontWeight: FontWeight.bold,
                                          color: AppTheme.textPrimary,
                                        ),
                                      ),
                                    ),
                                    IconButton(
                                      padding: EdgeInsets.zero,
                                      constraints: const BoxConstraints(),
                                      icon: const Icon(
                                        Icons.add,
                                        size: 16,
                                        color: AppTheme.textSecondary,
                                      ),
                                      onPressed: () {
                                        setState(() => _quantity++);
                                      },
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 6),

                          // SKU Code
                          Text(
                            'SKU: ${med.sku}',
                            style: GoogleFonts.plusJakartaSans(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: AppTheme.textLight,
                            ),
                          ),
                          const SizedBox(height: 8),

                          // Price Row
                          Row(
                            children: [
                              Text(
                                '\$${med.price.toStringAsFixed(2)}',
                                style: GoogleFonts.plusJakartaSans(
                                  fontSize: 18,
                                  fontWeight: FontWeight.bold,
                                  color: AppTheme.primaryColor,
                                ),
                              ),
                              if (med.originalPrice != null && med.originalPrice! > 0 && med.originalPrice! > med.price) ...[
                                const SizedBox(width: 8),
                                Text(
                                  '\$${med.originalPrice!.toStringAsFixed(2)}',
                                  style: GoogleFonts.plusJakartaSans(
                                    fontSize: 14,
                                    decoration: TextDecoration.lineThrough,
                                    color: AppTheme.textLight,
                                  ),
                                ),
                              ],
                            ],
                          ),

                          const SizedBox(height: 18),

                          // Specification Chips (Item Code, Category, Sold) - Returned as requested!
                          Row(
                            children: [
                              _buildSpecChip('Item Code (SKU)', med.sku),
                              const SizedBox(width: 8),
                              _buildSpecChip('Category', med.category),
                              const SizedBox(width: 8),
                              _buildSpecChip('Sold', '${med.soldCount}+ items'),
                            ],
                          ),

                          const SizedBox(height: 24),

                          // Description
                          Text(
                            'Description',
                            style: GoogleFonts.plusJakartaSans(
                              fontSize: 15,
                              fontWeight: FontWeight.bold,
                              color: AppTheme.textPrimary,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            med.description,
                            style: GoogleFonts.plusJakartaSans(
                              fontSize: 14,
                              color: AppTheme.textSecondary,
                              height: 1.6,
                            ),
                          ),
                          const SizedBox(height: 24),
                        ],
                      ),
                    ),
                  ),

                  // 4. Bottom Total price & Add to Cart (Aligend & sized perfectly)
                  Container(
                    padding: EdgeInsets.only(
                      left: 24,
                      right: 24,
                      top: 14,
                      bottom:
                          14 +
                          MediaQuery.of(context)
                              .padding
                              .bottom, // Dynamically handle bottom navigation safe area spacing
                    ),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.06),
                          blurRadius: 16,
                          offset: const Offset(0, -4),
                        ),
                      ],
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      crossAxisAlignment: CrossAxisAlignment
                          .center, // Centers the price column vertically with the button!
                      children: [
                        // Left: Total price label & dynamic price
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Text(
                              'Total price',
                              style: GoogleFonts.plusJakartaSans(
                                fontSize: 11,
                                fontWeight: FontWeight.w500,
                                color: AppTheme.textSecondary,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              '\$${totalPrice.toStringAsFixed(2)}',
                              style: GoogleFonts.plusJakartaSans(
                                fontSize: 19, // Slightly smaller size
                                fontWeight: FontWeight.bold,
                                color: AppTheme.textPrimary,
                              ),
                            ),
                          ],
                        ),

                        const SizedBox(width: 20), // Spacer
                        // Right: Add to Cart Button (Takes remaining horizontal space cleanly to prevent overflows!)
                        Expanded(
                          child: SizedBox(
                            height: 48, // Balanced height
                            child: ElevatedButton(
                              onPressed: () {
                                appState.addToCart(med, _quantity);
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
                              style: ElevatedButton.styleFrom(
                                backgroundColor:
                                    Colors.black, // Dark black button
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(24),
                                ),
                              ),
                              child: Text(
                                'Add to Cart',
                                style: GoogleFonts.plusJakartaSans(
                                  fontSize: 15,
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
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  // Specification Chip builder
  Widget _buildSpecChip(String label, String value) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
        decoration: BoxDecoration(
          color: const Color(0xFFFAFCFD),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: const Color(0xFFEDF1F5)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: GoogleFonts.plusJakartaSans(
                fontSize: 10,
                color: AppTheme.textSecondary,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              value,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: GoogleFonts.plusJakartaSans(
                fontSize: 12,
                fontWeight: FontWeight.bold,
                color: AppTheme.textPrimary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
