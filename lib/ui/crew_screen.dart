import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import 'package:defib_core/mission.dart';

import '../net/gateway_session.dart';

/// Ecran echipaj B44-O5: timpi de misiune + stare link + navigare.
class CrewScreen extends StatefulWidget {
  const CrewScreen({super.key});

  @override
  State<CrewScreen> createState() => _CrewScreenState();
}

class _CrewScreenState extends State<CrewScreen> {
  late final GatewaySession _session;
  final _urlCtrl = TextEditingController(text: 'http://127.0.0.1:8089');
  final _navCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _session = GatewaySession();
    _session.addListener(_onSession);
  }

  void _onSession() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _session.removeListener(_onSession);
    _session.dispose();
    _urlCtrl.dispose();
    _navCtrl.dispose();
    super.dispose();
  }

  Color _linkColor() => switch (_session.linkMode) {
        LinkMode.online => const Color(0xFF00C853),
        LinkMode.storeAndForward => const Color(0xFFFFAB00),
        LinkMode.offline => const Color(0xFFFF5252),
      };

  /// Afișează `HH:mm` din valoare ISO sau deja `HH:mm`.
  static String _displayTime(String? raw) {
    if (raw == null || raw.isEmpty) return '--:--';
    if (raw.length >= 16 && raw.contains('T')) {
      return raw.substring(11, 16);
    }
    if (raw.length >= 5 && raw.contains(':')) return raw.substring(0, 5);
    return raw;
  }

  Future<void> _openNavigation() async {
    final raw = _navCtrl.text.trim();
    if (raw.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Introdu adresă sau coordonate lat,lon')),
      );
      return;
    }
    // geo:lat,lon sau căutare text via geo:0,0?q=
    Uri uri;
    final coords = RegExp(r'^\s*(-?\d+(\.\d+)?)\s*,\s*(-?\d+(\.\d+)?)\s*$')
        .firstMatch(raw);
    if (coords != null) {
      final lat = coords.group(1);
      final lon = coords.group(3);
      uri = Uri.parse('geo:$lat,$lon');
    } else {
      uri = Uri.parse('geo:0,0?q=${Uri.encodeComponent(raw)}');
    }
    final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!ok && mounted) {
      // Fallback OsmAnd / Organic Maps scheme attempts.
      final q = Uri.encodeComponent(raw);
      for (final alt in [
        Uri.parse('osmand.geo:0,0?q=$q'),
        Uri.parse('organicmaps://map?q=$q'),
      ]) {
        if (await canLaunchUrl(alt)) {
          await launchUrl(alt, mode: LaunchMode.externalApplication);
          return;
        }
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text('Nicio aplicație de navigare disponibilă')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Echipaj — timpi misiune'),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: Center(
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: _linkColor().withOpacity(0.2),
                  border: Border.all(color: _linkColor()),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  _session.statusMessage,
                  style: TextStyle(color: _linkColor(), fontSize: 12),
                ),
              ),
            ),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          TextField(
            controller: _urlCtrl,
            decoration: const InputDecoration(
              labelText: 'Gateway URL (LAN)',
              hintText: 'http://127.0.0.1:8089',
              border: OutlineInputBorder(),
            ),
            keyboardType: TextInputType.url,
          ),
          const SizedBox(height: 8),
          FilledButton.icon(
            onPressed: () => _session.configure(_urlCtrl.text),
            icon: const Icon(Icons.link),
            label: const Text('Conectează gateway'),
          ),
          const SizedBox(height: 16),
          Text(
            _session.misiuneId ?? 'Nicio misiune activă',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          if (_session.liveVitalsLabel != null) ...[
            const SizedBox(height: 8),
            Text(
              _session.liveVitalsLabel!,
              style: const TextStyle(
                  fontFeatures: [FontFeature.tabularFigures()],
                  fontSize: 16),
            ),
          ],
          const SizedBox(height: 8),
          for (final spec in MissionButtonSpec.crewButtons) ...[
            const SizedBox(height: 6),
            SizedBox(
              height: 52,
              child: FilledButton(
                style: FilledButton.styleFrom(
                  backgroundColor: _session.timpi[spec.key] != null
                      ? Colors.blueGrey
                      : null,
                ),
                onPressed: _session.isBusy
                    ? null
                    : () async {
                        final ok = await _session.pressTimeButton(spec.key);
                        if (!ok && mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                                content: Text(
                                    'Apăsare ignorată (anti-dublu-click)')),
                          );
                        }
                      },
                child: Row(
                  children: [
                    Expanded(
                      child: Text(spec.label,
                          style: const TextStyle(
                              fontSize: 18, fontWeight: FontWeight.bold)),
                    ),
                    Text(
                      _displayTime(_session.timpi[spec.key]),
                      style: const TextStyle(fontSize: 18),
                    ),
                  ],
                ),
              ),
            ),
          ],
          const SizedBox(height: 24),
          Text('Navigare', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          TextField(
            controller: _navCtrl,
            decoration: const InputDecoration(
              labelText: 'Adresă sau lat,lon',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed: _openNavigation,
            icon: const Icon(Icons.navigation),
            label: const Text('NAVIGARE'),
          ),
          if (_session.queue.length > 0) ...[
            const SizedBox(height: 16),
            Text('Coadă offline: ${_session.queue.length} postări',
                style: const TextStyle(color: Colors.orangeAccent)),
          ],
        ],
      ),
    );
  }
}
