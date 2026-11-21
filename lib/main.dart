import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

// ====== APNE NAYE (alag) SUPABASE PROJECT KA URL AUR KEY YAHAN DAALEIN ======
const supabaseUrl = 'https://otkvaumqxqlxtyswveyr.supabase.co';
const supabaseKey = 'sb_publishable_NiXLrRQALuYioSBTcpQntA_JfspBL76';
// =============================================================================

const Color kBrand = Color(0xFF00796B);
const Color kBg = Color(0xFFF8F9FA);
const Color kGrey = Color(0xFF6B7280);

// Agreement ab database me rehta hai. Admin app me "Agreement" tab se likh/badal sakta hai.
Future<DbRow?> fetchAgreement() async {
  return await db
      .from('agreements')
      .select()
      .order('version', ascending: false)
      .limit(1)
      .maybeSingle();
}

const String kDeclarationText =
    'Main ghoshit karta/karti hu ki ye content meri apni original rachna hai, aur isme kisi aur ka copyrighted material (gaana, film clip, kitab ke page, doosre ki photo) bina ijazat nahi hai.';
// ====================================================================================

typedef DbRow = Map<String, dynamic>;
SupabaseClient get db => Supabase.instance.client;

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final configured =
      !supabaseUrl.startsWith('YAHAN') && !supabaseKey.startsWith('YAHAN');
  if (configured) {
    await Supabase.initialize(url: supabaseUrl, anonKey: supabaseKey);
  }
  runApp(TeacherApp(configured: configured));
}

class TeacherApp extends StatelessWidget {
  final bool configured;
  const TeacherApp({super.key, required this.configured});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Teacher Hub',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: kBrand),
        scaffoldBackgroundColor: kBg,
        useMaterial3: true,
      ),
      home: configured ? const AuthGate() : const SetupMissing(),
    );
  }
}

Card appCard({required Widget child, EdgeInsetsGeometry? margin}) => Card(
      color: Colors.white,
      surfaceTintColor: Colors.transparent,
      elevation: 3,
      shadowColor: Colors.black26,
      margin: margin ?? const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: child,
    );

void snack(BuildContext context, String text) {
  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
}

String errText(Object e) {
  if (e is AuthException) return e.message;
  if (e is FunctionException) {
    final d = e.details;
    return d is Map ? '${d['error'] ?? d}' : '$d';
  }
  return '$e';
}

class CenterMessage extends StatelessWidget {
  final String text;
  final List<Widget> actions;
  const CenterMessage({super.key, required this.text, this.actions = const []});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.school, size: 64, color: kBrand),
              const SizedBox(height: 16),
              Text(text, textAlign: TextAlign.center, style: const TextStyle(fontSize: 16)),
              const SizedBox(height: 16),
              ...actions,
            ],
          ),
        ),
      ),
    );
  }
}

class SetupMissing extends StatelessWidget {
  const SetupMissing({super.key});
  @override
  Widget build(BuildContext context) => const CenterMessage(
      text: 'Setup baaki hai.\n\nlib/main.dart me upar apni Supabase publishable key daalein.');
}

// ---------------------------------------------------------------------------
// Login / Register
// ---------------------------------------------------------------------------

