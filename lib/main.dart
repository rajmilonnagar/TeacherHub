import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

// ====== APNE SUPABASE PROJECT KA URL AUR KEY YAHAN DAALEIN ======
const supabaseUrl = 'https://otkvaumqxqlxtyswveyr.supabase.co';
const supabaseKey = 'YAHAN_APNI_NAYI_PUBLISHABLE_KEY';
// Edge Function ka slug (Supabase me jo URL ke aakhir me hai)
const String kDriveFn = 'swift-function';
// =================================================================

const Color kBrand = Color(0xFF00796B);
const Color kBg = Color(0xFFF8F9FA);
const Color kGrey = Color(0xFF6B7280);

typedef DbRow = Map<String, dynamic>;
SupabaseClient get db => Supabase.instance.client;

/// Koi bhi tab badalne/upload hone par ye badhta hai, aur tabs apna data dobara laate hain
final ValueNotifier<int> kRefresh = ValueNotifier<int>(0);

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

const String kPrivacyText = '''Privacy Policy (Teacher Hub)

1. Hum kya jaankari lete hain
Aapka naam, phone number, email, profile photo, bank details (payment ke liye), aur aapke dwara upload kiya gaya content (video, photo, PDF, text).

2. Jaankari ka istemal
- Aapka account chalane aur verify karne ke liye.
- Aapke content ko review karne aur shiksha ke liye istemal karne ke liye.
- Kaam ka bhugtaan (payout) karne ke liye.

3. Bank details
Bank details sirf bhugtaan ke liye hain. Inhe admin verify karta hai. Account number app me chhupa kar (masked) dikhaya jata hai. Inhe kisi teesre ko bechna ya share nahi kiya jata.

4. Upload kiya gaya content
Aapki files sanstha ke Google Drive me rakhi jati hain. Aapka naam, title, class, subject aur text/vivaran baaki teachers ko Home feed me dikh sakta hai. Files ke Drive link sirf admin ke paas rehte hain.

5. Report aur comment
Aap kisi bhi upload ko report kar sakte hain. Report admin dekhta hai.

6. Suraksha
Hum aapki jaankari surakshit rakhne ki koshish karte hain, par internet par koi bhi system 100% surakshit nahi hota.

7. Jaankari hatwana
Apna account ya jaankari hatwane ke liye sanstha ke admin se sampark karein.

8. Badlav
Ye policy badal sakti hai. Badlav hone par app me naya version dikhaya jayega.''';

void main() async {
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
        navigationBarTheme: NavigationBarThemeData(
          indicatorColor: kBrand.withOpacity(0.15),
          backgroundColor: Colors.white,
        ),
      ),
      home: configured ? const AuthGate() : const SetupMissing(),
    );
  }
}

// ---------------------------------------------------------------------------
// Chhote helpers
// ---------------------------------------------------------------------------

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
  if (e is PostgrestException) return e.message;
  if (e is FunctionException) {
    final d = e.details;
    return d is Map ? '${d['error'] ?? d}' : '$d';
  }
  return '$e';
}

String timeAgo(dynamic iso) {
  final t = DateTime.tryParse('$iso')?.toLocal();
  if (t == null) return '';
  final d = DateTime.now().difference(t);
  if (d.inMinutes < 1) return 'abhi';
  if (d.inMinutes < 60) return '${d.inMinutes} min pehle';
  if (d.inHours < 24) return '${d.inHours} ghante pehle';
  if (d.inDays < 7) return '${d.inDays} din pehle';
  return '${t.day}/${t.month}/${t.year}';
}

bool isToday(dynamic iso) {
  final t = DateTime.tryParse('$iso')?.toLocal();
  if (t == null) return false;
  final n = DateTime.now();
  return t.year == n.year && t.month == n.month && t.day == n.day;
}

String rupee(dynamic v) {
  final n = (v is num) ? v : (num.tryParse('$v') ?? 0);
  return '\u20B9${n % 1 == 0 ? n.toInt() : n.toStringAsFixed(2)}';
}

num numOf(dynamic v) => (v is num) ? v : (num.tryParse('$v') ?? 0);

