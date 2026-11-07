import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:livekit_client/livekit_client.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

const _url = 'https://rnqskmxjkodnwnkfklym.supabase.co';
const _key = 'sb_publishable_bq2SOdQ89LtDtjgj-94T9g_PtRs31Zy';
SupabaseClient get sb => Supabase.instance.client;

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Supabase.initialize(url: _url, anonKey: _key);
  runApp(const App());
}

Color colorFor(String n) {
  var h = 0;
  for (final c in n.codeUnits) { h = (h * 31 + c) % 360; }
  return HSLColor.fromAHSL(1, h.toDouble(), .75, .55).toColor();
}

void toast(BuildContext c, String m) =>
    ScaffoldMessenger.of(c).showSnackBar(SnackBar(content: Text(m)));

Future<void> ensureProfile(String? name) async {
  final u = sb.auth.currentUser!;
  final p = await sb.from('profiles').select('id').eq('id', u.id).maybeSingle();
  if (p == null) {
    final n = (name == null || name.isEmpty) ? u.email!.split('@').first : name;
    await sb.from('profiles').insert({'id': u.id, 'username': n});
  }
}

class App extends StatelessWidget {
  const App({super.key});
  @override
  Widget build(BuildContext c) => MaterialApp(
        title: 'VoiceNest',
        debugShowCheckedModeBanner: false,
        theme: ThemeData(
          brightness: Brightness.dark,
          useMaterial3: true,
          colorSchemeSeed: const Color(0xFFFFD23F),
          scaffoldBackgroundColor: const Color(0xFF1B1340),
        ),
        home: sb.auth.currentSession == null ? const AuthPage() : const HomePage(),
      );
}

class AuthPage extends StatefulWidget {
  const AuthPage({super.key});
  @override
  State<AuthPage> createState() => _AuthState();
}

class _AuthState extends State<AuthPage> {
  final em = TextEditingController(), pw = TextEditingController(), un = TextEditingController();
  bool signup = false, busy = false;

  Future<void> go() async {
    setState(() => busy = true);
    try {
      if (signup) {
        final r = await sb.auth.signUp(email: em.text.trim(), password: pw.text);
        if (r.session == null) { if (mounted) toast(context, 'Check your email to confirm, then sign in'); return; }
      } else {
        await sb.auth.signInWithPassword(email: em.text.trim(), password: pw.text);
      }
      await ensureProfile(un.text.trim());
      if (mounted) Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => const HomePage()));
    } catch (e) {
      if (mounted) toast(context, e.toString());
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext c) => Scaffold(
        body: SafeArea(
          child: ListView(padding: const EdgeInsets.all(24), children: [
            const SizedBox(height: 40),
            const Text('VoiceNest', style: TextStyle(fontSize: 38, fontWeight: FontWeight.w900, color: Color(0xFFFFD23F))),
            const Text('Voice rooms to hang out with friends.'),
            const SizedBox(height: 24),
            if (signup) TextField(controller: un, decoration: const InputDecoration(labelText: 'Username')),
            TextField(controller: em, keyboardType: TextInputType.emailAddress, decoration: const InputDecoration(labelText: 'Email')),
            TextField(controller: pw, obscureText: true, decoration: const InputDecoration(labelText: 'Password (6+ characters)')),
            const SizedBox(height: 20),
            FilledButton(onPressed: busy ? null : go, child: Text(signup ? 'Create account' : 'Sign in')),
            TextButton(
              onPressed: () => setState(() => signup = !signup),
              child: Text(signup ? 'Have an account? Sign in' : 'New here? Create account'),
            ),
          ]),
        ),
      );
}

class HomePage extends StatefulWidget {
  const HomePage({super.key});
  @override
  State<HomePage> createState() => _HomeState();
}

class _HomeState extends State<HomePage> {
  List<Map<String, dynamic>> rooms = [];

  @override
  void initState() { super.initState(); ensureProfile(null).then((_) => load()); }

