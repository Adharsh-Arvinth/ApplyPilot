import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

/// Scan the sign-in QR code shown on your computer (Settings › Data & privacy › Sign in on your phone).
/// Returns the scanned sign-in link, or null if closed.
class ScanScreen extends StatefulWidget {
  const ScanScreen({super.key});

  static Future<String?> open(BuildContext context) => Navigator.of(context).push<String>(PageRouteBuilder(
        opaque: true,
        transitionDuration: const Duration(milliseconds: 380),
        reverseTransitionDuration: const Duration(milliseconds: 260),
        pageBuilder: (_, __, ___) => const ScanScreen(),
        transitionsBuilder: (_, a, __, child) {
          final c = CurvedAnimation(parent: a, curve: Curves.easeOutCubic, reverseCurve: Curves.easeInCubic);
          return FadeTransition(opacity: c, child: ScaleTransition(scale: Tween(begin: 1.04, end: 1.0).animate(c), child: child));
        },
      ));

  @override
  State<ScanScreen> createState() => _ScanScreenState();
}

class _ScanScreenState extends State<ScanScreen> with SingleTickerProviderStateMixin {
  final _controller = MobileScannerController(detectionSpeed: DetectionSpeed.noDuplicates, formats: const [BarcodeFormat.qrCode]);
  late final AnimationController _pulse = AnimationController(vsync: this, duration: const Duration(milliseconds: 1800))..repeat();
  bool _torch = false, _found = false;
  String? _hint;

  @override
  void dispose() {
    _pulse.dispose();
    _controller.dispose();
    super.dispose();
  }

  bool _isSignInLink(String v) {
    final u = Uri.tryParse(v.trim());
    return u != null && u.hasScheme && (u.scheme == 'https' || u.scheme == 'http') && (u.queryParameters['token'] ?? '').isNotEmpty;
  }

  void _onDetect(BarcodeCapture cap) {
    if (_found) return;
    for (final b in cap.barcodes) {
      final v = b.rawValue ?? '';
      if (_isSignInLink(v)) {
        _found = true;
        HapticFeedback.mediumImpact();
        setState(() {});
        Future.delayed(const Duration(milliseconds: 420), () { if (mounted) Navigator.of(context).pop(v.trim()); });
        return;
      }
      if (v.isNotEmpty && _hint == null) {
        HapticFeedback.selectionClick();
        setState(() => _hint = "That isn't an ApplyPilot sign-in code. Use the one in Settings › Data & privacy.");
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    final box = (size.width * 0.68).clamp(200.0, 320.0);
    final rect = Rect.fromCenter(center: Offset(size.width / 2, size.height * 0.44), width: box, height: box);
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light.copyWith(statusBarColor: Colors.transparent, systemNavigationBarColor: Colors.black),
      child: Scaffold(
        backgroundColor: Colors.black,
        body: Stack(children: [
          Positioned.fill(
            child: MobileScanner(
              controller: _controller,
              onDetect: _onDetect,
              errorBuilder: (_, e) => _CameraProblem(error: e),
            ),
          ),
          // Soft dark veil with a rounded window, and animated corner brackets around it
          Positioned.fill(
            child: AnimatedBuilder(
              animation: _pulse,
              builder: (_, __) => CustomPaint(painter: _Viewfinder(rect: rect, t: _pulse.value, found: _found)),
            ),
          ),
          SafeArea(
            child: Column(children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(8, 4, 8, 0),
                child: Row(children: [
                  _GlassButton(icon: Icons.close_rounded, label: 'Close', onTap: () => Navigator.of(context).pop()),
                  const Spacer(),
                  _GlassButton(
                    icon: _torch ? Icons.flashlight_on_rounded : Icons.flashlight_off_rounded,
                    label: _torch ? 'Torch off' : 'Torch on',
                    onTap: () { _controller.toggleTorch(); setState(() => _torch = !_torch); HapticFeedback.selectionClick(); },
                  ),
                ]),
              ),
              const SizedBox(height: 18),
              const Text('Scan to sign in', style: TextStyle(color: Colors.white, fontSize: 26, fontWeight: FontWeight.w700, letterSpacing: -0.5)),
              const SizedBox(height: 8),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 36),
                child: Text('On your computer, open ApplyPilot › Settings › Data & privacy › Sign in on your phone › Show QR code.',
                    textAlign: TextAlign.center, style: TextStyle(color: Colors.white.withValues(alpha: 0.75), fontSize: 14.5, height: 1.4)),
              ),
              const Spacer(),
              AnimatedSwitcher(
                duration: const Duration(milliseconds: 260),
                child: _found
                    ? const _Pill(key: ValueKey('ok'), icon: Icons.check_circle_rounded, text: 'Got it, signing you in…', color: Color(0xFF34B394))
                    : _hint != null
                        ? _Pill(key: const ValueKey('hint'), icon: Icons.info_outline_rounded, text: _hint!, color: const Color(0xFFE0A24A))
                        : const SizedBox(key: ValueKey('none'), height: 0),
              ),
              const SizedBox(height: 36),
            ]),
          ),
        ]),
      ),
    );
  }
}