/// Kaam accept karne ke 3 din me se kitna samay bacha
String leftText(dynamic acceptedAt) {
  final t = DateTime.tryParse('$acceptedAt')?.toLocal();
  if (t == null) return '';
  final d = t.add(const Duration(days: 3)).difference(DateTime.now());
  if (d.isNegative) return 'Samay khatam';
  return '${d.inDays} din ${d.inHours % 24} ghante baaki';
}

bool leftIsShort(dynamic acceptedAt) {
  final t = DateTime.tryParse('$acceptedAt')?.toLocal();
  if (t == null) return false;
  return t.add(const Duration(days: 3)).difference(DateTime.now()).inHours < 24;
}

class Avatar extends StatelessWidget {
  final String? url;
  final String name;
  final double radius;
  const Avatar({super.key, this.url, required this.name, this.radius = 20});

  @override
  Widget build(BuildContext context) {
    final has = url != null && url!.isNotEmpty;
    final initial = name.trim().isEmpty ? '?' : name.trim()[0].toUpperCase();
    return CircleAvatar(
      radius: radius,
      backgroundColor: kBrand.withOpacity(0.15),
      backgroundImage: has ? NetworkImage(url!) : null,
      child: has
          ? null
          : Text(initial,
              style: TextStyle(
                  color: kBrand, fontWeight: FontWeight.bold, fontSize: radius * 0.9)),
    );
  }
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
  final String title;
  const AgreementScreen({super.key, required this.text, this.title = 'Agreement'});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(title),
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
        if (a != null && '${p['agreement_version'] ?? ''}' != '${a['version']}') {
          return AcceptAgreementScreen(agreement: a, onDone: _reload);
        }
        return TeacherShell(profile: p);
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
// Common: status, type, links
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

Color taskColor(String s) {
  switch (s) {
    case 'accepted':
      return Colors.blue;
    case 'submitted':
      return Colors.orange;
    case 'done':
      return Colors.green;
    default:
      return kBrand;
  }
}

String taskLabel(String s) {
  switch (s) {
    case 'accepted':
      return 'Accepted';
    case 'submitted':
      return 'Review me';
    case 'done':
      return 'Poora';
    default:
      return 'Khula';
  }
}

class TaskChip extends StatelessWidget {
  final String status;
  const TaskChip(this.status, {super.key});
  @override
  Widget build(BuildContext context) {
    final c = taskColor(status);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
          color: c.withOpacity(0.12), borderRadius: BorderRadius.circular(20)),
      child: Text(taskLabel(status),
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

String? submissionLink(DbRow r) {
  final d = r['drive_link'];
  if (d is String && d.isNotEmpty) return d;
  final l = r['link'];
  if (l is String && l.isNotEmpty) return l;
  return null;
}

String metaLine(DbRow r) {
  final type = '${r['type'] ?? ''}';
  final parts = <String>[
    kTypeLabels[type] ?? type,
    '${r['medium'] ?? ''}',
    '${r['class_name'] ?? ''}',
    '${r['subject'] ?? ''}',
    '${r['chapter'] ?? ''}',
  ].where((s) => s.trim().isNotEmpty).toList();
  return parts.join(' \u2022 ');
}

// ---------------------------------------------------------------------------
// Teacher: 4 tab wala main screen
// ---------------------------------------------------------------------------

class TeacherShell extends StatefulWidget {
  final DbRow profile;
  const TeacherShell({super.key, required this.profile});
  @override
  State<TeacherShell> createState() => _TeacherShellState();
}

class _TeacherShellState extends State<TeacherShell> {
  int _i = 0;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(
        index: _i,
        children: [
          HomeFeedTab(profile: widget.profile),
          UploadTab(onDone: () => setState(() => _i = 0)),
          AccountTab(profile: widget.profile),
          const TasksTab(),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _i,
        onDestinationSelected: (i) {
          setState(() => _i = i);
          if (i != 1) kRefresh.value++;
        },
        destinations: const [
          NavigationDestination(
              icon: Icon(Icons.home_outlined), selectedIcon: Icon(Icons.home), label: 'Home'),
          NavigationDestination(
              icon: Icon(Icons.add_circle_outline),
              selectedIcon: Icon(Icons.add_circle),
              label: 'Upload'),
          NavigationDestination(
              icon: Icon(Icons.person_outline), selectedIcon: Icon(Icons.person), label: 'Account'),
          NavigationDestination(
              icon: Icon(Icons.assignment_outlined),
              selectedIcon: Icon(Icons.assignment),
              label: 'Kaam'),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Tab 1: Home feed (sab teachers ke recent uploads, like, report)
// ---------------------------------------------------------------------------

class HomeFeedTab extends StatefulWidget {
  final DbRow profile;
  const HomeFeedTab({super.key, required this.profile});
  @override
  State<HomeFeedTab> createState() => _HomeFeedTabState();
}

class _HomeFeedTabState extends State<HomeFeedTab> {
  late Future<List<DbRow>> _future = _load();

  Future<List<DbRow>> _load() async => List<DbRow>.from(await db
      .from('feed_posts')
      .select()
      .order('updated_at', ascending: false)
      .limit(100));

  void _refresh() {
    if (mounted) setState(() => _future = _load());
  }

  @override
  void initState() {
    super.initState();
    kRefresh.addListener(_refresh);
  }

  @override
  void dispose() {
    kRefresh.removeListener(_refresh);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Teacher Hub'),
        backgroundColor: kBrand,
        foregroundColor: Colors.white,
      ),
      body: FutureBuilder<List<DbRow>>(
        future: _future,
        builder: (context, snap) {
          if (snap.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator(color: kBrand));
          }
          if (snap.hasError) {
            return Center(
                child: Padding(
              padding: const EdgeInsets.all(20),
              child: Text('Data nahi aaya:\n${snap.error}', textAlign: TextAlign.center),
            ));
          }
          final rows = snap.data ?? [];
          if (rows.isEmpty) {
            return const Center(
                child: Text('Abhi koi upload nahi.\nPehla upload aap karein!',
                    textAlign: TextAlign.center, style: TextStyle(color: kGrey, fontSize: 16)));
          }
          final today = rows.where((r) => isToday(r['created_at'])).length;
          return RefreshIndicator(
            onRefresh: () async => _refresh(),
            child: ListView.builder(
              padding: const EdgeInsets.only(top: 6, bottom: 20),
              itemCount: rows.length + 1,
              itemBuilder: (context, i) {
                if (i == 0) {
                  return Padding(
                    padding: const EdgeInsets.fromLTRB(18, 8, 18, 2),
                    child: Text(
                        today == 0 ? 'Aaj abhi koi naya upload nahi' : 'Aaj $today naye upload',
                        style: const TextStyle(
                            fontWeight: FontWeight.w700, fontSize: 15, color: kBrand)),
                  );
                }
                return PostCard(key: ValueKey(rows[i - 1]['id']), post: rows[i - 1]);
              },
            ),
          );
        },
      ),
    );
  }
}

class PostCard extends StatefulWidget {
  final DbRow post;
  const PostCard({super.key, required this.post});
  @override
  State<PostCard> createState() => _PostCardState();
}

class _PostCardState extends State<PostCard> {
  late bool _liked = widget.post['liked'] == true;
  late int _likes = numOf(widget.post['like_count']).toInt();

  String get _myId => db.auth.currentUser!.id;
  bool get _mine => '${widget.post['teacher_id']}' == _myId;

  Future<void> _toggleLike() async {
    final was = _liked;
    setState(() {
      _liked = !was;
      _likes += was ? -1 : 1;
    });
    try {
      if (was) {
        await db
            .from('post_likes')
            .delete()
            .eq('submission_id', widget.post['id'])
            .eq('user_id', _myId);
      } else {
        await db
            .from('post_likes')
            .insert({'submission_id': widget.post['id'], 'user_id': _myId});
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _liked = was;
          _likes += was ? 1 : -1;
        });
        snack(context, 'Nahi hua: ${errText(e)}');
      }
    }
  }

  Future<void> _report() async {
    final ctrl = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Report karein'),
        content: TextField(
          controller: ctrl,
          minLines: 3,
          maxLines: 5,
          decoration: const InputDecoration(
              labelText: 'Kya galat hai? Comment likhein', border: OutlineInputBorder()),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Bhejein')),
        ],
      ),
    );
    if (ok != true) return;
    final text = ctrl.text.trim();
    if (text.isEmpty) {
      if (mounted) snack(context, 'Comment khali nahi ho sakta');
      return;
    }
    try {
      await db.from('post_reports').insert({
        'submission_id': widget.post['id'],
        'user_id': _myId,
        'comment': text,
      });
      if (mounted) snack(context, 'Report admin ko bhej diya gaya');
    } catch (e) {
      if (mounted) snack(context, 'Nahi hua: ${errText(e)}');
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = widget.post;
    final name = '${p['teacher_name'] ?? ''}';
    final type = '${p['type'] ?? ''}';
    final desc = '${p['description'] ?? ''}';
    final body = '${p['body'] ?? ''}';
    final preview = desc.isNotEmpty ? desc : body;
    final created = DateTime.tryParse('${p['created_at']}');
    final updated = DateTime.tryParse('${p['updated_at']}');
    final edited = created != null &&
        updated != null &&
        updated.difference(created).inMinutes >= 1;
    final status = '${p['status']}';
    return appCard(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Avatar(url: p['avatar_url'] as String?, name: name, radius: 20),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(name.isEmpty ? 'Teacher' : name,
                          style: const TextStyle(fontWeight: FontWeight.w700)),
                      Text(
                          '${timeAgo(edited ? p['updated_at'] : p['created_at'])}${edited ? ' \u2022 badla gaya' : ''}',
                          style: const TextStyle(color: kGrey, fontSize: 12)),
                    ],
                  ),
                ),
                if (status == 'pending') const StatusChip('pending'),
              ],
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Icon(typeIcon(type), color: kBrand, size: 20),
                const SizedBox(width: 8),
                Expanded(
                  child: Text('${p['title']}',
                      style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(metaLine(p), style: const TextStyle(color: kGrey, fontSize: 13)),
            if (preview.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(preview, maxLines: 3, overflow: TextOverflow.ellipsis),
              ),
            const Divider(height: 22),
            Row(
              children: [
                TextButton.icon(
                  onPressed: _toggleLike,
                  icon: Icon(_liked ? Icons.favorite : Icons.favorite_border,
                      color: _liked ? Colors.red : kGrey),
                  label: Text('Like${_likes > 0 ? ' ($_likes)' : ''}',
                      style: TextStyle(color: _liked ? Colors.red : kGrey)),
                ),
                const Spacer(),
                if (!_mine)
                  TextButton.icon(
                    onPressed: _report,
                    icon: const Icon(Icons.flag_outlined, color: kGrey),
                    label: const Text('Report', style: TextStyle(color: kGrey)),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Tab 2: Upload (step by step)
// ---------------------------------------------------------------------------

const List<String> kMediums = ['Assamese', 'Bengali', 'Hindi', 'English', 'Bodo'];
const List<String> kSubjects = [
  'Assamese',
  'English',
  'Hindi',
  'Mathematics',
  'Science',
  'Social Science',
  'Physics',
  'Chemistry',
  'Biology',
  'History',
  'Geography',
  'Political Science',
  'Economics',
  'Accountancy',
  'Business Studies',
  'Computer',
  'Sanskrit',
  'Other',
];
final List<String> kClasses = [for (var i = 1; i <= 12; i++) 'Class $i'];

class UploadTab extends StatefulWidget {
  final VoidCallback onDone;
  const UploadTab({super.key, required this.onDone});
  @override
  State<UploadTab> createState() => _UploadTabState();
}

class _UploadTabState extends State<UploadTab> {
  int _n = 0;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Naya upload'),
        backgroundColor: kBrand,
        foregroundColor: Colors.white,
      ),
      body: SubmissionWizard(
        key: ValueKey(_n),
        onSaved: () {
          setState(() => _n++);
          kRefresh.value++;
          snack(context, 'Review ke liye bhej diya gaya');
          widget.onDone();
        },
      ),
    );
  }
}

/// Edit karne ya kaam jama karne ke liye alag page
class WizardPage extends Stateless
