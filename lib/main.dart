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
class WizardPage extends StatelessWidget {
  final DbRow? row;
  final DbRow? task;
  const WizardPage({super.key, this.row, this.task});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(row != null ? 'Badlein' : 'Kaam jama karein'),
        backgroundColor: kBrand,
        foregroundColor: Colors.white,
      ),
      body: SubmissionWizard(
        row: row,
        task: task,
        onSaved: () => Navigator.pop(context, true),
      ),
    );
  }
}

class SubmissionWizard extends StatefulWidget {
  final DbRow? row;
  final DbRow? task;
  final VoidCallback onSaved;
  const SubmissionWizard({super.key, this.row, this.task, required this.onSaved});
  @override
  State<SubmissionWizard> createState() => _SubmissionWizardState();
}

class _SubmissionWizardState extends State<SubmissionWizard> {
  final _title = TextEditingController();
  final _desc = TextEditingController();
  final _body = TextEditingController();
  final _chapter = TextEditingController();
  final _subjectOther = TextEditingController();
  String? _medium;
  String? _class;
  String? _subject;
  String _type = 'video';
  int _step = 0;
  PlatformFile? _picked;
  double? _progress;
  bool _declared = false;
  bool _busy = false;

  bool get _isFile => kFileTypes.contains(_type);

  String get _finalSubject =>
      _subject == 'Other' ? _subjectOther.text.trim() : (_subject ?? '');

  @override
  void initState() {
    super.initState();
    final r = widget.row;
    final t = widget.task;
    _medium = r?['medium'] as String?;
    _class = (r?['class_name'] ?? t?['class_name']) as String?;
    final subj = (r?['subject'] ?? t?['subject']) as String?;
    if (subj != null && subj.isNotEmpty) {
      if (kSubjects.contains(subj) && subj != 'Other') {
        _subject = subj;
      } else {
        _subject = 'Other';
        _subjectOther.text = subj;
      }
    }
    _chapter.text = '${r?['chapter'] ?? ''}';
    _title.text = '${r?['title'] ?? t?['title'] ?? ''}';
    _desc.text = '${r?['description'] ?? ''}';
    _body.text = '${r?['body'] ?? ''}';
    _type = '${r?['type'] ?? t?['content_type'] ?? 'video'}';
    if (!kTypeLabels.containsKey(_type)) _type = 'video';
    if (r != null) _step = 4;
  }

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

