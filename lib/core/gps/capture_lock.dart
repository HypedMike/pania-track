/// Recording a trail and following one (a tour) both use the same native GPS service and its
/// single point buffer, so only one of them can run at a time.
enum CaptureOwner { recording, tour }

abstract final class CaptureLock {
  static CaptureOwner? _owner;

  /// Takes the lock. Returns false when the other feature holds it.
  static bool claim(CaptureOwner who) {
    if (_owner != null && _owner != who) return false;
    _owner = who;
    return true;
  }

  static void release(CaptureOwner who) {
    if (_owner == who) _owner = null;
  }

  static CaptureOwner? get heldBy => _owner;
}
