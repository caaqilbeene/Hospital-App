import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';
import '../../config/app_theme.dart';
import '../../services/app_state.dart';
import '../../models/user_model.dart';
import '../../models/doctor_model.dart';
import 'dart:typed_data';
import '../../services/image_picker_service.dart';
import '../../services/supabase_service.dart';
import '../../services/encryption_service.dart';
import '../../widgets/network_or_asset_image.dart';

class MessagesScreen extends StatefulWidget {
  final DoctorModel? doctor;
  const MessagesScreen({super.key, this.doctor});

  @override
  State<MessagesScreen> createState() => _MessagesScreenState();
}

class _MessagesScreenState extends State<MessagesScreen> {
  Widget _buildChatImage(String imageUrl) {
    return GestureDetector(
      onTap: () {
        showDialog(
          context: context,
          builder: (ctx) => Dialog(
            backgroundColor: Colors.black.withOpacity(0.9),
            insetPadding: EdgeInsets.zero,
            child: Stack(
              children: [
                Center(
                  child: InteractiveViewer(
                    minScale: 0.5,
                    maxScale: 4.0,
                    child: NetworkOrAssetImage(
                      imageUrl: imageUrl,
                      fit: BoxFit.contain,
                    ),
                  ),
                ),
                Positioned(
                  top: 40,
                  right: 20,
                  child: IconButton(
                    icon: const Icon(Icons.close, color: Colors.white, size: 28),
                    onPressed: () => Navigator.pop(ctx),
                  ),
                ),
              ],
            ),
          ),
        );
      },
      child: NetworkOrAssetImage(
        imageUrl: imageUrl,
        width: 220,
        height: 180,
        fit: BoxFit.cover,
        borderRadius: BorderRadius.circular(16),
      ),
    );
  }

  Timer? _pollTimer;
  DoctorModel? _activeChatDoctor;
  Timer? _typingTimer;

