import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../config/app_theme.dart';
import '../../services/app_state.dart';
import '../../services/supabase_service.dart';
import 'order_success_page.dart';

class MyOrdersScreen extends StatefulWidget {
  const MyOrdersScreen({super.key});

  @override
  State<MyOrdersScreen> createState() => _MyOrdersScreenState();
}

class _MyOrdersScreenState extends State<MyOrdersScreen> {
  bool _isLoading = false;
  RealtimeChannel? _ordersChannel;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _refresh();
        _startRealtimeListener();
      }
    });
  }

  void _startRealtimeListener() {
    final client = SupabaseService.instance.client;
    if (client == null) return;

    _ordersChannel?.unsubscribe();

    _ordersChannel = client
        .channel('my_orders_realtime_${DateTime.now().millisecondsSinceEpoch}')
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'orders',
          callback: (payload) {
            if (!mounted) return;

            final updatedRecord = payload.newRecord;
            final deletedRecord = payload.oldRecord;

            if (payload.eventType == PostgresChangeEvent.update &&
                updatedRecord.isNotEmpty) {
              print(
                  '🟢 [MY_ORDERS] Realtime UPDATE: ${updatedRecord['id']} → status: ${updatedRecord['status']}');

              // Update directly in AppState so the card re-renders via watch().
              final appState =
                  Provider.of<AppState>(context, listen: false);
              final String id = updatedRecord['id']?.toString() ?? '';
              final idx = appState.orders
                  .indexWhere((o) => o['id']?.toString() == id);
              if (idx != -1) {
                appState.orders[idx] =
                    Map<String, dynamic>.from(updatedRecord);
              } else {
                appState.orders.insert(
                    0, Map<String, dynamic>.from(updatedRecord));
              }
              appState.notifyListeners();

            } else if (payload.eventType == PostgresChangeEvent.insert &&
                updatedRecord.isNotEmpty) {
              final appState =
                  Provider.of<AppState>(context, listen: false);
              final String id = updatedRecord['id']?.toString() ?? '';
              final exists =
                  appState.orders.any((o) => o['id']?.toString() == id);
              if (!exists) {
                appState.orders.insert(
                    0, Map<String, dynamic>.from(updatedRecord));
                appState.notifyListeners();
              }
            } else if (payload.eventType == PostgresChangeEvent.delete &&
                deletedRecord.isNotEmpty) {
              final appState =
                  Provider.of<AppState>(context, listen: false);
              final String id = deletedRecord['id']?.toString() ?? '';
              appState.orders
                  .removeWhere((o) => o['id']?.toString() == id);
              appState.notifyListeners();
            }
          },
        )
        .subscribe();
  }

  @override
  void dispose() {
    _ordersChannel?.unsubscribe();
    super.dispose();
  }

  Future<void> _refresh() async {
    if (!mounted) return;
    setState(() => _isLoading = true);
    await Provider.of<AppState>(context, listen: false).fetchUserOrders();
    if (mounted) setState(() => _isLoading = false);
  }

  // ──────────────────────────────────────────────────────────
  // Dynamic status badge style
  // ──────────────────────────────────────────────────────────
  _StatusStyle _getStatusStyle(String status) {
    final s = status.trim().toLowerCase();
    if (s.contains('deliver') && !s.contains('out') && !s.contains('ready')) {
      return _StatusStyle(
        bg: const Color(0xFFE8F5E9),
        fg: const Color(0xFF2E7D32),
        icon: Icons.home_rounded,
        label: 'Delivered',
      );
    }
    if (s.contains('out') || s.contains('way')) {
      return _StatusStyle(
        bg: const Color(0xFFFFF3E0),
        fg: const Color(0xFFF57C00),
        icon: Icons.two_wheeler_rounded,
        label: 'Out for Delivery',
      );
    }
    if (s.contains('ready')) {
      return _StatusStyle(
        bg: const Color(0xFFF3E5F5),
        fg: const Color(0xFF7B1FA2),
        icon: Icons.inventory_rounded,
        label: status.trim().isEmpty ? 'Ready' : status.trim(),
      );
    }
    if (s.contains('prep')) {
      return _StatusStyle(
        bg: const Color(0xFFFFFDE7),
        fg: const Color(0xFFF9A825),
        icon: Icons.inventory_2_outlined,
        label: 'Preparing',
      );
    }
    if (s.contains('accept') || s.contains('approv')) {
      return _StatusStyle(
        bg: const Color(0xFFE3F2FD),
        fg: const Color(0xFF1565C0),
        icon: Icons.check_circle_outline_rounded,
        label: 'Accepted',
      );
    }
    if (s.contains('cancel')) {
      return _StatusStyle(
        bg: const Color(0xFFFFEBEE),
        fg: const Color(0xFFC62828),
        icon: Icons.cancel_outlined,
        label: 'Cancelled',
      );
    }
    // Pending / default
    return _StatusStyle(
      bg: const Color(0xFFF5F5F5),
      fg: const Color(0xFF757575),
      icon: Icons.access_time_rounded,
      label: status.trim().isEmpty ? 'Pending' : status.trim(),
    );
  }

  @override
  Widget build(BuildContext context) {
    final appState = context.watch<AppState>();
    // ✅ Sort newest first — create a sorted copy, do NOT mutate the source list
    final orders = [...appState.orders]
      ..sort((a, b) {
        final aDate = DateTime.tryParse(a['created_at']?.toString() ?? '') ??
            DateTime(2000);
        final bDate = DateTime.tryParse(b['created_at']?.toString() ?? '') ??
            DateTime(2000);
        return bDate.compareTo(aDate); // descending
      });

    return Scaffold(
      backgroundColor: const Color(0xFFF9F9F6),
      appBar: AppBar(
        backgroundColor: const Color(0xFFF9F9F6),
        elevation: 0,
        centerTitle: false,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded,
              color: Color(0xFF1F1F1F), size: 20),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          'My Orders',
          style: GoogleFonts.plusJakartaSans(
            fontSize: 22,
            fontWeight: FontWeight.w800,
            color: const Color(0xFF1F1F1F),
          ),
        ),
        actions: [
          IconButton(
            icon: _isLoading
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: AppTheme.primaryColor),
                  )
                : const Icon(Icons.refresh_rounded,
                    color: AppTheme.primaryColor),
            onPressed: _isLoading ? null : _refresh,
          ),
          const SizedBox(width: 4),
        ],
      ),
      body: _isLoading && orders.isEmpty
          ? const Center(
              child: CircularProgressIndicator(color: AppTheme.primaryColor))
          : orders.isEmpty
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.receipt_long_rounded,
                          size: 64, color: Colors.grey[400]),
                      const SizedBox(height: 16),
                      Text(
                        'Wali ma samayn wax dalab ah',
                        style: GoogleFonts.plusJakartaSans(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: Colors.grey[700],
                        ),
                      ),
                    ],
                  ),
                )
              : ListView.separated(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 16, vertical: 12),
                  itemCount: orders.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 16),
                  itemBuilder: (context, index) {
                    final order = orders[index];
                    final String orderId =
                        order['id'].toString() ?? '';
                    final String orderNum =
                        order['order_number'].toString() ?? orderId;
                    final String status =
                        order['status'].toString() ?? 'Pending';
                    final String rawDate =
                        order['created_at'].toString() ?? '';
                    final double totalAmount =
                        (order['total_amount'] as num?)?.toDouble() ??
                            0.0;

                    // ✅ Format date: UTC → Local device time using intl
                    String formattedDate = '';
                    if (rawDate.isNotEmpty) {
                      try {
                        final dt = DateTime.parse(rawDate).toLocal();
                        formattedDate =
                            DateFormat('MMM dd, yyyy — hh:mm a').format(dt);
                      } catch (_) {
                        formattedDate = rawDate.length > 16
                            ? rawDate.substring(0, 16)
                            : rawDate;
                      }
                    }

                    final style = _getStatusStyle(status);

                    return GestureDetector(
                      onTap: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => OrderSuccessPage(
                              orderId: orderId.isNotEmpty
                                  ? orderId
                                  : orderNum,
                            ),
                          ),
                        );
                      },
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 300),
                        padding: const EdgeInsets.all(18),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(20),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withOpacity(0.04),
                              blurRadius: 12,
                              offset: const Offset(0, 4),
                            ),
                          ],
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            // ── Top row: order number + badge + trash ──
                            Row(
                              mainAxisAlignment:
                                  MainAxisAlignment.spaceBetween,
                              children: [
                                Text(
                                  '#${orderNum.startsWith('#') ? orderNum.substring(1) : orderNum}',
                                  style: GoogleFonts.plusJakartaSans(
                                    fontSize: 16,
                                    fontWeight: FontWeight.bold,
                                    color: const Color(0xFF1F1F1F),
                                  ),
                                ),
                                Row(
                                  children: [
                                    // ── Dynamic status badge ──
                                    AnimatedContainer(
                                      duration: const Duration(
                                          milliseconds: 300),
                                      padding:
                                          const EdgeInsets.symmetric(
                                              horizontal: 12,
                                              vertical: 6),
                                      decoration: BoxDecoration(
                                        color: style.bg,
                                        borderRadius:
                                            BorderRadius.circular(16),
                                      ),
                                      child: Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Icon(style.icon,
                                              size: 14,
                                              color: style.fg),
                                          const SizedBox(width: 5),
                                          Text(
                                            style.label,
                                            style: GoogleFonts
                                                .plusJakartaSans(
                                              fontSize: 12,
                                              fontWeight: FontWeight.bold,
                                              color: style.fg,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    // ── Delete button ──
                                    GestureDetector(
                                      onTap: () {
                                        final s = status.trim().toLowerCase();
                                        if (s.contains('deliver') || s.contains('out') || s.contains('way')) {
                                          ScaffoldMessenger.of(context).showSnackBar(
                                            const SnackBar(
                                              content: Text('Dalabkan waa la gaarsiiyay ama wuxuu ku jiraa jidka, laguma tirtiri karo.'),
                                              backgroundColor: Colors.orange,
                                            ),
                                          );
                                          return;
                                        }
                                        showDialog(
                                          context: context,
                                          builder: (ctx) => AlertDialog(
                                            title: const Text('Delete Order'),
                                            content: const Text('Ma ziirtaa in aad tirtirto dalabkan?'),
                                            actions: [
                                              TextButton(
                                                onPressed: () =>
                                                    Navigator.pop(ctx),
                                                child:
                                                    const Text('Jooji'),
                                              ),
                                              ElevatedButton(
                                                onPressed: () {
                                                  Navigator.pop(ctx);
                                                  appState.deleteOrder(
                                                      orderId);
                                                  ScaffoldMessenger.of(context).showSnackBar(
                                                    const SnackBar(
                                                      content: Text('Dalabka waa la tirtiray.'),
                                                      backgroundColor: Colors.green,
                                                    ),
                                                  );
                                                },
                                                style: ElevatedButton
                                                    .styleFrom(
                                                        backgroundColor:
                                                            Colors.red),
                                                child: const Text(
                                                    'Tirtir',
                                                    style: TextStyle(
                                                        color:
                                                            Colors.white)),
                                              ),
                                            ],
                                          ),
                                        );
                                      },
                                      child: const Icon(
                                        Icons.delete_outline_rounded,
                                        color: Color(0xFFEF5350),
                                        size: 20,
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ),

                            const SizedBox(height: 14),
                            const Divider(
                                height: 1, color: Color(0xFFF0F0F0)),
                            const SizedBox(height: 14),

                            // ── Date row ──
                            if (formattedDate.isNotEmpty)
                              Row(
                                children: [
                                  const Icon(
                                      Icons.calendar_today_outlined,
                                      size: 16,
                                      color: Colors.grey),
                                  const SizedBox(width: 8),
                                  Text(
                                    formattedDate,
                                    style: GoogleFonts.plusJakartaSans(
                                      fontSize: 13,
                                      color: Colors.grey[600],
                                    ),
                                  ),
                                ],
                              ),

                            const SizedBox(height: 14),

                            // ── Total + Reorder button ──
                            Row(
                              mainAxisAlignment:
                                  MainAxisAlignment.spaceBetween,
                              crossAxisAlignment: CrossAxisAlignment.end,
                              children: [
                                Column(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      'Total Amount',
                                      style: GoogleFonts.plusJakartaSans(
                                        fontSize: 12,
                                        color: Colors.grey[500],
                                      ),
                                    ),
                                    const SizedBox(height: 2),
                                    Text(
                                      '\$${totalAmount.toStringAsFixed(2)}',
                                      style: GoogleFonts.plusJakartaSans(
                                        fontSize: 18,
                                        fontWeight: FontWeight.w800,
                                        color: const Color(0xFF1F1F1F),
                                      ),
                                    ),
                                  ],
                                ),
                                ElevatedButton.icon(
                                  onPressed: () {
                                    ScaffoldMessenger.of(context)
                                        .showSnackBar(
                                      const SnackBar(
                                        content: Text(
                                            'Dawaayinka waxaa dib loogu daray Cart-ka!'),
                                        backgroundColor:
                                            AppTheme.primaryColor,
                                      ),
                                    );
                                    context
                                        .read<AppState>()
                                        .setPatientNavIndex(1);
                                  },
                                  icon: const Icon(Icons.refresh_rounded,
                                      size: 16, color: Colors.white),
                                  label: Text(
                                    'Dalbo Mar Kale',
                                    style: GoogleFonts.plusJakartaSans(
                                      fontSize: 13,
                                      fontWeight: FontWeight.bold,
                                      color: Colors.white,
                                    ),
                                  ),
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: AppTheme.primaryColor,
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 16, vertical: 10),
                                    shape: RoundedRectangleBorder(
                                      borderRadius:
                                          BorderRadius.circular(12),
                                    ),
                                    elevation: 0,
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
    );
  }
}

// ── Badge style data class ──
class _StatusStyle {
  final Color bg;
  final Color fg;
  final IconData icon;
  final String label;

  const _StatusStyle({
    required this.bg,
    required this.fg,
    required this.icon,
    required this.label,
  });
}