class AuthGate extends StatelessWidget {
  const AuthGate({super.key});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<AuthState>(
      stream: db.auth.onAuthStateChange,
      builder: (context, _) =>
          db.auth.currentSession == null ? const LoginScreen() : const ProfileGate(),
    );
  }
}

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});
  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _name = TextEditingController();
  final _phone = TextEditingController();
  final _email = TextEditingController();
  final _pass = TextEditingController();
  bool _register = false;
  bool _agree = false;
  bool _busy = false;
  String? _msg;
  DbRow? _agreement;

  @override
  void initState() {
    super.initState();
    _loadAgreement();
  }

  Future<void> _loadAgreement() async {
    try {
      final a = await fetchAgreement();
      if (mounted) setState(() => _agreement = a);
    } catch (_) {}
  }

  Future<void> _submit() async {
    final email = _email.text.trim();
    final pass = _pass.text;
    if (email.isEmpty || pass.length < 6) {
      setState(() => _msg = 'Email daalein aur password kam se kam 6 akshar ka rakhein.');
      return;
    }
    if (_register && _name.text.trim().isEmpty) {
      setState(() => _msg = 'Apna naam daalein.');
      return;
    }
    if (_register && _agreement == null) {
      setState(() => _msg = 'Agreement abhi taiyar nahi hai. Admin ko pehle agreement likhna hai.');
      _loadAgreement();
      return;
    }
    if (_register && '${_agreement!['body']}'.contains('[')) {
      setState(() => _msg = 'Agreement adhura hai ([ ] baaki hain). Admin ko use poora karna hai.');
      return;
    }
    if (_register && !_agree) {
      setState(() => _msg = 'Pehle agreement padhkar "sahmat hu" par tick karein.');
      return;
    }
    setState(() {
      _busy = true;
      _msg = null;
    });
    try {
      if (_register) {
        final res = await db.auth.signUp(
          email: email,
          password: pass,
          data: {
            'full_name': _name.text.trim(),
            'phone': _phone.text.trim(),
            'agreement_version': '${_agreement!['version']}',
          },
        );
        if (res.session == null) {
          _msg = 'Account ban gaya. Email confirm maanga ho to inbox dekhein, phir login karein.';
        }
      } else {
        await db.auth.signInWithPassword(email: email, password: pass);
      }
    } catch (e) {
      _msg = errText(e);
    }
    if (mounted) setState(() => _busy = false);
  }

  Widget _field(TextEditingController c, String label,
      {bool obscure = false, TextInputType? type}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: TextField(
        controller: c,
        obscureText: obscure,
        keyboardType: type,
        decoration: InputDecoration(labelText: label, border: const OutlineInputBorder()),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            children: [
              const Icon(Icons.school, size: 72, color: kBrand),
              const SizedBox(height: 8),
              const Text('Teacher Hub',
                  style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
              const SizedBox(height: 4),
              Text(_register ? 'Naya teacher account' : 'Login',
                  style: const TextStyle(color: kGrey)),
              const SizedBox(height: 20),
              if (_register) ...[
                _field(_name, 'Poora naam'),
                _field(_phone, 'Phone number', type: TextInputType.phone),
              ],
              _field(_email, 'Email', type: TextInputType.emailAddress),
              _field(_pass, 'Password', obscure: true),
              if (_register)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Row(
                    children: [
                      Checkbox(
                        value: _agree,
                        activeColor: kBrand,
                        onChanged: (v) => setState(() => _agree = v ?? false),
                      ),
                      const Expanded(
                          child: Text('Maine agreement padh liya hai aur sahmat hu')),
                    ],
                  ),
                ),
              if (_register)
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton.icon(
                    onPressed: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                            builder: (_) => AgreementScreen(
                                text: '${_agreement?['body'] ?? 'Agreement abhi uplabdh nahi hai.'}'))),
                    icon: const Icon(Icons.description),
                    label: const Text('Agreement padhein'),
                  ),
                ),
              if (_msg != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Text(_msg!, style: const TextStyle(color: Colors.red)),
                ),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: _busy ? null : _submit,
                  child: Text(_busy ? 'Ruko...' : (_register ? 'Account banayein' : 'Login')),
                ),
              ),
              TextButton(
                onPressed: () => setState(() {
                  _register = !_register;
                  _msg = null;
                }),
                child: Text(_register ? 'Pehle se account hai? Login' : 'Naya teacher? Register karein'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class AgreementScreen extends StatelessWidget {
  final String text;
  const AgreementScreen({super.key, required this.text});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Agreement'),
        backgroundColor: kBrand,
        foregroundColor: Colors.white,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(18),
        child: SelectableText(text, style: const TextStyle(fontSize: 15, height: 1.5)),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Profile check: admin / approved teacher / pending teacher
// ---------------------------------------------------------------------------

class ProfileGate extends StatefulWidget {
  const ProfileGate({super.key});
  @override
  State<ProfileGate> createState() => _ProfileGateState();
}

class _ProfileGateState extends State<ProfileGate> {
  late Future<List<DbRow?>> _future = _load();

  Future<List<DbRow?>> _load() async {
    final p = await db
        .from('profiles')
        .select()
        .eq('id', db.auth.currentUser!.id)
        .maybeSingle();
    DbRow? a;
    try {
      a = await fetchAgreement();
    } catch (_) {}
    return [p, a];
  }

  void _reload() => setState(() => _future = _load());

  List<Widget> _buttons() => [
        FilledButton(onPressed: _reload, child: const Text('Dobara check karein')),
        TextButton(onPressed: () => db.auth.signOut(), child: const Text('Logout')),
      ];

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<DbRow?>>(
      future: _future,
      builder: (context, snap) {
        if (snap.connectionState != ConnectionState.done) {
          return const Scaffold(body: Center(child: CircularProgressIndicator(color: kBrand)));
        }
        if (snap.hasError) {
          return CenterMessage(text: 'Data nahi aaya:\n${snap.error}', actions: _buttons());
        }
        final p = snap.data![0];
        final a = snap.data![1];
        if (p == null) {
          return CenterMessage(
              text: 'Aapki profile nahi mili. Logout karke dobara register karein.',
              actions: _buttons());
        }
        final active = p['active'] == true;
        if (!active) {
          return CenterMessage(
              text: 'Aapka account abhi approval ke liye ruka hai.\nAdmin approve karega tab aap upload kar payenge.',
              actions: _buttons());
        }
        if (p['role'] == 'admin') return const AdminHome();
        // Agreement badal gaya ho to teacher ko dobara sahmati deni hoti hai
        if (a != null && '${p['agreement_version'] ?? ''}' != '${a['version']}') {
          return AcceptAgreementScreen(agreement: a, onDone: _reload);
        }
        return TeacherHome(profile: p);
      },
    );
  }
}

class AcceptAgreementScreen extends StatefulWidget {
  final DbRow agreement;
  final VoidCallback onDone;
  const AcceptAgreementScreen({super.key, required this.agreement, required this.onDone});
  @override
  State<AcceptAgreementScreen> createState() => _AcceptAgreementScreenState();
}

class _AcceptAgreementScreenState extends State<AcceptAgreementScreen> {
  bool _agree = false;
  bool _busy = false;

  Future<void> _accept() async {
    setState(() => _busy = true);
    try {
      await db.rpc('accept_agreement', params: {'v': widget.agreement['version']});
      widget.onDone();
    } catch (e) {
      if (mounted) {
        setState(() => _busy = false);
        snack(context, 'Nahi hua: ${errText(e)}');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Agreement badal gaya hai'),
        backgroundColor: kBrand,
        foregroundColor: Colors.white,
      ),
      body: Column(
        children: [
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 12, 16, 0),
            child: Text('Upload jaari rakhne ke liye naya agreement padhkar sahmati dein.',
                style: TextStyle(color: kGrey)),
          ),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: SelectableText('${widget.agreement['body']}',
                  style: const TextStyle(fontSize: 15, height: 1.5)),
            ),
          ),
          Row(
            children: [
              Checkbox(
                value: _agree,
                activeColor: kBrand,
                onChanged: (v) => setState(() => _agree = v ?? false),
              ),
              const Expanded(child: Text('Maine naya agreement padh liya hai aur sahmat hu')),
            ],
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: SizedBox(
              width: double.infinity,
              child: FilledButton(
                style: FilledButton.styleFrom(backgroundColor: kBrand, padding: const EdgeInsets.all(14)),
                onPressed: (_agree && !_busy) ? _accept : null,
                child: Text(_busy ? 'Ruko...' : 'Sahmat hu, aage badhein'),
              ),
            ),
          ),
          TextButton(onPressed: () => db.auth.signOut(), child: const Text('Logout')),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Teacher: apne uploads + naya upload
// ---------------------------------------------------------------------------

Color statusColor(String s) =>
    s == 'approved' ? Colors.green : (s == 'rejected' ? Colors.red : Colors.orange);

String statusLabel(String s) =>
    s == 'approved' ? 'Approved' : (s == 'rejected' ? 'Rejected' : 'Pending');

class StatusChip extends StatelessWidget {
  final String status;
  const StatusChip(this.status, {super.key});
  @override
  Widget build(BuildContext context) {
    final c = statusColor(status);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
          color: c.withOpacity(0.12), borderRadius: BorderRadius.circular(20)),
      child: Text(statusLabel(status),
          style: TextStyle(color: c, fontWeight: FontWeight.w600, fontSize: 12)),
    );
  }
}

Future<void> openLink(BuildContext context, String link) async {
  try {
    await launchUrl(Uri.parse(link), mode: LaunchMode.externalApplication);
  } catch (e) {
    if (context.mounted) snack(context, 'Link nahi khula');
  }
}

// Content ke prakar
const Map<String, String> kTypeLabels = {
  'video': 'Video',
  'photo': 'Photo',
  'pdf': 'PDF',
  'text': 'Text / Notes',
  'question': 'Question',
  'answer': 'Answer',
  'rachna': 'Rachna (Composition)',
};
const List<String> kFileTypes = ['video', 'photo', 'pdf'];

IconData typeIcon(String t) {
  switch (t) {
    case 'video':
      return Icons.play_circle_fill;
    case 'photo':
      return Icons.image;
    case 'pdf':
      return Icons.picture_as_pdf;
    case 'question':
      return Icons.help;
    case 'answer':
      return Icons.check_circle;
    case 'rachna':
      return Icons.edit_note;
    default:
      return Icons.notes;
  }
}

/// Drive ka link ho to wo, nahi to purana link, nahi to null (text wale content me)
String? submissionLink(DbRow r) {
  final d = r['drive_link'];
  if (d is String && d.isNotEmpty) return d;
  final l = r['link'];
  if (l is String && l.isNotEmpty) return l;
  return null;
}

class TeacherHome extends StatefulWidget {
  final DbRow profile;
  const TeacherHome({super.key, required this.profile});
  @override
  State<TeacherHome> createState() => _TeacherHomeState();
}

class _TeacherHomeState extends State<TeacherHome> {
  late Future<List<DbRow>> _future = _load();

  Future<List<DbRow>> _load() async => List<DbRow>.from(await db
      .from('submissions')
      .select()
      .order('created_at', ascending: false));

  void _refresh() => setState(() => _future = _load());

  Future<void> _openForm([DbRow? row]) async {
    final saved = await Navigator.push<bool>(
      context,
      MaterialPageRoute(builder: (_) => SubmissionForm(row: row)),
    );
    if (saved == true) _refresh();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Namaste, ${widget.profile['full_name'] ?? ''}'),
        backgroundColor: kBrand,
        foregroundColor: Colors.white,
        actions: [
          IconButton(
              tooltip: 'Bank details',
              icon: const Icon(Icons.account_balance),
              onPressed: () => Navigator.push(
                  context, MaterialPageRoute(builder: (_) => const BankScreen()))),
          IconButton(
              tooltip: 'Logout',
              icon: const Icon(Icons.logout),
              onPressed: () => db.auth.signOut()),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: kBrand,
        foregroundColor: Colors.white,
        onPressed: () => _openForm(),
        icon: const Icon(Icons.upload),
        label: const Text('Naya upload'),
      ),
      body: FutureBuilder<List<DbRow>>(
        future: _future,
        builder: (context, snap) {
          if (snap.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator(color: kBrand));
          }
          if (snap.hasError) {
            return Center(child: Text('Data nahi aaya:\n${snap.error}', textAlign: TextAlign.center));
          }
          final rows = snap.data ?? [];
          if (rows.isEmpty) {
            return const Center(
                child: Text('Abhi koi upload nahi.\nNeeche "Naya upload" dabayein.',
                    textAlign: TextAlign.center, style: TextStyle(color: kGrey, fontSize: 16)));
          }
          return RefreshIndicator(
            onRefresh: () async => _refresh(),
            child: ListView.builder(
              padding: const EdgeInsets.only(top: 8, bottom: 90),
              itemCount: rows.length,
              itemBuilder: (context, i) {
                final r = rows[i];
                final status = '${r['status']}';
                final note = '${r['admin_note'] ?? ''}';
                final type = '${r['type']}';
                // Drive file sirf admin ki hoti hai, teacher ko wahan link nahi dikhate
                final link = '${r['link'] ?? ''}'.isNotEmpty ? '${r['link']}' : null;
                final body = '${r['body'] ?? ''}';
                return appCard(
                  child: Padding(
                    padding: const EdgeInsets.all(14),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Icon(typeIcon(type), color: kBrand),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text('${r['title']}',
                                  style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
                            ),
                            StatusChip(status),
                          ],
                        ),
                        const SizedBox(height: 6),
                        Text('${kTypeLabels[type] ?? type} • ${r['class_name']} • ${r['subject']}',
                            style: const TextStyle(color: kGrey)),
                        if (body.isNotEmpty)
                          Padding(
                            padding: const EdgeInsets.only(top: 6),
                            child: Text(body, maxLines: 3, overflow: TextOverflow.ellipsis),
                          ),
                        if (status == 'rejected' && note.isNotEmpty)
                          Padding(
                            padding: const EdgeInsets.only(top: 8),
                            child: Text('Admin ka note: $note',
                                style: const TextStyle(color: Colors.red)),
                          ),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.end,
                          children: [
                            if (link != null)
                              TextButton(
                                  onPressed: () => openLink(context, link),
                                  child: const Text('Dekhein')),
                            if (status != 'approved')
                              TextButton(onPressed: () => _openForm(r), child: const Text('Badlein'))
                            else
                              const Padding(
                                padding: EdgeInsets.only(right: 8),
                                child: Text('Approved: badal nahi sakte',
                                    style: TextStyle(color: kGrey, fontSize: 12)),
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
        },
      ),
    );
  }
}

class SubmissionForm extends StatefulWidget {
  final DbRow? row;
  const SubmissionForm({super.key, this.row});
  @override
  State<SubmissionForm> createState() => _SubmissionFormState();
}

class _SubmissionFormState extends State<SubmissionForm> {
  late final _title = TextEditingController(text: widget.row?['title'] as String? ?? '');
  late final _subject = TextEditingController(text: widget.row?['subject'] as String? ?? '');
  late final _desc = TextEditingController(text: widget.row?['description'] as String? ?? '');
  late final _body = TextEditingController(text: widget.row?['body'] as String? ?? '');
  late String _class = widget.row?['class_name'] as String? ?? 'Class 10';
  late String _type = widget.row?['type'] as String? ?? 'video';
  PlatformFile? _picked;
  double? _progress;
  bool _declared = false;
  bool _busy = false;

  final _classes = [for (var i = 1; i <= 12; i++) 'Class $i'];

  bool get _isFile => kFileTypes.contains(_type);

  String _mime(String name) {
    final e = name.toLowerCase().split('.').last;
    const m = {
      'mp4': 'video/mp4',
      'mov': 'video/quicktime',
      'mkv': 'video/x-matroska',
      'webm': 'video/webm',
      '3gp': 'video/3gpp',
      'jpg': 'image/jpeg',
      'jpeg': 'image/jpeg',
      'png': 'image/png',
      'webp': 'image/webp',
      'pdf': 'application/pdf',
    };
    return m[e] ?? 'application/octet-stream';
  }

  Future<void> _pick() async {
    final ft = _type == 'video'
        ? FileType.video
        : (_type == 'photo' ? FileType.image : FileType.custom);
    final res = await FilePicker.platform.pickFiles(
      type: ft,
      allowedExtensions: _type == 'pdf' ? ['pdf'] : null,
    );
    if (res == null || res.files.isEmpty) return;
    setState(() => _picked = res.files.first);
  }

  // File seedha Google Drive par jati hai (Supabase function se ijazat leke)
  Future<Map<String, dynamic>> _uploadFile(PlatformFile f) async {
    final path = f.path;
    if (path == null) throw 'File ka rasta nahi mila';
    final file = File(path);
    final len = await file.length();
    final mime = _mime(f.name);
    if (mime == 'application/octet-stream') throw 'Is prakar ki file allowed nahi hai';

    final res = await db.functions.invoke('drive',
        body: {'action': 'session', 'name': f.name, 'mime': mime, 'size': len});
    final data = res.data;
    if (data is! Map || data['uploadUrl'] == null) {
      throw 'Drive se upload ki ijazat nahi mili';
    }

    final req = http.StreamedRequest('PUT', Uri.parse(data['uploadUrl'] as String));
    req.headers['Content-Type'] = mime;
    req.contentLength = len;
    var sent = 0;
    var last = 0.0;
    final sending = req.send();
    await req.sink.addStream(file.openRead().map((chunk) {
      sent += chunk.length;
      final p = sent / len;
      if (p - last >= 0.01 && mounted) {
        last = p;
        setState(() => _progress = p);
      }
      return chunk;
    }));
    await req.sink.close();
    final resp = await sending;
    final text = await resp.stream.bytesToString();
    if (resp.statusCode != 200 && resp.statusCode != 201) {
      throw 'Upload poora nahi hua (code ${resp.statusCode}). Dobara try karein.';
    }
    final j = jsonDecode(text) as Map<String, dynamic>;
    if (j['id'] == null) throw 'Upload ke baad file ID nahi mili';
    return {'id': j['id'], 'name': f.name};
  }

  Future<void> _save() async {
    final title = _title.text.trim();
    final subject = _subject.text.trim();
    if (title.isEmpty || subject.isEmpty) {
      snack(context, 'Title aur Subject daalna zaroori hai');
      return;
    }
    final old = widget.row;
    final hasOldFile = old != null &&
        old['type'] == _type &&
        ('${old['drive_file_id'] ?? ''}'.isNotEmpty || '${old['link'] ?? ''}'.isNotEmpty);
    if (_isFile && _picked == null && !hasOldFile) {
      snack(context, 'Pehle file chunein');
      return;
    }
    if (!_isFile && _body.text.trim().isEmpty) {
      snack(context, '${kTypeLabels[_type]} likhna zaroori hai');
      return;
    }
    if (!_declared) {
      snack(context, 'Pehle copyright declaration par tick karein');
      return;
    }
    setState(() {
      _busy = true;
      _progress = null;
    });
    try {
      final vals = <String, dynamic>{
        'title': title,
        'subject': subject,
        'class_name': _class,
        'type': _type,
        'description': _desc.text.trim().isEmpty ? null : _desc.text.trim(),
        'status': 'pending',
        'admin_note': null,
        'declaration_accepted': true,
        'declared_at': DateTime.now().toUtc().toIso8601String(),
      };
      if (_isFile) {
        if (_picked != null) {
          final up = await _uploadFile(_picked!);
          vals['drive_file_id'] = up['id'];
          vals['drive_link'] = 'https://drive.google.com/file/d/${up['id']}/view';
          vals['file_name'] = up['name'];
          vals['link'] = null;
          vals['body'] = null;
        }
      } else {
        final body = _body.text.trim();
        vals['body'] = body;
        vals['link'] = null;
        // Drive me text ki copy (na ho paye to bhi database me save rehta hai)
        try {
          final res = await db.functions.invoke('drive', body: {
            'action': 'text',
            'name': '$title.txt',
            'content': '$title\n${kTypeLabels[_type]} | $_class | $subject\n\n$body\n',
          });
          final d = res.data;
          if (d is Map && d['fileId'] != null) {
            vals['drive_file_id'] = d['fileId'];
            vals['drive_link'] = d['link'];
          }
        } catch (_) {}
      }
      if (old == null) {
        await db.from('submissions').insert(vals);
      } else {
        await db.from('submissions').update(vals).eq('id', old['id']);
      }
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) {
        setState(() => _busy = false);
        snack(context, 'Save nahi hua: ${errText(e)}');
      }
    }
  }

  Widget _gap(Widget w) => Padding(padding: const EdgeInsets.only(bottom: 14), child: w);

  @override
  Widget build(BuildContext context) {
    final hasOld = widget.row != null &&
        widget.row!['type'] == _type &&
        ('${widget.row!['drive_file_id'] ?? ''}'.isNotEmpty ||
            '${widget.row!['link'] ?? ''}'.isNotEmpty);
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.row == null ? 'Naya upload' : 'Badlein'),
        backgroundColor: kBrand,
        foregroundColor: Colors.white,
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _gap(DropdownButtonFormField<String>(
            value: _type,
            decoration: const InputDecoration(labelText: 'Kya upload karna hai', border: OutlineInputBorder()),
            items: [
              for (final e in kTypeLabels.entries)
                DropdownMenuItem(value: e.key, child: Text(e.value))
            ],
            onChanged: _busy
                ? null
                : (v) => setState(() {
                      _type = v ?? _type;
                      _picked = null;
                    }),
          )),
          _gap(TextField(
              controller: _title,
              decoration: const InputDecoration(labelText: 'Title', border: OutlineInputBorder()))),
          _gap(DropdownButtonFormField<String>(
            value: _class,
            decoration: const InputDecoration(labelText: 'Class', border: OutlineInputBorder()),
            items: [for (final c in _classes) DropdownMenuItem(value: c, child: Text(c))],
            onChanged: (v) => setState(() => _class = v ?? _class),
          )),
          _gap(TextField(
              controller: _subject,
              decoration: const InputDecoration(labelText: 'Subject', border: OutlineInputBorder()))),
          if (_isFile) ...[
            OutlinedButton.icon(
              onPressed: _busy ? null : _pick,
              icon: const Icon(Icons.attach_file),
              label: Text(_picked == null
                  ? (hasOld ? 'Nayi file chunein (optional)' : 'File chunein')
                  : 'Badlein'),
            ),
            if (_picked != null)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                    '${_picked!.name}  (${(_picked!.size / (1024 * 1024)).toStringAsFixed(1)} MB)',
                    style: const TextStyle(fontWeight: FontWeight.w600)),
              ),
            if (hasOld && _picked == null)
              const Padding(
                padding: EdgeInsets.only(top: 8),
                child: Text('Pehle se file jodi hui hai', style: TextStyle(color: kGrey)),
              ),
            const Padding(
              padding: EdgeInsets.only(top: 8, bottom: 14),
              child: Text(
                  'File seedha sanstha ke Google Drive me jaati hai. Upload ke baad aap use delete nahi kar sakte. Badi video ke liye Wi-Fi use karein aur upload poora hone tak app na band karein.',
                  style: TextStyle(color: kGrey, fontSize: 12)),
            ),
          ] else
            _gap(TextField(
              controller: _body,
              minLines: 8,
              maxLines: 20,
              decoration: InputDecoration(
                  labelText: '${kTypeLabels[_type]} yahan likhein',
                  alignLabelWithHint: true,
                  border: const OutlineInputBorder()),
            )),
          _gap(TextField(
              controller: _desc,
              minLines: 2,
              maxLines: 5,
              decoration: const InputDecoration(
                  labelText: 'Chhota vivaran (optional)', border: OutlineInputBorder()))),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Checkbox(
                value: _declared,
                activeColor: kBrand,
                onChanged: (v) => setState(() => _declared = v ?? false),
              ),
              const Expanded(
                child: Padding(
                  padding: EdgeInsets.only(top: 12),
                  child: Text(kDeclarationText, style: TextStyle(fontSize: 13)),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          if (_busy && _progress != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Column(
                children: [
                  LinearProgressIndicator(value: _progress, color: kBrand),
                  const SizedBox(height: 4),
                  Text('Upload ho raha hai... ${(_progress! * 100).toStringAsFixed(0)}%'),
                ],
              ),
            ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: kBrand, padding: const EdgeInsets.all(14)),
            onPressed: _busy ? null : _save,
            child: Text(_busy ? 'Ruko...' : 'Review ke liye bhejein'),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Admin: review + teachers
// ---------------------------------------------------------------------------

class AdminHome extends StatelessWidget {
  const AdminHome({super.key});

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 6,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Admin'),
          backgroundColor: kBrand,
          foregroundColor: Colors.white,
          actions: [
            IconButton(
                tooltip: 'Logout',
                icon: const Icon(Icons.logout),
                onPressed: () => db.auth.signOut()),
          ],
          bottom: const TabBar(
            isScrollable: true,
            indicatorColor: Colors.white,
            labelColor: Colors.white,
            unselectedLabelColor: Colors.white70,
            tabs: [
              Tab(text: 'Pending'),
              Tab(text: 'Approved'),
              Tab(text: 'Rejected'),
              Tab(text: 'Teachers'),
              Tab(text: 'Bank'),
              Tab(text: 'Agreement'),
            ],
          ),
        ),
        body: const TabBarView(
          children: [
            SubmissionList(status: 'pending'),
            SubmissionList(status: 'approved'),
            SubmissionList(status: 'rejected'),
            TeacherList(),
            BankAdminTab(),
            AgreementAdminTab(),
          ],
        ),
      ),
    );
  }
}