  @override
  void initState() {
    super.initState();
    // Instant initial fetch so messages appear immediately (0ms delay)
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (mounted) {
        final appState = Provider.of<AppState>(context, listen: false);
        await appState.fetchMessagesSilently();

        if (widget.doctor != null) {
          final pId = appState.currentUser?.fullName ?? 'usr_1';
          final convId = await appState.getOrCreateConversation(
            patientId: pId,
            doctorId: widget.doctor!.id,
          );
          if (!mounted) return;
          await appState.setActiveConversation(convId);
          await appState.fetchMessagesForActiveConversation();
        }

        _msgController.addListener(() {
          if (!mounted) return;
          final text = _msgController.text.trim();
          if (text.isNotEmpty) {
            appState.setPatientTyping(true);
            _typingTimer?.cancel();
            _typingTimer = Timer(const Duration(seconds: 2), () {
              if (mounted) {
                appState.setPatientTyping(false);
              }
            });
          }
        });
      }
    });
  }

  @override
  void didUpdateWidget(covariant MessagesScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.doctor != null && widget.doctor!.id != oldWidget.doctor?.id) {
      final appState = Provider.of<AppState>(context, listen: false);
      final pId = appState.currentUser?.fullName ?? 'usr_1';
      appState
          .getOrCreateConversation(patientId: pId, doctorId: widget.doctor!.id)
          .then((convId) {
            if (mounted) {
              appState.setActiveConversation(convId);
            }
          });
    }
  }

  final TextEditingController _msgController = TextEditingController();
  final ScrollController _scrollController = ScrollController();

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  Future<void> _pickAndSendImage(
    BuildContext context,
    AppState appState,
    UserModel? user,
    ImageSource source,
  ) async {
    try {
      final Uint8List? bytes = await ImagePickerService.pickImageBytes(source: source);
      if (bytes == null || bytes.isEmpty) return;

      // Single source of truth: Upload image directly to Supabase Storage bucket
      String publicStorageUrl = await ImagePickerService.uploadAndGetUrl(
        bytes,
        folder: 'chat_images',
      );
      if (publicStorageUrl.isEmpty) {
        // Compress image bytes to ~20KB so Supabase DB HTTP insert succeeds 100% of the time
        final compressed = ImagePickerService.compressBytes(bytes, maxWidth: 450, quality: 65);
        publicStorageUrl = 'data:image/jpeg;base64,${base64Encode(compressed)}';
      }

      final currentDoc = widget.doctor ?? _activeChatDoctor;
      final senderId = user?.id ?? user?.fullName ?? 'usr_1';
      final pName = user?.fullName ?? 'Patient';
      final cleanDocTarget = currentDoc?.id == 'admin_support' ? 'support' : (currentDoc?.id.replaceAll('doc_', '') ?? 'support');
      final convId = 'conv_${senderId}_$cleanDocTarget';

      await appState.sendChatMessage(
        senderId,
        pName,
        publicStorageUrl,
        senderId,
        imageUrl: publicStorageUrl,
        doctorId: currentDoc?.id,
        doctorName: currentDoc?.name,
        conversationId: convId,
      );

      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Sawirkii waa la diray!'),
            backgroundColor: Colors.green,
            duration: Duration(seconds: 2),
          ),
        );
      }
      _scrollToBottom();
    } catch (e) {
      debugPrint("Error picking/sending image: $e");
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Sawirka soo qaadista kuma guulaysanin: $e')),
        );
      }
    }
  }

  void _showImagePicker(
    BuildContext context,
    AppState appState,
    UserModel? user,
  ) {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (context) {
        return Container(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Send Prescription / Medicine Image',
                style: GoogleFonts.plusJakartaSans(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: AppTheme.textPrimary,
                ),
              ),
              const SizedBox(height: 20),
              // Gallery + Camera (on mobile) or Files (on web/laptop)
              if (kIsWeb)
                // On web: single full-width "Choose File" button
                InkWell(
                  onTap: () => _pickAndSendImage(
                    context,
                    appState,
                    user,
                    ImageSource.gallery, // gallery maps to file picker on web
                  ),
                  borderRadius: BorderRadius.circular(16),
                  child: Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(vertical: 20),
                    decoration: BoxDecoration(
                      color: AppTheme.primaryLight,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                        color: AppTheme.primaryColor.withOpacity(0.2),
                      ),
                    ),
                    child: Column(
                      children: [
                        const Icon(
                          Icons.upload_file_rounded,
                          color: AppTheme.primaryColor,
                          size: 32,
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Select Image from Computer / Phone',
                          style: GoogleFonts.plusJakartaSans(
                            fontWeight: FontWeight.bold,
                            color: AppTheme.primaryColor,
                            fontSize: 13,
                          ),
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'PNG, JPG, JPEG',
                          style: GoogleFonts.plusJakartaSans(
                            fontSize: 11,
                            color: AppTheme.textSecondary,
                          ),
                        ),
                      ],
                    ),
                  ),
                )
              else
                // On mobile: Gallery + Camera buttons
                Row(
                  children: [
                    Expanded(
                      child: InkWell(
                        onTap: () => _pickAndSendImage(
                          context,
                          appState,
                          user,
                          ImageSource.gallery,
                        ),
                        borderRadius: BorderRadius.circular(16),
                        child: Container(
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          decoration: BoxDecoration(
                            color: AppTheme.primaryLight,
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(
                              color: AppTheme.primaryColor.withOpacity(0.15),
                            ),
                          ),
                          child: Column(
                            children: [
                              const Icon(
                                Icons.photo_library_rounded,
                                color: AppTheme.primaryColor,
                                size: 28,
                              ),
                              const SizedBox(height: 8),
                              Text(
                                'Gallery',
                                style: GoogleFonts.plusJakartaSans(
                                  fontWeight: FontWeight.bold,
                                  color: AppTheme.primaryColor,
                                  fontSize: 13,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: InkWell(
                        onTap: () => _pickAndSendImage(
                          context,
                          appState,
                          user,
                          ImageSource.camera,
                        ),
                        borderRadius: BorderRadius.circular(16),
                        child: Container(
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          decoration: BoxDecoration(
                            color: AppTheme.primaryLight,
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(
                              color: AppTheme.primaryColor.withOpacity(0.15),
                            ),
                          ),
                          child: Column(
                            children: [
                              const Icon(
                                Icons.camera_alt_rounded,
                                color: AppTheme.primaryColor,
                                size: 28,
                              ),
                              const SizedBox(height: 8),
                              Text(
                                'Kamarada',
                                style: GoogleFonts.plusJakartaSans(
                                  fontWeight: FontWeight.bold,
                                  color: AppTheme.primaryColor,
                                  fontSize: 13,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              const SizedBox(height: 24),
              Text(
                'Or select a template / Ama ka dooro kuwan:',
                style: GoogleFonts.plusJakartaSans(
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  color: AppTheme.textSecondary,
                ),
              ),
              const SizedBox(height: 12),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  _buildMockImageOption(
                    context,
                    appState,
                    user,
                    label: 'Cough Syrup',
                    url: '',
                  ),

                  _buildMockImageOption(
                    context,
                    appState,
                    user,
                    label: 'Tablets Pack',
                    url: '',
                  ),
                  _buildMockImageOption(
                    context,
                    appState,
                    user,
                    label: 'Capsules',
                    url: '',
                  ),
                ],
              ),
              const SizedBox(height: 16),
            ],
          ),
        );
      },
    );
  }

  Widget _buildMockImageOption(
    BuildContext context,
    AppState appState,
    UserModel? user, {
    required String label,
    required String url,
  }) {
    return GestureDetector(
      onTap: () {
        if (user != null) {
          final currentDoc = widget.doctor ?? _activeChatDoctor;
          appState.sendChatMessage(
            user.id,
            user.fullName,
            '', // No text!
            user.fullName, // Keep patientId consistent as user.fullName!
            imageUrl: url,
            doctorId: currentDoc?.id,
            doctorName: currentDoc?.name,
          );
        }
        Navigator.pop(context);
        _scrollToBottom();
      },
      child: Column(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(16),
            child: Image.network(url, width: 80, height: 80, fit: BoxFit.cover),
          ),
          const SizedBox(height: 8),
          Text(
            label,
            style: GoogleFonts.plusJakartaSans(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: AppTheme.textSecondary,
            ),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    _typingTimer?.cancel();
    _msgController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final appState = context.watch<AppState>();
    final user = appState.currentUser;

    final DoctorModel supportDoctor = DoctorModel(
      id: 'admin_support',
      name: 'Nasiib Hospital Support',
      specialty: 'admin@nasiibhospital.com',
      hospital: 'Nasiib Hospital',
      imageUrl: 'assets/images/logo.jpeg',
      rating: 5.0,
      reviewsCount: 100,
      experience: '24/7',
      patientsCount: '10k+',
      workingHours: '24/7',
      about: 'Centralized Hospital Helpdesk Support',
      consultationFee: 0,
    );

    final activeDoctor = widget.doctor ?? _activeChatDoctor ?? supportDoctor;

    final messages = appState.chatMessages.where((m) {
      final mDocId = m['doctor_id']?.toString() ?? '';
      final mDocName = m['doctor_name']?.toString() ?? '';
      final cleanActiveDocId = activeDoctor.id.replaceAll('doc_', '');

      final bool matchDoctor =
          mDocId.isEmpty ||
          mDocId == activeDoctor.id ||
          mDocId == cleanActiveDocId ||
          activeDoctor.id.contains(mDocId) ||
          mDocId.contains(cleanActiveDocId) ||
          (mDocName.isNotEmpty &&
              (mDocName.toLowerCase() == activeDoctor.name.toLowerCase() ||
                  activeDoctor.name.toLowerCase().contains(
                    mDocName.toLowerCase(),
                  )));

      final pId = m['patient_id']?.toString() ?? '';
      final sId = m['sender_id']?.toString() ?? '';
      final sName = m['sender_name']?.toString() ?? '';
      final uId = user?.id ?? '';
      final uName = user?.fullName ?? '';

      final bool matchPatient =
          pId.isEmpty ||
          (uId.isNotEmpty && (pId == uId || sId == uId)) ||
          (uName.isNotEmpty &&
              (pId == uName || sId == uName || sName == uName)) ||
          (sId != 'doctor' && sId != 'admin');

      return matchDoctor && matchPatient;
    }).toList();

    final String doctorName = activeDoctor.name;
    final String doctorImageUrl = activeDoctor.imageUrl;

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0.5,
        leading: IconButton(
          icon: const Icon(
            Icons.arrow_back_ios_new_rounded,
            color: AppTheme.textPrimary,
            size: 20,
          ),
          onPressed: () {
            if (widget.doctor != null) {
              Navigator.pop(context);
            } else {
              setState(() {
                _activeChatDoctor = null;
              });
            }
          },
        ),
        title: Row(
          children: [
            NetworkOrAssetImage(
              key: ValueKey('header_${activeDoctor.id}_$doctorImageUrl'),
              imageUrl: doctorImageUrl,
              width: 36,
              height: 36,
              borderRadius: BorderRadius.circular(18),
              fit: BoxFit.cover,
            ),

            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          doctorName,
                          style: GoogleFonts.plusJakartaSans(
                            fontSize: 15,
                            fontWeight: FontWeight.bold,
                            color: AppTheme.textPrimary,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      const SizedBox(width: 4),
                      const Icon(
                        Icons.check_circle_rounded,
                        color: Color(0xFF0F8CFF),
                        size: 14,
                      ),
                    ],
                  ),
                  Builder(
                    builder: (context) {
                      final watchedState = context.watch<AppState>();
                      DoctorModel liveDoc;
                      try {
                        liveDoc = watchedState.doctors.firstWhere(
                          (d) => d.id == activeDoctor.id,
                        );
                      } catch (_) {
                        liveDoc = activeDoctor;
                      }
                      final bool isTyping = liveDoc.isTyping;
                      if (!isTyping) return const SizedBox.shrink();

                      return Row(
                        children: [
                          Container(
                            width: 8,
                            height: 8,
                            decoration: const BoxDecoration(
                              color: Color(0xFF14B8A6),
                              shape: BoxShape.circle,
                            ),
                          ),
                          const SizedBox(width: 4),
                          Text(
                            'typing...',
                            style: GoogleFonts.plusJakartaSans(
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                              color: const Color(0xFF14B8A6),
                              fontStyle: FontStyle.italic,
                            ),
                          ),
                        ],
                      );
                    },
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
      body: Column(
        children: [
          // Message Feed
          // Direct Supabase Realtime Message Feed Stream
          Expanded(
            child: StreamBuilder<List<Map<String, dynamic>>>(
              stream: SupabaseService.instance.client != null
                  ? SupabaseService.instance.client!
                      .from('messages')
                      .stream(primaryKey: ['id'])
                      .order('created_at', ascending: true)
                  : const Stream.empty(),
              builder: (context, snapshot) {
                final currentPId = user?.id ?? user?.fullName ?? '';
                final currentPName = user?.fullName ?? '';
                final cleanDocTarget = activeDoctor.id == 'admin_support' ? 'support' : activeDoctor.id.replaceAll('doc_', '');
                final targetConvId = 'conv_${currentPId}_$cleanDocTarget';
                final genericConvId = 'conv_$currentPId';

                final rawDocs = snapshot.data ?? [];
                final localDocs = appState.chatMessages;

                final Map<String, Map<String, dynamic>> combined = {};

                for (var m in localDocs) {
                  final key = m['id']?.toString() ?? DateTime.now().millisecondsSinceEpoch.toString();
                  combined[key] = Map<String, dynamic>.from(m);
                }

                for (var m in rawDocs) {
                  final key = m['id']?.toString() ?? DateTime.now().millisecondsSinceEpoch.toString();
                  if (combined.containsKey(key)) {
                    final existing = combined[key]!;
                    final merged = Map<String, dynamic>.from(m);
                    if ((merged['image_url'] ?? '').toString().isEmpty && (existing['image_url'] ?? '').toString().isNotEmpty) {
                      merged['image_url'] = existing['image_url'];
                    }
                    combined[key] = merged;
                  } else {
                    combined[key] = Map<String, dynamic>.from(m);
                  }
                }

                final streamedMessages = combined.values.where((m) {
                  final pId = (m['patient_id']?.toString() ?? '').trim();
                  final sId = (m['sender_id']?.toString() ?? '').trim();
                  final sName = (m['sender_name']?.toString() ?? '').trim();
                  final cId = (m['conversation_id']?.toString() ?? '').trim();

                  final bool matchesPatient = currentPId.isNotEmpty &&
                      (pId == currentPId || sId == currentPId || pId == currentPName || sName == currentPName || cId == targetConvId || cId == genericConvId || cId.contains(currentPId));

                  return matchesPatient;
                }).toList();

                if (snapshot.connectionState == ConnectionState.waiting && streamedMessages.isEmpty) {
                  return const Center(
                    child: CircularProgressIndicator(strokeWidth: 2),
                  );
                }

                if (streamedMessages.isEmpty) {
                  return Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Container(
                          padding: const EdgeInsets.all(20),
                          decoration: const BoxDecoration(
                            color: Color(0xFFF8FAFC),
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(
                            Icons.chat_bubble_outline_rounded,
                            size: 48,
                            color: Color(0xFF94A3B8),
                          ),
                        ),
                        const SizedBox(height: 16),
                        Text(
                          'Wali wax fariin ah ma aadan dirin.',
                          style: GoogleFonts.plusJakartaSans(
                            fontSize: 14,
                            fontWeight: FontWeight.bold,
                            color: const Color(0xFF64748B),
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Ku qor fariintaada hoos si aad u bilowdo.',
                          style: GoogleFonts.plusJakartaSans(
                            fontSize: 12,
                            color: const Color(0xFF94A3B8),
                          ),
                        ),
                      ],
                    ),
                  );
                }

                return ListView.builder(
                  controller: _scrollController,
                  padding: const EdgeInsets.all(16),
                  itemCount: streamedMessages.length,
                  itemBuilder: (context, index) {
                    final msg = streamedMessages[index];
                    final msgId = (msg['id']?.toString() ?? DateTime.now().millisecondsSinceEpoch.toString());
                    final sId = (msg['sender_id']?.toString() ?? '').trim();
                    final sRole = (msg['sender_role']?.toString() ?? '').trim();
                    final isMe = (sId == currentPId || sId == currentPName) && sRole != 'doctor' && sRole != 'admin' && sId != 'admin' && sId != 'doctor' && sId != 'support';

                    final patientAvatar = (user?.avatarUrl != null && user!.avatarUrl.isNotEmpty) ? user.avatarUrl : '';
                    final doctorAvatar = doctorImageUrl;

                    final rawText = msg['message'] ?? msg['text'] ?? msg['content'] ?? '';
                    final decryptedText = EncryptionService.decrypt(rawText.toString());

                    String imgUrl = (msg['image_url'] ?? msg['media_url'] ?? msg['attachment_url'] ?? '').toString().trim();
                    if (imgUrl.isEmpty && (rawText.toString().startsWith('http://') || rawText.toString().startsWith('https://') || rawText.toString().startsWith('data:image/'))) {
                      imgUrl = rawText.toString().trim();
                    }

                    final hasImage = imgUrl.isNotEmpty;
                    final hasText = !hasImage && decryptedText.isNotEmpty && decryptedText != '[Sawir]' && !rawText.toString().startsWith('http://') && !rawText.toString().startsWith('https://') && !rawText.toString().startsWith('data:image/');

                      return Dismissible(
                        key: Key(msgId),
                        direction: DismissDirection.horizontal,
                        background: Container(
                          alignment: Alignment.centerLeft,
                          padding: const EdgeInsets.symmetric(horizontal: 20),
                          color: AppTheme.errorRed.withOpacity(0.8),
                          child: const Icon(
                            Icons.delete_forever_rounded,
                            color: Colors.white,
                          ),
                        ),
                        secondaryBackground: Container(
                          alignment: Alignment.centerRight,
                          padding: const EdgeInsets.symmetric(horizontal: 20),
                          color: AppTheme.errorRed.withOpacity(0.8),
                          child: const Icon(
                            Icons.delete_forever_rounded,
                            color: Colors.white,
                          ),
                        ),
                        onDismissed: (direction) {
                          appState.deleteChatMessage(msgId);
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text(
                                'Fariintii si joogto ah ayaa loo tirtiray (Permanently Deleted).',
                              ),
                            ),
                          );
                        },
                        child: Padding(
                          padding: const EdgeInsets.symmetric(vertical: 6.0),
                          child: Row(
                            mainAxisAlignment: isMe
                                ? MainAxisAlignment.end
                                : MainAxisAlignment.start,
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              if (!isMe) ...[
                                NetworkOrAssetImage(
                                  imageUrl: doctorAvatar,
                                  width: 32,
                                  height: 32,
                                  fit: BoxFit.cover,
                                  borderRadius: BorderRadius.circular(16),
                                ),
                                const SizedBox(width: 8),
                              ],
                              Flexible(
                                child: Column(
                                  crossAxisAlignment: isMe
                                      ? CrossAxisAlignment.end
                                      : CrossAxisAlignment.start,
                                  children: [
                                    if (hasImage) ...[
                                      Container(
                                        margin: const EdgeInsets.only(
                                          bottom: 4,
                                        ),
                                        decoration: BoxDecoration(
                                          borderRadius: BorderRadius.circular(
                                            16,
                                          ),
                                          boxShadow: [
                                            BoxShadow(
                                              color: Colors.black.withOpacity(
                                                0.08,
                                              ),
                                              blurRadius: 8,
                                              offset: const Offset(0, 2),
                                            ),
                                          ],
                                        ),
                                        child: ClipRRect(
                                          borderRadius: BorderRadius.circular(
                                            16,
                                          ),
                                          child: _buildChatImage(
                                            imgUrl,
                                          ),
                                        ),
                                      ),
                                    ],
                                    if (hasText) ...[
                                      Container(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 16,
                                          vertical: 10,
                                        ),
                                        decoration: BoxDecoration(
                                          color: isMe
                                              ? const Color(0xFF14B8A6)
                                              : const Color(0xFFF1F5F9),
                                          borderRadius:
                                              BorderRadius.circular(
                                                16,
                                              ).copyWith(
                                                bottomRight: isMe
                                                    ? const Radius.circular(0)
                                                    : const Radius.circular(16),
                                                bottomLeft: isMe
                                                    ? const Radius.circular(16)
                                                    : const Radius.circular(0),
                                              ),
                                        ),
                                        constraints: BoxConstraints(
                                          maxWidth:
                                              MediaQuery.of(
                                                context,
                                              ).size.width *
                                              0.65,
                                        ),
                                        child: Text(
                                          decryptedText.isEmpty ? (msg['text'] ?? msg['message'] ?? '').toString() : decryptedText,
                                          style: GoogleFonts.plusJakartaSans(
                                            fontSize: 13.5,
                                            color: isMe
                                                ? Colors.white
                                                : AppTheme.textPrimary,
                                            fontWeight: isMe
                                                ? FontWeight.w600
                                                : FontWeight
                                                      .w500, // Extra bright white, bolder
                                            height: 1.4,
                                          ),
                                        ),
                                      ),
                                    ],
                                    Padding(
                                      padding: const EdgeInsets.only(
                                        top: 2.0,
                                        left: 4,
                                        right: 4,
                                      ),
                                      child: isMe
                                          ? Row(
                                              mainAxisSize: MainAxisSize.min,
                                              children: [
                                                Text(
                                                  'Sent',
                                                  style:
                                                      GoogleFonts.plusJakartaSans(
                                                        fontSize: 9,
                                                        fontWeight:
                                                            FontWeight.bold,
                                                        color: Colors.black45,
                                                      ),
                                                ),
                                                const SizedBox(width: 4),
                                                Icon(
                                                  Icons.done_all_rounded,
                                                  size: 16,
                                                  color:
                                                      (msg['is_read'] ?? false)
                                                      ? const Color(0xFF0F8CFF)
                                                      : const Color(0xFF94A3B8),
                                                ),
                                              ],
                                            )
                                          : Text(
                                              msg['sender_name'] ?? 'Doctor',
                                              style:
                                                  GoogleFonts.plusJakartaSans(
                                                    fontSize: 9,
                                                    fontWeight: FontWeight.bold,
                                                    color: Colors.black45,
                                                  ),
                                            ),
                                    ),
                                  ],
                                ),
                              ),
                              if (isMe) ...[
                                const SizedBox(width: 8),
                                NetworkOrAssetImage(
                                  imageUrl: patientAvatar,
                                  width: 32,
                                  height: 32,
                                  fit: BoxFit.cover,
                                  borderRadius: BorderRadius.circular(16),
                                ),
                              ],
                            ],
                          ),
                        ),
                      );
                    },
                  );
              },
            ),
          ),

          // Message input bar
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: const BoxDecoration(
              color: Colors.white,
              border: Border(top: BorderSide(color: Color(0xFFE2E8F0))),
            ),
            child: SafeArea(
              child: Row(
                children: [
                  // Attachment image button
                  GestureDetector(
                    onTap: () => _pickAndSendImage(
                      context,
                      appState,
                      user,
                      ImageSource.gallery,
                    ),
                    child: Container(
                      padding: const EdgeInsets.all(10),
                      decoration: const BoxDecoration(
                        color: Color(0xFFF1F5F9),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(
                        Icons.image_outlined,
                        color: AppTheme.primaryColor,
                        size: 20,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: TextField(
                      controller: _msgController,
                      autocorrect: false,
                      enableSuggestions: false,
                      style: GoogleFonts.plusJakartaSans(fontSize: 14),
                      decoration: InputDecoration(
                        hintText: 'Qor fariintaada halkaan...',
                        hintStyle: GoogleFonts.plusJakartaSans(
                          fontSize: 13,
                          color: const Color(0xFF94A3B8),
                        ),
                        fillColor: const Color(0xFFF8FAFC),
                        filled: true,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(24),
                          borderSide: BorderSide.none,
                        ),
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 20,
                          vertical: 10,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  GestureDetector(
                    onTap: () async {
                      final text = _msgController.text.trim();
                      if (text.isNotEmpty && user != null) {
                        final String patientId = user.id.isNotEmpty ? user.id : user.fullName;
                        final String patientName = user.fullName.isNotEmpty ? user.fullName : 'Patient';
                        final String cleanDocTarget = activeDoctor.id == 'admin_support' ? 'support' : activeDoctor.id.replaceAll('doc_', '');
                        final String convId = 'conv_${patientId}_$cleanDocTarget';

                        _msgController.clear();

                        // 1. Instantly reflect in local state & scroll
                        appState.sendChatMessage(
                          patientId,
                          patientName,
                          text,
                          patientId,
                          doctorId: activeDoctor.id,
                          doctorName: activeDoctor.name,
                          conversationId: convId,
                        );
                        _scrollToBottom();
                      }
                    },
                    child: Container(
                      padding: const EdgeInsets.all(12),
                      decoration: const BoxDecoration(
                        color: AppTheme.primaryColor,
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(
                        Icons.send_rounded,
                        color: Colors.white,
                        size: 20,
                      ),
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
}
