import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';

import '../../config/app_theme.dart';
import '../../models/appointment_model.dart';
import '../../services/app_state.dart';
import '../../services/push_notification_service.dart';
import '../../utils/somali_phone_formatter.dart';
import 'appointment_confirmed_screen.dart';
import 'main_patient_layout.dart';
import 'my_orders_screen.dart';

// ─────────────────────────────────────────────
// Payment Method enum
// ─────────────────────────────────────────────
enum _PayMethod { evcPlus, eDahab, card }

class PaymentScreen extends StatefulWidget {
  final AppointmentModel booking;
  const PaymentScreen({super.key, required this.booking});

  @override
  State<PaymentScreen> createState() => _PaymentScreenState();
}

class _PaymentScreenState extends State<PaymentScreen> {
  // ✅ Null = nothing selected initially — no radio pre-checked
  _PayMethod? _selectedMethod;
  bool _isProcessing = false;

  // Mobile wallet phone controller
  final TextEditingController _phoneController = TextEditingController();

  // Card controllers
  final TextEditingController _cardNameController = TextEditingController();
  final TextEditingController _cardNumberController = TextEditingController();
  final TextEditingController _expiryController = TextEditingController();
  final TextEditingController _cvcController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _cardNumberController.addListener(() => setState(() {}));
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        final appState = Provider.of<AppState>(context, listen: false);
        final u = appState.currentUser;
        // Auto-fill patient name for card holder
        final String pName = widget.booking.patientName.isNotEmpty
            ? widget.booking.patientName
            : (u?.fullName ?? '');
        if (pName.isNotEmpty && _cardNameController.text.isEmpty) {
          _cardNameController.text = pName;
        }
      }
    });
  }

  @override
  void dispose() {
    _phoneController.dispose();
    _cardNameController.dispose();
    _cardNumberController.dispose();
    _expiryController.dispose();
    _cvcController.dispose();
    super.dispose();
  }

  String get _methodLabel {
    switch (_selectedMethod) {
      case _PayMethod.evcPlus:
        return 'EVC Plus';
      case _PayMethod.eDahab:
        return 'E-Dahab';
      case _PayMethod.card:
        final raw = _cardNumberController.text.replaceAll(' ', '');
        final last4 = raw.length >= 4 ? raw.substring(raw.length - 4) : '••••';
        final type = raw.startsWith('4')
            ? 'Visa'
            : raw.startsWith('5')
            ? 'Mastercard'
            : 'Card';
        return '$type (•••• $last4)';
      case null:
        return '';
    }
  }

  bool get _isDelivery =>
      widget.booking.reasonForVisit.startsWith('Delivery:') ||
      widget.booking.doctorName.toLowerCase().contains('order') ||
      widget.booking.doctorName.toLowerCase().contains('cart');

  bool get _isNurse =>
      widget.booking.doctorSpecialty.toLowerCase().contains('nurse') ||
      widget.booking.doctorName.toLowerCase().contains('nurse') ||
      widget.booking.reasonForVisit.toLowerCase().contains('nurse') ||
      widget.booking.doctorSpecialty.toLowerCase().contains('kalkaali') ||
      widget.booking.doctorName.toLowerCase().contains('kalkaali') ||
      widget.booking.id.startsWith('nurse_');

  Future<void> _onPayNow() async {
    // 1. Guard: check if method selected
    if (_selectedMethod == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please select a payment method'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    // 2. Validate EVC Plus & E-Dahab strict prefixes
    if (_selectedMethod == _PayMethod.evcPlus ||
        _selectedMethod == _PayMethod.eDahab) {
      final rawInput = _phoneController.text.trim();
      final phoneError = validateSomaliPhoneNumber(rawInput);
      if (phoneError != null) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(phoneError),
            backgroundColor: Colors.red,
          ),
        );
        return;
      }

      final digits = rawInput.replaceAll(RegExp(r'\D'), '');
      String localPrefix = digits;
      if (localPrefix.startsWith('252')) {
        localPrefix = localPrefix.substring(3);
      } else if (localPrefix.startsWith('0')) {
        localPrefix = localPrefix.substring(1);
      }

      if (_selectedMethod == _PayMethod.evcPlus) {
        if (!localPrefix.startsWith('61')) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                'EVC Plus accepts Hormuud numbers only (starting with 61).',
              ),
              backgroundColor: Colors.red,
            ),
          );
          return;
        }
      } else if (_selectedMethod == _PayMethod.eDahab) {
        if (!localPrefix.startsWith('62')) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                'E-Dahab accepts Somtel numbers only (starting with 62).',
              ),
              backgroundColor: Colors.red,
            ),
          );
          return;
        }
      }
    }

    // 3. Validate Credit / Debit Card (All fields strictly required)
    if (_selectedMethod == _PayMethod.card) {
      final cardHolder = _cardNameController.text.trim();
      final cardNumber = _cardNumberController.text.trim();
      final expiry = _expiryController.text.trim();
      final cvv = _cvcController.text.trim();

      if (cardHolder.isEmpty ||
          cardNumber.isEmpty ||
          expiry.isEmpty ||
          cvv.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Please fill all card details (Name, Card Number, Expiry, and CVV)',
            ),
            backgroundColor: Colors.red,
          ),
        );
        return;
      }

      if (cardNumber.replaceAll(' ', '').length < 16) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Please enter a valid 16-digit card number'),
            backgroundColor: Colors.red,
          ),
        );
        return;
      }
    }

    if (_isProcessing) return;
    setState(() => _isProcessing = true);

    final appState = context.read<AppState>();
    appState.updateDraftBooking(paymentMethod: _methodLabel);

    if (_isNurse) {
      try {
        final rawReason = widget.booking.reasonForVisit
            .replaceAll('Nurse Request: ', '')
            .replaceAll('Delivery: ', '');
        final parts = rawReason.split(',');
        final district = parts.length > 1 ? parts[parts.length - 2].trim() : (parts.isNotEmpty ? parts[0].trim() : 'Hodan');
        final address = rawReason;

        final bookingId = await appState.placeNurseOrder(
          nurseId: widget.booking.doctorId,
          nurseName: widget.booking.doctorName,
          patientName: widget.booking.patientName,
          phone: widget.booking.patientPhone,
          district: district,
          address: address,
          notes: widget.booking.reasonForVisit,
          fee: widget.booking.amount,
          paymentMethod: _methodLabel,
          status: 'Pending',
        );

        final String finalBookingId = bookingId ?? widget.booking.referenceId;

        appState.confirmCurrentBooking();
        final confirmedBooking = AppointmentModel(
          id: widget.booking.id,
          referenceId: finalBookingId,
          doctorId: widget.booking.doctorId,
          doctorName: widget.booking.doctorName,
          doctorSpecialty: widget.booking.doctorSpecialty,
          doctorImageUrl: widget.booking.doctorImageUrl,
          hospitalName: widget.booking.hospitalName,
          date: widget.booking.date,
          time: widget.booking.time,
          appointmentType: widget.booking.appointmentType,
          patientName: widget.booking.patientName,
          patientPhone: widget.booking.patientPhone,
          patientAge: widget.booking.patientAge,
          patientGender: widget.booking.patientGender,
          reasonForVisit: widget.booking.reasonForVisit,
          paymentMethod: _methodLabel,
          amount: widget.booking.amount,
          queueNumber: widget.booking.queueNumber,
          status: 'Confirmed',
          createdAt: widget.booking.createdAt,
        );
        appState.addAppointment(confirmedBooking);

        if (mounted) {
          _showPaymentSuccessDialog(
            context: context,
            orderId: bookingId ?? widget.booking.referenceId,
            itemCount: 1,
            address: district,
            paymentMethod: _methodLabel,
            totalAmount: widget.booking.amount,
            isNurse: true,
            nurseName: widget.booking.doctorName,
          );
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Nurse booking failed: $e'),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    } else if (_isDelivery) {
      final items = appState.cartItems
          .map(
            (c) => {
              'name': c.medicine.title,
              'price': c.medicine.price,
              'quantity': c.quantity,
            },
          )
          .toList();

      if (items.isEmpty) {
        items.add({
          'name': widget.booking.doctorName,
          'price': widget.booking.amount,
          'quantity': 1,
        });
      }

      try {
        String realDistrict = 'Hodan';
        final reasonStr = widget.booking.reasonForVisit;
        if (reasonStr.contains(',')) {
          final parts = reasonStr.split(',');
          if (parts.length >= 2) {
            realDistrict = parts[parts.length - 2].trim();
          }
        }
        if (realDistrict == 'Medicines & Skincare' || realDistrict.isEmpty) {
          final hosp = widget.booking.hospitalName;
          if (hosp.contains('(') && hosp.contains(')')) {
            realDistrict = hosp.split('(').last.replaceAll(')', '').trim();
          }
        }
        if (realDistrict.isEmpty || realDistrict == 'Medicines & Skincare') {
          realDistrict = 'Hodan';
        }

        final orderId = await appState.placeOrder(
          patientName: widget.booking.patientName,
          patientPhone: widget.booking.patientPhone,
          city: 'Mogadishu',
          district: realDistrict,
          deliveryAddress: widget.booking.reasonForVisit.replaceAll(
            'Delivery: ',
            '',
          ),
          subtotal: widget.booking.amount,
          deliveryFee: 0.0,
          totalAmount: widget.booking.amount,
          paymentMethod: _methodLabel,
          paymentStatus: 'Paid',
          items: items,
        );

        if (mounted) {
          // ✅ Await clearCart() so ALL storage keys are wiped before dialog
          await context.read<AppState>().clearCart();

          // Show local notification strictly on this patient's device
          PushNotificationService.instance.showLocalNotification(
            title: 'Nasiib Pharmacy',
            body: 'Waan helnay dalabkaaga dawooyinka, dhakhso ayaan kuugu soo diyaarinaynaa.',
          );

          _showPaymentSuccessDialog(
            context: context,
            orderId: orderId ?? widget.booking.referenceId,
            itemCount: items.length,
            address: widget.booking.reasonForVisit.replaceAll('Delivery: ', ''),
            paymentMethod: _methodLabel,
            totalAmount: widget.booking.amount,
            purchasedItems: items,
          );
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Order failed: $e'),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    } else {
      // Appointment payment flow
      final int dynamicQueue = await appState.getRealNextQueueNumber(
        doctorId: widget.booking.doctorId,
        doctorName: widget.booking.doctorName,
        date: widget.booking.date,
      );

      final confirmedBooking = AppointmentModel(
        id: widget.booking.id,
        referenceId: widget.booking.referenceId,
        doctorId: widget.booking.doctorId,
        doctorName: widget.booking.doctorName,
        doctorSpecialty: widget.booking.doctorSpecialty,
        doctorImageUrl: widget.booking.doctorImageUrl,
        hospitalName: widget.booking.hospitalName,
        date: widget.booking.date,
        time: widget.booking.time,
        appointmentType: widget.booking.appointmentType,
        patientName: widget.booking.patientName,
        patientPhone: widget.booking.patientPhone,
        patientAge: widget.booking.patientAge,
        patientGender: widget.booking.patientGender,
        reasonForVisit: widget.booking.reasonForVisit,
        paymentMethod: _methodLabel,
        amount: widget.booking.amount,
        queueNumber: dynamicQueue,
        status: 'Confirmed',
        createdAt: DateTime.now().toIso8601String(),
      );
      await appState.addAppointment(confirmedBooking);

      if (mounted) {
        // Show local notification strictly on this patient's device
        PushNotificationService.instance.showLocalNotification(
          title: 'Nasiib Hospital',
          body: 'Ballantaadii Dhaqtarka waa la xaqiijiyay! Lambarka safkaaga waa #$dynamicQueue.',
        );

        _showPaymentSuccessDialog(
          context: context,
          orderId: widget.booking.referenceId,
          itemCount: 1,
          address: widget.booking.hospitalName,
          paymentMethod: _methodLabel,
          totalAmount: widget.booking.amount,
          isDoctorAppointment: true,
          doctorName: widget.booking.doctorName,
          doctorSpecialty: widget.booking.doctorSpecialty,
          appointmentDate: widget.booking.date,
          appointmentTime: widget.booking.time,
          queueNumber: dynamicQueue,
        );
      }
    }

    if (mounted) setState(() => _isProcessing = false);
  }

  @override
  Widget build(BuildContext context) {
    final appState = context.watch<AppState>();
    final subtotal = widget.booking.amount;
    final deliveryFee = 0.0;
    final total = widget.booking.amount;

    return Scaffold(
      backgroundColor: const Color(0xFFF4F6FB),
      appBar: AppBar(
        backgroundColor: const Color(0xFFF4F6FB),
        elevation: 0,
        centerTitle: true,
        leading: IconButton(
          icon: const Icon(
            Icons.arrow_back_ios_new_rounded,
            color: Color(0xFF1F1F1F),
            size: 20,
          ),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          'Payment Option',
          style: GoogleFonts.plusJakartaSans(
            fontSize: 18,
            fontWeight: FontWeight.bold,
            color: const Color(0xFF1F1F1F),
          ),
        ),
      ),
      body: SafeArea(
        child: Column(
          children: [
            // ── Scrollable content ──────────────────────────────
            Expanded(
              child: SingleChildScrollView(
                physics: const BouncingScrollPhysics(),
                padding: const EdgeInsets.symmetric(
                  horizontal: 20,
                  vertical: 14,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // ── Payment Method header ──
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          'Payment Method',
                          style: GoogleFonts.plusJakartaSans(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            color: const Color(0xFF1F1F1F),
                          ),
                        ),
                        if (_selectedMethod == _PayMethod.card)
                          Text(
                            '+ Add New Card',
                            style: GoogleFonts.plusJakartaSans(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: AppTheme.primaryColor,
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 12),

                    // ── Radio tiles ──
                    _buildMethodCard(
                      method: _PayMethod.evcPlus,
                      title: 'EVC Plus',
                      subtitle: 'Hormuud Telecom',
                      leading: _walletBadge('EVC', const Color(0xFF00796B)),
                    ),
                    const SizedBox(height: 8),
                    _buildMethodCard(
                      method: _PayMethod.eDahab,
                      title: 'E-Dahab',
                      subtitle: 'Somtel',
                      leading: _walletBadge('E-Dahab', const Color(0xFFFFB300)),
                    ),
                    const SizedBox(height: 8),
                    _buildMethodCard(
                      method: _PayMethod.card,
                      title: 'Credit / Debit Card',
                      subtitle: 'Visa · Mastercard',
                      leading: FittedBox(
                        fit: BoxFit.scaleDown,
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Image.network(
                              'https://img.icons8.com/color/48/visa.png',
                              width: 20,
                              height: 20,
                              errorBuilder: (_, _, _) => const Icon(
                                Icons.credit_card_rounded,
                                size: 18,
                              ),
                            ),
                            const SizedBox(width: 2),
                            Image.network(
                              'https://img.icons8.com/color/48/mastercard.png',
                              width: 20,
                              height: 20,
                              errorBuilder: (_, _, _) => const Icon(
                                Icons.credit_card_rounded,
                                size: 18,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),

                    // ── Dynamic input form (only when a method is selected) ──
                    if (_selectedMethod != null) ...[
                      const SizedBox(height: 16),
                      AnimatedSwitcher(
                        duration: const Duration(milliseconds: 280),
                        transitionBuilder: (child, anim) =>
                            FadeTransition(opacity: anim, child: child),
                        child: _selectedMethod == _PayMethod.card
                            ? _buildCardForm()
                            : _buildWalletForm(),
                      ),
                    ],

                    const SizedBox(height: 16),
                  ],
                ),
              ),
            ),

            // ── Payment Summary + Pay Button ────────────────────
            _buildBottomSummary(
              subtotal: subtotal,
              deliveryFee: deliveryFee,
              total: total,
              isDelivery: _isDelivery,
            ),
          ],
        ),
      ),
    );
  }

  // ─────────────────────────────────────────────
  // Radio tile card
  // ─────────────────────────────────────────────
  Widget _buildMethodCard({
    required _PayMethod method,
    required String title,
    required String subtitle,
    required Widget leading,
  }) {
    final bool selected = _selectedMethod == method;
    void selectMethod(_PayMethod? v) {
      setState(() {
        if (_selectedMethod != v) {
          _phoneController.clear();
        }
        _selectedMethod = v;
      });
    }

    return GestureDetector(
      onTap: () => selectMethod(method),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: selected ? AppTheme.primaryColor : const Color(0xFFE8ECF4),
            width: selected ? 2 : 1.2,
          ),
          boxShadow: selected
              ? [
                  BoxShadow(
                    color: AppTheme.primaryColor.withOpacity(0.08),
                    blurRadius: 12,
                    offset: const Offset(0, 4),
                  ),
                ]
              : [],
        ),
        child: Row(
          children: [
            SizedBox(
              width: 44,
              child: Center(
                child: FittedBox(fit: BoxFit.scaleDown, child: leading),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    title,
                    style: GoogleFonts.plusJakartaSans(
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                      color: const Color(0xFF1F1F1F),
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: GoogleFonts.plusJakartaSans(
                      fontSize: 12,
                      color: const Color(0xFF94A3B8),
                    ),
                  ),
                ],
              ),
            ),
            Radio<_PayMethod?>(
              value: method,
              groupValue: _selectedMethod,
              onChanged: (v) => selectMethod(v),
              activeColor: AppTheme.primaryColor,
              materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
          ],
        ),
      ),
    );
  }

  // ─────────────────────────────────────────────
  // Wallet badge icon (EVC / eDahab)
  // ─────────────────────────────────────────────
  Widget _walletBadge(String label, Color color) {
    return Container(
      width: 44,
      height: 40,
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Center(
        child: Text(
          label,
          style: GoogleFonts.plusJakartaSans(
            fontSize: label.length > 3 ? 9 : 11,
            fontWeight: FontWeight.w800,
            color: Colors.white,
          ),
        ),
      ),
    );
  }

  // ─────────────────────────────────────────────
  // Mobile wallet form (phone number)
  // ─────────────────────────────────────────────
  Widget _buildWalletForm() {
    final isEvc = _selectedMethod == _PayMethod.evcPlus;
    final walletName = isEvc ? 'EVC Plus' : 'E-Dahab';
    final hint = isEvc ? '61XXXXXXX' : '62XXXXXXX';

    return Container(
      key: ValueKey(walletName),
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE8ECF4)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '$walletName Phone Number',
            style: GoogleFonts.plusJakartaSans(
              fontSize: 13,
              fontWeight: FontWeight.bold,
              color: const Color(0xFF1F1F1F),
            ),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _phoneController,
            keyboardType: TextInputType.phone,
            inputFormatters: [
              FilteringTextInputFormatter.digitsOnly,
              SomaliPhoneInputFormatter(),
            ],
            style: GoogleFonts.plusJakartaSans(fontSize: 14),
            decoration: InputDecoration(
              hintText: hint,
              hintStyle: GoogleFonts.plusJakartaSans(
                color: const Color(0xFFCBD5E1),
              ),
              prefixIcon: const Icon(
                Icons.phone_android_rounded,
                size: 20,
                color: Color(0xFF94A3B8),
              ),
              filled: true,
              fillColor: const Color(0xFFF8FAFC),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(color: Color(0xFFE8ECF4)),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(color: Color(0xFFE8ECF4)),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(
                  color: AppTheme.primaryColor,
                  width: 1.5,
                ),
              ),
              contentPadding: const EdgeInsets.symmetric(
                vertical: 14,
                horizontal: 14,
              ),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Lacagta waxaa laga goosanayaa taleefankaaga $walletName',
            style: GoogleFonts.plusJakartaSans(
              fontSize: 11,
              color: const Color(0xFF94A3B8),
            ),
          ),
        ],
      ),
    );
  }

  // ─────────────────────────────────────────────
  // Credit/Debit Card form
  // ─────────────────────────────────────────────
  Widget _buildCardForm() {
    Widget prefixIcon() {
      final text = _cardNumberController.text.replaceAll(' ', '');
      if (text.startsWith('4')) {
        return Padding(
          padding: const EdgeInsets.all(10),
          child: Image.network(
            'https://img.icons8.com/color/48/visa.png',
            width: 24,
            errorBuilder: (_, _, _) => const Icon(Icons.credit_card_rounded),
          ),
        );
      } else if (text.startsWith('5')) {
        return Padding(
          padding: const EdgeInsets.all(10),
          child: Image.network(
            'https://img.icons8.com/color/48/mastercard.png',
            width: 24,
            errorBuilder: (_, _, _) => const Icon(Icons.credit_card_rounded),
          ),
        );
      }
      return const Icon(Icons.credit_card_rounded, color: Color(0xFF94A3B8));
    }

    final inputDecoration = InputDecoration(
      filled: true,
      fillColor: const Color(0xFFF8FAFC),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: Color(0xFFE8ECF4)),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: Color(0xFFE8ECF4)),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: AppTheme.primaryColor, width: 1.5),
      ),
      contentPadding: const EdgeInsets.symmetric(vertical: 14, horizontal: 14),
    );

    return Container(
      key: const ValueKey('card_form'),
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE8ECF4)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Cardholder name
          Text(
            'Cardholder Name',
            style: GoogleFonts.plusJakartaSans(
              fontSize: 13,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _cardNameController,
            style: GoogleFonts.plusJakartaSans(fontSize: 14),
            textCapitalization: TextCapitalization.words,
            decoration: inputDecoration.copyWith(hintText: 'e.g. Full Name'),
          ),
          const SizedBox(height: 14),

          // Card number
          Text(
            'Card Number',
            style: GoogleFonts.plusJakartaSans(
              fontSize: 13,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _cardNumberController,
            keyboardType: TextInputType.number,
            style: GoogleFonts.plusJakartaSans(fontSize: 14),
            inputFormatters: [CardNumberInputFormatter()],
            decoration: inputDecoration.copyWith(
              hintText: 'xxxx  xxxx  xxxx  xxxx',
              prefixIcon: prefixIcon(),
            ),
          ),
          const SizedBox(height: 14),

          // Expiry + CVC row
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Expiry (MM/YY)',
                      style: GoogleFonts.plusJakartaSans(
                        fontSize: 13,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: _expiryController,
                      keyboardType: TextInputType.number,
                      style: GoogleFonts.plusJakartaSans(fontSize: 14),
                      inputFormatters: [CardExpiryInputFormatter()],
                      decoration: inputDecoration.copyWith(hintText: '12/28'),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'CVC',
                      style: GoogleFonts.plusJakartaSans(
                        fontSize: 13,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: _cvcController,
                      keyboardType: TextInputType.number,
                      obscureText: true,
                      style: GoogleFonts.plusJakartaSans(fontSize: 14),
                      inputFormatters: [
                        FilteringTextInputFormatter.digitsOnly,
                        LengthLimitingTextInputFormatter(3),
                      ],
                      decoration: inputDecoration.copyWith(hintText: '•••'),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // ─────────────────────────────────────────────
  // Bottom summary + Pay Now button
  // ─────────────────────────────────────────────
  Widget _buildBottomSummary({
    required double subtotal,
    required double deliveryFee,
    required double total,
    required bool isDelivery,
  }) {
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 24),
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        boxShadow: [
          BoxShadow(
            color: Color(0x14000000),
            blurRadius: 20,
            offset: Offset(0, -4),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Title
          Align(
            alignment: Alignment.centerLeft,
            child: Text(
              'Payment Summary',
              style: GoogleFonts.plusJakartaSans(
                fontSize: 15,
                fontWeight: FontWeight.bold,
                color: const Color(0xFF1F1F1F),
              ),
            ),
          ),
          const SizedBox(height: 14),

          // Items total row / Nurse Fee
          if (_isNurse) ...[
            _summaryRow(
              label: 'Nurse Fee',
              value: '\$${total.toStringAsFixed(2)}',
            ),
          ] else ...[
            _summaryRow(
              label: isDelivery ? 'Items Total' : 'Consultation Fee',
              value: '\$${subtotal.toStringAsFixed(2)}',
            ),
            if (isDelivery) ...[
              const SizedBox(height: 6),
              _summaryRow(
                label: 'Delivery Fee',
                value: '\$${deliveryFee.toStringAsFixed(2)}',
              ),
            ],
          ],

          const SizedBox(height: 10),
          _buildDashedDivider(),
          const SizedBox(height: 10),

          // Total row
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Total:',
                style: GoogleFonts.plusJakartaSans(
                  fontSize: 15,
                  fontWeight: FontWeight.bold,
                  color: const Color(0xFF1F1F1F),
                ),
              ),
              Text(
                '\$${total.toStringAsFixed(2)}',
                style: GoogleFonts.plusJakartaSans(
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                  color: AppTheme.primaryColor,
                ),
              ),
            ],
          ),

          const SizedBox(height: 18),

          // Pay Now button
          SizedBox(
            width: double.infinity,
            height: 52,
            child: ElevatedButton(
              onPressed: _isProcessing ? null : _onPayNow,
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF1A1F36),
                disabledBackgroundColor: const Color(
                  0xFF1A1F36,
                ).withOpacity(0.6),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
                elevation: 0,
              ),
              child: _isProcessing
                  ? const SizedBox(
                      width: 22,
                      height: 22,
                      child: CircularProgressIndicator(
                        color: Colors.white,
                        strokeWidth: 2.5,
                      ),
                    )
                  : Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          'Pay Now',
                          style: GoogleFonts.plusJakartaSans(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                          ),
                        ),
                        const SizedBox(width: 10),
                        const Icon(
                          Icons.arrow_forward_rounded,
                          color: Colors.white,
                          size: 20,
                        ),
                      ],
                    ),
            ),
          ),

          const SizedBox(height: 6),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(
                Icons.lock_outline_rounded,
                size: 13,
                color: Color(0xFF94A3B8),
              ),
              const SizedBox(width: 4),
              Text(
                'Secure & encrypted payment',
                style: GoogleFonts.plusJakartaSans(
                  fontSize: 11,
                  color: const Color(0xFF94A3B8),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _summaryRow({required String label, required String value}) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: GoogleFonts.plusJakartaSans(
            fontSize: 13,
            color: const Color(0xFF94A3B8),
          ),
        ),
        Text(
          value,
          style: GoogleFonts.plusJakartaSans(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: const Color(0xFF1F1F1F),
          ),
        ),
      ],
    );
  }

  Widget _buildDashedDivider() {
    return LayoutBuilder(
      builder: (context, constraints) {
        final count = (constraints.constrainWidth() / 10).floor();
        return Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: List.generate(
            count,
            (_) =>
                Container(width: 5, height: 1, color: const Color(0xFFE2E8F0)),
          ),
        );
      },
    );
  }
}

