import 'dart:async';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../config/app_theme.dart';
import '../../services/app_state.dart';
import '../../services/supabase_service.dart';
import 'main_patient_layout.dart';

class OrderSuccessPage extends StatefulWidget {
  final String orderId;

  const OrderSuccessPage({super.key, required this.orderId});

  @override
  State<OrderSuccessPage> createState() => _OrderSuccessPageState();
}

class _OrderSuccessPageState extends State<OrderSuccessPage> {
  RealtimeChannel? _orderChannel;
  Timer? _pollingTimer;

  // Local status state — updated directly by Realtime callback without waiting
  // for the full AppState to rebuild.
  String _currentStatus = 'Pending';

  @override
  void initState() {
    super.initState();

    // Seed _currentStatus from the AppState snapshot that exists at mount time.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final appState = Provider.of<AppState>(context, listen: false);
      final existing = appState.orders.firstWhere(
        (o) =>
            o['id'].toString() == widget.orderId ||
            o['order_number']?.toString() == widget.orderId,
        orElse: () => <String, dynamic>{},
      );
      if (existing.isNotEmpty && mounted) {
        setState(() {
          _currentStatus = existing['status']?.toString() ?? 'Pending';
        });
      }

      // Start the dedicated per-order Realtime channel.
      _startOrderTracking();
    });
  }

  void _startOrderTracking() {
    final client = SupabaseService.instance.client;
    if (client == null) return;

    final channelName =
        'orders_tracker_${widget.orderId}_${DateTime.now().millisecondsSinceEpoch}';
    debugPrint('[ORDER_TRACKING] Connecting channel: $channelName');

    _orderChannel = client
        .channel(channelName)
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'orders',
          callback: (payload) {
            final updatedData = payload.newRecord;
            if (updatedData.isEmpty) return;

            final payloadId = updatedData['id']?.toString() ?? '';
            final payloadOrderNum =
                updatedData['order_number']?.toString() ?? '';

            if (payloadId == widget.orderId ||
                payloadOrderNum == widget.orderId) {
              final newStatus =
                  updatedData['status']?.toString() ?? _currentStatus;
              if (mounted) {
                setState(() {
                  _currentStatus = newStatus;
                });

                final appState =
                    Provider.of<AppState>(context, listen: false);
                final idx = appState.orders.indexWhere(
                    (o) => o['id'].toString() == payloadId);
                if (idx != -1) {
                  appState.orders[idx] =
                      Map<String, dynamic>.from(updatedData);
                  appState.notifyListeners();
                }
              }
            }
          },
        )
        .subscribe();

    _pollingTimer = Timer.periodic(const Duration(seconds: 2), (_) async {
      final supabaseClient = SupabaseService.instance.client;
      if (supabaseClient != null && SupabaseService.instance.isInitialized) {
        try {
          final res = await supabaseClient
              .from('orders')
              .select()
              .or('id.eq.${widget.orderId},order_number.eq.${widget.orderId}');
          if (res is List && res.isNotEmpty) {
            final st = res.first['status']?.toString() ?? '';
            if (st.isNotEmpty && mounted && st != _currentStatus) {
              setState(() {
                _currentStatus = st;
              });
              final appState = Provider.of<AppState>(context, listen: false);
              appState.updateOrderStatus(widget.orderId, st);
            }
          }
        } catch (_) {}
      }
    });
  }

  @override
  void dispose() {
    _pollingTimer?.cancel();
    _orderChannel?.unsubscribe();
    super.dispose();
  }

  /// Flexible, case-insensitive step resolver matching all status variations.
  int _getStepIndex(String? status) {
    final s = (status ?? '').trim().toLowerCase().replaceAll('_', ' ');
    if (s.contains('delivered') || s.contains('gaarsiiyay')) {
      return 5; // Step 6: Delivered (0-indexed 5)
    } else if (s.contains('out for delivery') || s.contains('on the way') || s.contains('wadada') || s.contains('soo qaaday') || s.contains('out') || s.contains('way')) {
      return 4; // Step 5: Out for Delivery (0-indexed 4)
    } else if (s.contains('ready')) {
      return 3; // Step 4: Ready
    } else if (s.contains('preparing') || s.contains('diyaarinta') || s.contains('prep')) {
      return 2; // Step 3: Preparing
    } else if (s.contains('accepted') || s.contains('la aqbalay') || s.contains('accept')) {
      return 1; // Step 2: Accepted
    }
    return 0; // Step 1: Received / Pending
  }

  @override
  Widget build(BuildContext context) {
    // Also watch AppState so updates via the global system_sync channel also
    // propagate here.
    final appState = context.watch<AppState>();

    // Merge: prefer local _currentStatus if it's more advanced than AppState.
    final liveOrder = appState.orders.firstWhere(
      (o) =>
          o['id'].toString() == widget.orderId ||
          o['order_number']?.toString() == widget.orderId,
      orElse: () => <String, dynamic>{},
    );
    final appStateStatus = liveOrder['status']?.toString() ?? '';

    // Use whichever step index is higher (more advanced) between local and
    // AppState sources to prevent going backwards on UI.
    final localIdx = _getStepIndex(_currentStatus);
    final appIdx = _getStepIndex(appStateStatus);
    final currentStepIndex = localIdx >= appIdx ? localIdx : appIdx;

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded,
              color: AppTheme.textPrimary, size: 20),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          'Live Order Tracking',
          style: GoogleFonts.plusJakartaSans(
            fontSize: 18,
            fontWeight: FontWeight.bold,
            color: AppTheme.textPrimary,
          ),
        ),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding:
              const EdgeInsets.symmetric(horizontal: 24.0, vertical: 16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              const SizedBox(height: 12),

              Text(
                'Dalabkaaga Waa La Aqbalay!',
                textAlign: TextAlign.center,
                style: GoogleFonts.plusJakartaSans(
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                  color: AppTheme.textPrimary,
                ),
              ),

              const SizedBox(height: 6),

              Text(
                'Farmashiyaha Nasiib Hospital ayaa hada bilaabay diyaarinta dalabkaaga.',
                textAlign: TextAlign.center,
                style: GoogleFonts.plusJakartaSans(
                  fontSize: 13,
                  color: AppTheme.textSecondary,
                  height: 1.4,
                ),
              ),

              const SizedBox(height: 16),

              // Live status badge
              AnimatedContainer(
                duration: const Duration(milliseconds: 300),
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                decoration: BoxDecoration(
                  color: currentStepIndex == 5
                      ? const Color(0xFF10B981).withOpacity(0.12)
                      : AppTheme.primaryColor.withOpacity(0.10),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 8,
                      height: 8,
                      decoration: BoxDecoration(
                        color: currentStepIndex == 5
                            ? const Color(0xFF10B981)
                            : AppTheme.primaryColor,
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      (currentStepIndex >= 4 && currentStepIndex < 5)
                          ? "Out for Delivery / Waa la soo qaaday (Wadada ku jiraa)"
                          : (_currentStatus.isEmpty ? 'Pending' : _currentStatus),
                      style: GoogleFonts.plusJakartaSans(
                        fontSize: 13,
                        fontWeight: FontWeight.bold,
                        color: currentStepIndex == 5
                            ? const Color(0xFF10B981)
                            : AppTheme.primaryColor,
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 24),

              Column(
                children: [
                  _buildTrackingStep('Order Received', 'Dalabkaaga waa la heley', 0,
                      currentStepIndex, Icons.assignment_turned_in_rounded),
                  _buildTrackingStep('Accepted',
                      'Dalabkaaga waa la aqbalay', 1,
                      currentStepIndex, Icons.check_circle_outline_rounded),
                  _buildTrackingStep('Preparing',
                      'Dawooyinkaaga waa la diyaarinooyaa', 2,
                      currentStepIndex, Icons.inventory_2_outlined),
                  _buildTrackingStep('Ready', 'Daawooyinkaaga waa diyaar', 3,
                      currentStepIndex, Icons.inventory_rounded),
                  _buildTrackingStep('Out for Delivery',
                      'Waa la soo qaaday', 4,
                      currentStepIndex, Icons.two_wheeler_rounded),
                  _buildTrackingStep('Delivered',
                      'Hambalyo! Daawooyinka waa lagu soo gaarsiiyay', 5,
                      currentStepIndex, Icons.task_alt_rounded, isLast: true),
                ],
              ),

              const SizedBox(height: 20),

              Builder(
                builder: (context) {
                  final rName = (liveOrder['rider_name'] ?? liveOrder['driver_name'] ?? '').toString();
                  final rPhone = (liveOrder['rider_phone'] ?? liveOrder['driver_phone'] ?? '').toString();
                  final s = (liveOrder['status'] ?? _currentStatus).toString().trim().toLowerCase();
                  final isOut = s == 'out for delivery' || s == 'on the way' || s == 'delivered' || currentStepIndex >= 4;

                  if (isOut && rName.isNotEmpty) {
                    return Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF0FDF4),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: const Color(0xFFDCFCE7)),
                      ),
                      child: Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(10),
                            decoration: const BoxDecoration(
                              color: Color(0xFFDCFCE7),
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(Icons.two_wheeler_rounded, color: Color(0xFF15803D), size: 24),
                          ),
                          const SizedBox(width: 14),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Darawalka Gaarsiinaya:',
                                  style: GoogleFonts.plusJakartaSans(
                                    fontSize: 11,
                                    color: Colors.grey.shade600,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                                Text(
                                  rName,
                                  style: GoogleFonts.plusJakartaSans(
                                    fontSize: 15,
                                    fontWeight: FontWeight.bold,
                                    color: const Color(0xFF0F172A),
                                  ),
                                ),
                                if (rPhone.isNotEmpty)
                                  Text(
                                    rPhone,
                                    style: GoogleFonts.plusJakartaSans(
                                      fontSize: 13,
                                      color: const Color(0xFF15803D),
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    );
                  }
                  return const SizedBox.shrink();
                },
              ),

              const SizedBox(height: 24),

              SizedBox(
                width: double.infinity,
                height: 52,
                child: ElevatedButton(
                  onPressed: () {
                    Navigator.of(context).pushAndRemoveUntil(
                      MaterialPageRoute(
                        builder: (context) => const MainPatientLayout(),
                      ),
                      (route) => false,
                    );
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.primaryColor,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                  child: Text(
                    'Ku noqo Bogga Hore',
                    style: GoogleFonts.plusJakartaSans(
                      fontSize: 15,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                ),
              ),

              const SizedBox(height: 16),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTrackingStep(
    String title,
    String subtitle,
    int stepIndex,
    int currentIndex,
    IconData icon, {
    bool isLast = false,
  }) {
    final bool isCompleted = stepIndex <= currentIndex;
    final bool isCurrent = stepIndex == currentIndex;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Column(
          children: [
            AnimatedContainer(
              duration: const Duration(milliseconds: 400),
              curve: Curves.easeInOut,
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: (isCompleted || isCurrent)
                    ? const Color(0xFF10B981)
                    : const Color(0xFFF1F5F9),
                shape: BoxShape.circle,
              ),
              child: Icon(
                icon,
                size: 18,
                color: (isCompleted || isCurrent)
                    ? Colors.white
                    : const Color(0xFF94A3B8),
              ),
            ),
            if (!isLast)
              AnimatedContainer(
                duration: const Duration(milliseconds: 400),
                width: 2,
                height: 32,
                color: (isCompleted || isCurrent)
                    ? const Color(0xFF10B981)
                    : const Color(0xFFE2E8F0),
              ),
          ],
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.only(top: 4.0, bottom: 8.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 14,
                    fontWeight:
                        isCurrent ? FontWeight.bold : FontWeight.w600,
                    color: isCompleted
                        ? AppTheme.textPrimary
                        : const Color(0xFF94A3B8),
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 12,
                    color: isCompleted
                        ? AppTheme.textSecondary
                        : const Color(0xFFCBD5E1),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
