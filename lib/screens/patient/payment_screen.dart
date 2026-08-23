import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';

import '../../config/app_theme.dart';
import '../../models/appointment_model.dart';
import '../../services/app_state.dart';
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
    // Phone field starts empty — user types their own number
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

    // 2. Validate EVC Plus & E-Dahab
    if (_selectedMethod == _PayMethod.evcPlus ||
        _selectedMethod == _PayMethod.eDahab) {
      final phone = _phoneController.text.trim();
      if (phone.isEmpty || phone.length < 7) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Please enter a valid phone number'),
            backgroundColor: Colors.red,
          ),
        );
        return;
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

    if (_isDelivery) {
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
        final orderId = await appState.placeOrder(
          patientName: widget.booking.patientName,
          patientPhone: widget.booking.patientPhone,
          city: 'Mogadishu',
          district: widget.booking.doctorSpecialty.isNotEmpty
              ? widget.booking.doctorSpecialty
              : 'Hodan',
          deliveryAddress: widget.booking.reasonForVisit.replaceAll(
            'Delivery: ',
            '',
          ),
          subtotal: widget.booking.amount > 2.0
              ? widget.booking.amount - 2.0
              : widget.booking.amount,
          deliveryFee: 2.0,
          totalAmount: widget.booking.amount,
          paymentMethod: _methodLabel,
          paymentStatus: 'Paid',
          items: items,
        );

        if (mounted) {
          // ✅ Await clearCart() so ALL storage keys are wiped before dialog
          await context.read<AppState>().clearCart();
          _showPaymentSuccessDialog(
            context: context,
            orderId: orderId ?? widget.booking.referenceId,
            itemCount: items.length,
            address: widget.booking.reasonForVisit.replaceAll('Delivery: ', ''),
            paymentMethod: _methodLabel,
            totalAmount: widget.booking.amount,
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
      appState.confirmCurrentBooking();
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
        queueNumber: widget.booking.queueNumber,
        status: 'Confirmed',
        createdAt: widget.booking.createdAt,
      );
      appState.addAppointment(confirmedBooking);

      if (mounted) {
        Navigator.pushAndRemoveUntil(
          context,
          MaterialPageRoute(
            builder: (_) =>
                AppointmentConfirmedScreen(booking: confirmedBooking),
          ),
          (route) => false,
        );
      }
    }

    if (mounted) setState(() => _isProcessing = false);
  }

  @override
  Widget build(BuildContext context) {
    final appState = context.watch<AppState>();
    final subtotal = widget.booking.amount > 2.0
        ? widget.booking.amount - 2.0
        : widget.booking.amount;
    final deliveryFee = _isDelivery ? 2.0 : 0.0;
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
    return GestureDetector(
      onTap: () => setState(() => _selectedMethod = method),
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
              onChanged: (v) => setState(() => _selectedMethod = v),
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

          // Items total row
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
// Payment Success Dialog (unchanged logic)
// ─────────────────────────────────────────────
void _showPaymentSuccessDialog({
  required BuildContext context,
  required String orderId,
  required int itemCount,
  required String address,
  required String paymentMethod,
  required double totalAmount,
}) {
  showDialog(
    context: context,
    barrierDismissible: false,
    builder: (ctx) {
      return Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        backgroundColor: Colors.white,
        insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
        child: SingleChildScrollView(
          child: Padding(
            padding: const EdgeInsets.all(24.0),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Align(
                  alignment: Alignment.topRight,
                  child: IconButton(
                    icon: const Icon(
                      Icons.close_rounded,
                      color: Color(0xFF1E562A),
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
                Container(
                  width: 80,
                  height: 80,
                  decoration: const BoxDecoration(
                    color: Color(0xFFE8F5E9),
                    shape: BoxShape.circle,
                  ),
                  child: Center(
                    child: Container(
                      width: 56,
                      height: 56,
                      decoration: const BoxDecoration(
                        color: Color(0xFF2E7D32),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(
                        Icons.check_rounded,
                        color: Colors.white,
                        size: 36,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 20),
                Text(
                  'PAYMENT SUCCESSFUL!',
                  textAlign: TextAlign.center,
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.5,
                    color: const Color(0xFF1B5E20),
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Thank you for your purchase. Your order has been placed and is being prepared.',
                  textAlign: TextAlign.center,
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 12,
                    color: Colors.grey[700],
                    height: 1.4,
                  ),
                ),
                const SizedBox(height: 20),

                // Summary receipt
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFAFAFC),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: const Color(0xFFE0E0E0)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _dialogRow(
                        'Order ID',
                        orderId.startsWith('#') ? orderId : '#$orderId',
                      ),
                      const SizedBox(height: 6),
                      _dialogRow('Items', '$itemCount Items'),
                      const SizedBox(height: 6),
                      _dialogRow(
                        'Address',
                        address.isNotEmpty ? address : 'Mogadishu',
                      ),
                      const SizedBox(height: 6),
                      _dialogRow('Payment', paymentMethod),
                      const Divider(height: 16, color: Color(0xFFE0E0E0)),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            'TOTAL',
                            style: GoogleFonts.plusJakartaSans(
                              fontSize: 14,
                              fontWeight: FontWeight.w800,
                              color: const Color(0xFF1B5E20),
                            ),
                          ),
                          Text(
                            '\$${totalAmount.toStringAsFixed(2)}',
                            style: GoogleFonts.plusJakartaSans(
                              fontSize: 18,
                              fontWeight: FontWeight.w800,
                              color: const Color(0xFF1B5E20),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 20),

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
