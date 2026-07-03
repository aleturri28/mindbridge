import 'dart:async';

import 'package:flutter/material.dart';
import 'package:just_audio/just_audio.dart';

import '../../core/routing/app_router.dart';
import '../../core/theme/app_theme.dart';
import '../../core/theme/app_tokens.dart';
import '../../core/util/l10n_ext.dart';
import '../../data/pause_types.dart';

/// Musica rilassante: loop ambient locale (nessun contenuto remoto),
/// 5 minuti con stop anticipato. L'audio qui è scelto esplicitamente
/// dall'utente, quindi non viola il default silenzioso (NFR4).
class MusicScreen extends StatefulWidget {
  const MusicScreen({super.key});

  static const Duration pauseDuration = Duration(minutes: 5);

  @override
  State<MusicScreen> createState() => _MusicScreenState();
}

class _MusicScreenState extends State<MusicScreen> {
  final AudioPlayer _player = AudioPlayer();
  late Duration _remaining;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _remaining = MusicScreen.pauseDuration;
    _timer = Timer.periodic(const Duration(seconds: 1), (_) => _tick());
    unawaited(_startAudio());
  }

  Future<void> _startAudio() async {
    // Se l'audio non parte (asset o audio focus), la pausa resta valida:
    // timer e schermata continuano in silenzio.
    try {
      await _player.setAsset('assets/audio/relax_loop.wav');
      await _player.setLoopMode(LoopMode.one);
      unawaited(_player.play());
    } on Exception catch (e) {
      debugPrint('musica pausa non disponibile: $e');
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    unawaited(_player.dispose());
    super.dispose();
  }

  void _tick() {
    if (_remaining > const Duration(seconds: 1)) {
      setState(() => _remaining -= const Duration(seconds: 1));
    } else {
      _finish();
    }
  }

  void _finish() {
    _timer?.cancel();
    unawaited(_player.stop());
    unawaited(
      Navigator.of(context).pushReplacementNamed(
        AppRoutes.pauseDone,
        arguments: PauseKind.music,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final double progress = 1 -
        _remaining.inSeconds / MusicScreen.pauseDuration.inSeconds;
    final String clock =
        '${_remaining.inMinutes}:${(_remaining.inSeconds % 60).toString().padLeft(2, '0')}';

    return Scaffold(
      appBar: AppBar(title: Text(context.l10n.musicTitle)),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              const Spacer(),
              Center(
                child: SizedBox(
                  width: 220,
                  height: 220,
                  child: Stack(
                    fit: StackFit.expand,
                    children: <Widget>[
                      CircularProgressIndicator(
                        value: progress,
                        strokeWidth: AppSpacing.sm,
                        color: AppColors.primary,
                        backgroundColor:
                            AppColors.primary.withValues(alpha: 0.15),
                      ),
                      const Center(
                        child: Icon(
                          Icons.music_note,
                          size: 72,
                          color: AppColors.primary,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: AppSpacing.lg),
              Text(
                clock,
                textAlign: TextAlign.center,
                style: AppTheme.timerStyle.copyWith(fontSize: 48),
              ),
              const SizedBox(height: AppSpacing.sm),
              Text(
                context.l10n.musicSubtitle,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodyLarge,
              ),
              const Spacer(),
              OutlinedButton(
                onPressed: _finish,
                child: Text(context.l10n.musicStop),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
