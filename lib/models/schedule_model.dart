class Schedule {
  final String id;
  final String teacherId;
  final String subject;
  final String classId;
  final String time;

  Schedule({
    required this.id,
    required this.teacherId,
    required this.subject,
    required this.classId,
    required this.time,
  });

  Map<String, dynamic> toMap() {
    return {
      'teacher_id': teacherId,
      'subject': subject,
      'class_id': classId,
      'time': time,
    };
  }

  factory Schedule.fromMap(String id, Map<String, dynamic> map) {
    return Schedule(
      id: id,
      teacherId: map['teacher_id'],
      subject: map['subject'],
      classId: map['class_id'],
      time: map['time'],
    );
  }
}