class SubmissionList extends StatefulWidget {
  final String status;
  const SubmissionList({super.key, required this.status});
  @override
  State<SubmissionList> createState() => _SubmissionListState();
}

class _SubmissionListState extends State<SubmissionList> {
  late Future<List<DbRow>> _future = _load();

  Future<List<DbRow>> _load() async => List<DbRow>.from(await db
      .from('submissions')
      .select('*, profiles(full_name, phone)')
      .eq('status', widget.status)
      .order('created_at', ascending: false));

  void _refresh() => setState(() => _future = _load());

  Future<void> _setStatus(DbRow r, String status, {String? note}) async {
    try {
      await db
          .from('submissions')
          .update({'status': status, 'admin_note': note}).eq('id', r['id']);
      _refresh();
    } catch (e) {
      if (mounted) snack(context, 'Nahi hua: ${errText(e)}');
    }
  }

  Future<void> _reject(DbRow r) async {
    final ctrl = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Reject karein'),
        content: TextField(
          controller: ctrl,
          minLines: 2,
          maxLines: 4,
          decoration: const InputDecoration(
              labelText: 'Teacher ke liye note (kya theek karna hai)',
              border: OutlineInputBorder()),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Reject')),
        ],
      ),
    );
    if (ok == true) await _setStatus(r, 'rejected', note: ctrl.text.trim());
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<DbRow>>(
      future: _future,
      builder: (context, snap) {
        if (snap.connectionState != ConnectionState.done) {
          return const Center(child: CircularProgressIndicator(color: kBrand));
        }
        if (snap.hasError) {
          return Center(child: Text('Data nahi aaya:\n${snap.error}', textAlign: TextAlign.center));
        }
        final rows = snap.data ?? [];
        if (rows.isEmpty) {
          return const Center(child: Text('Yahan kuch nahi hai', style: TextStyle(color: kGrey)));
        }
        return RefreshIndicator(
          onRefresh: () async => _refresh(),
          child: ListView.builder(
            padding: const EdgeInsets.symmetric(vertical: 8),
            itemCount: rows.length,
            itemBuilder: (context, i) {
              final r = rows[i];
              final teacher = (r['profiles'] is Map) ? r['profiles'] as Map : {};
              final desc = '${r['description'] ?? ''}';
              return appCard(
                child: Padding(
                  padding: const EdgeInsets.all(14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('${r['title']}',
                          style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
                      const SizedBox(height: 4),
                      Text('${r['class_name']} • ${r['subject']} • ${r['type']}',
                          style: const TextStyle(color: kGrey)),
                      Text('Teacher: ${teacher['full_name'] ?? '-'}  ${teacher['phone'] ?? ''}',
                          style: const TextStyle(color: kGrey)),
                      Text(
                          r['declaration_accepted'] == true
                              ? 'Copyright declaration: ha, ${r['declared_at'] ?? ''}'
                              : 'Copyright declaration: nahi',
                          style: const TextStyle(color: kGrey, fontSize: 12)),
                      if (desc.isNotEmpty)
                        Padding(padding: const EdgeInsets.only(top: 6), child: Text(desc)),
                      if ('${r['body'] ?? ''}'.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(top: 8),
                          child: SelectableText('${r['body']}',
                              style: const TextStyle(fontSize: 14, height: 1.4)),
                        ),
                      if (widget.status == 'rejected' && '${r['admin_note'] ?? ''}'.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(top: 6),
                          child: Text('Note: ${r['admin_note']}',
                              style: const TextStyle(color: Colors.red)),
                        ),
                      const SizedBox(height: 6),
                      Wrap(
                        spacing: 6,
                        children: [
                          if (submissionLink(r) != null)
                            OutlinedButton.icon(
                              onPressed: () => openLink(context, submissionLink(r)!),
                              icon: const Icon(Icons.open_in_new, size: 18),
                              label: const Text('Dekhein'),
                            ),
                          if (widget.status != 'approved')
                            FilledButton(
                              style: FilledButton.styleFrom(backgroundColor: Colors.green),
                              onPressed: () => _setStatus(r, 'approved'),
                              child: const Text('Approve'),
                            ),
                          if (widget.status != 'rejected')
                            FilledButton(
                              style: FilledButton.styleFrom(backgroundColor: Colors.red),
                              onPressed: () => _reject(r),
                              child: const Text('Reject'),
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
      },
    );
  }
}

class TeacherList extends StatefulWidget {
  const TeacherList({super.key});
  @override
  State<TeacherList> createState() => _TeacherListState();
}

class _TeacherListState extends State<TeacherList> {
  late Future<List<DbRow>> _future = _load();

  Future<List<DbRow>> _load() async => List<DbRow>.from(await db
      .from('profiles')
      .select()
      .neq('role', 'admin')
      .order('created_at', ascending: false));

  void _refresh() => setState(() => _future = _load());

  Future<void> _toggle(DbRow p, bool value) async {
    try {
      await db.from('profiles').update({'active': value}).eq('id', p['id']);
      _refresh();
    } catch (e) {
      if (mounted) snack(context, 'Nahi hua: ${errText(e)}');
    }
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<DbRow>>(
      future: _future,
      builder: (context, snap) {
        if (snap.connectionState != ConnectionState.done) {
          return const Center(child: CircularProgressIndicator(color: kBrand));
        }
        if (snap.hasError) {
          return Center(child: Text('Data nahi aaya:\n${snap.error}', textAlign: TextAlign.center));
        }
        final rows = snap.data ?? [];
        if (rows.isEmpty) {
          return const Center(child: Text('Abhi koi teacher nahi', style: TextStyle(color: kGrey)));
        }
        return RefreshIndicator(
          onRefresh: () async => _refresh(),
          child: ListView.builder(
            padding: const EdgeInsets.symmetric(vertical: 8),
            itemCount: rows.length,
            itemBuilder: (context, i) {
              final p = rows[i];
              final active = p['active'] == true;
              return appCard(
                child: SwitchListTile(
                  activeColor: kBrand,
                  title: Text('${p['full_name'] ?? ''}',
                      style: const TextStyle(fontWeight: FontWeight.w700)),
                  subtitle: Text('${p['phone'] ?? ''}\n${active ? 'Approved teacher' : 'Approval baaki'}'),
                  isThreeLine: true,
                  value: active,
                  onChanged: (v) => _toggle(p, v),
                ),
              );
            },
          ),
        );
      },
    );
  }
}

// ---------------------------------------------------------------------------
// Bank / payment details
// ---------------------------------------------------------------------------

String maskAcc(String n) =>
    n.length <= 4 ? n : '${'X' * (n.length - 4)}${n.substring(n.length - 4)}';

Widget kvRow(String k, String v) => Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(width: 118, child: Text(k, style: const TextStyle(color: kGrey))),
          Expanded(child: SelectableText(v, style: const TextStyle(fontWeight: FontWeight.w600))),
        ],
      ),
    );

List<Widget> bankRows(DbRow d, {required bool mask}) {
  final acc = '${d['account_number'] ?? ''}';
  return [
    kvRow('Khata dharak', '${d['account_holder'] ?? ''}'),
    kvRow('Account number', mask ? maskAcc(acc) : acc),
    kvRow('IFSC', '${d['ifsc'] ?? ''}'),
    if ('${d['bank_name'] ?? ''}'.isNotEmpty) kvRow('Bank', '${d['bank_name']}'),
    if ('${d['upi_id'] ?? ''}'.isNotEmpty) kvRow('UPI ID', '${d['upi_id']}'),
    kvRow('Phone', '${d['phone'] ?? ''}'),
  ];
}

class BankScreen extends StatefulWidget {
  const BankScreen({super.key});
  @override
  State<BankScreen> createState() => _BankScreenState();
}

class _BankScreenState extends State<BankScreen> {
  late Future<List<DbRow?>> _future = _load();

  Future<List<DbRow?>> _load() async {
    final uid = db.auth.currentUser!.id;
    final d = await db.from('bank_details').select().eq('teacher_id', uid).maybeSingle();
    final r = await db
        .from('bank_requests')
        .select()
        .eq('teacher_id', uid)
        .order('created_at', ascending: false)
        .limit(1)
        .maybeSingle();
    return [d, r];
  }

  void _refresh() => setState(() => _future = _load());

  Future<void> _openForm(DbRow? current) async {
    final ok = await Navigator.push<bool>(
      context,
      MaterialPageRoute(builder: (_) => BankRequestForm(current: current)),
    );
    if (ok == true) _refresh();
  }

  Future<void> _withdraw(DbRow req) async {
    try {
      await db.from('bank_requests').delete().eq('id', req['id']);
      _refresh();
    } catch (e) {
      if (mounted) snack(context, 'Nahi hua: ${errText(e)}');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Bank details'),
        backgroundColor: kBrand,
        foregroundColor: Colors.white,
      ),
      body: FutureBuilder<List<DbRow?>>(
        future: _future,
        builder: (context, snap) {
          if (snap.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator(color: kBrand));
          }
          if (snap.hasError) {
            return Center(child: Text('Data nahi aaya:\n${snap.error}', textAlign: TextAlign.center));
          }
          final details = snap.data![0];
          final req = snap.data![1];
          final pending = req != null && req['status'] == 'pending';
          final rejected = req != null && req['status'] == 'rejected';
          return ListView(
            padding: const EdgeInsets.symmetric(vertical: 12),
            children: [
              if (details != null)
                appCard(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Row(children: [
                          Icon(Icons.verified, color: Colors.green),
                          SizedBox(width: 8),
                          Text('Verified bank details',
                              style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
                        ]),
                        const SizedBox(height: 8),
                        ...bankRows(details, mask: true),
                      ],
                    ),
                  ),
                )
              else if (!pending)
                const Padding(
                  padding: EdgeInsets.all(20),
                  child: Text('Abhi bank details nahi jude hain. Bhugtaan ke liye details jodein. Admin verify karega.',
                      style: TextStyle(color: kGrey, fontSize: 15)),
                ),
              if (pending)
                appCard(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Row(children: [
                          Icon(Icons.hourglass_top, color: Colors.orange),
                          SizedBox(width: 8),
                          Expanded(
                            child: Text('Request verify hone ke liye ruki hai',
                                style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
                          ),
                        ]),
                        const SizedBox(height: 8),
                        ...bankRows(req, mask: true),
                        Align(
                          alignment: Alignment.centerRight,
                          child: TextButton(
                              onPressed: () => _withdraw(req),
                              child: const Text('Request wapas lein')),
                        ),
                      ],
                    ),
                  ),
                ),
              if (rejected && '${req['admin_note'] ?? ''}'.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 6),
                  child: Text('Pichli request reject hui. Admin ka note: ${req['admin_note']}',
                      style: const TextStyle(color: Colors.red)),
                ),
              if (!pending)
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                  child: FilledButton(
                    style: FilledButton.styleFrom(
                        backgroundColor: kBrand, padding: const EdgeInsets.all(14)),
                    onPressed: () => _openForm(details),
                    child: Text(details == null
                        ? 'Bank details jodein'
                        : 'Badlaav ki request bhejein'),
                  ),
                ),
              if (details != null && !pending)
                const Padding(
                  padding: EdgeInsets.fromLTRB(20, 10, 20, 0),
                  child: Text(
                      'Suraksha ke liye details seedha nahi badalte. Naye details ki request admin verify karega, tab badlenge.',
                      style: TextStyle(color: kGrey, fontSize: 12)),
                ),
            ],
          );
        },
      ),
    );
  }
}

