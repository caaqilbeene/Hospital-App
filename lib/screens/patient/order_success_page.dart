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

            // Match by id OR order_number — no strict filter to avoid
            // payload mismatch on Supabase Realtime.
            if (payloadId == widget.orderId ||
                payloadOrderNum == widget.orderId) {
              final newStatus =
                  updatedData['status']?.toString() ?? _currentStatus;
              print(
                  '🟢 [ORDER_TRACKING] Status update received: $newStatus');
              if (mounted) {
                setState(() {
                  _currentStatus = newStatus;
                });

                // Also update AppState so other screens are consistent.
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
  }

  @override
  void dispose() {
    _orderChannel?.unsubscribe();
    super.dispose();
  }

  /// Flexible, case-insensitive step resolver.
  int _getStepIndex(String status) {
    final s = status.trim().toLowerCase();
    if ((s.contains('deliver') || s.contains('complet')) &&
        !s.contains('out') &&
        !s.contains('ready')) {
      return 5; // Delivered / Completed
    }
    if (s.contains('out')) return 4; // Out for Delivery
    if (s.contains('ready')) return 3; // Ready / Ready for Delivery
    if (s.contains('prep')) return 2; // Preparing
    if (s.contains('accept') || s.contains('approv')) return 1; // Accepted
    return 0; // Order Received / Pending / Placed
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
                      _currentStatus.isEmpty ? 'Pending' : _currentStatus,
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

              const SizedBox(height: 24),

              SizedBox(
                width: double.infinity,
                height: 52,
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
                color: isCurrent
                    ? AppTheme.primaryColor
                    : isCompleted
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
                color: isCompleted
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
