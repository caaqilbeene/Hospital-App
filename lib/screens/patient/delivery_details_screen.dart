import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../config/app_theme.dart';
import '../../models/appointment_model.dart';
import '../../services/app_state.dart';
import 'payment_screen.dart';

class DeliveryDetailsScreen extends StatefulWidget {
  final AppointmentModel? customOrder;

  const DeliveryDetailsScreen({super.key, this.customOrder});

  @override
  State<DeliveryDetailsScreen> createState() => _DeliveryDetailsScreenState();
}

class _DeliveryDetailsScreenState extends State<DeliveryDetailsScreen> {
  String selectedCity = "Mogadishu";
  String? selectedDistrict;

  List<String> mogadishuDistricts = [
    "Abdiaziz",
    "Bondhere",
    "Daynile",
    "Dharkenley",
    "Hodan",
    "Howlwadag",
    "Huriwaa",
    "Kaxda",
    "Karaan",
    "Shangani",
    "Shibis",
    "Waberi",
    "Wadajir",
    "Wardhigley",
    "Yaaqshid",
    "Xamar Jajab",
    "Xamar Weyne",
  ]..sort();

  Map<String, double> deliveryFees = {
    "Abdiaziz": 0.0,
    "Bondhere": 0.0,
    "Daynile": 0.0,
    "Dharkenley": 0.0,
    "Hodan": 0.0,
    "Howlwadag": 0.0,
    "Huriwaa": 0.0,
    "Kaxda": 0.0,
    "Karaan": 0.0,
    "Shangani": 0.0,
    "Shibis": 0.0,
    "Waberi": 0.0,
    "Wadajir": 0.0,
    "Wardhigley": 0.0,
    "Yaaqshid": 0.0,
    "Xamar Jajab": 0.0,
    "Xamar Weyne": 0.0,
  };

  double deliveryFee = 0.0;
  bool isLoading = false;
  bool _hasAttemptedSubmit = false;

  final TextEditingController nameController = TextEditingController();
  final TextEditingController phoneController = TextEditingController();
  final TextEditingController detailsController = TextEditingController();
  final _formKey = GlobalKey<FormState>();

  @override
  void initState() {
    super.initState();
    _loadUserProfile();
  }

  Future<void> _loadUserProfile() async {
    try {
      final appState = Provider.of<AppState>(context, listen: false);
      final user = appState.currentUser;

      final prefs = await SharedPreferences.getInstance();
      String? cachedName = prefs.getString('profile_name');
      String? cachedDistrict = prefs.getString('selected_district');

      String? name = cachedName ?? user?.fullName;
      String? phone = user?.phoneNumber;

      if (mounted) {
        setState(() {
          if (name != null && name.isNotEmpty) {
            nameController.text = name;
          }
          if (phone != null && phone.isNotEmpty) {
            phoneController.text = phone;
          }
        });
      }
    } catch (e) {
      debugPrint("Error loading user profile at checkout: $e");
    }
  }

  @override
  void dispose() {
    nameController.dispose();
    phoneController.dispose();
    detailsController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final appState = context.watch<AppState>();
    final isCustomOrder = widget.customOrder != null;
    final cartItems = isCustomOrder ? [] : appState.cartItems;
    final double subtotal = isCustomOrder
        ? (widget.customOrder?.amount ?? 0.0)
        : appState.cartSubtotal;
    final double totalAmount = subtotal + deliveryFee;

    const accentColor = AppTheme.primaryColor;

    return Scaffold(
      backgroundColor: Colors.white,
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
          "Delivery Details",
          style: GoogleFonts.plusJakartaSans(
            fontSize: 20,
            fontWeight: FontWeight.bold,
            color: AppTheme.textPrimary,
          ),
        ),
        centerTitle: false,
      ),