class BankRequestForm extends StatefulWidget {
  final DbRow? current;
  const BankRequestForm({super.key, this.current});
  @override
  State<BankRequestForm> createState() => _BankRequestFormState();
}

class _BankRequestFormState extends State<BankRequestForm> {
  late final _holder = TextEditingController(text: '${widget.current?['account_holder'] ?? ''}');
  late final _acc = TextEditingController();
  late final _acc2 = TextEditingController();
  late final _ifsc = TextEditingController(text: '${widget.current?['ifsc'] ?? ''}');
  late final _bank = TextEditingController(text: '${widget.current?['bank_name'] ?? ''}');
  late final _upi = TextEditingController(text: '${widget.current?['upi_id'] ?? ''}');
  late final _phone = TextEditingController(text: '${widget.current?['phone'] ?? ''}');
  final _reason = TextEditingController();
  bool _busy = false;

  Widget _gap(Widget w) => Padding(padding: const EdgeInsets.only(bottom: 14), child: w);

  Widget _tf(TextEditingController c, String label,
          {TextInputType? type, String? helper, TextCapitalization cap = TextCapitalization.none}) =>
      _gap(TextField(
        controller: c,
        keyboardType: type,
        textCapitalization: cap,
        decoration: InputDecoration(
            labelText: label, helperText: helper, border: const OutlineInputBorder()),
      ));

