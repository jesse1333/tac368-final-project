import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';

void main() {
  runApp(const SpaceInvadersApp());
}

class SpaceInvadersApp extends StatelessWidget {
  const SpaceInvadersApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Space Invaders',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.indigo),
      ),
      initialRoute: '/',
      routes: {
        '/': (context) => const HomeScreen(),
        '/game': (context) => const GameScreen(),
        '/scores': (context) => const HighScoresScreen(),
      },
    );
  }
}

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            colors: [Color(0xFF060B2B), Color(0xFF19204D)],
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
          ),
        ),
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.rocket_launch, color: Colors.white, size: 76),
                const SizedBox(height: 12),
                const Text(
                  'Space Invaders',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 34,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 8),
                const Text(
                  'Move with WASD keys.\nShoot with Space bar.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.white70, fontSize: 16),
                ),
                const SizedBox(height: 28),
                FilledButton(
                  onPressed: () => Navigator.pushNamed(context, '/game'),
                  child: const Text('Start Game'),
                ),
                const SizedBox(height: 12),
                OutlinedButton(
                  onPressed: () => Navigator.pushNamed(context, '/scores'),
                  child: const Text('High Scores'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class HighScoresScreen extends StatefulWidget {
  const HighScoresScreen({super.key});

  @override
  State<HighScoresScreen> createState() => _HighScoresScreenState();
}

class _HighScoresScreenState extends State<HighScoresScreen> {
  late Future<List<int>> _scoresFuture;

  @override
  void initState() {
    super.initState();
    _scoresFuture = ScoreStore.readScores();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('High Scores')),
      body: FutureBuilder<List<int>>(
        future: _scoresFuture,
        builder: (context, snapshot) {
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }

          final scores = snapshot.data!;
          if (scores.isEmpty) {
            return const Center(
              child: Text('No scores yet. Play a game to create one!'),
            );
          }

          return ListView.separated(
            padding: const EdgeInsets.all(16),
            itemCount: scores.length,
            separatorBuilder: (_, index) => const Divider(),
            itemBuilder: (context, index) => ListTile(
              leading: CircleAvatar(child: Text('${index + 1}')),
              title: Text('Score: ${scores[index]}'),
            ),
          );
        },
      ),
    );
  }
}

class GameScreen extends StatefulWidget {
  const GameScreen({super.key});

  @override
  State<GameScreen> createState() => _GameScreenState();
}

class _GameScreenState extends State<GameScreen> {
  static const double gameWidth = 360;
  static const double gameHeight = 640;
  static const double shipWidth = 42;
  static const double shipHeight = 42;
  static const double alienWidth = 34;
  static const double alienHeight = 34;
  static const double laserWidth = 6;
  static const double laserHeight = 18;
  static const double enemyBulletWidth = 7;
  static const double enemyBulletHeight = 18;

  final FocusNode _focusNode = FocusNode();
  final Random _random = Random();
  final AudioPlayer _shootSfxPlayer = AudioPlayer();
  final AudioPlayer _hitSfxPlayer = AudioPlayer();
  final AudioPlayer _explosionSfxPlayer = AudioPlayer();
  final AudioPlayer _enemyFireSfxPlayer = AudioPlayer();
  final AudioPlayer _playerHitSfxPlayer = AudioPlayer();
  final AudioPlayer _gameOverSfxPlayer = AudioPlayer();
  final AudioPlayer _musicPlayer = AudioPlayer();

  Timer? _loop;
  double _playerX = gameWidth / 2 - shipWidth / 2;
  int _lives = 3;
  int _score = 0;
  int _wave = 1;
  bool _isGameOver = false;
  bool _isInvulnerable = false;
  bool _showPlayerSprite = true;
  DateTime _lastShotAt = DateTime.fromMillisecondsSinceEpoch(0);
  Duration _shootCooldown = const Duration(milliseconds: 120);

