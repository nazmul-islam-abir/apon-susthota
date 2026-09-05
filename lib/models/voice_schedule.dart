/// Re-export the voice-schedule model from `voice_message.dart`
/// so consumers can `import '../models/voice_schedule.dart';` to
/// match the plan's file layout. Keeping a separate file would
/// duplicate the enum + helper; a barrel re-export keeps the
/// public surface area aligned with the approved plan.
library;

export 'voice_message.dart' show VoiceSchedule, VoiceScheduleStatus, VoiceScheduleStatusX;