class _Viewfinder extends CustomPainter {
  final Rect rect;
  final double t;
  final bool found;
  _Viewfinder({required this.rect, required this.t, required this.found});

  @override
  void paint(Canvas canvas, Size size) {
    final r = RRect.fromRectAndRadius(rect, const Radius.circular(28));
    final veil = Path()..addRect(Offset.zero & size);
    final hole = Path()..addRRect(r);
    canvas.drawPath(Path.combine(PathOperation.difference, veil, hole), Paint()..color = const Color(0xA6000000));

    // Corner brackets that breathe gently (and turn green when a code is found)
    final breathe = found ? 0.0 : (0.5 - (t - 0.5).abs()) * 6; // 0 → 3 → 0 px
    final b = r.outerRect.inflate(4 + breathe);
    final color = found ? const Color(0xFF34B394) : Colors.white;
    final p = Paint()..color = color..style = PaintingStyle.stroke..strokeWidth = 4..strokeCap = StrokeCap.round;
    const L = 46.0, R = 24.0; // bracket arm length, corner radius
    void corner(Offset o, double sx, double sy) {
      final path = Path()
        ..moveTo(o.dx, o.dy + sy * L)
        ..lineTo(o.dx, o.dy + sy * R)
        ..arcToPoint(Offset(o.dx + sx * R, o.dy), radius: const Radius.circular(R), clockwise: sx * sy > 0)
        ..lineTo(o.dx + sx * L, o.dy);
      canvas.drawPath(path, p);
    }
    corner(b.topLeft, 1, 1);
    corner(b.topRight, -1, 1);
    corner(b.bottomLeft, 1, -1);
    corner(b.bottomRight, -1, -1);

    // A soft light sweeping down the window
    if (!found) {
      final y = rect.top + rect.height * (0.08 + 0.84 * Curves.easeInOut.transform(t));
      final line = Rect.fromLTWH(rect.left + 18, y - 1, rect.width - 36, 2);
      canvas.drawRRect(RRect.fromRectAndRadius(line.inflate(6), const Radius.circular(8)),
          Paint()..shader = LinearGradient(colors: [Colors.transparent, Colors.white.withValues(alpha: 0.18), Colors.transparent]).createShader(line.inflate(6)));
      canvas.drawRRect(RRect.fromRectAndRadius(line, const Radius.circular(1)),
          Paint()..shader = LinearGradient(colors: [Colors.white.withValues(alpha: 0), Colors.white.withValues(alpha: 0.85), Colors.white.withValues(alpha: 0)]).createShader(line));
    }
  }

  @override
  bool shouldRepaint(_Viewfinder old) => old.t != t || old.found != found || old.rect != rect;
}

class _GlassButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  const _GlassButton({required this.icon, required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) => Semantics(
        button: true,
        label: label,
        child: GestureDetector(
          onTap: onTap,
          child: Container(
            width: 46, height: 46,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: Colors.white.withValues(alpha: 0.14),
              border: Border.all(color: Colors.white.withValues(alpha: 0.22)),
            ),
            child: Icon(icon, color: Colors.white, size: 22),
          ),
        ),
      );
}

class _Pill extends StatelessWidget {
  final IconData icon;
  final String text;
  final Color color;
  const _Pill({super.key, required this.icon, required this.text, required this.color});

  @override
  Widget build(BuildContext context) => Container(
        margin: const EdgeInsets.symmetric(horizontal: 28),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(color: Colors.black.withValues(alpha: 0.55), borderRadius: BorderRadius.circular(22),
            border: Border.all(color: Colors.white.withValues(alpha: 0.12))),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon, color: color, size: 20),
          const SizedBox(width: 10),
          Flexible(child: Text(text, style: const TextStyle(color: Colors.white, fontSize: 14, height: 1.35))),
        ]),
      );
}

class _CameraProblem extends StatelessWidget {
  final MobileScannerException error;
  const _CameraProblem({required this.error});

  @override
  Widget build(BuildContext context) {
    final denied = error.errorCode == MobileScannerErrorCode.permissionDenied;
    return Container(
      color: Colors.black,
      alignment: Alignment.center,
      padding: const EdgeInsets.all(36),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Icon(denied ? Icons.no_photography_outlined : Icons.videocam_off_outlined, color: Colors.white70, size: 40),
        const SizedBox(height: 14),
        Text(denied ? 'Camera access is off' : "The camera isn't available",
            style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w600)),
        const SizedBox(height: 8),
        Text(denied ? 'Allow the camera for ApplyPilot in your phone settings, or paste the sign-in link instead.' : 'Paste the sign-in link instead.',
            textAlign: TextAlign.center, style: const TextStyle(color: Colors.white70, fontSize: 14, height: 1.4)),
      ]),
    );
  }
}