  final List<Laser> _playerLasers = [];
  final List<EnemyBullet> _enemyBullets = [];
  final List<Alien> _aliens = [];
  final Set<LogicalKeyboardKey> _pressedKeys = {};

  @override
  void initState() {
    super.initState();
    _spawnWave();
    _loop = Timer.periodic(const Duration(milliseconds: 16), (_) => _tick());
    _initAudio();
  }

  @override
  void dispose() {
    _loop?.cancel();
    _shootSfxPlayer.dispose();
    _hitSfxPlayer.dispose();
    _explosionSfxPlayer.dispose();
    _enemyFireSfxPlayer.dispose();
    _playerHitSfxPlayer.dispose();
    _gameOverSfxPlayer.dispose();
    _musicPlayer.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  Future<void> _initAudio() async {
    try {
      await _shootSfxPlayer.setPlayerMode(PlayerMode.lowLatency);
      await _hitSfxPlayer.setPlayerMode(PlayerMode.lowLatency);
      await _explosionSfxPlayer.setPlayerMode(PlayerMode.lowLatency);
      await _enemyFireSfxPlayer.setPlayerMode(PlayerMode.lowLatency);
      await _playerHitSfxPlayer.setPlayerMode(PlayerMode.lowLatency);
      await _gameOverSfxPlayer.setPlayerMode(PlayerMode.lowLatency);
      await _shootSfxPlayer.setSource(AssetSource('audio/shoot.wav'));
      final shootDuration = await _shootSfxPlayer.getDuration();
      if (shootDuration != null && shootDuration > Duration.zero) {
        _shootCooldown = Duration(
          milliseconds: (shootDuration.inMilliseconds * 1.5).round(),
        );
      }
      await _musicPlayer.setReleaseMode(ReleaseMode.loop);
      await _musicPlayer.setVolume(0.35);
      await _musicPlayer.play(AssetSource('audio/fastinvader1.wav'));
    } catch (_) {
      // Keep gameplay running even if audio assets are unavailable.
    }
  }

  Future<void> _playSfx(
    AudioPlayer player,
    String fileName, {
    double volume = 0.9,
  }) async {
    try {
      await player.setVolume(volume);
      await player.play(AssetSource('audio/$fileName'));
    } catch (_) {
      // Ignore SFX failures to avoid interrupting gameplay.
    }
  }

  void _spawnWave() {
    _aliens.clear();
    const int rows = 4;
    const int cols = 8;
    const double gapX = 10;
    const double gapY = 10;
    const double startX = 18;
    const double startY = 60;
    final double waveSpeedBoost = 1 + ((_wave - 1) * 0.12);
    for (int row = 0; row < rows; row++) {
      for (int col = 0; col < cols; col++) {
        _aliens.add(
          Alien(
            x: startX + col * (alienWidth + gapX),
            y: startY + row * (alienHeight + gapY),
            speedY: (0.18 + (row * 0.02)) * waveSpeedBoost,
          ),
        );
      }
    }
  }

  void _tick() {
    if (!mounted || _isGameOver) return;

    _updateMovement();
    _updateLasers();
    _updateEnemyBullets();
    _updateAliens();
    _checkCollisions();
    _maybeShootBack();

    if (_aliens.isEmpty) {
      _wave += 1;
      _spawnWave();
    }

    setState(() {});
  }

  void _updateMovement() {
    const double speed = 4.5;
    if (_pressedKeys.contains(LogicalKeyboardKey.keyA)) {
      _playerX -= speed;
    }
    if (_pressedKeys.contains(LogicalKeyboardKey.keyD)) {
      _playerX += speed;
    }
    _playerX = _playerX.clamp(0.0, gameWidth - shipWidth);
  }

  void _updateLasers() {
    for (final laser in _playerLasers) {
      laser.y -= 8;
    }
    _playerLasers.removeWhere((laser) => laser.y + laserHeight < 0);
  }

  void _updateEnemyBullets() {
    final double playerY = gameHeight - 20 - shipHeight;
    final List<EnemyBullet> bulletsToRemove = [];

    for (final bullet in _enemyBullets) {
      bullet.y += bullet.speedY;

      final bool hitsPlayer = _overlap(
        bullet.x,
        bullet.y,
        enemyBulletWidth,
        enemyBulletHeight,
        _playerX,
        playerY,
        shipWidth,
        shipHeight,
      );

      if (hitsPlayer && !_isInvulnerable) {
        bulletsToRemove.add(bullet);
        _loseLife();
      } else if (bullet.y > gameHeight) {
        bulletsToRemove.add(bullet);
      }
    }

    _enemyBullets.removeWhere(bulletsToRemove.contains);
  }

  void _updateAliens() {
    final double playerY = gameHeight - 20 - shipHeight;
    for (final alien in _aliens) {
      alien.y += alien.speedY;
      alien.x += sin(alien.y * 0.03) * 0.45;
      final bool reachesBottom = alien.y + alienHeight >= gameHeight;
      final bool touchesShooter = _overlap(
        alien.x,
        alien.y,
        alienWidth,
        alienHeight,
        _playerX,
        playerY,
        shipWidth,
        shipHeight,
      );
      if (reachesBottom || (touchesShooter && !_isInvulnerable)) {
        _loseLife();
        return;
      }
    }
  }

  void _checkCollisions() {
    final List<Laser> lasersToRemove = [];
    final List<Alien> aliensToRemove = [];

    for (final laser in _playerLasers) {
      for (final alien in _aliens) {
        if (_overlap(
          laser.x,
          laser.y,
          laserWidth,
          laserHeight,
          alien.x,
          alien.y,
          alienWidth,
          alienHeight,
        )) {
          lasersToRemove.add(laser);
          aliensToRemove.add(alien);
          _score += 10;
          unawaited(_playSfx(_hitSfxPlayer, 'invaderkilled.wav'));
          unawaited(_playSfx(_explosionSfxPlayer, 'explosion.wav', volume: 0.8));
        }
      }
    }

    _playerLasers.removeWhere(lasersToRemove.contains);
    _aliens.removeWhere(aliensToRemove.contains);
  }

  bool _overlap(
    double ax,
    double ay,
    double aw,
    double ah,
    double bx,
    double by,
    double bw,
    double bh,
  ) {
    return ax < bx + bw && ax + aw > bx && ay < by + bh && ay + ah > by;
  }

  void _maybeShootBack() {
    final int fireThreshold = max(50, 220 - ((_wave - 1) * 18));
    if (_random.nextInt(fireThreshold) != 0) return;
    if (_aliens.isEmpty) return;
    final shooter = _aliens[_random.nextInt(_aliens.length)];
    final double bulletSpeed = 4.3 + ((_wave - 1) * 0.35);
    _enemyBullets.add(
      EnemyBullet(
        x: shooter.x + alienWidth / 2 - enemyBulletWidth / 2,
        y: shooter.y + alienHeight,
        speedY: bulletSpeed,
      ),
    );
    unawaited(_playSfx(_enemyFireSfxPlayer, 'enemy_fire.mp3', volume: 0.8));
  }

  void _shoot() {
    if (_isGameOver) return;
    final now = DateTime.now();
    if (now.difference(_lastShotAt) < _shootCooldown) return;
    _lastShotAt = now;

    _playerLasers.add(
      Laser(
        x: _playerX + shipWidth / 2 - laserWidth / 2,
        y: gameHeight - 85,
      ),
    );
    unawaited(_playSfx(_shootSfxPlayer, 'shoot.wav'));
    setState(() {});
  }

  Future<void> _loseLife() async {
    if (_isGameOver) return;
    _lives -= 1;
    unawaited(_playSfx(_playerHitSfxPlayer, 'player_hit.mp3', volume: 0.9));
    if (_lives > 0) {
      unawaited(_startDamageBlink());
      return;
    }
    _isGameOver = true;
    _loop?.cancel();
    await _musicPlayer.stop();
    await _playSfx(_gameOverSfxPlayer, 'game_over.mp3', volume: 0.9);
    await ScoreStore.saveScore(_score);
    if (mounted) {
      setState(() {});
    }
  }

  void _restart() {
    _loop?.cancel();
    setState(() {
      _playerX = gameWidth / 2 - shipWidth / 2;
      _lives = 3;
      _score = 0;
      _wave = 1;
      _isGameOver = false;
      _isInvulnerable = false;
      _showPlayerSprite = true;
      _playerLasers.clear();
      _enemyBullets.clear();
      _pressedKeys.clear();
      _spawnWave();
      _loop = Timer.periodic(const Duration(milliseconds: 16), (_) => _tick());
    });
    unawaited(_musicPlayer.play(AssetSource('audio/fastinvader1.wav')));
  }

  Future<void> _startDamageBlink() async {
    if (_isInvulnerable) return;
    _isInvulnerable = true;

    for (int i = 0; i < 8; i++) {
      if (!mounted || _isGameOver) return;
      await Future<void>.delayed(const Duration(milliseconds: 90));
      if (!mounted || _isGameOver) return;
      setState(() {
        _showPlayerSprite = !_showPlayerSprite;
      });
    }

    if (!mounted) return;
    setState(() {
      _showPlayerSprite = true;
      _isInvulnerable = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Space Invaders'),
        actions: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 16),
            child: Text('Score: $_score'),
          ),
          Padding(
            padding: const EdgeInsets.only(right: 16, top: 16, bottom: 16),
            child: Text('Lives: $_lives'),
          ),
        ],
      ),
      body: Center(
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () => _focusNode.requestFocus(),
          child: Focus(
            autofocus: true,
            focusNode: _focusNode,
            onKeyEvent: (node, event) {
              final key = event.logicalKey;
              final handledKeys = <LogicalKeyboardKey>{
                LogicalKeyboardKey.keyA,
                LogicalKeyboardKey.keyD,
                LogicalKeyboardKey.keyW,
                LogicalKeyboardKey.keyS,
                LogicalKeyboardKey.space,
              };

              if (event is KeyDownEvent) {
                _pressedKeys.add(key);
                if (key == LogicalKeyboardKey.space) {
                  _shoot();
                }
              } else if (event is KeyUpEvent) {
                _pressedKeys.remove(key);
              }

              if (handledKeys.contains(key)) {
                return KeyEventResult.handled;
              }
              return KeyEventResult.ignored;
            },
            child: FittedBox(
              fit: BoxFit.contain,
              alignment: Alignment.center,
              child: SizedBox(
                width: gameWidth,
                height: gameHeight,
                child: Container(
                  decoration: const BoxDecoration(
                    gradient: LinearGradient(
                      colors: [Color(0xFF020617), Color(0xFF0F172A)],
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                    ),
                  ),
                  child: Stack(
                    clipBehavior: Clip.hardEdge,
                    children: [
                  for (final alien in _aliens)
                    Positioned(
                      left: alien.x,
                      top: alien.y,
                      child: Image.asset(
                        'assets/images/alien.png',
                        width: alienWidth,
                        height: alienHeight,
                        fit: BoxFit.contain,
                        errorBuilder: (context, error, stackTrace) {
                          return const Icon(
                            Icons.broken_image,
                            color: Colors.red,
                            size: alienWidth,
                          );
                        },
                      ),
                    ),
                  for (final laser in _playerLasers)
                    Positioned(
                      left: laser.x,
                      top: laser.y,
                      child: Container(
                        width: laserWidth,
                        height: laserHeight,
                        decoration: const BoxDecoration(
                          color: Color(0xFFF59E0B),
                          borderRadius: BorderRadius.all(Radius.circular(2)),
                        ),
                      ),
                    ),
                  for (final bullet in _enemyBullets)
                    Positioned(
                      left: bullet.x,
                      top: bullet.y,
                      child: Container(
                        width: enemyBulletWidth,
                        height: enemyBulletHeight,
                        decoration: const BoxDecoration(
                          color: Color(0xFFEF4444),
                          borderRadius: BorderRadius.all(Radius.circular(2)),
                        ),
                      ),
                    ),
                  if (_showPlayerSprite)
                    Positioned(
                      left: _playerX,
                      bottom: 20,
                      child: Image.asset(
                        'assets/images/player_ship.png',
                        width: shipWidth,
                        height: shipHeight,
                        fit: BoxFit.contain,
                        errorBuilder: (context, error, stackTrace) {
                          return const Icon(
                            Icons.broken_image,
                            color: Colors.red,
                            size: shipWidth,
                          );
                        },
                      ),
                    ),
                  if (_isGameOver)
                    Positioned.fill(
                      child: Container(
                        color: Colors.black87,
                        child: Center(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Text(
                                'Game Over',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 30,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              const SizedBox(height: 12),
                              Text(
                                'Final Score: $_score',
                                style: const TextStyle(
                                  color: Colors.white70,
                                  fontSize: 18,
                                ),
                              ),
                              const SizedBox(height: 20),
                              FilledButton(
                                onPressed: _restart,
                                child: const Text('Play Again'),
                              ),
                              const SizedBox(height: 8),
                              OutlinedButton(
                                onPressed: () => Navigator.pushNamed(
                                  context,
                                  '/scores',
                                ),
                                child: const Text('View High Scores'),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
      bottomNavigationBar: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            Expanded(
              child: FilledButton(
                onPressed: () {
                  _pressedKeys.add(LogicalKeyboardKey.keyA);
                  Future<void>.delayed(const Duration(milliseconds: 150), () {
                    _pressedKeys.remove(LogicalKeyboardKey.keyA);
                  });
                },
                child: const Text('Left'),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: FilledButton(
                onPressed: _shoot,
                child: const Text('Shoot'),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: FilledButton(
                onPressed: () {
                  _pressedKeys.add(LogicalKeyboardKey.keyD);
                  Future<void>.delayed(const Duration(milliseconds: 150), () {
                    _pressedKeys.remove(LogicalKeyboardKey.keyD);
                  });
                },
                child: const Text('Right'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class Laser {
  Laser({required this.x, required this.y});
  double x;
  double y;
}

class Alien {
  Alien({required this.x, required this.y, required this.speedY});
  double x;
  double y;
  double speedY;
}

class EnemyBullet {
  EnemyBullet({required this.x, required this.y, required this.speedY});
  double x;
  double y;
  double speedY;
}

class ScoreStore {
  static const String _fileName = 'high_scores.json';

  static Future<File> _getScoreFile() async {
    final dir = await getApplicationDocumentsDirectory();
    return File('${dir.path}/$_fileName');
  }

  static Future<List<int>> readScores() async {
    try {
      final file = await _getScoreFile();
      if (!await file.exists()) {
        return <int>[];
      }
      final content = await file.readAsString();
      if (content.trim().isEmpty) {
        return <int>[];
      }
      final decoded = jsonDecode(content);
      if (decoded is! List) {
        return <int>[];
      }
      final scores = decoded.whereType<num>().map((e) => e.toInt()).toList()
        ..sort((a, b) => b.compareTo(a));
      return scores;
    } catch (_) {
      return <int>[];
    }
  }

  static Future<void> saveScore(int score) async {
    final existing = await readScores();
    existing.add(score);
    existing.sort((a, b) => b.compareTo(a));
    final topTen = existing.take(10).toList();
    final file = await _getScoreFile();
    await file.writeAsString(jsonEncode(topTen));
  }
}