      // Bottom Confirm Order Button
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 10, 20, 20),
          child: SizedBox(
            height: 54,
            child: ElevatedButton(
              onPressed: isLoading
                  ? null
                  : () async {
                      setState(() {
                        _hasAttemptedSubmit = true;
                      });
                      if (_formKey.currentState!.validate()) {
                        if (selectedDistrict == null ||
                            selectedDistrict!.trim().isEmpty) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text('Please select district!'),
                              backgroundColor: Colors.red,
                            ),
                          );
                          return;
                        }

                        setState(() {
                          isLoading = true;
                        });

                        try {
                          final prefs = await SharedPreferences.getInstance();
                          await prefs.setString(
                            'selected_district',
                            selectedDistrict!,
                          );
                          await prefs.setString(
                            'profile_name',
                            nameController.text,
                          );

                          final String refId =
                              '#ORD${10000 + DateTime.now().millisecond}';
                          final String orderId =
                              'ord_${DateTime.now().millisecondsSinceEpoch}';

                          final orderBooking = AppointmentModel(
                            id: orderId,
                            referenceId: refId,
                            doctorId:
                                widget.customOrder?.doctorId ?? 'pharmacy',
                            doctorName:
                                widget.customOrder?.doctorName ??
                                'Nasiib Hospital Pharmacy',
                            doctorSpecialty: 'Medicines & Skincare',
                            doctorImageUrl: '',
                            hospitalName:
                                'Nasiib Hospital - Mogadishu ($selectedDistrict)',
                            date: 'Today',
                            time: 'Immediate Delivery',
                            appointmentType:
                                widget.customOrder?.appointmentType ??
                                'Delivery Order',
                            patientName: nameController.text.trim(),
                            patientPhone: phoneController.text.trim(),
                            patientAge: 24,
                            patientGender: 'Male',
                            reasonForVisit:
                                'Delivery: ${detailsController.text.trim()}, $selectedDistrict, Mogadishu',
                            paymentMethod: 'EVC Plus',
                            amount: totalAmount,
                            queueNumber: 5,
                            status: 'Confirmed',
                            createdAt: DateTime.now().toIso8601String(),
                          );

                          if (context.mounted) {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) =>
                                    PaymentScreen(booking: orderBooking),
                              ),
                            );
                          }
                        } catch (e) {
                          debugPrint("Error confirming delivery order: $e");
                        } finally {
                          if (mounted) {
                            setState(() {
                              isLoading = false;
                            });
                          }
                        }
                      }
                    },
              style: ElevatedButton.styleFrom(
                backgroundColor: accentColor,
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
              child: isLoading
                  ? const CircularProgressIndicator(color: Colors.white)
                  : Text(
                      "Confirm Order",
                      style: GoogleFonts.plusJakartaSans(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
            ),
          ),
        ),
      ),

      body: Form(
        key: _formKey,
        autovalidateMode: _hasAttemptedSubmit
            ? AutovalidateMode.onUserInteraction
            : AutovalidateMode.disabled,
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Full Name Label & Field (Editable)
              Padding(
                padding: const EdgeInsets.only(left: 4, bottom: 4),
                child: Text(
                  "Full Name",
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 13,
                    color: AppTheme.textSecondary,
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: TextFormField(
                  controller: nameController,
                  textCapitalization: TextCapitalization.words,
                  readOnly: false,
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: AppTheme.textPrimary,
                  ),
                  validator: (val) {
                    if (val == null || val.trim().isEmpty) {
                      return 'Please enter your full name';
                    }
                    return null;
                  },
                  decoration: InputDecoration(
                    fillColor: Colors.white,
                    filled: true,
                    suffixIcon: const Icon(
                      Icons.person_outline_rounded,
                      size: 18,
                      color: accentColor,
                    ),
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 10,
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: const BorderSide(
                        color: accentColor,
                        width: 1.2,
                      ),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: const BorderSide(
                        color: accentColor,
                        width: 1.6,
                      ),
                    ),
                    errorBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: const BorderSide(
                        color: Colors.red,
                        width: 1.2,
                      ),
                    ),
                    focusedErrorBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: const BorderSide(
                        color: Colors.red,
                        width: 1.6,
                      ),
                    ),
                  ),
                ),
              ),

              // Phone Number Label & Field (Editable)
              Padding(
                padding: const EdgeInsets.only(left: 4, bottom: 4),
                child: Text(
                  "Phone Number",
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 13,
                    color: AppTheme.textSecondary,
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: TextFormField(
                  keyboardType: TextInputType.phone,
                  controller: phoneController,
                  readOnly: false,
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: AppTheme.textPrimary,
                  ),
                  validator: (val) {
                    if (val == null || val.trim().isEmpty) {
                      return 'Please enter your phone number';
                    }
                    return null;
                  },
                  decoration: InputDecoration(
                    fillColor: Colors.white,
                    filled: true,
                    suffixIcon: const Icon(
                      Icons.phone_outlined,
                      size: 18,
                      color: accentColor,
                    ),
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 10,
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: const BorderSide(
                        color: accentColor,
                        width: 1.2,
                      ),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: const BorderSide(
                        color: accentColor,
                        width: 1.6,
                      ),
                    ),
                    errorBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: const BorderSide(
                        color: Colors.red,
                        width: 1.2,
                      ),
                    ),
                    focusedErrorBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: const BorderSide(
                        color: Colors.red,
                        width: 1.6,
                      ),
                    ),
                  ),
                ),
              ),

              // City Field (Locked to Mogadishu)
              Padding(
                padding: const EdgeInsets.only(left: 4, bottom: 4),
                child: Text(
                  "City",
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 13,
                    color: AppTheme.textSecondary,
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: TextFormField(
                  initialValue: "Mogadishu",
                  readOnly: true,
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: AppTheme.textPrimary,
                  ),
                  decoration: InputDecoration(
                    fillColor: const Color(0xFFF8FAF9),
                    filled: true,
                    suffixIcon: const Icon(
                      Icons.lock_outline_rounded,
                      size: 16,
                      color: AppTheme.textLight,
                    ),
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 10,
                    ),
                    disabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: const BorderSide(
                        color: accentColor,
                        width: 1.2,
                      ),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: const BorderSide(
                        color: accentColor,
                        width: 1.2,
                      ),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: const BorderSide(
                        color: accentColor,
                        width: 1.2,
                      ),
                    ),
                  ),
                ),
              ),

              // District Dropdown
              Padding(
                padding: const EdgeInsets.only(left: 4, bottom: 4),
                child: Text(
                  "District",
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 13,
                    color: AppTheme.textSecondary,
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: DropdownButtonFormField<String>(
                  isExpanded: true,
                  initialValue: selectedDistrict,
                  hint: Text(
                    "Select District",
                    style: GoogleFonts.plusJakartaSans(
                      color: AppTheme.textLight,
                      fontSize: 14,
                    ),
                  ),
                  validator: (value) {
                    if (value == null || value.trim().isEmpty) {
                      return "Please select your district";
                    }
                    return null;
                  },
                  decoration: InputDecoration(
                    fillColor: Colors.white,
                    filled: true,
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 10,
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: const BorderSide(
                        color: accentColor,
                        width: 1.2,
                      ),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: const BorderSide(
                        color: accentColor,
                        width: 1.6,
                      ),
                    ),
                    errorBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: const BorderSide(
                        color: Colors.red,
                        width: 1.2,
                      ),
                    ),
                    focusedErrorBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: const BorderSide(
                        color: Colors.red,
                        width: 1.6,
                      ),
                    ),
                  ),
                  items: mogadishuDistricts.map((district) {
                    return DropdownMenuItem(
                      value: district,
                      child: Text(
                        district,
                        style: GoogleFonts.plusJakartaSans(
                          fontSize: 14,
                          color: AppTheme.textPrimary,
                        ),
                      ),
                    );
                  }).toList(),
                  onChanged: (value) {
                    setState(() {
                      selectedDistrict = value;
                      if (value != null) {
                        deliveryFee = deliveryFees[value] ?? 0.0;
                      }
                    });
                  },
                ),
              ),

              // Details Multiline Box
              Padding(
                padding: const EdgeInsets.only(left: 4, bottom: 4),
                child: Text(
                  "Details",
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 13,
                    color: AppTheme.textSecondary,
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: TextFormField(
                  controller: detailsController,
                  autocorrect: false,
                  enableSuggestions: false,
                  maxLines: 2,
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 14,
                    color: AppTheme.textPrimary,
                  ),
                  validator: (value) {
                    if (value == null || value.trim().isEmpty) {
                      return "Please enter address or house details";
                    }
                    return null;
                  },
                  decoration: InputDecoration(
                    fillColor: Colors.white,
                    filled: true,
                    hintText:
                        'Ku qor faahfaahin dheeri ah oo ku saabsan ciwaanka ama guriga...',
                    hintStyle: GoogleFonts.plusJakartaSans(
                      color: AppTheme.textLight,
                      fontSize: 13,
                    ),
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 10,
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: const BorderSide(
                        color: accentColor,
                        width: 1.2,
                      ),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: const BorderSide(
                        color: accentColor,
                        width: 1.6,
                      ),
                    ),
                    errorBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: const BorderSide(
                        color: Colors.red,
                        width: 1.2,
                      ),
                    ),
                    focusedErrorBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: const BorderSide(
                        color: Colors.red,
                        width: 1.6,
                      ),
                    ),
                  ),
                ),
              ),

              // Clean summary layout for Nurse / Home Service vs Pharmacy Order
              if (isCustomOrder) ...[
                const Divider(height: 32),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      widget.customOrder!.doctorName,
                      style: GoogleFonts.plusJakartaSans(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: AppTheme.textPrimary,
                      ),
                    ),
                    Text(
                      '\$${(widget.customOrder?.amount ?? 0.0).toStringAsFixed(2)}',
                      style: GoogleFonts.plusJakartaSans(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: const Color(0xFF00897B),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
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
                      '\$${(widget.customOrder?.amount ?? 0.0).toStringAsFixed(2)}',
                      style: GoogleFonts.plusJakartaSans(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                        color: const Color(0xFF00897B),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 24),
              ] else ...[
                // Order Summary Header for Pharmacy Orders
                Text(
                  "Order Summary",
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: AppTheme.textPrimary,
                  ),
                ),
                const SizedBox(height: 6),

                ...cartItems.map(
                  (item) => Padding(
                    padding: const EdgeInsets.symmetric(vertical: 6),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            item.medicine.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: GoogleFonts.plusJakartaSans(
                              fontSize: 15,
                              color: AppTheme.textPrimary,
                            ),
                          ),
                        ),
                        Text(
                          "x${item.quantity}",
                          style: GoogleFonts.plusJakartaSans(
                            color: accentColor,
                            fontWeight: FontWeight.bold,
                            fontSize: 14,
                          ),
                        ),
                        const SizedBox(width: 16),
                        Text(
                          "\$${(item.medicine.price * item.quantity).toStringAsFixed(2)}",
                          style: GoogleFonts.plusJakartaSans(
                            fontWeight: FontWeight.w600,
                            fontSize: 15,
                            color: AppTheme.textPrimary,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),

                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 12),
                  child: Divider(color: Color(0xFFEEEEEE)),
                ),

                Row(
                  children: [
                    Text(
                      "Items (${appState.cartCount})",
                      style: GoogleFonts.plusJakartaSans(
                        fontSize: 14,
                        color: AppTheme.textSecondary,
                      ),
                    ),
                    const Spacer(),
                    Text(
                      "\$${subtotal.toStringAsFixed(2)}",
                      style: GoogleFonts.plusJakartaSans(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: AppTheme.textPrimary,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),

                Row(
                  children: [
                    Text(
                      "Delivery Fee",
                      style: GoogleFonts.plusJakartaSans(
                        fontSize: 14,
                        color: AppTheme.textSecondary,
                      ),
                    ),
                    const Spacer(),
                    Text(
                      "\$${deliveryFee.toStringAsFixed(2)}",
                      style: GoogleFonts.plusJakartaSans(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: AppTheme.textPrimary,
                      ),
                    ),
                  ],
                ),

                const SizedBox(height: 12),

                Row(
                  children: [
                    Text(
                      "Total Amount",
                      style: GoogleFonts.plusJakartaSans(
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                        color: AppTheme.textPrimary,
                      ),
                    ),
                    const Spacer(),
                    Text(
                      "\$${totalAmount.toStringAsFixed(2)}",
                      style: GoogleFonts.plusJakartaSans(
                        color: const Color(0xFF00897B),
                        fontWeight: FontWeight.bold,
                        fontSize: 18,
                      ),
                    ),
                  ],
                ),

                const SizedBox(height: 20),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
