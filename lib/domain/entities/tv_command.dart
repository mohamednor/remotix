// lib/domain/entities/tv_command.dart

enum TvCommand {
  power,
  volumeUp,
  volumeDown,
  channelUp,
  channelDown,
  up,
  down,
  left,
  right,
  ok,
  home,
  back,
  mute,
}

extension TvCommandExtension on TvCommand {
  String get displayName {
    switch (this) {
      case TvCommand.power:
        return 'Power';
      case TvCommand.volumeUp:
        return 'Vol+';
      case TvCommand.volumeDown:
        return 'Vol-';
      case TvCommand.channelUp:
        return 'CH+';
      case TvCommand.channelDown:
        return 'CH-';
      case TvCommand.up:
        return 'Up';
      case TvCommand.down:
        return 'Down';
      case TvCommand.left:
        return 'Left';
      case TvCommand.right:
        return 'Right';
      case TvCommand.ok:
        return 'OK';
      case TvCommand.home:
        return 'Home';
      case TvCommand.back:
        return 'Back';
      case TvCommand.mute:
        return 'Mute';
    }
  }
}