  Future<Map<String, dynamic>> _uploadFile(PlatformFile f) async {
    final path = f.path;
    if (path == null) throw 'File ka rasta nahi mila';
    final file = File(path);
    final len = await file.length();
    final mime = _mime(f.name);
    if (mime == 'application/octet-stream') throw 'Is prakar ki file allowed nahi hai';

    final res = await db.functions.invoke(kDriveFn,
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

  void _goto(int s, String msg) {
    setState(() => _step = s);
    snack(context, msg);
  }

  void _next() {
    if (_step == 0 && _medium == null) {
      snack(context, 'Pehle medium chunein');
      return;
    }
    if (_step == 1 && _class == null) {
      snack(context, 'Pehle class chunein');
      return;
    }
    if (_step == 2 && _finalSubject.isEmpty) {
      snack(context, 'Pehle subject chunein');
      return;
    }
    if (_step == 3 && _chapter.text.trim().isEmpty) {
      snack(context, 'Chapter ka naam ya number likhein');
      return;
    }
    setState(() => _step++);
  }

  Future<void> _save() async {
    if (_medium == null) return _goto(0, 'Medium chunein');
    if (_class == null) return _goto(1, 'Class chunein');
    if (_finalSubject.isEmpty) return _goto(2, 'Subject chunein');
    if (_chapter.text.trim().isEmpty) return _goto(3, 'Chapter likhein');
    final title = _title.text.trim();
    if (title.isEmpty) {
      snack(context, 'Title daalna zaroori hai');
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
        'medium': _medium,
        'class_name': _class,
        'subject': _finalSubject,
        'chapter': _chapter.text.trim(),
        'type': _type,
        'description': _desc.text.trim().isEmpty ? null : _desc.text.trim(),
        'status': 'pending',
        'admin_note': null,
        'declaration_accepted': true,
        'declared_at': DateTime.now().toUtc().toIso8601String(),
      };
      if (old == null && widget.task != null) vals['task_id'] = widget.task!['id'];
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
        try {
          final res = await db.functions.invoke(kDriveFn, body: {
            'action': 'text',
            'name': '$title.txt',
            'content':
                '$title\n${kTypeLabels[_type]} | $_medium | $_class | $_finalSubject | ${_chapter.text.trim()}\n\n$body\n',
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
      if (mounted) widget.onSaved();
    } catch (e) {
      if (mounted) {
        setState(() => _busy = false);
        snack(context, 'Save nahi hua: ${errText(e)}');
      }
    }
  }

  Widget _gap(Widget w) => Padding(padding: const EdgeInsets.only(bottom: 14), child: w);

  Widget _chips(List<String> items, String? sel, void Function(String) on) {
    return Wrap(
      spacing: 8,
      runSpacing: 4,
      children: [
        for (final s in items)
          ChoiceChip(
            label: Text(s),
            selected: sel == s,
            selectedColor: kBrand.withOpacity(0.2),
            onSelected: _busy ? null : (_) => on(s),
          ),
      ],
    );
  }

  StepState _st(int i, bool done) =>
      (done && _step > i) ? StepState.complete : StepState.indexed;

  @override
  Widget build(BuildContext context) {
    final old = widget.row;
    final hasOld = old != null &&
        old['type'] == _type &&
        ('${old['drive_file_id'] ?? ''}'.isNotEmpty || '${old['link'] ?? ''}'.isNotEmpty);
    return Stepper(
      currentStep: _step,
      onStepTapped: _busy ? null : (i) => setState(() => _step = i),
      controlsBuilder: (context, d) {
        return Padding(
          padding: const EdgeInsets.only(top: 12),
          child: Row(
            children: [
              if (_step < 4)
                FilledButton(
                  style: FilledButton.styleFrom(backgroundColor: kBrand),
                  onPressed: _next,
                  child: const Text('Aage'),
                ),
              if (_step > 0)
                TextButton(
                    onPressed: _busy ? null : () => setState(() => _step--),
                    child: const Text('Peeche')),
            ],
          ),
        );
      },
      steps: [
        Step(
          title: Text(_medium == null ? 'Bhasha / Medium' : 'Medium: $_medium'),
          isActive: _step >= 0,
          state: _st(0, _medium != null),
          content: Align(
            alignment: Alignment.centerLeft,
            child: _chips(kMediums, _medium, (s) {
              setState(() {
                _medium = s;
                _step = 1;
              });
            }),
          ),
        ),
        Step(
          title: Text(_class == null ? 'Class' : _class!),
          isActive: _step >= 1,
          state: _st(1, _class != null),
          content: Align(
            alignment: Alignment.centerLeft,
            child: _chips(kClasses, _class, (s) {
              setState(() {
                _class = s;
                _step = 2;
              });
            }),
          ),
        ),
        Step(
          title: Text(_finalSubject.isEmpty ? 'Subject' : 'Subject: $_finalSubject'),
          isActive: _step >= 2,
          state: _st(2, _finalSubject.isNotEmpty),
          content: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _chips(kSubjects, _subject, (s) {
                setState(() {
                  _subject = s;
                  if (s != 'Other') _step = 3;
                });
              }),
              if (_subject == 'Other')
                Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: TextField(
                    controller: _subjectOther,
                    decoration: const InputDecoration(
                        labelText: 'Subject ka naam', border: OutlineInputBorder()),
                  ),
                ),
            ],
          ),
        ),
        Step(
          title: Text(_chapter.text.trim().isEmpty ? 'Chapter' : 'Chapter: ${_chapter.text.trim()}'),
          isActive: _step >= 3,
          state: _st(3, _chapter.text.trim().isNotEmpty),
          content: TextField(
            controller: _chapter,
            onChanged: (_) => setState(() {}),
            decoration: const InputDecoration(
                labelText: 'Chapter ka naam ya number', border: OutlineInputBorder()),
          ),
        ),
        Step(
          title: const Text('Content ki details'),
          isActive: _step >= 4,
          state: StepState.indexed,
          content: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _gap(DropdownButtonFormField<String>(
                value: _type,
                decoration: const InputDecoration(
                    labelText: 'Kya upload karna hai', border: OutlineInputBorder()),
                items: [
                  for (final e in kTypeLabels.entries)
                    DropdownMenuItem(value: e.key, child: Text(e.value))
                ],
                onChanged: (_busy || widget.task != null)
                    ? null
                    : (v) => setState(() {
                          _type = v ?? _type;
                          _picked = null;
                        }),
              )),
              _gap(TextField(
                  controller: _title,
                  decoration:
                      const InputDecoration(labelText: 'Title', border: OutlineInputBorder()))),
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
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  style: FilledButton.styleFrom(
                      backgroundColor: kBrand, padding: const EdgeInsets.all(14)),
                  onPressed: _busy ? null : _save,
                  child: Text(_busy ? 'Ruko...' : 'Review ke liye bhejein'),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Tab 3: Account
// ---------------------------------------------------------------------------

class AccountTab extends StatefulWidget {
  final DbRow profile;
  const AccountTab({super.key, required this.profile});
  @override
  State<AccountTab> createState() => _AccountTabState();
}

class _AccountTabState extends State<AccountTab> {
  late Future<Map<String, dynamic>> _future = _load();
  bool _photoBusy = false;

  Future<Map<String, dynamic>> _load() async {
    final uid = db.auth.currentUser!.id;
    try {
      await db.rpc('release_expired_tasks');
    } catch (_) {}
    final p = await db.from('profiles').select().eq('id', uid).maybeSingle();
    final bank = await db.from('bank_details').select().eq('teacher_id', uid).maybeSingle();
    final tasks = List<DbRow>.from(await db
        .from('tasks')
        .select()
        .eq('accepted_by', uid)
        .order('accepted_at', ascending: false));
    DbRow? a;
    try {
      a = await fetchAgreement();
    } catch (_) {}
    return {'p': p, 'bank': bank, 'tasks': tasks, 'a': a};
  }

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

  Future<void> _changePhoto() async {
    final res = await FilePicker.platform.pickFiles(type: FileType.image);
    if (res == null || res.files.isEmpty) return;
    final f = res.files.first;
    if (f.path == null) return;
    if (f.size > 5 * 1024 * 1024) {
      if (mounted) snack(context, 'Photo 5 MB se chhoti honi chahiye');
      return;
    }
    setState(() => _photoBusy = true);
    try {
      final uid = db.auth.currentUser!.id;
      final ext = f.name.toLowerCase().split('.').last;
      final mime = ext == 'png' ? 'image/png' : (ext == 'webp' ? 'image/webp' : 'image/jpeg');
      final path = '$uid/avatar';
      await db.storage.from('avatars').upload(path, File(f.path!),
          fileOptions: FileOptions(upsert: true, contentType: mime));
      final url =
          '${db.storage.from('avatars').getPublicUrl(path)}?v=${DateTime.now().millisecondsSinceEpoch}';
      await db.rpc('set_avatar', params: {'url': url});
      _refresh();
    } catch (e) {
      if (mounted) snack(context, 'Photo nahi lagi: ${errText(e)}');
    }
    if (mounted) setState(() => _photoBusy = false);
  }

  Future<void> _submitTask(DbRow t) async {
    final ok = await Navigator.push<bool>(
      context,
      MaterialPageRoute(builder: (_) => WizardPage(task: t)),
    );
    if (ok == true) {
      kRefresh.value++;
      if (mounted) snack(context, 'Kaam review ke liye bhej diya gaya');
    }
  }

  Widget _heading(String t) => Padding(
        padding: const EdgeInsets.fromLTRB(18, 16, 18, 2),
        child: Text(t,
            style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16, color: kBrand)),
      );

  Widget _menu(IconData icon, String title, String? sub, VoidCallback onTap) => appCard(
        child: ListTile(
          leading: Icon(icon, color: kBrand),
          title: Text(title, style: const TextStyle(fontWeight: FontWeight.w600)),
          subtitle: sub == null ? null : Text(sub),
          trailing: const Icon(Icons.chevron_right),
          onTap: onTap,
        ),
      );

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Account'),
        backgroundColor: kBrand,
        foregroundColor: Colors.white,
      ),
      body: FutureBuilder<Map<String, dynamic>>(
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
          final d = snap.data!;
          final p = (d['p'] as DbRow?) ?? widget.profile;
          final bank = d['bank'] as DbRow?;
          final tasks = d['tasks'] as List<DbRow>;
          final a = d['a'] as DbRow?;
          final name = '${p['full_name'] ?? ''}';
          final working = tasks.where((t) => t['status'] == 'accepted' || t['status'] == 'submitted').toList();
          final done = tasks.where((t) => t['status'] == 'done').toList();
          num earned = 0, paid = 0;
          for (final t in done) {
            earned += numOf(t['amount']);
            if (t['paid'] == true) paid += numOf(t['amount']);
          }
          final due = earned - paid;
          return RefreshIndicator(
            onRefresh: () async => _refresh(),
            child: ListView(
              padding: const EdgeInsets.only(bottom: 30),
              children: [
                const SizedBox(height: 16),
                Center(
                  child: Stack(
                    children: [
                      Avatar(url: p['avatar_url'] as String?, name: name, radius: 46),
                      Positioned(
                        right: 0,
                        bottom: 0,
                        child: InkWell(
                          onTap: _photoBusy ? null : _changePhoto,
                          child: CircleAvatar(
                            radius: 16,
                            backgroundColor: kBrand,
                            child: _photoBusy
                                ? const SizedBox(
                                    width: 14,
                                    height: 14,
                                    child: CircularProgressIndicator(
                                        strokeWidth: 2, color: Colors.white))
                                : const Icon(Icons.camera_alt, size: 16, color: Colors.white),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 10),
                Center(
                  child: Text(name,
                      style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
                ),
                Center(
                  child: Text('${p['phone'] ?? ''}', style: const TextStyle(color: kGrey)),
                ),
                _heading('Mere kaam (${working.length})'),
                if (working.isEmpty)
                  const Padding(
                    padding: EdgeInsets.fromLTRB(18, 6, 18, 0),
                    child: Text('Abhi koi accepted kaam nahi. "Kaam" tab se kaam lein.',
                        style: TextStyle(color: kGrey)),
                  ),
                for (final t in working)
                  appCard(
                    child: Padding(
                      padding: const EdgeInsets.all(14),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Icon(typeIcon('${t['content_type']}'), color: kBrand),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text('${t['title']}',
                                    style: const TextStyle(
                                        fontWeight: FontWeight.w700, fontSize: 15)),
                              ),
                              Text(rupee(t['amount']),
                                  style: const TextStyle(
                                      fontWeight: FontWeight.w800, color: Colors.green)),
                            ],
                          ),
                          const SizedBox(height: 6),
                          if (t['status'] == 'accepted') ...[
                            Text(leftText(t['accepted_at']),
                                style: TextStyle(
                                    color: leftIsShort(t['accepted_at']) ? Colors.red : kGrey,
                                    fontWeight: FontWeight.w600)),
                            const SizedBox(height: 8),
                            SizedBox(
                              width: double.infinity,
                              child: FilledButton(
                                style: FilledButton.styleFrom(backgroundColor: kBrand),
                                onPressed: () => _submitTask(t),
                                child: const Text('Kaam jama karein'),
                              ),
                            ),
                          ] else
                            const Text('Admin review kar raha hai',
                                style: TextStyle(color: Colors.orange, fontWeight: FontWeight.w600)),
                        ],
                      ),
                    ),
                  ),
                _heading('Payout'),
                appCard(
                  child: Padding(
                    padding: const EdgeInsets.all(14),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceAround,
                          children: [
                            _stat('Kul kamai', rupee(earned), Colors.black87),
                            _stat('Mil gaya', rupee(paid), Colors.green),
                            _stat('Baaki', rupee(due), Colors.deepOrange),
                          ],
                        ),
                        if (done.isNotEmpty) const Divider(height: 22),
                        for (final t in done)
                          Padding(
                            padding: const EdgeInsets.symmetric(vertical: 3),
                            child: Row(
                              children: [
                                Expanded(
                                    child: Text('${t['title']}',
                                        maxLines: 1, overflow: TextOverflow.ellipsis)),
                                Text(rupee(t['amount']),
                                    style: const TextStyle(fontWeight: FontWeight.w600)),
                                const SizedBox(width: 8),
                                Text(t['paid'] == true ? 'Paid' : 'Baaki',
                                    style: TextStyle(
                                        fontSize: 12,
                                        color: t['paid'] == true ? Colors.green : Colors.deepOrange,
                                        fontWeight: FontWeight.w600)),
                              ],
                            ),
                          ),
                        if (done.isEmpty)
                          const Padding(
                            padding: EdgeInsets.only(top: 10),
                            child: Text('Kaam approve hone par yahan kamai dikhegi.',
                                style: TextStyle(color: kGrey, fontSize: 12)),
                          ),
                      ],
                    ),
                  ),
                ),
                _heading('Meri jaankari'),
                _menu(
                  Icons.account_balance,
                  'Bank account',
                  bank == null
                      ? 'Abhi nahi jude hain'
                      : '${bank['account_holder'] ?? ''}  ${maskAcc('${bank['account_number'] ?? ''}')}',
                  () async {
                    await Navigator.push(
                        context, MaterialPageRoute(builder: (_) => const BankScreen()));
                    _refresh();
                  },
                ),
                _menu(
                  Icons.description,
                  'Agreement',
                  a == null ? null : 'Version ${a['version']}',
                  () => Navigator.push(
                      context,
                      MaterialPageRoute(
                          builder: (_) => AgreementScreen(
                              text: '${a?['body'] ?? 'Agreement abhi uplabdh nahi hai.'}'))),
                ),
                _menu(
                  Icons.privacy_tip,
                  'Privacy policy',
                  null,
                  () => Navigator.push(
                      context,
                      MaterialPageRoute(
                          builder: (_) =>
                              const AgreementScreen(text: kPrivacyText, title: 'Privacy policy'))),
                ),
                _menu(
                  Icons.folder_open,
                  'Mere uploads',
                  'Apne bheje hue content dekhein aur badlein',
                  () => Navigator.push(
                      context, MaterialPageRoute(builder: (_) => const MyUploadsScreen())),
                ),
                const SizedBox(height: 10),
                Center(
                  child: TextButton.icon(
                    onPressed: () => db.auth.signOut(),
                    icon: const Icon(Icons.logout, color: Colors.red),
                    label: const Text('Logout', style: TextStyle(color: Colors.red)),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _stat(String label, String value, Color c) => Column(
        children: [
          Text(value, style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: c)),
          const SizedBox(height: 2),
          Text(label, style: const TextStyle(color: kGrey, fontSize: 12)),
        ],
      );
}

class MyUploadsScreen extends StatefulWidget {
  const MyUploadsScreen({super.key});
  @override
  State<MyUploadsScreen> createState() => _MyUploadsScreenState();
}

class _MyUploadsScreenState extends State<MyUploadsScreen> {
  late Future<List<DbRow>> _future = _load();

  Future<List<DbRow>> _load() async => List<DbRow>.from(await db
      .from('submissions')
      .select()
      .eq('teacher_id', db.auth.currentUser!.id)
      .order('created_at', ascending: false));

  void _refresh() => setState(() => _future = _load());

  Future<void> _edit(DbRow r) async {
    final saved = await Navigator.push<bool>(
      context,
      MaterialPageRoute(builder: (_) => WizardPage(row: r)),
    );
    if (saved == true) {
      _refresh();
      kRefresh.value++;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Mere uploads'),
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
            return Center(child: Text('Data nahi aaya:\n${snap.error}', textAlign: TextAlign.center));
          }
          final rows = snap.data ?? [];
          if (rows.isEmpty) {
            return const Center(
                child: Text('Abhi koi upload nahi.',
                    style: TextStyle(color: kGrey, fontSize: 16)));
          }
          return RefreshIndicator(
            onRefresh: () async => _refresh(),
            child: ListView.builder(
              padding: const EdgeInsets.only(top: 8, bottom: 30),
              itemCount: rows.length,
              itemBuilder: (context, i) {
                final r = rows[i];
                final status = '${r['status']}';
                final note = '${r['admin_note'] ?? ''}';
                final type = '${r['type']}';
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
                        Text(metaLine(r), style: const TextStyle(color: kGrey)),
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
                              TextButton(onPressed: () => _edit(r), child: const Text('Badlein'))
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

// ---------------------------------------------------------------------------
// Tab 4: Kaam ki list (admin ne diya hua)
// ---------------------------------------------------------------------------

class TasksTab extends StatefulWidget {
  const TasksTab({super.key});
  @override
  State<TasksTab> createState() => _TasksTabState();
}

class _TasksTabState extends State<TasksTab> {
  late Future<List<DbRow>> _future = _load();

  Future<List<DbRow>> _load() async {
    try {
      await db.rpc('release_expired_tasks');
    } catch (_) {}
    return List<DbRow>.from(await db
        .from('tasks')
        .select()
        .eq('status', 'open')
        .order('created_at', ascending: false));
  }

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
        title: const Text('Kaam ki list'),
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
                child: Text('Abhi koi kaam nahi hai.\nAdmin naya kaam jodega to yahan dikhega.',
                    textAlign: TextAlign.center, style: TextStyle(color: kGrey, fontSize: 16)));
          }
          return RefreshIndicator(
            onRefresh: () async => _refresh(),
            child: ListView.builder(
              padding: const EdgeInsets.only(top: 8, bottom: 20),
              itemCount: rows.length,
              itemBuilder: (context, i) {
                final t = rows[i];
                final type = '${t['content_type']}';
                return appCard(
                  child: ListTile(
                    leading: Icon(typeIcon(type), color: kBrand),
                    title: Text('${t['title']}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontWeight: FontWeight.w600)),
                    subtitle: Text(kTypeLabels[type] ?? type),
                    trailing: Text(rupee(t['amount']),
                        style: const TextStyle(
                            fontWeight: FontWeight.w800, fontSize: 16, color: Colors.green)),
                    onTap: () => Navigator.push(
                        context, MaterialPageRoute(builder: (_) => TaskDetailScreen(task: t))),
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

class TaskDetailScreen extends StatefulWidget {
  final DbRow task;
  const TaskDetailScreen({super.key, required this.task});
  @override
  State<TaskDetailScreen> createState() => _TaskDetailScreenState();
}

class _TaskDetailScreenState extends State<TaskDetailScreen> {
  bool _busy = false;

  Future<void> _accept() async {
    setState(() => _busy = true);
    try {
      await db.rpc('accept_task', params: {'t_id': widget.task['id']});
      kRefresh.value++;
      if (mounted) {
        snack(context, 'Kaam accept ho gaya. Account tab me "Mere kaam" dekhein.');
        Navigator.pop(context);
      }
    } catch (e) {
      kRefresh.value++;
      if (mounted) {
        setState(() => _busy = false);
        snack(context, errText(e));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = widget.task;
    final type = '${t['content_type']}';
    final desc = '${t['description'] ?? ''}';
    final extra = <String>[
      '${t['class_name'] ?? ''}',
      '${t['subject'] ?? ''}',
    ].where((s) => s.isNotEmpty).join(' \u2022 ');
    return Scaffold(
      appBar: AppBar(
        title: const Text('Kaam ki details'),
        backgroundColor: kBrand,
        foregroundColor: Colors.white,
      ),
      body: ListView(
        padding: const EdgeInsets.all(18),
        children: [
          Row(
            children: [
              Icon(typeIcon(type), color: kBrand, size: 30),
              const SizedBox(width: 10),
              Expanded(
                child: Text('${t['title']}',
                    style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                    color: Colors.green.withOpacity(0.12),
                    borderRadius: BorderRadius.circular(20)),
                child: Text(rupee(t['amount']),
                    style: const TextStyle(
                        color: Colors.green, fontWeight: FontWeight.w800, fontSize: 16)),
              ),
              const SizedBox(width: 10),
              Text(kTypeLabels[type] ?? type, style: const TextStyle(color: kGrey)),
            ],
          ),
          if (extra.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 10),
              child: Text(extra, style: const TextStyle(color: kGrey)),
            ),
          const SizedBox(height: 16),
          Text(desc.isEmpty ? 'Koi extra vivaran nahi diya gaya.' : desc,
              style: const TextStyle(fontSize: 15, height: 1.5)),
          const SizedBox(height: 18),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
                color: Colors.orange.withOpacity(0.12), borderRadius: BorderRadius.circular(12)),
            child: const Text(
                'Accept karne ke baad 3 din ke andar kaam karke review ke liye bhejna hoga. Nahi bheja to kaam wapas list me chala jayega aur doosre teacher le sakte hain.',
                style: TextStyle(color: Colors.deepOrange)),
          ),
          const SizedBox(height: 18),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: kBrand, padding: const EdgeInsets.all(14)),
            onPressed: _busy ? null : _accept,
            child: Text(_busy ? 'Ruko...' : 'Ye kaam accept karein'),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Admin
// ---------------------------------------------------------------------------

class AdminHome extends StatelessWidget {
  const AdminHome({super.key});

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 8,
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
              Tab(text: 'Kaam'),
              Tab(text: 'Reports'),
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
            AdminTasksTab(),
            AdminReportsTab(),
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
                      Text(metaLine(r), style: const TextStyle(color: kGrey)),
                      Text('Teacher: ${teacher['full_name'] ?? '-'}  ${teacher['phone'] ?? ''}',
                          style: const TextStyle(color: kGrey)),
                      if (r['task_id'] != null)
                        const Text('Ye kaam (task) ka jawab hai',
                            style: TextStyle(color: Colors.blue, fontSize: 12)),
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

// Admin: kaam (task) banana aur dekhna
class AdminTasksTab extends StatefulWidget {
  const AdminTasksTab({super.key});
  @override
  State<AdminTasksTab> createState() => _AdminTasksTabState();
}

class _AdminTasksTabState extends State<AdminTasksTab> {
  late Future<List<DbRow>> _future = _load();

  Future<List<DbRow>> _load() async {
    try {
      await db.rpc('release_expired_tasks');
    } catch (_) {}
    return List<DbRow>.from(await db
        .from('tasks')
        .select('*, profiles(full_name, phone)')
        .order('created_at', ascending: false));
  }

  void _refresh() => setState(() => _future = _load());

  Future<void> _add() async {
    final ok = await Navigator.push<bool>(
        context, MaterialPageRoute(builder: (_) => const TaskForm()));
    if (ok == true) _refresh();
  }

  Future<void> _update(DbRow t, Map<String, dynamic> vals) async {
    try {
      await db.from('tasks').update(vals).eq('id', t['id']);
      _refresh();
    } catch (e) {
      if (mounted) snack(context, 'Nahi hua: ${errText(e)}');
    }
  }

  Future<void> _delete(DbRow t) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Kaam hataein?'),
        content: Text('"${t['title']}" hata diya jayega.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Nahi')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Haan')),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await db.from('tasks').delete().eq('id', t['id']);
      _refresh();
    } catch (e) {
      if (mounted) snack(context, 'Nahi hua: ${errText(e)}');
    }
  }

  @