  Future<void> load() async {
    final d = await sb.from('rooms').select().order('created_at', ascending: false).limit(30);
    if (mounted) setState(() => rooms = List<Map<String, dynamic>>.from(d));
  }

  Future<void> create() async {
    final name = TextEditingController();
    var priv = false;
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => StatefulBuilder(
        builder: (_, set) => AlertDialog(
          title: const Text('Create a room'),
          content: Column(mainAxisSize: MainAxisSize.min, children: [
            TextField(controller: name, decoration: const InputDecoration(labelText: 'Room name')),
            SwitchListTile(title: const Text('Private'), value: priv, onChanged: (v) => set(() => priv = v)),
          ]),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
            FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Create')),
          ],
        ),
      ),
    );
    if (ok == true && name.text.trim().isNotEmpty) {
      try {
        await sb.from('rooms').insert({'name': name.text.trim(), 'owner_id': sb.auth.currentUser!.id, 'is_private': priv});
        load();
      } catch (e) { if (mounted) toast(context, e.toString()); }
    }
  }

  @override
  Widget build(BuildContext c) => Scaffold(
        appBar: AppBar(
          title: const Text('VoiceNest'),
          backgroundColor: Colors.transparent,
          actions: [
            IconButton(icon: const Icon(Icons.refresh), onPressed: load),
            IconButton(
              icon: const Icon(Icons.logout),
              onPressed: () async {
                await sb.auth.signOut();
                if (c.mounted) Navigator.pushReplacement(c, MaterialPageRoute(builder: (_) => const AuthPage()));
              },
            ),
          ],
        ),
        floatingActionButton: FloatingActionButton.extended(onPressed: create, icon: const Icon(Icons.add), label: const Text('New room')),
        body: rooms.isEmpty
            ? const Center(child: Text('No rooms yet. Create the first one!'))
            : ListView(
                padding: const EdgeInsets.all(12),
                children: rooms.map((r) => Card(
                      child: ListTile(
                        leading: CircleAvatar(backgroundColor: colorFor(r['name']), child: Text(r['name'][0].toUpperCase())),
                        title: Text(r['name']),
                        subtitle: Text(r['is_private'] == true ? 'Private' : 'Public'),
                        trailing: FilledButton(
                          onPressed: () => Navigator.push(c, MaterialPageRoute(builder: (_) => RoomPage(room: r))),
                          child: const Text('Join'),
                        ),
                      ),
                    )).toList(),
              ),
      );
}

class RoomPage extends StatefulWidget {
  final Map<String, dynamic> room;
  const RoomPage({super.key, required this.room});
  @override
  State<RoomPage> createState() => _RoomState();
}

class _RoomState extends State<RoomPage> {
  final lk = Room(
    roomOptions: const RoomOptions(
      defaultAudioCaptureOptions: AudioCaptureOptions(
        noiseSuppression: true,
        echoCancellation: true,
        autoGainControl: true,
      ),
    ),
  );
  final names = <String, String>{};
  final chat = <String>[];
  final msg = TextEditingController();
  EventsListener<RoomEvent>? ev;
  bool ready = false, muted = false;
  String status = 'Connecting…';

  @override
  void initState() { super.initState(); join(); }

  Future<void> join() async {
    try {
      final res = await sb.functions.invoke('livekit-token', body: {'roomId': widget.room['id']});
      final d = res.data as Map;
      if (d['error'] != null) throw Exception(d['error']);
      ev = lk.createListener()
        ..on<RoomReconnectingEvent>((_) { if (mounted) setState(() => status = 'Reconnecting…'); })
        ..on<RoomReconnectedEvent>((_) { if (mounted) setState(() => status = 'Connected'); })
        ..on<RoomDisconnectedEvent>((_) { if (mounted) setState(() => status = 'Disconnected'); })
        ..on<ParticipantConnectedEvent>((_) => refresh())
        ..on<ParticipantDisconnectedEvent>((_) => refresh())
        ..on<ActiveSpeakersChangedEvent>((_) => refresh())
        ..on<DataReceivedEvent>((e) {
          try {
            final m = jsonDecode(utf8.decode(e.data));
            final who = names[e.participant?.identity] ?? 'Guest';
            setState(() => chat.add('$who: ${m['v']}'));
          } catch (_) {}
        });
      await lk.connect(d['url'], d['token']);
      await lk.localParticipant!.setMicrophoneEnabled(true);
      ready = true;
      status = 'Connected';
      refresh();
    } catch (e) {
      if (mounted) { toast(context, 'Could not join: $e'); Navigator.pop(context); }
    }
  }