// ─────────────────────────────────────────────
// Address cleaning & deduplication helper
// ─────────────────────────────────────────────
String _cleanFormattedAddress(String raw) {
  if (raw.trim().isEmpty) return 'Mogadishu';
  var cleaned = raw.replaceAll('Delivery: ', '').trim();
  final parts = cleaned.split(',').map((p) => p.trim()).where((p) => p.isNotEmpty).toList();
  final seen = <String>{};
  final result = <String>[];

  for (final p in parts) {
    final normalized = p.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');
    if (!seen.contains(normalized)) {
      seen.add(normalized);
      result.add(p);
    }
  }

  return result.isNotEmpty ? result.join(', ') : 'Mogadishu';
}

// ─────────────────────────────────────────────
// Payment Success Dialog (Image Receipt Capture + Pure Text Share)
// ─────────────────────────────────────────────
void _showPaymentSuccessDialog({
  required BuildContext context,
  required String orderId,
  required int itemCount,
  required String address,
  required String paymentMethod,
  required double totalAmount,
  bool isNurse = false,
  String? nurseName,
  bool isDoctorAppointment = false,
  String? doctorName,
  String? doctorSpecialty,
  String? appointmentDate,
  String? appointmentTime,
  int? queueNumber,
  List<Map<String, dynamic>>? purchasedItems,
}) {
  final cleanAddress = _cleanFormattedAddress(address);
  final cleanOrderId = orderId.startsWith('#') ? orderId : '#$orderId';
  final nowStr = DateFormat('MMMM d, yyyy, h:mm a').format(DateTime.now());
  final serviceTitle = isDoctorAppointment
      ? 'Doctor Consultation: ${doctorName ?? 'Doctor'}'
      : (isNurse ? (nurseName ?? 'Home Nurse Care') : 'Medicines & Delivery ($itemCount items)');

  final GlobalKey receiptRepaintKey = GlobalKey();

  Future<void> captureAndShareReceipt() async {
    final receiptTextSummary = StringBuffer()
      ..writeln(isDoctorAppointment
          ? '🏥 *NASIIB HOSPITAL - APPOINTMENT PAYMENT RECEIPT*'
          : '🏥 *NASIIB HOSPITAL - OFFICIAL PAYMENT RECEIPT*')
      ..writeln('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━')
      ..writeln('✅ *Status:* PAID')
      ..writeln('🧾 *Receipt ID:* $cleanOrderId')
      ..writeln('📅 *Date:* $nowStr');

    if (isDoctorAppointment) {
      if (doctorName != null) receiptTextSummary.writeln('👨‍⚕️ *Doctor:* $doctorName');
      if (doctorSpecialty != null) receiptTextSummary.writeln('🩺 *Specialty:* $doctorSpecialty');
      if (appointmentDate != null) receiptTextSummary.writeln('🗓️ *Appointment Date:* $appointmentDate');
      if (appointmentTime != null) receiptTextSummary.writeln('⏰ *Time:* $appointmentTime');
      if (queueNumber != null) receiptTextSummary.writeln('🔢 *Queue Number:* #$queueNumber');
    } else if (purchasedItems != null && purchasedItems.isNotEmpty) {
      receiptTextSummary.writeln('📋 *Items Purchased:*');
      for (final it in purchasedItems) {
        final qty = (it['quantity'] as num?)?.toInt() ?? 1;
        final unitPrice = (it['price'] as num?)?.toDouble() ?? 0.0;
        final itTotal = unitPrice * qty;
        receiptTextSummary.writeln('  • ${it['name']} x$qty - \$${itTotal.toStringAsFixed(2)}');
      }
    } else {
      receiptTextSummary.writeln('🩺 *Service:* $serviceTitle');
    }

    if (!isDoctorAppointment) {
      receiptTextSummary.writeln('📍 *Address:* $cleanAddress');
    }
    receiptTextSummary
      ..writeln('💳 *Payment Method:* $paymentMethod')
      ..writeln('💵 *Total Paid:* \$${totalAmount.toStringAsFixed(2)}')
      ..writeln('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━')
      ..writeln(isDoctorAppointment
          ? 'Thank you for booking with Nasiib Hospital!'
          : 'Thank you for your purchase!');

    try {
      final boundary = receiptRepaintKey.currentContext?.findRenderObject()
          as RenderRepaintBoundary?;
      if (boundary != null) {
        final ui.Image image = await boundary.toImage(pixelRatio: 3.0);
        final ByteData? byteData =
            await image.toByteData(format: ui.ImageByteFormat.png);
        if (byteData != null) {
          final pngBytes = byteData.buffer.asUint8List();
          final tempDir = Directory.systemTemp;
          final safeId = cleanOrderId.replaceAll(RegExp(r'[^a-zA-Z0-9]'), '_');
          final file = File('${tempDir.path}/Receipt_$safeId.png');
          await file.writeAsBytes(pngBytes);

          await Share.shareXFiles(
            [XFile(file.path)],
            text: 'Nasiib Hospital Payment Receipt - $cleanOrderId',
          );
          return;
        }
      }
    } catch (e) {
      debugPrint('[RECEIPT_SHARE_ERROR] $e');
    }

    // Fallback if image generation is unavailable
    await Share.share(
      receiptTextSummary.toString(),
      subject: 'Nasiib Hospital Payment Receipt - $cleanOrderId',
    );
  }

  showDialog(
    context: context,
    barrierDismissible: false,
    builder: (ctx) {
      return PopScope(
        canPop: false,
        onPopInvokedWithResult: (didPop, result) {
          if (didPop) return;
          Navigator.pushAndRemoveUntil(
            context,
            MaterialPageRoute(
              builder: (_) => const MainPatientLayout(),
            ),
            (route) => false,
          );
        },
        child: Dialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
          backgroundColor: Colors.white,
          insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
          child: SingleChildScrollView(
            child: Padding(
              padding: const EdgeInsets.all(20.0),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Top Close button only
                  Align(
                    alignment: Alignment.topRight,
                    child: IconButton(
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(),
                      icon: const Icon(
                        Icons.close_rounded,
                        color: Color(0xFF64748B),
                        size: 24,
                      ),
                      onPressed: () {
                        Navigator.pushAndRemoveUntil(
                          context,
                          MaterialPageRoute(
                            builder: (_) => const MainPatientLayout(),
                          ),
                          (route) => false,
                        );
                      },
                    ),
                  ),
                  const SizedBox(height: 6),

                  // 📄 Capture-Ready Receipt Card (Matching Screenshot 2 Style)
                  RepaintBoundary(
                    key: receiptRepaintKey,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 20,
                        vertical: 24,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: const Color(0xFFE2E8F0)),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.03),
                            blurRadius: 10,
                            offset: const Offset(0, 4),
                          ),
                        ],
                      ),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          // Green Checkmark Icon Badge
                          Container(
                            width: 52,
                            height: 52,
                            decoration: const BoxDecoration(
                              color: Color(0xFFD1FADF),
                              shape: BoxShape.circle,
                            ),
                            child: const Center(
                              child: Icon(
                                Icons.check_rounded,
                                color: Color(0xFF12B76A),
                                size: 32,
                              ),
                            ),
                          ),
                          const SizedBox(height: 12),
                          Text(
                            isDoctorAppointment
                                ? 'Appointment Booked'
                                : 'Payment Successful',
                            style: GoogleFonts.plusJakartaSans(
                              fontSize: 20,
                              fontWeight: FontWeight.w800,
                              color: const Color(0xFF0F172A),
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'Nasiib Hospital',
                            style: GoogleFonts.plusJakartaSans(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: const Color(0xFF0D7C66),
                            ),
                          ),
                          const Divider(height: 24, color: Color(0xFFE2E8F0)),

                          // Date & Receipt ID
                          _dialogRow('Date', nowStr),
                          const SizedBox(height: 8),
                          _dialogRow(
                            isDoctorAppointment ? 'Reference ID' : 'Receipt ID',
                            cleanOrderId,
                          ),
                          const Divider(height: 24, color: Color(0xFFE2E8F0)),

                          // 📋 Doctor Details OR Itemized Medicines OR Service Details
                          if (isDoctorAppointment) ...[
                            if (doctorName != null) ...[
                              _dialogRow('Doctor', doctorName),
                              const SizedBox(height: 8),
                            ],
                            if (doctorSpecialty != null) ...[
                              _dialogRow('Specialty', doctorSpecialty),
                              const SizedBox(height: 8),
                            ],
                            if (appointmentDate != null) ...[
                              _dialogRow('Date', appointmentDate),
                              const SizedBox(height: 8),
                            ],
                            if (appointmentTime != null) ...[
                              _dialogRow('Time', appointmentTime),
                              const SizedBox(height: 8),
                            ],
                            if (queueNumber != null) ...[
                              _dialogRow('Queue Number', '#$queueNumber'),
                              const SizedBox(height: 8),
                            ],
                          ] else if (purchasedItems != null && purchasedItems.isNotEmpty) ...[
                            for (final it in purchasedItems) ...[
                              Padding(
                                padding: const EdgeInsets.symmetric(vertical: 3.0),
                                child: Row(
                                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                  children: [
                                    Expanded(
                                      child: Text(
                                        '${it['name']} x${it['quantity'] ?? 1}',
                                        style: GoogleFonts.plusJakartaSans(
                                          fontSize: 13,
                                          fontWeight: FontWeight.w600,
                                          color: const Color(0xFF334155),
                                        ),
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    Text(
                                      '\$${(((it['price'] as num?)?.toDouble() ?? 0.0) * ((it['quantity'] as num?)?.toInt() ?? 1)).toStringAsFixed(2)}',
                                      style: GoogleFonts.plusJakartaSans(
                                        fontSize: 13,
                                        fontWeight: FontWeight.w600,
                                        color: const Color(0xFF0F172A),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                            const SizedBox(height: 4),
                          ] else ...[
                            _dialogRow(
                              isNurse ? 'Service' : 'Items',
                              serviceTitle,
                            ),
                            const SizedBox(height: 8),
                          ],

                          if (!isDoctorAppointment) ...[
                            _dialogRow('Address', cleanAddress),
                            const SizedBox(height: 8),
                            _dialogRow('Subtotal', '\$${totalAmount.toStringAsFixed(2)}'),
                            const SizedBox(height: 8),
                            _dialogRow('Delivery Fee', 'Free'),
                            const Divider(height: 24, color: Color(0xFFE2E8F0)),
                          ],

                          // Payment Method & Total
                          _dialogRow('Payment Method', paymentMethod),
                          const SizedBox(height: 10),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                'Total Paid',
                                style: GoogleFonts.plusJakartaSans(
                                  fontSize: 15,
                                  fontWeight: FontWeight.w800,
                                  color: const Color(0xFF0F172A),
                                ),
                              ),
                              Text(
                                '\$${totalAmount.toStringAsFixed(2)}',
                                style: GoogleFonts.plusJakartaSans(
                                  fontSize: 18,
                                  fontWeight: FontWeight.w900,
                                  color: const Color(0xFF0D7C66),
                                ),
                              ),
                            ],
                          ),
                          const Divider(height: 24, color: Color(0xFFE2E8F0)),

                          // Footer note
                          Text(
                            isDoctorAppointment
                                ? 'Thank you for booking with Nasiib Hospital!'
                                : 'Thank you for your purchase!',
                            textAlign: TextAlign.center,
                            style: GoogleFonts.plusJakartaSans(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: const Color(0xFF475569),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),

                  // 📤 Share Receipt Button (Clean text link with icon, no container border)
                  TextButton.icon(
                    onPressed: () => captureAndShareReceipt(),
                    icon: const Icon(
                      Icons.ios_share_rounded,
                      color: Color(0xFF00A86B),
                      size: 20,
                    ),
                    label: Text(
                      'Share Receipt',
                      style: GoogleFonts.plusJakartaSans(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: const Color(0xFF00A86B),
                        decoration: TextDecoration.underline,
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),

                  // GO TO HOME Button
                  SizedBox(
                    width: double.infinity,
                    height: 48,
                    child: ElevatedButton(
                      onPressed: () {
                        Navigator.pushAndRemoveUntil(
                          context,
                          MaterialPageRoute(
                            builder: (_) => const MainPatientLayout(),
                          ),
                          (route) => false,
                        );
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF1A1F36),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(24),
                        ),
                        elevation: 0,
                      ),
                      child: Text(
                        'GO TO HOME',
                        style: GoogleFonts.plusJakartaSans(
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                          letterSpacing: 0.5,
                        ),
                      ),
                    ),
                  ),
                  if (!isNurse && !isDoctorAppointment) ...[
                    const SizedBox(height: 10),
                    SizedBox(
                      width: double.infinity,
                      height: 48,
                      child: OutlinedButton(
                        onPressed: () {
                          Navigator.pushAndRemoveUntil(
                            context,
                            MaterialPageRoute(
                              builder: (_) => const MyOrdersScreen(),
                            ),
                            (route) => route.isFirst,
                          );
                        },
                        style: OutlinedButton.styleFrom(
                          side: const BorderSide(
                            color: Color(0xFF1E562A),
                            width: 1.5,
                          ),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(24),
                          ),
                        ),
                        child: Text(
                          'TRACK ORDER',
                          style: GoogleFonts.plusJakartaSans(
                            fontSize: 14,
                            fontWeight: FontWeight.bold,
                            color: const Color(0xFF1E562A),
                            letterSpacing: 0.5,
                          ),
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      );
    },
  );
}

Widget _dialogRow(String label, String value) {
  return Row(
    mainAxisAlignment: MainAxisAlignment.spaceBetween,
    children: [
      Text(
        label,
        style: GoogleFonts.plusJakartaSans(
          fontSize: 12,
          color: Colors.grey[600],
        ),
      ),
      Flexible(
        child: Text(
          value,
          textAlign: TextAlign.right,
          overflow: TextOverflow.ellipsis,
          style: GoogleFonts.plusJakartaSans(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: const Color(0xFF212121),
          ),
        ),
      ),
    ],
  );
}

// ─────────────────────────────────────────────
// Input formatters
// ─────────────────────────────────────────────
class CardExpiryInputFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    var text = newValue.text;
    if (oldValue.text.length > text.length) return newValue;
    text = text.replaceAll(RegExp(r'[^0-9]'), '');
    if (text.length > 4) text = text.substring(0, 4);
    final formatted = text.length >= 2
        ? '${text.substring(0, 2)}/${text.substring(2)}'
        : text;
    return TextEditingValue(
      text: formatted,
      selection: TextSelection.collapsed(offset: formatted.length),
    );
  }
}

class CardNumberInputFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    var text = newValue.text;
    if (newValue.selection.baseOffset == 0) return newValue;
    var digits = text.replaceAll(RegExp(r'\D'), '');
    if (digits.length > 16) digits = digits.substring(0, 16);
    final buffer = StringBuffer();
    for (int i = 0; i < digits.length; i++) {
      buffer.write(digits[i]);
      if ((i + 1) % 4 == 0 && (i + 1) != digits.length) buffer.write('  ');
    }
    final result = buffer.toString();
    return newValue.copyWith(
      text: result,
      selection: TextSelection.collapsed(offset: result.length),
    );
  }
}
