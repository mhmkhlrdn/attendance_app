class Schedule {
  final String id;
  final String teacherId;
  final String subject;
  final String classId;
  final String time;
  final String scheduleType; // 'daily_morning' or 'subject_specific'
  final String? dayOfWeek; // Only for subject-specific schedules

  Schedule({
    required this.id,
    required this.teacherId,
    required this.subject,
    required this.classId,
    required this.time,
    required this.scheduleType,
    this.dayOfWeek,
  });

  Map<String, dynamic> toMap() {
    return {
      'teacher_id': teacherId,
      'subject': subject,
      'class_id': classId,
      'time': time,
      'schedule_type': scheduleType,
      'day_of_week': dayOfWeek,
    };
  }

  factory Schedule.fromMap(String id, Map<String, dynamic> map) {
    return Schedule(
      id: id,
      teacherId: map['teacher_id'],
      subject: map['subject'],
      classId: map['class_id'],
      time: map['time'],
      scheduleType: map['schedule_type'] ?? 'subject_specific',
      dayOfWeek: map['day_of_week'],
    );
  }

  // Helper method to check if this is a daily morning attendance schedule
  bool get isDailyMorning => scheduleType == 'daily_morning';
  
  // Helper method to check if this is a subject-specific schedule
  bool get isSubjectSpecific => scheduleType == 'subject_specific';
  
  // Helper method to get display text for schedule type
  String get scheduleTypeDisplay {
    switch (scheduleType) {
      case 'daily_morning':
        return 'Presensi Pagi Harian';
      case 'subject_specific':
        return 'Mata Pelajaran';
      default:
        return 'Tidak Diketahui';
    }
  }
}