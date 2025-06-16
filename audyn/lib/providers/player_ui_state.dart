import 'package:flutter/foundation.dart';

class PlayerUIState with ChangeNotifier {
  bool _hideBottomPlayer = false;

  bool get hideBottomPlayer => _hideBottomPlayer;

  set hideBottomPlayer(bool value) {
    if (_hideBottomPlayer != value) {
      _hideBottomPlayer = value;
      notifyListeners();
    }
  }
}
