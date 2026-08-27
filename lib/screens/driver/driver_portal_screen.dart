import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import '../../config/app_theme.dart';
import '../../services/app_state.dart';
import '../../services/supabase_service.dart';

class DriverPortalScreen extends StatefulWidget {
  final Map<String, dynamic>? initialDriver;
  const DriverPortalScreen({super.key, this.initialDriver});

  @override
  State<DriverPortalScreen> createState() => _DriverPortalScreenState();
}

class _DriverPortalScreenState extends State<DriverPortalScreen> {
  final TextEditingController _phoneController = TextEditingController();
  bool _isLoading = false;
  Map<String, dynamic>? _loggedInDriver;

  @override
  void initState() {
    super.initState();
    if (widget.initialDriver != null) {
      _loggedInDriver = Map<String, dynamic>.from(widget.initialDriver!);
      _phoneController.text = (widget.initialDriver!['phone'] ?? '').toString();
    }
    _loadPersistedDriverSession();
  }

  Future<void> _loadPersistedDriverSession() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final savedPhone = prefs.getString('logged_driver_phone');
      final savedName = prefs.getString('logged_driver_name');
      if (savedPhone != null && savedPhone.isNotEmpty && mounted && _loggedInDriver == null) {
        setState(() {
          _phoneController.text = savedPhone;
          _loggedInDriver = {
            'name': savedName ?? 'Darawal',
            'phone': savedPhone,
            'status': 'active',
          };
        });
      }
    } catch (_) {}
  }

  Future<void> _saveDriverSession(String phone, String name) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('logged_driver_phone', phone);
      await prefs.setString('logged_driver_name', name);
    } catch (_) {}
  }

  Future<void> _loginDriver() async {
    final rawPhone = _phoneController.text.trim();
    if (rawPhone.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Fadlan geli nambarkaaga taleefanka.'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    setState(() => _isLoading = true);

    String digits = rawPhone.replaceAll(RegExp(r'\D'), '');
    if (digits.startsWith('252') && digits.length >= 12) {
      digits = digits.substring(3);
    }
    if (digits.startsWith('0') && digits.length >= 10) {
      digits = digits.substring(1);
    }

    final vBase = digits;
    final vZero = '0$digits';
    final v252 = '252$digits';
    final vPlus252 = '+252$digits';
    final possibleFormats = [vBase, vZero, v252, vPlus252];

    try {
      final client = SupabaseService.instance.client;
      if (client != null && SupabaseService.instance.isInitialized) {
        final res = await client
            .from('drivers')
            .select()
            .or('phone.in.(${possibleFormats.join(",")}),status.eq.active');

        if (res is List && res.isNotEmpty) {
          final matched = res.firstWhere(
            (d) {
              final ph = (d['phone'] ?? '').toString();
              final st = (d['status'] ?? '').toString();
              return st == 'active' && possibleFormats.any((fmt) => ph.contains(fmt));
            },
            orElse: () => res.first,
          );

          final dName = (matched['name'] ?? matched['full_name'] ?? 'Darawal').toString();
          final dPhone = (matched['phone'] ?? matched['phone_number'] ?? rawPhone).toString();
          await _saveDriverSession(dPhone, dName);

          setState(() {
            _loggedInDriver = Map<String, dynamic>.from(matched);
            _isLoading = false;
          });
          return;
        }

        final userRes = await client
            .from('users')
            .select()
            .eq('role', 'driver');
        if (userRes is List && userRes.isNotEmpty) {
          final matchedUser = userRes.firstWhere(
            (u) {
              final ph = (u['phone'] ?? u['phone_number'] ?? '').toString();
              return possibleFormats.any((fmt) => ph.contains(fmt));
            },
            orElse: () => userRes.first,
          );

          final dName = (matchedUser['full_name'] ?? matchedUser['name'] ?? 'Darawal').toString();
          final dPhone = (matchedUser['phone'] ?? matchedUser['phone_number'] ?? vPlus252).toString();
          await _saveDriverSession(dPhone, dName);

          setState(() {
            _loggedInDriver = {
              'id': matchedUser['id'],
              'name': dName,
              'phone': dPhone,
              'status': 'active',
            };
            _isLoading = false;
          });
          return;
        }
      }
    } catch (e) {
      debugPrint('Driver login error: $e');
    }

    setState(() => _isLoading = false);

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Nambarkan "$rawPhone" kuma diiwaangashana darawallada active-ka ah.'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  void _logoutDriver() {
    setState(() {
      _loggedInDriver = null;
      _phoneController.clear();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: AppBar(
        backgroundColor: const Color(0xFFF0FDF4),
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, color: Color(0xFF065F46), size: 20),
          onPressed: () {
            if (Navigator.canPop(context)) {
              Navigator.pop(context);
            } else {
              Navigator.pushReplacementNamed(context, '/');
            }
          },
        ),
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                color: const Color(0xFFDCFCE7),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Icon(Icons.delivery_dining_rounded, color: Color(0xFF15803D), size: 22),
            ),
            const SizedBox(width: 10),
            Text(
              'Nasiib Hospital — Driver Portal',
              style: GoogleFonts.plusJakartaSans(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: const Color(0xFF065F46),
              ),
            ),
          ],
        ),
        actions: [
          if (_loggedInDriver != null)
            Padding(
              padding: const EdgeInsets.only(right: 16),
              child: TextButton.icon(
                onPressed: () async {
                  try {
                    final prefs = await SharedPreferences.getInstance();
                    await prefs.remove('logged_driver_phone');
                    await prefs.remove('logged_driver_name');
                  } catch (_) {}
                  if (mounted) {
                    setState(() {
                      _loggedInDriver = null;
                      _phoneController.clear();
                    });
                  }
                },
                icon: const Icon(Icons.logout_rounded, color: Colors.red, size: 18),
                label: Text(
                  'Kabax',
                  style: GoogleFonts.plusJakartaSans(
                    fontWeight: FontWeight.bold,
                    color: Colors.red,
                  ),
                ),
              ),
            ),
        ],
      ),
      body: _loggedInDriver == null ? _buildLoginView() : _buildDashboardView(),
    );
  }

  Widget _buildLoginView() {
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Container(
          constraints: const BoxConstraints(maxWidth: 420),
          padding: const EdgeInsets.all(28),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: const Color(0xFFE2E8F0)),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.04),
                blurRadius: 16,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  padding: const EdgeInsets.all(16),
                  decoration: const BoxDecoration(
                    color: Color(0xFFDCFCE7),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.two_wheeler_rounded,
                    size: 40,
                    color: Color(0xFF15803D),
                  ),
                ),
              ),
              const SizedBox(height: 18),
              Center(
                child: Text(
                  'Gal Qaybta Darawalka',
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                    color: const Color(0xFF0F172A),
                  ),
                ),
              ),
              const SizedBox(height: 6),
              Center(
                child: Text(
                  'Geli nambarkaaga taleefanka si aad u aragto amarrada kuu qoondeysan.',
                  textAlign: TextAlign.center,
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 13,
                    color: AppTheme.textSecondary,
                  ),
                ),
              ),
              const SizedBox(height: 28),
              Text(
                'Nambarka Taleefanka (Phone Number)',
                style: GoogleFonts.plusJakartaSans(
                  fontSize: 13,
                  fontWeight: FontWeight.bold,
                  color: const Color(0xFF0F172A),
                ),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _phoneController,
                keyboardType: TextInputType.phone,
                inputFormatters: [
                  FilteringTextInputFormatter.allow(RegExp(r'[0-9+]')),
                ],
                style: GoogleFonts.plusJakartaSans(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  color: const Color(0xFF0F172A),
                ),
                decoration: InputDecoration(
                  prefixIcon: const Icon(Icons.phone_rounded, color: Color(0xFF15803D)),
                  hintText: 'e.g. 612949911 ama +252612949911',
                  hintStyle: GoogleFonts.plusJakartaSans(fontSize: 13, color: Colors.grey.shade400),
                  filled: true,
                  fillColor: const Color(0xFFF8FAFC),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: const BorderSide(color: Color(0xFF15803D), width: 2),
                  ),
                ),
                onSubmitted: (_) => _loginDriver(),
              ),
              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                height: 52,
                child: ElevatedButton.icon(
                  onPressed: _isLoading ? null : _loginDriver,
                  icon: _isLoading
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                        )
                      : const Icon(Icons.login_rounded, color: Colors.white, size: 20),
                  label: Text(
                    _isLoading ? 'Waa la hubinayaa...' : 'Gal Portal-ka Darawalka',
                    style: GoogleFonts.plusJakartaSans(
                      fontSize: 15,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF15803D),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  String formatCleanAddress(Map<String, dynamic> order) {
    String address = (order['delivery_address'] ?? order['address'] ?? order['location'] ?? '').toString();
    address = address.replaceAll(RegExp(r'Medicines\s*&\s*Skincare\s*,?', caseSensitive: false), '').trim();
    if (address.startsWith(',')) address = address.substring(1).trim();
    final district = (order['district'] ?? '').toString().trim();
    if (district.isNotEmpty && !address.toLowerCase().contains(district.toLowerCase())) {
      return "$district, $address";
    }
    return address.isNotEmpty ? address : 'Mogadishu';
  }

  Widget _buildDashboardView() {
    final driverName = (_loggedInDriver?['name'] ?? _loggedInDriver?['full_name'] ?? 'Darawal').toString();
    final driverPhone = (_loggedInDriver?['phone'] ?? _loggedInDriver?['phone_number'] ?? '').toString();

    String digits = driverPhone.replaceAll(RegExp(r'\D'), '');
    if (digits.startsWith('252') && digits.length >= 12) {
      digits = digits.substring(3);
    }
    if (digits.startsWith('0') && digits.length >= 10) {
      digits = digits.substring(1);
    }
    final vBase = digits;
    final vZero = '0$digits';
    final v252 = '252$digits';
    final vPlus252 = '+252$digits';
    final possibleFormats = [vBase, vZero, v252, vPlus252, driverName];

    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Driver Banner
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: const Color(0xFFDCFCE7), width: 1.5),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.02),
                  blurRadius: 8,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: const BoxDecoration(
                    color: Color(0xFFDCFCE7),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.person_pin_rounded, color: Color(0xFF15803D), size: 28),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Qaybta Darawalka: $driverName',
                        style: GoogleFonts.plusJakartaSans(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: const Color(0xFF0F172A),
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'Tel: $driverPhone | Hawlaha kugu aadan oo kaliya',
                        style: GoogleFonts.plusJakartaSans(
                          fontSize: 13,
                          color: AppTheme.textSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 24),

          Text(
            'Amarrada On The Way (Active Deliveries)',
            style: GoogleFonts.plusJakartaSans(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: const Color(0xFF0F172A),
            ),
          ),
          const SizedBox(height: 12),

          StreamBuilder<List<Map<String, dynamic>>>(
            stream: (SupabaseService.instance.client != null && SupabaseService.instance.isInitialized)
                ? SupabaseService.instance.client!.from('orders').stream(primaryKey: ['id'])
                : const Stream.empty(),
            builder: (context, snapshot) {
              final allOrders = snapshot.data ?? [];
              final driverOrders = allOrders.where((o) {
                final st = (o['status'] ?? '').toString();
                final rPhone = (o['rider_phone'] ?? o['driver_phone'] ?? '').toString();
                final rName = (o['rider_name'] ?? o['driver_name'] ?? '').toString();

                final isWay = st == 'On The Way' || st == 'Out for Delivery';
                final isMyOrder = possibleFormats.any((fmt) => fmt.isNotEmpty && (rPhone.contains(fmt) || rName.contains(fmt)));
                return isWay && isMyOrder;
              }).toList();

              if (driverOrders.isEmpty) {
                return Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(40),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: const Color(0xFFE2E8F0)),
                  ),
                  child: Column(
                    children: [
                      const Icon(Icons.check_circle_outline_rounded, size: 48, color: Color(0xFF15803D)),
                      const SizedBox(height: 12),
                      Text(
                        'Hada wax order ah ma ku aadan.',
                        style: GoogleFonts.plusJakartaSans(
                          fontSize: 15,
                          fontWeight: FontWeight.bold,
                          color: const Color(0xFF0F172A),
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Marka Farmasiyaha kugu aadiyo dawo gaarsiin ah, halkan ayay ka soo muuqan doontaa.',
                        textAlign: TextAlign.center,
                        style: GoogleFonts.plusJakartaSans(
                          fontSize: 13,
                          color: AppTheme.textSecondary,
                        ),
                      ),
                    ],
                  ),
                );
              }

              return ListView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: driverOrders.length,
                itemBuilder: (context, index) {
                  final order = driverOrders[index];
                  final orderId = order['id']?.toString() ?? '';
                  final orderNum = order['order_number']?.toString() ?? '#ORD';
                  final patientName = order['patient_name']?.toString() ?? 'Bukaan';
                  final patientPhone = order['patient_phone']?.toString() ?? 'N/A';
                  final district = order['district']?.toString() ?? 'Hodan';
                  final address = order['delivery_address']?.toString() ?? 'Mogadishu';
                  final total = (order['total_amount'] as num?)?.toDouble() ?? 0.0;
                  final itemsSummary = (order['items_summary'] ?? 'Dawooyinka bukaan-ka').toString();

                  return Container(
                    margin: const EdgeInsets.only(bottom: 16),
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(18),
                      border: Border.all(color: const Color(0xFFDCFCE7), width: 2),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.04),
                          blurRadius: 10,
                          offset: const Offset(0, 3),
                        ),
                      ],
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Row(
                              children: [
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFFDCFCE7),
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                  child: Text(
                                    orderNum,
                                    style: GoogleFonts.plusJakartaSans(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 14,
                                      color: const Color(0xFF15803D),
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                  decoration: BoxDecoration(
                                    color: Colors.orange.shade50,
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: Text(
                                    'On The Way',
                                    style: GoogleFonts.plusJakartaSans(
                                      fontSize: 12,
                                      fontWeight: FontWeight.bold,
                                      color: Colors.orange.shade900,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            Text(
                              '\$${total.toStringAsFixed(2)}',
                              style: GoogleFonts.plusJakartaSans(
                                fontWeight: FontWeight.bold,
                                fontSize: 18,
                                color: const Color(0xFF15803D),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 16),
                        Row(
                          children: [
                            const Icon(Icons.person_rounded, size: 18, color: Color(0xFF64748B)),
                            const SizedBox(width: 8),
                            Text(
                              'Bukaanka: ',
                              style: GoogleFonts.plusJakartaSans(fontSize: 14, color: const Color(0xFF64748B)),
                            ),
                            Text(
                              patientName,
                              style: GoogleFonts.plusJakartaSans(fontSize: 14, fontWeight: FontWeight.bold, color: const Color(0xFF0F172A)),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            const Icon(Icons.phone_rounded, size: 18, color: Color(0xFF64748B)),
                            const SizedBox(width: 8),
                            Text(
                              'Taleefanka: ',
                              style: GoogleFonts.plusJakartaSans(fontSize: 14, color: const Color(0xFF64748B)),
                            ),
                            SelectableText(
                              patientPhone,
                              style: GoogleFonts.plusJakartaSans(fontSize: 14, fontWeight: FontWeight.bold, color: const Color(0xFF15803D)),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            const Icon(Icons.location_on_rounded, size: 18, color: Color(0xFF64748B)),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                'Cinwaanka: ${formatCleanAddress(order)}',
                                style: GoogleFonts.plusJakartaSans(fontSize: 14, color: const Color(0xFF0F172A)),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 20),
                        SizedBox(
                          width: double.infinity,
                          height: 52,
                          child: ElevatedButton.icon(
                            onPressed: () async {
                              final confirm = await showDialog<bool>(
                                context: context,
                                builder: (ctx) => AlertDialog(
                                  title: const Text('Xaqiiji Gaarsiinta'),
                                  content: Text('Ma hubtaa inaad gaarsiisay order-ka $orderNum bukaan "$patientName"?'),
                                  actions: [
                                    TextButton(
                                      onPressed: () => Navigator.pop(ctx, false),
                                      child: const Text('Ka noqo'),
                                    ),
                                    ElevatedButton(
                                      style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF15803D)),
                                      onPressed: () => Navigator.pop(ctx, true),
                                      child: const Text('Haa, Waan Gaarsiiyay', style: TextStyle(color: Colors.white)),
                                    ),
                                  ],
                                ),
                              );

                              if (confirm == true) {
                                final client = SupabaseService.instance.client;
                                if (client != null && SupabaseService.instance.isInitialized) {
                                  try {
                                    await client.from('orders').update({
                                      'status': 'Delivered',
                                    }).eq('id', orderId);
                                  } catch (e) {
                                    debugPrint('Update order delivered error: $e');
                                  }
                                }

                                if (context.mounted) {
                                  context.read<AppState>().updateOrderStatus(orderId, 'Delivered');
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(
                                      content: Text('Guul! Order-ka $orderNum waa la gaarsiiyay!'),
                                      backgroundColor: const Color(0xFF15803D),
                                    ),
                                  );
                                }
                              }
                            },
                            icon: const Icon(Icons.check_circle_rounded, color: Colors.white, size: 22),
                            label: Text(
                              '✅ Waan Gaarsiiyay',
                              style: GoogleFonts.plusJakartaSans(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                                color: Colors.white,
                              ),
                            ),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFF15803D),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                            ),
                          ),
                        ),
                      ],
                    ),
                  );
                },
              );
            },
          ),
        ],
      ),
    );
  }
}