  Future<void> refresh() async {
    final me = sb.auth.currentUser!.id;
    final ids = [me, ...lk.remoteParticipants.values.map((p) => p.identity)].where((i) => !names.containsKey(i)).toList();
    if (ids.isNotEmpty) {
      final d = await sb.from('profiles').select('id,username').inFilter('id', ids);
      for (final p in d) { names[p['id']] = p['username']; }
    }
    if (mounted) setState(() {});
  }

  void send() {
    final t = msg.text.trim();
    if (t.isEmpty || !ready) return;
    lk.localParticipant!.publishData(utf8.encode(jsonEncode({'t': 'c', 'v': t})));
    setState(() => chat.add('You: $t'));
    msg.clear();
  }

  @override
  void dispose() {
    ev?.dispose();
    lk.disconnect();
    lk.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext c) {
    final List<Participant> ps = ready ? <Participant>[lk.localParticipant!, ...lk.remoteParticipants.values] : <Participant>[];
    return Scaffold(
      appBar: AppBar(title: Text(widget.room['name']), backgroundColor: Colors.transparent),
      body: Column(children: [
        if (status != 'Connected')
          Container(width: double.infinity, color: Colors.orange.shade800, padding: const EdgeInsets.all(6), child: Text(status, textAlign: TextAlign.center)),
        Padding(
          padding: const EdgeInsets.all(12),
          child: Wrap(
            spacing: 18, runSpacing: 14,
            children: ps.map((p) {
              final n = p == lk.localParticipant ? 'You' : (names[p.identity] ?? 'Guest');
              return SizedBox(
                width: 80,
                child: Column(children: [
                  Container(
                    padding: const EdgeInsets.all(3),
                    decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: p.isSpeaking ? const Color(0xFF2EE6C5) : Colors.transparent, width: 3)),
                    child: CircleAvatar(radius: 30, backgroundColor: colorFor(n), child: Text(n[0].toUpperCase(), style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w900, color: Colors.white))),
                  ),
                  Text(n, overflow: TextOverflow.ellipsis),
                ]),
              );
            }).toList(),
          ),
        ),
        Expanded(child: ListView(padding: const EdgeInsets.all(12), children: chat.map((m) => Padding(padding: const EdgeInsets.only(bottom: 6), child: Text(m))).toList())),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Row(children: [
            Expanded(child: TextField(controller: msg, onSubmitted: (_) => send(), decoration: const InputDecoration(hintText: 'Type a message'))),
            IconButton(icon: const Icon(Icons.send), onPressed: send),
          ]),
        ),
        SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Row(children: [
              Expanded(child: FilledButton.tonal(
                onPressed: !ready ? null : () async {
                  muted = !muted;
                  await lk.localParticipant!.setMicrophoneEnabled(!muted);
                  setState(() {});
                },
                child: Text(muted ? 'Unmute' : 'Mute'),
              )),
              const SizedBox(width: 10),
              Expanded(child: FilledButton(
                style: FilledButton.styleFrom(backgroundColor: Colors.redAccent, foregroundColor: Colors.white),
                onPressed: () => Navigator.pop(c),
                child: const Text('Leave'),
              )),
            ]),
          ),
        ),
      ]),
    );
  }
}