  Future<void> _save() async {
    final holder = _holder.text.trim();
    final acc = _acc.text.trim();
    final ifsc = _ifsc.text.trim().toUpperCase();
    final phone = _phone.text.trim();
    if (holder.isEmpty) { snack(context, 'Khata dharak ka naam daalein'); return; }
    if (!RegExp(r'^\d{9,18}$').hasMatch(acc)) {
      { snack(context, 'Account number 9 se 18 ank ka hona chahiye'); return; }
    }
    if (acc != _acc2.text.trim()) { snack(context, 'Dono account number alag hain'); return; }
    if (!RegExp(r'^[A-Z]{4}0[A-Z0-9]{6}$').hasMatch(ifsc)) {
      { snack(context, 'IFSC code galat hai (jaise SBIN0001234)'); return; }
    }
    if (!RegExp(r'^\d{10}$').hasMatch(phone)) {
      { snack(context, 'Phone number 10 ank ka hona chahiye'); return; }
    }
    if (widget.current != null && _reason.text.trim().isEmpty) {
      { snack(context, 'Badlaav ka karan likhein'); return; }
    }
    setState(() => _busy = true);
    try {
      await db.from('bank_requests').insert({
        'account_holder': holder,
        'account_number': acc,
        'ifsc': ifsc,
        'bank_name': _bank.text.trim().isEmpty ? null : _bank.text.trim(),
        'upi_id': _upi.text.trim().isEmpty ? null : _upi.text.trim(),
        'phone': phone,
        'reason': _reason.text.trim().isEmpty ? null : _reason.text.trim(),
      });
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) {
        setState(() => _busy = false);
        snack(context, 'Nahi hua: ${errText(e)}');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isChange = widget.current != null;
    return Scaffold(
      appBar: AppBar(
        title: Text(isChange ? 'Bank details badlaav' : 'Bank details'),
        backgroundColor: kBrand,
        foregroundColor: Colors.white,
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _tf(_holder, 'Khata dharak ka naam (jaisa bank me hai)', cap: TextCapitalization.words),
          _tf(_acc, 'Account number', type: TextInputType.number),
          _tf(_acc2, 'Account number dobara likhein', type: TextInputType.number),
          _tf(_ifsc, 'IFSC code', cap: TextCapitalization.characters),
          _tf(_bank, 'Bank ka naam (optional)'),
          _tf(_upi, 'UPI ID (optional)'),
          _tf(_phone, 'Bank se juda phone number', type: TextInputType.phone),
          if (isChange) _tf(_reason, 'Badlaav ka karan'),
          const Text(
              'Ye details admin verify karega, uske baad hi bhugtaan inhi par hoga. Sahi aur apne naam ka khata hi daalein.',
              style: TextStyle(color: kGrey, fontSize: 12)),
          const SizedBox(height: 14),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: kBrand, padding: const EdgeInsets.all(14)),
            onPressed: _busy ? null : _save,
            child: Text(_busy ? 'Ruko...' : 'Verify ke liye bhejein'),
          ),
        ],
      ),
    );
  }
}

// Admin: bank requests verify karna + verified accounts dekhna
class BankAdminTab extends StatefulWidget {
  const BankAdminTab({super.key});
  @override
  State<BankAdminTab> createState() => _BankAdminTabState();
}

class _BankAdminTabState extends State<BankAdminTab> {
  late Future<List<dynamic>> _future = _load();

  Future<List<dynamic>> _load() async {
    final reqs = List<DbRow>.from(await db
        .from('bank_requests')
        .select('*, profiles(full_name, phone)')
        .eq('status', 'pending')
        .order('created_at', ascending: true));
    final dets = List<DbRow>.from(await db
        .from('bank_details')
        .select('*, profiles(full_name)')
        .order('verified_at', ascending: false));
    return [reqs, dets];
  }

  void _refresh() => setState(() => _future = _load());

  Future<void> _approve(DbRow r) async {
    try {
      await db.rpc('approve_bank_request', params: {'req_id': r['id']});
      _refresh();
    } catch (e) {
      if (mounted) snack(context, 'Nahi hua: ${errText(e)}');
    }
  }

  Future<void> _reject(DbRow r) async {
    final ctrl = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Reject karein'),
        content: TextField(
          controller: ctrl,
          minLines: 2,
          maxLines: 4,
          decoration: const InputDecoration(
              labelText: 'Teacher ke liye note (kya galat hai)', border: OutlineInputBorder()),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Reject')),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await db.from('bank_requests').update({
        'status': 'rejected',
        'admin_note': ctrl.text.trim(),
        'decided_at': DateTime.now().toUtc().toIso8601String(),
      }).eq('id', r['id']);
      _refresh();
    } catch (e) {
      if (mounted) snack(context, 'Nahi hua: ${errText(e)}');
    }
  }

  Widget _heading(String t) => Padding(
        padding: const EdgeInsets.fromLTRB(18, 14, 18, 4),
        child: Text(t, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16, color: kBrand)),
      );

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<dynamic>>(
      future: _future,
      builder: (context, snap) {
        if (snap.connectionState != ConnectionState.done) {
          return const Center(child: CircularProgressIndicator(color: kBrand));
        }
        if (snap.hasError) {
          return Center(child: Text('Data nahi aaya:\n${snap.error}', textAlign: TextAlign.center));
        }
        final reqs = snap.data![0] as List<DbRow>;
        final dets = snap.data![1] as List<DbRow>;
        final byTeacher = {for (final d in dets) '${d['teacher_id']}': d};
        return RefreshIndicator(
          onRefresh: () async => _refresh(),
          child: ListView(
            padding: const EdgeInsets.only(bottom: 30),
            children: [
              _heading('Verify baaki (${reqs.length})'),
              if (reqs.isEmpty)
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 18, vertical: 8),
                  child: Text('Koi request nahi', style: TextStyle(color: kGrey)),
                ),
              for (final r in reqs)
                appCard(
                  child: Padding(
                    padding: const EdgeInsets.all(14),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                            '${(r['profiles'] is Map ? r['profiles']['full_name'] : '') ?? ''}',
                            style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
                        Text(byTeacher.containsKey('${r['teacher_id']}')
                            ? 'Badlaav ki request'
                            : 'Pehli baar jodna',
                            style: const TextStyle(color: kGrey)),
                        if ('${r['reason'] ?? ''}'.isNotEmpty)
                          Text('Karan: ${r['reason']}', style: const TextStyle(color: kGrey)),
                        const Divider(),
                        const Text('Naye details', style: TextStyle(fontWeight: FontWeight.w700)),
                        ...bankRows(r, mask: false),
                        if (byTeacher.containsKey('${r['teacher_id']}')) ...[
                          const Divider(),
                          const Text('Abhi ke verified details',
                              style: TextStyle(fontWeight: FontWeight.w700)),
                          ...bankRows(byTeacher['${r['teacher_id']}']!, mask: false),
                        ],
                        const SizedBox(height: 8),
                        Wrap(
                          spacing: 8,
                          children: [
                            FilledButton(
                              style: FilledButton.styleFrom(backgroundColor: Colors.green),
                              onPressed: () => _approve(r),
                              child: const Text('Verified, Approve'),
                            ),
                            FilledButton(
                              style: FilledButton.styleFrom(backgroundColor: Colors.red),
                              onPressed: () => _reject(r),
                              child: const Text('Reject'),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              _heading('Verified accounts (${dets.length})'),
              for (final d in dets)
                appCard(
                  child: ExpansionTile(
                    shape: const Border(),
                    collapsedShape: const Border(),
                    title: Text('${(d['profiles'] is Map ? d['profiles']['full_name'] : '') ?? ''}',
                        style: const TextStyle(fontWeight: FontWeight.w700)),
                    subtitle: Text(maskAcc('${d['account_number']}'),
                        style: const TextStyle(color: kGrey)),
                    childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
                    expandedAlignment: Alignment.centerLeft,
                    children: bankRows(d, mask: false),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}

// ---------------------------------------------------------------------------
// Admin: agreement likhna / badalna
// ---------------------------------------------------------------------------

class AgreementAdminTab extends StatefulWidget {
  const AgreementAdminTab({super.key});
  @override
  State<AgreementAdminTab> createState() => _AgreementAdminTabState();
}

class _AgreementAdminTabState extends State<AgreementAdminTab> {
  late Future<DbRow?> _future = fetchAgreement();

  void _refresh() => setState(() => _future = fetchAgreement());

  Future<void> _edit(String initial) async {
    final ok = await Navigator.push<bool>(
      context,
      MaterialPageRoute(builder: (_) => AgreementEditor(initial: initial)),
    );
    if (ok == true) _refresh();
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<DbRow?>(
      future: _future,
      builder: (context, snap) {
        if (snap.connectionState != ConnectionState.done) {
          return const Center(child: CircularProgressIndicator(color: kBrand));
        }
        if (snap.hasError) {
          return Center(child: Text('Data nahi aaya:\n${snap.error}', textAlign: TextAlign.center));
        }
        final a = snap.data;
        final body = a == null ? '' : '${a['body']}';
        return RefreshIndicator(
          onRefresh: () async => _refresh(),
          child: ListView(
            padding: const EdgeInsets.only(bottom: 30),
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(18, 14, 18, 4),
                child: Text(
                  a == null
                      ? 'Abhi koi agreement nahi hai'
                      : 'Abhi ka agreement: Version ${a['version']}  (${'${a['created_at']}'.split('T').first})',
                  style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16, color: kBrand),
                ),
              ),
              if (body.contains('['))
                Container(
                  margin: const EdgeInsets.fromLTRB(14, 6, 14, 6),
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                      color: Colors.orange.withOpacity(0.12), borderRadius: BorderRadius.circular(12)),
                  child: const Text(
                      'Agreement me abhi [ ] wali jagah khali hain. Jab tak ye bhari nahi jati, naye teachers register nahi kar payenge. Neeche "Naya version likhein" dabakar bharein.',
                      style: TextStyle(color: Colors.deepOrange)),
                ),
              if (a != null)
                appCard(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: SelectableText(body, style: const TextStyle(fontSize: 14, height: 1.5)),
                  ),
                ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 6),
                child: FilledButton.icon(
                  style: FilledButton.styleFrom(backgroundColor: kBrand, padding: const EdgeInsets.all(14)),
                  onPressed: () => _edit(body),
                  icon: const Icon(Icons.edit),
                  label: Text(a == null ? 'Agreement likhein' : 'Naya version likhein'),
                ),
              ),
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 20),
                child: Text(
                    'Save karne par naya version banta hai. Purane version ka record rehta hai, aur sab teachers ko dobara sahmati deni hogi.',
                    style: TextStyle(color: kGrey, fontSize: 12)),
              ),
            ],
          ),
        );
      },
    );
  }
}

class AgreementEditor extends StatefulWidget {
  final String initial;
  const AgreementEditor({super.key, required this.initial});
  @override
  State<AgreementEditor> createState() => _AgreementEditorState();
}

class _AgreementEditorState extends State<AgreementEditor> {
  late final _c = TextEditingController(text: widget.initial);
  bool _busy = false;

  Future<void> _save() async {
    final text = _c.text.trim();
    if (text.isEmpty) {
      snack(context, 'Agreement khali nahi ho sakta');
      return;
    }
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Naya version save karein?'),
        content: const Text(
            'Sab teachers ko dobara sahmati deni hogi, tab hi wo upload kar payenge. Purana version record me rahega.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Nahi')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Haan, save')),
        ],
      ),
    );
    if (ok != true) return;
    setState(() => _busy = true);
    try {
      await db.from('agreements').insert({'body': text});
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) {
        setState(() => _busy = false);
        snack(context, 'Save nahi hua: ${errText(e)}');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Agreement likhein'),
        backgroundColor: kBrand,
        foregroundColor: Colors.white,
        actions: [
          TextButton(
            onPressed: _busy ? null : _save,
            child: Text(_busy ? 'Ruko...' : 'Save',
                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(12),
        child: TextField(
          controller: _c,
          expands: true,
          maxLines: null,
          minLines: null,
          textAlignVertical: TextAlignVertical.top,
          decoration: const InputDecoration(border: OutlineInputBorder()),
        ),
      ),
    );
  }
}
